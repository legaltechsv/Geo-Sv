import 'dart:ui';

import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../capture/domain/capture_record.dart';

/// "Smart Share Payload": imagen + texto con enlace directo a Google Maps.
///
/// Los tres métodos viajan juntos en un solo envío:
///   1. QR visible en la foto     -> sobrevive a capturas de pantalla e impresión.
///   2. EXIF GPS en el .jpg       -> para software (Google Fotos, QGIS, peritajes).
///   3. Texto con enlace tocable  -> el receptor toca y abre Maps / la ruta.
class ShareService {
  /// Texto que acompaña a la imagen. WhatsApp/Telegram convierten las URLs
  /// en enlaces tocables automáticamente.
  static String buildPayloadText(CaptureRecord r) {
    final b = StringBuffer()
      ..writeln('📍 Ubicación de la evidencia fotográfica')
      ..writeln(r.address ?? r.coordsText)
      ..writeln()
      ..writeln('🗺️ Ver en Google Maps:')
      ..writeln(r.mapsUrl)
      ..writeln()
      ..writeln('🚗 Cómo llegar:')
      ..writeln(r.directionsUrl)
      ..writeln()
      ..writeln('🕒 ${r.time.display} · ${r.time.source.label}')
      ..writeln('🎯 Precisión: ±${r.accuracy.toStringAsFixed(0)} m')
      ..write('🔐 Código: ${r.verificationCode}');
    return b.toString();
  }

  /// Envía imagen + texto a la app que elija el usuario.
  ///
  /// [origin] es obligatorio en iPad (ancla del popover); pásalo desde el
  /// RenderBox del botón.
  Future<ShareResultStatus> shareCapture(CaptureRecord r, {Rect? origin}) async {
    final file = XFile(
      r.filePath,
      mimeType: 'image/jpeg',
      name: 'Evidencia_${r.time.fileStamp}.jpg',
    );
    final result = await SharePlus.instance.share(
      ShareParams(
        files: [file],
        text: buildPayloadText(r),
        subject: 'Evidencia fotográfica – ${r.address ?? r.coordsText}',
        sharePositionOrigin: origin,
      ),
    );
    return result.status;
  }

  /// Respaldo: algunas apps (p. ej. WhatsApp en iOS) descartan el texto
  /// cuando se envía junto a una imagen. Este botón envía solo el enlace.
  Future<ShareResultStatus> shareLinkOnly(CaptureRecord r, {Rect? origin}) async {
    final result = await SharePlus.instance.share(
      ShareParams(text: buildPayloadText(r), sharePositionOrigin: origin),
    );
    return result.status;
  }

  Future<void> copyLink(CaptureRecord r) =>
      Clipboard.setData(ClipboardData(text: r.mapsUrl));
}
