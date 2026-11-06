import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LogoException implements Exception {
  LogoException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Logotipo de la institución/empresa. Se usa en:
/// la pantalla de inicio, el visor de cámara, la marca de agua de las fotos,
/// y el encabezado de los reportes PDF y Word.
///
/// Siempre se guarda normalizado: PNG de máximo 512 px (conserva
/// transparencia y pesa poco).
class LogoService extends ValueNotifier<String?> {
  LogoService() : super(null);

  Uint8List? _cache;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final path = prefs.getString('logoPath');
    if (path != null && await File(path).exists()) value = path;
  }

  /// Bytes PNG del logo (en memoria para no leer el disco en cada foto).
  Future<Uint8List?> bytes() async {
    final path = value;
    if (path == null) return null;
    return _cache ??= await File(path).readAsBytes();
  }

  /// Elegir una imagen de la galería del teléfono.
  /// (Android 13+ usa el selector de fotos del sistema: no pide permisos.)
  Future<bool> pickFromGallery() async {
    final file = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1024);
    if (file == null) return false;
    await _store(await file.readAsBytes());
    return true;
  }

  /// Elegir un ARCHIVO de logotipo: PNG, JPG o PDF.
  /// Si es PDF, se convierte su primera página en imagen.
  Future<bool> pickFile() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['png', 'jpg', 'jpeg', 'pdf'],
      withData: true,
    );
    final f = res?.files.single;
    if (f == null) return false;
    final data = f.bytes ?? (f.path == null ? null : await File(f.path!).readAsBytes());
    if (data == null) throw LogoException('No se pudo leer el archivo.');
    if ((f.extension ?? '').toLowerCase() == 'pdf') {
      await _store(await _pdfFirstPageToPng(data));
    } else {
      await _store(data);
    }
    return true;
  }

  /// Rasteriza la primera página del PDF y recorta el margen blanco.
  Future<Uint8List> _pdfFirstPageToPng(Uint8List pdf) async {
    try {
      final page = await Printing.raster(pdf, pages: const [0], dpi: 200).first;
      final png = await page.toPng();
      return await Isolate.run(() {
        final im = img.decodePng(png);
        if (im == null) return png;
        // Recortar bordes casi blancos para que el logo no quede con márgenes grandes.
        var minX = im.width, minY = im.height, maxX = -1, maxY = -1;
        for (var y = 0; y < im.height; y += 2) {
          for (var x = 0; x < im.width; x += 2) {
            final p = im.getPixel(x, y);
            if (p.r < 245 || p.g < 245 || p.b < 245) {
              if (x < minX) minX = x;
              if (y < minY) minY = y;
              if (x > maxX) maxX = x;
              if (y > maxY) maxY = y;
            }
          }
        }
        if (maxX <= minX || maxY <= minY) return png;
        final x0 = (minX - 8).clamp(0, im.width - 1);
        final y0 = (minY - 8).clamp(0, im.height - 1);
        final c = img.copyCrop(im,
            x: x0,
            y: y0,
            width: (maxX - minX + 16).clamp(1, im.width - x0),
            height: (maxY - minY + 16).clamp(1, im.height - y0));
        return img.encodePng(c);
      });
    } catch (_) {
      throw LogoException('No se pudo convertir el PDF. Prueba con una imagen PNG o JPG.');
    }
  }

  /// Descargar el logo desde un enlace directo a la imagen
  /// (en Google Imágenes: mantener presionada la imagen -> "Copiar dirección de la imagen").
  Future<void> downloadFromUrl(String url) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !(uri.isScheme('https') || uri.isScheme('http'))) {
      throw LogoException('El enlace no es válido. Debe empezar con https://');
    }
    final http.Response res;
    try {
      res = await http.get(uri).timeout(const Duration(seconds: 15));
    } catch (_) {
      throw LogoException('No se pudo descargar. Revisa tu conexión a internet.');
    }
    if (res.statusCode != 200) {
      throw LogoException('El sitio respondió con error ${res.statusCode}.');
    }
    final type = res.headers['content-type'] ?? '';
    if (type.contains('text/html')) {
      throw LogoException('Ese enlace es una página web, no una imagen. '
          'Mantén presionada la imagen y elige "Copiar dirección de la imagen".');
    }
    await _store(res.bodyBytes);
  }

  Future<void> remove() async {
    final path = value;
    if (path != null) {
      try {
        await File(path).delete();
      } catch (_) {}
    }
    _cache = null;
    value = null;
    (await SharedPreferences.getInstance()).remove('logoPath');
  }

  /// Valida que sea una imagen real, la reduce y la guarda como PNG.
  Future<void> _store(Uint8List raw) async {
    final png = await Isolate.run(() {
      final im = img.decodeImage(raw);
      if (im == null) return null;
      final r = (im.width > 512 || im.height > 512)
          ? img.copyResize(im,
              width: im.width >= im.height ? 512 : null,
              height: im.height > im.width ? 512 : null)
          : im;
      return img.encodePng(r);
    });
    if (png == null) {
      throw LogoException('El archivo no es una imagen compatible (usa PNG o JPG).');
    }
    final dir = await getApplicationDocumentsDirectory();
    // Nombre nuevo cada vez para que Flutter no muestre la imagen anterior en caché.
    final path = p.join(dir.path, 'logo_${DateTime.now().millisecondsSinceEpoch}.png');
    await File(path).writeAsBytes(png, flush: true);
    final old = value;
    _cache = Uint8List.fromList(png);
    value = path;
    (await SharedPreferences.getInstance()).setString('logoPath', path);
    if (old != null && old != path) {
      try {
        await File(old).delete();
      } catch (_) {}
    }
  }
}
