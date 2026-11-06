import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/location/compass_service.dart';
import '../../core/time/trusted_time_service.dart';
import '../capture/domain/capture_record.dart';

/// Compartir evidencias y reportes.
///
/// Mensaje CORTO (por defecto), pensado para WhatsApp: 2 líneas.
///   📍 Barrio San José, Cojutepeque · 05/11 23:40 · Inspección
///   https://maps.google.com/?q=13.72045,-88.93607
///
/// - `maps.google.com/?q=` es el enlace más corto que abre Google Maps
///   (app o web) en el punto exacto, sin acortadores externos.
/// - 5 decimales ≈ 1 m: suficiente y más corto que 6.
class ShareService {
  static String compactText(CaptureRecord r) {
    // Lugar corto: barrio + municipio, sin el Plus Code ("P3C7+5GH") ni el país.
    final parts = (r.address ?? '')
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty && !e.contains('+') && !RegExp(r'^\d').hasMatch(e))
        .take(2)
        .toList();
    final place = parts.isEmpty ? 'Ubicación' : parts.join(', ');
    final when = DateFormat('dd/MM HH:mm').format(r.time.local);
    final act = r.activity == null ? '' : ' · ${r.activity}';
    return '📍 $place · $when$act\n${shortMapsUrl(r.latitude, r.longitude)}';
  }

  static String shortMapsUrl(double lat, double lng) =>
      'https://maps.google.com/?q=${lat.toStringAsFixed(5)},${lng.toStringAsFixed(5)}';

  /// Versión completa (si el usuario desactiva "mensaje corto" en Ajustes).
  static String fullText(CaptureRecord r) {
    final b = StringBuffer()
      ..writeln('📍 Ubicación de la evidencia fotográfica')
      ..writeln(r.address ?? r.coordsText)
      ..writeln()
      ..writeln('🗺️ Ver en Google Maps: ${r.mapsUrl}')
      ..writeln('🚗 Cómo llegar: ${r.directionsUrl}')
      ..writeln()
      ..writeln('🕒 ${r.time.display} · ${r.time.source.label}')
      ..writeln('🎯 Precisión: ±${r.accuracy.toStringAsFixed(0)} m');
    if (r.heading != null) b.writeln('🧭 Dirección de la foto: ${CompassService.label(r.heading!)}');
    if (r.activity != null) b.writeln('🛠️ Actividad: ${r.activity}');
    b.write('🔐 Código: ${r.verificationCode}');
    return b.toString();
  }

  static String payload(CaptureRecord r, {required bool compact}) =>
      compact ? compactText(r) : fullText(r);

  /// Foto + texto. En el menú de compartir aparece WhatsApp, Telegram, correo…
  Future<void> shareCapture(CaptureRecord r, {required bool compact, Rect? origin}) async {
    await SharePlus.instance.share(ShareParams(
      files: [XFile(r.filePath, mimeType: 'image/jpeg', name: 'Evidencia_${r.time.fileStamp}.jpg')],
      text: payload(r, compact: compact),
      sharePositionOrigin: origin,
    ));
  }

  /// Abre WhatsApp DIRECTAMENTE con el mensaje de ubicación listo para enviar
  /// (el usuario solo elige el chat). Ideal para "ubicar a otro".
  Future<bool> whatsappLocation(CaptureRecord r, {required bool compact}) =>
      openWhatsAppText(payload(r, compact: compact));

  static Future<bool> openWhatsAppText(String text) => launchUrl(
        Uri.parse('https://wa.me/?text=${Uri.encodeComponent(text)}'),
        mode: LaunchMode.externalApplication,
      );

  /// Comparte un archivo (PDF/Word). Android e iOS no permiten adjuntar un
  /// archivo directo a WhatsApp sin pasar por el menú del sistema; en ese
  /// menú WhatsApp suele aparecer primero.
  Future<void> shareFile({
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
    String? text,
    Rect? origin,
  }) async {
    final dir = await getTemporaryDirectory();
    final path = p.join(dir.path, fileName);
    await File(path).writeAsBytes(bytes, flush: true);
    await SharePlus.instance.share(ShareParams(
      files: [XFile(path, mimeType: mimeType, name: fileName)],
      text: text,
      sharePositionOrigin: origin,
    ));
  }

  Future<void> copyLink(CaptureRecord r) =>
      Clipboard.setData(ClipboardData(text: shortMapsUrl(r.latitude, r.longitude)));
}
