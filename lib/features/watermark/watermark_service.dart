import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/time/trusted_time_service.dart';
import '../../core/utils/maps_link.dart';
import '../templates/watermark_template.dart';

/// Todo lo que se estampa sobre la foto.
class WatermarkData {
  const WatermarkData({
    required this.latitude,
    required this.longitude,
    required this.accuracy,
    required this.time,
    required this.address,
    required this.verificationCode,
    this.brandLabel = 'GeoMark',
    this.config = const WatermarkConfig(),
  });

  final double latitude;
  final double longitude;
  final double accuracy;
  final TrustedTime time;
  final String? address;
  final String verificationCode;
  final String brandLabel;

  /// Plantilla elegida en el visor (estilo, proyecto, nota, campos visibles).
  final WatermarkConfig config;

  /// Lo que codifica el QR: enlace universal a Google Maps.
  String get qrPayload => MapsLink.search(latitude, longitude);
}

/// Dibuja la marca de agua (texto + QR) sobre la foto y la devuelve en JPEG.
///
/// Pipeline:
///   JPEG cámara -> ui.Image -> Canvas (foto + panel + texto + QR)
///   -> RGBA crudo -> [isolate] JPEG
///
/// - Se usa el Canvas de Flutter (Skia/Impeller) para tener tipografía
///   nítida con acentos/ñ, en vez de las fuentes bitmap del paquete image.
/// - La codificación JPEG (lo más pesado) va en un isolate para no
///   congelar la UI.
/// - Todo es offline: el QR es solo texto codificado.
class WatermarkService {
  Future<Uint8List> render({
    required Uint8List sourceJpeg,
    required WatermarkData data,
    int jpegQuality = 90,
  }) async {
    // 1. Decodificar. El codec de Flutter aplica la orientación EXIF de la
    //    cámara, así la marca queda siempre "abajo" visualmente.
    final codec = await ui.instantiateImageCodec(sourceJpeg);
    final src = (await codec.getNextFrame()).image;
    codec.dispose();

    final w = src.width.toDouble();
    final h = src.height.toDouble();
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, w, h));
    canvas.drawImage(src, Offset.zero, Paint());

    // 2. Unidad relativa (1 % del lado corto) => la marca se ve igual en
    //    una foto de 2 MP o de 50 MP, vertical u horizontal.
    final u = math.min(w, h) / 100;
    final pad = 3 * u;
    final qrBox = 24 * u; // QR + margen blanco ("quiet zone")
    final qrQuiet = 1.6 * u;
    final textMaxW = w - qrBox - pad * 3 - 2.6 * u;

    // 3. Texto según la plantilla. Mismo orden que LiveWatermarkOverlay.
    final cfg = data.config;
    final style = cfg.style;
    final accent = style.accent;
    final minimal = style == WatermarkStyle.minimo;

    final clock = _text(
      DateFormat('HH:mm').format(data.time.local),
      size: (minimal ? 7 : 9) * u,
      weight: FontWeight.w800,
      maxWidth: textMaxW,
    );
    final date = _text(
      '${DateFormat('dd/MM/yyyy').format(data.time.local)}  ${_weekday(data.time.local)}',
      size: 3.2 * u,
      weight: FontWeight.w600,
      maxWidth: textMaxW,
    );
    final lines = <String>[
      MapsLink.coordsText(data.latitude, data.longitude),
      if (cfg.showAccuracy && !minimal)
        'Precisión GPS: ±${data.accuracy.toStringAsFixed(0)} m',
      if (cfg.showAddress && !minimal)
        data.address ?? 'Sin conexión · coordenadas exactas',
      if (cfg.hasNote && !minimal) 'Nota: ${cfg.note.trim()}',
      if (!minimal) '${data.time.tzLabel} · ${data.time.source.label}',
      '${data.brandLabel} · Código ${data.verificationCode}',
    ];
    final body = _text(lines.join('\n'),
        size: 2.8 * u, weight: FontWeight.w500, maxWidth: textMaxW, height: 1.35);

    // Encabezado de proyecto (estilos Obra y Reporte, o si hay proyecto).
    final showHeader = cfg.hasProject || style == WatermarkStyle.obra;
    final header = showHeader
        ? _text(
            cfg.hasProject ? cfg.projectName.trim().toUpperCase() : 'REGISTRO DE OBRA',
            size: 3.4 * u,
            weight: FontWeight.w800,
            maxWidth: w - pad * 2,
            color: style == WatermarkStyle.obra
                ? const Color(0xFF000000)
                : const Color(0xFFFFFFFF),
          )
        : null;
    final headerH = header == null ? 0.0 : header.height + 2 * u;

    final textH = clock.height + date.height + 1.5 * u + body.height;
    final contentH = math.max(qrBox, textH);
    final panelH = headerH + contentH + pad * 2;
    final panelTop = h - panelH;

    // 4. Panel inferior semitransparente.
    canvas.drawRect(
      Rect.fromLTWH(0, panelTop, w, panelH),
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, panelTop),
          Offset(0, h),
          [const Color(0xA6000000), const Color(0xE0000000)],
        ),
    );
    if (header != null) {
      canvas.drawRect(
        Rect.fromLTWH(0, panelTop, w, headerH),
        Paint()
          ..color = style == WatermarkStyle.obra
              ? accent
              : accent.withValues(alpha: 0.85),
      );
      header.paint(canvas, Offset(pad, panelTop + 1 * u));
    }
    // Barra de acento lateral
    if (!minimal) {
      canvas.drawRect(
        Rect.fromLTWH(pad, panelTop + headerH + pad, 0.9 * u, contentH),
        Paint()..color = accent,
      );
    }

    // 5. Texto
    final textLeft = pad + (minimal ? 0 : 2.6 * u);
    var y = panelTop + headerH + pad + (contentH - textH) / 2;
    clock.paint(canvas, Offset(textLeft, y));
    y += clock.height;
    date.paint(canvas, Offset(textLeft, y));
    y += date.height + 1.5 * u;
    body.paint(canvas, Offset(textLeft, y));

    // 6. QR sobre fondo blanco (los lectores fallan sin margen claro).
    final qrLeft = w - pad - qrBox;
    final qrTop = panelTop + headerH + pad + (contentH - qrBox) / 2;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(qrLeft, qrTop, qrBox, qrBox), Radius.circular(1.2 * u)),
      Paint()..color = const Color(0xFFFFFFFF),
    );
    final qr = QrPainter(
      data: data.qrPayload,
      version: QrVersions.auto,
      // Nivel M (15 %) tolera algo de suciedad/compresión de WhatsApp sin
      // volver el QR tan denso que cueste leerlo desde una pantalla.
      errorCorrectionLevel: QrErrorCorrectLevel.M,
      gapless: true,
      eyeStyle: const QrEyeStyle(
          eyeShape: QrEyeShape.square, color: Color(0xFF000000)),
      dataModuleStyle: const QrDataModuleStyle(
          dataModuleShape: QrDataModuleShape.square, color: Color(0xFF000000)),
    );
    canvas.save();
    canvas.translate(qrLeft + qrQuiet, qrTop + qrQuiet);
    qr.paint(canvas, Size.square(qrBox - qrQuiet * 2));
    canvas.restore();

    // 7. Rasterizar y pasar a RGBA crudo.
    final picture = recorder.endRecording();
    final out = await picture.toImage(src.width, src.height);
    final bytes = await out.toByteData(format: ui.ImageByteFormat.rawRgba);
    final width = out.width, height = out.height;
    src.dispose();
    out.dispose();
    picture.dispose();
    if (bytes == null) throw StateError('No se pudo rasterizar la marca de agua');

    // 8. JPEG en isolate. TransferableTypedData evita copiar ~48 MB
    //    (foto de 12 MP) entre isolates.
    final transferable = TransferableTypedData.fromList(
        [bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes)]);
    return Isolate.run(() {
      final rgba = transferable.materialize();
      final image = img.Image.fromBytes(
        width: width,
        height: height,
        bytes: rgba,
        numChannels: 4,
        order: img.ChannelOrder.rgba,
      );
      return img.encodeJpg(image, quality: jpegQuality);
    });
  }

  static const _days = ['lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado', 'domingo'];
  String _weekday(DateTime d) => _days[d.weekday - 1];

  TextPainter _text(
    String s, {
    required double size,
    required FontWeight weight,
    required double maxWidth,
    double height = 1.15,
    Color color = const Color(0xFFFFFFFF),
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: s,
        style: TextStyle(
          color: color,
          fontSize: size,
          fontWeight: weight,
          height: height,
          shadows: const [Shadow(blurRadius: 2, color: Color(0x99000000))],
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 8,
      ellipsis: '…',
    );
    tp.layout(maxWidth: maxWidth);
    return tp;
  }
}
