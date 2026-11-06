import 'package:intl/intl.dart';
import 'package:ntp/ntp.dart';

/// De dónde salió la hora estampada en la foto.
enum TimeSource { ntp, gnss, device }

extension TimeSourceLabel on TimeSource {
  String get label => switch (this) {
        TimeSource.ntp => 'Hora de red (NTP)',
        TimeSource.gnss => 'Hora GPS',
        TimeSource.device => 'Hora del dispositivo',
      };
}

class TrustedTime {
  TrustedTime(this.utc, this.source, this.tzOffset);

  final DateTime utc;
  final TimeSource source;

  /// Zona horaria del dispositivo al capturar (ej. -06:00 en El Salvador).
  final Duration tzOffset;

  DateTime get local => utc.add(tzOffset);

  String get tzLabel {
    final sign = tzOffset.isNegative ? '-' : '+';
    final m = tzOffset.inMinutes.abs();
    return 'UTC$sign${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';
  }

  String get display => '${DateFormat('dd/MM/yyyy HH:mm:ss').format(local)} ($tzLabel)';
  String get fileStamp => DateFormat('yyyyMMdd_HHmmss').format(local);
}

/// Hora "de red" resistente a que el usuario cambie el reloj del teléfono.
///
/// Truco: al sincronizar guardamos la hora NTP + un [Stopwatch] (reloj
/// monotónico). Después, hora = NTP_sync + tiempo transcurrido. Si el
/// usuario adelanta/atrasa el reloj del sistema, el Stopwatch no cambia.
class TrustedTimeService {
  DateTime? _ntpAtSync;
  final Stopwatch _sinceSync = Stopwatch();

  bool get isSynced => _ntpAtSync != null;

  /// Llamar al iniciar y al recuperar conexión. Falla en silencio si offline.
  Future<void> sync() async {
    try {
      final offsetMs = await NTP.getNtpOffset(
        lookUpAddress: 'time.google.com',
        timeout: const Duration(seconds: 3),
      );
      _ntpAtSync = DateTime.now().toUtc().add(Duration(milliseconds: offsetMs));
      _sinceSync
        ..reset()
        ..start();
    } catch (_) {
      // Sin red: se usará la hora GPS o la del dispositivo (y se etiqueta).
    }
  }

  /// Prioridad: NTP > hora del fix GPS > reloj del dispositivo.
  TrustedTime now({DateTime? gnssTimestamp}) {
    final tz = DateTime.now().timeZoneOffset;
    final ntpBase = _ntpAtSync;
    if (ntpBase != null) {
      return TrustedTime(ntpBase.add(_sinceSync.elapsed), TimeSource.ntp, tz);
    }
    if (gnssTimestamp != null) {
      return TrustedTime(gnssTimestamp.toUtc(), TimeSource.gnss, tz);
    }
    return TrustedTime(DateTime.now().toUtc(), TimeSource.device, tz);
  }
}
