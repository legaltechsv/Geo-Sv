import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
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
