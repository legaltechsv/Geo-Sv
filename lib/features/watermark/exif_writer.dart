import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:native_exif/native_exif.dart';

import '../../core/time/trusted_time_service.dart';
import '../../core/utils/maps_link.dart';

/// Escribe las coordenadas GPS "puras" en el EXIF del .jpg final.
///
/// Importante: el JPEG que sale de WatermarkService NO trae EXIF (se
/// recodificó), así que aquí se escribe desde cero. Esto además elimina
/// metadatos originales de la cámara que no queremos filtrar.
///
/// native_exif usa ExifInterface (Android) / ImageIO (iOS); recibe
/// grados decimales absolutos + referencia N/S/E/W y los convierte al
/// formato racional grados/minutos/segundos del estándar EXIF.
class ExifWriter {
  Future<void> writeGps({
    required String jpegPath,
    required double latitude,
    required double longitude,
    required TrustedTime time,
    required String verificationCode,
  }) async {
    final exif = await Exif.fromPath(jpegPath);
    try {
      await exif.writeAttributes({
        'GPSLatitude': latitude.abs().toString(),
        'GPSLatitudeRef': latitude >= 0 ? 'N' : 'S',
        'GPSLongitude': longitude.abs().toString(),
        'GPSLongitudeRef': longitude >= 0 ? 'E' : 'W',
        // Hora local de captura (formato EXIF obligatorio "yyyy:MM:dd HH:mm:ss")
        'DateTimeOriginal': DateFormat('yyyy:MM:dd HH:mm:ss').format(time.local),
        // Enlace de Maps también en metadatos: útil para software de auditoría.
        'ImageDescription':
            '${MapsLink.search(latitude, longitude)} | Código $verificationCode',
      });

      // Verificación en modo debug: releer y confirmar que quedó escrito.
      if (kDebugMode) {
        final ll = await exif.getLatLong();
        debugPrint('EXIF GPS -> ${ll?.latitude}, ${ll?.longitude}');
      }
    } finally {
      await exif.close();
    }
  }
}
