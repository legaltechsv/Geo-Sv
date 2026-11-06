import '../../../core/time/trusted_time_service.dart';
import '../../../core/utils/maps_link.dart';

/// Una evidencia fotográfica. Los campos de captura son inmutables;
/// solo [address] puede completarse después (modo offline).
class CaptureRecord {
  CaptureRecord({
    required this.id,
    required this.filePath,
    required this.latitude,
    required this.longitude,
    required this.accuracy,
    required this.altitude,
    required this.capturedAtUtc,
    required this.tzOffset,
    required this.timeSource,
    required this.address,
    required this.verificationCode,
    required this.fileSha256,
    this.inspectionId,
    this.heading,
    this.activity,
    this.segmentId,
    this.pointRole,
  });

  final String id;
  final String filePath;
  final double latitude;
  final double longitude;
  final double accuracy;
  final double altitude;
  final DateTime capturedAtUtc;
  final Duration tzOffset;
  final TimeSource timeSource;

  /// null = se capturó sin internet y falta el reverse geocoding.
  final String? address;

  /// Huella corta impresa en la foto (ver CaptureController._verificationCode).
  final String verificationCode;

  /// SHA-256 del .jpg final: si alguien edita la foto, ya no coincide.
  final String fileSha256;

  /// Inspección a la que pertenece la foto (null = foto suelta).
  final String? inspectionId;

  /// Rumbo de la cámara en grados (0 = Norte, 90 = Este). null si el
  /// teléfono no tiene brújula.
  final double? heading;

  /// Actividad que el usuario indicó después de tomar la foto.
  final String? activity;

  /// Tramo de calle al que pertenece y rol del punto ('inicio',
  /// 'intermedio', 'final').
  final String? segmentId;
  final String? pointRole;

  bool get addressPending => address == null;
  String get mapsUrl => MapsLink.search(latitude, longitude);
  String get directionsUrl => MapsLink.directions(latitude, longitude);
  String get coordsText => MapsLink.coordsText(latitude, longitude);
  TrustedTime get time => TrustedTime(capturedAtUtc, timeSource, tzOffset);

  CaptureRecord copyWith({String? address}) => CaptureRecord(
        id: id,
        filePath: filePath,
        latitude: latitude,
        longitude: longitude,
        accuracy: accuracy,
        altitude: altitude,
        capturedAtUtc: capturedAtUtc,
        tzOffset: tzOffset,
        timeSource: timeSource,
        address: address ?? this.address,
        verificationCode: verificationCode,
        fileSha256: fileSha256,
        inspectionId: inspectionId,
        heading: heading,
        activity: activity,
        segmentId: segmentId,
        pointRole: pointRole,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'file_path': filePath,
        'lat': latitude,
        'lng': longitude,
        'accuracy': accuracy,
        'altitude': altitude,
        'captured_at_utc': capturedAtUtc.toIso8601String(),
        'tz_offset_min': tzOffset.inMinutes,
        'time_source': timeSource.name,
        'address': address,
        'address_pending': addressPending ? 1 : 0,
        'verification_code': verificationCode,
        'file_sha256': fileSha256,
        'inspection_id': inspectionId,
        'heading': heading,
        'activity': activity,
        'segment_id': segmentId,
        'point_role': pointRole,
      };

  factory CaptureRecord.fromMap(Map<String, Object?> m) => CaptureRecord(
        id: m['id']! as String,
        filePath: m['file_path']! as String,
        latitude: (m['lat']! as num).toDouble(),
        longitude: (m['lng']! as num).toDouble(),
        accuracy: (m['accuracy']! as num).toDouble(),
        altitude: (m['altitude'] as num?)?.toDouble() ?? 0,
        capturedAtUtc: DateTime.parse(m['captured_at_utc']! as String).toUtc(),
        tzOffset: Duration(minutes: m['tz_offset_min']! as int),
        timeSource: TimeSource.values.byName(m['time_source']! as String),
        address: m['address'] as String?,
        verificationCode: m['verification_code']! as String,
        fileSha256: m['file_sha256']! as String,
        inspectionId: m['inspection_id'] as String?,
        heading: (m['heading'] as num?)?.toDouble(),
        activity: m['activity'] as String?,
        segmentId: m['segment_id'] as String?,
        pointRole: m['point_role'] as String?,
      );
}
