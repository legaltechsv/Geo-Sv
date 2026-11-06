import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../../core/geocoding/geocoding_service.dart';
import '../../../core/location/location_service.dart';
import '../../../core/permissions/permission_service.dart';
import '../../../core/time/trusted_time_service.dart';
import '../../templates/watermark_template.dart';
import '../../watermark/exif_writer.dart';
import '../../watermark/watermark_service.dart';
import '../data/capture_repository.dart';
import '../domain/capture_record.dart';

enum CaptureStatus { idle, initializing, ready, capturing, error }

class CaptureException implements Exception {
  CaptureException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Orquesta el flujo completo del obturador:
///
///   [disparo] ──┬── takePicture()          ┐ en PARALELO
///               └── getFixAtShutter() GPS  ┘
///        │
///        ├─ anti-mock (ubicación falsa => bloquea)
///        ├─ hora confiable (NTP > GPS > dispositivo)
///        ├─ reverse geocoding (si hay red; si no, queda pendiente)
///        ├─ marca de agua (texto + QR)  -> JPEG
///        ├─ EXIF GPS
///        ├─ SHA-256 del archivo final
///        └─ guardar en SQLite (offline-first)
class CaptureController extends ChangeNotifier {
  CaptureController({
    required this.permissions,
    required this.location,
    required this.time,
    required this.geocoding,
    required this.watermark,
    required this.exif,
    required this.repository,
  });

  final PermissionService permissions;
  final LocationService location;
  final TrustedTimeService time;
  final GeocodingService geocoding;
  final WatermarkService watermark;
  final ExifWriter exif;
  final CaptureRepository repository;

  CameraController? camera;
  CaptureStatus status = CaptureStatus.idle;
  String? errorMessage;
  PermissionOutcome? blockingPermission;

  ValueListenable<Position?> get livePosition => location.live;

  /// Dirección aproximada para la marca en vivo del visor.
  final ValueNotifier<String?> liveAddress = ValueNotifier<String?>(null);

  /// Última evidencia (miniatura de la galería en el visor).
  final ValueNotifier<CaptureRecord?> lastRecord = ValueNotifier<CaptureRecord?>(null);

  FlashMode flashMode = FlashMode.auto;

  Position? _lastGeocoded;
  DateTime _lastGeocodeAt = DateTime.fromMillisecondsSinceEpoch(0);
  bool _geocoding = false;

  /// Reverse geocoding "en vivo" con freno: solo si nos movimos > 25 m y
  /// pasaron > 10 s. Evita gastar datos y que el geocoder nos limite.
  Future<void> _onLivePosition() async {
    final p = location.live.value;
    if (p == null || _geocoding) return;
    final moved = _lastGeocoded == null ||
        Geolocator.distanceBetween(
                p.latitude, p.longitude, _lastGeocoded!.latitude, _lastGeocoded!.longitude) >
            25;
    if (!moved || DateTime.now().difference(_lastGeocodeAt).inSeconds < 10) return;
    _geocoding = true;
    _lastGeocodeAt = DateTime.now();
    try {
      final a = await geocoding.reverse(p.latitude, p.longitude);
      if (a != null) {
        liveAddress.value = a;
        _lastGeocoded = p;
      }
    } finally {
      _geocoding = false;
    }
  }

  /// Hora confiable para el reloj del visor (se refresca cada segundo en la UI).
  TrustedTime nowForPreview() => time.now(gnssTimestamp: location.live.value?.timestamp);

  /// Flash: automático -> encendido -> apagado.
  Future<void> cycleFlash() async {
    final next = switch (flashMode) {
      FlashMode.auto => FlashMode.always,
      FlashMode.always => FlashMode.off,
      _ => FlashMode.auto,
    };
    await camera?.setFlashMode(next);
    flashMode = next;
    notifyListeners();
  }

  Future<void> loadLastRecord() async {
    final all = await repository.all();
    lastRecord.value = all.isEmpty ? null : all.first;
  }

  // ───────────────────────── Inicialización ─────────────────────────

  Future<void> initialize() async {
    _set(CaptureStatus.initializing);

    final cam = await permissions.ensureCamera();
    if (cam != PermissionOutcome.granted) {
      blockingPermission = cam;
      return _fail('Se necesita acceso a la cámara para tomar evidencias.');
    }

    final loc = await permissions.ensureLocation();
    if (loc != PermissionOutcome.granted) {
      blockingPermission = loc;
      return _fail(switch (loc) {
        PermissionOutcome.serviceDisabled => 'Activa el GPS del teléfono.',
        PermissionOutcome.permanentlyDenied =>
          'El permiso de ubicación fue bloqueado. Actívalo en Ajustes (ubicación PRECISA).',
        _ => 'Se necesita la ubicación PRECISA: sin ella la foto no es evidencia.',
      });
    }
    blockingPermission = null;

    unawaited(time.sync()); // NTP en segundo plano; no bloquea el visor
    location.startWarmup(); // el GPS converge mientras el usuario encuadra
    location.live
      ..removeListener(_onLivePosition)
      ..addListener(_onLivePosition);
    unawaited(loadLastRecord());

    try {
      await _initCamera();
      _set(CaptureStatus.ready);
    } on CameraException catch (e) {
      _fail('No se pudo abrir la cámara: ${e.description ?? e.code}');
    }
  }

  Future<void> _initCamera() async {
    // Si quedó una cámara abierta (p. ej. se reabre el visor), liberarla.
    final old = camera;
    camera = null;
    await old?.dispose();
    final cams = await availableCameras();
    if (cams.isEmpty) throw CameraException('no_camera', 'Sin cámaras');
    final back = cams.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => cams.first,
    );
    final c = CameraController(
      back,
      ResolutionPreset.veryHigh, // ~1080p-4K según equipo; equilibrio calidad/peso
      enableAudio: false, // no pedimos micrófono
      imageFormatGroup: ImageFormatGroup.jpeg,
    );
    await c.initialize();
    await c.setFlashMode(flashMode);
    camera = c;
    notifyListeners();
  }

  /// Llamar desde AppLifecycleState.inactive: la cámara es un recurso
  /// exclusivo y el SO puede quitárnosla.
  Future<void> pause() async {
    final c = camera;
    camera = null;
    notifyListeners();
    await c?.dispose();
    await location.stopWarmup();
  }

  Future<void> resume() async {
    if (status == CaptureStatus.error) return initialize();
    if (camera != null) return;
    location.startWarmup();
    await _initCamera();
  }

  // ───────────────────────── Disparo ─────────────────────────

  Future<CaptureRecord> capture({
    WatermarkConfig config = const WatermarkConfig(),
    String? inspectionId,
    double? heading,
    Uint8List? logo,
    Uint8List? mapImage,
    Future<String?> Function()? askActivity,
    String? segmentId,
    Future<String?> Function()? askPointRole,
  }) async {
    final cam = camera;
    if (cam == null || !cam.value.isInitialized) {
      throw CaptureException('La cámara no está lista.');
    }
    if (status == CaptureStatus.capturing || cam.value.isTakingPicture) {
      throw CaptureException('Procesando la foto anterior…');
    }
    _set(CaptureStatus.capturing);

    XFile? rawShot;
    try {
      // 1. Foto y GPS SIMULTÁNEOS: el punto corresponde al instante real
      //    del obturador, no a "unos segundos después".
      final (XFile, GeoFix) result;
      try {
        result = await (cam.takePicture(), location.getFixAtShutter()).wait;
      } on ParallelWaitError<(XFile?, GeoFix?), (AsyncError?, AsyncError?)> catch (e) {
        final orphan = e.values.$1; // la foto salió pero el GPS no
        if (orphan != null) _safeDelete(orphan.path);
        throw CaptureException(e.errors.$2 != null
            ? 'No se obtuvo señal GPS a tiempo. Sal a cielo abierto e inténtalo de nuevo.'
            : 'No se pudo tomar la foto.');
      }
      final (shot, fix) = result;
      rawShot = shot;

      // 2. Proof of Work: rechazar apps de ubicación falsa.
      if (fix.isMocked) {
        throw CaptureException(
            'Se detectó una ubicación simulada. La captura fue bloqueada.');
      }

      // 2b. Preguntar la actividad. GPS y hora YA quedaron fijados en el
      //     disparo, así que el tiempo que tarde en responder no altera la
      //     evidencia. Se pregunta antes de estampar para incluirla en la foto.
      final rawActivity = askActivity == null ? null : await askActivity();
      final activity =
          (rawActivity == null || rawActivity.trim().isEmpty) ? null : rawActivity.trim();
      // En modo tramo: ¿inicio, intermedio o final?
      final pointRole = askPointRole == null ? null : await askPointRole();

      // 3. Hora confiable y datos derivados.
      final t = time.now(gnssTimestamp: fix.timestamp);
      final id = const Uuid().v4();
      final address = await geocoding.reverse(fix.latitude, fix.longitude);
      final code = _verificationCode(id, fix, t);

      // 4. Marca de agua (texto + QR) -> JPEG.
      final jpeg = await watermark.render(
        sourceJpeg: await shot.readAsBytes(),
        data: WatermarkData(
          latitude: fix.latitude,
          longitude: fix.longitude,
          accuracy: fix.accuracy,
          time: t,
          address: address,
          verificationCode: code,
          config: config,
          heading: heading,
          activity: activity,
          logo: logo,
          mapImage: mapImage,
        ),
      );

      // 5. Guardar en almacenamiento privado de la app (no en la galería
      //    pública, para que no se mezcle con fotos editables).
      final dir = await _capturesDir();
      final outPath = p.join(dir.path, 'GM_${t.fileStamp}_${id.substring(0, 8)}.jpg');
      await File(outPath).writeAsBytes(jpeg, flush: true);

      // 6. EXIF GPS sobre el archivo final.
      await exif.writeGps(
        jpegPath: outPath,
        latitude: fix.latitude,
        longitude: fix.longitude,
        time: t,
        verificationCode: code,
      );

      // 7. Huella del archivo final (después del EXIF).
      final fileHash = sha256.convert(await File(outPath).readAsBytes()).toString();

      final record = CaptureRecord(
        id: id,
        filePath: outPath,
        latitude: fix.latitude,
        longitude: fix.longitude,
        accuracy: fix.accuracy,
        altitude: fix.altitude,
        capturedAtUtc: t.utc,
        tzOffset: t.tzOffset,
        timeSource: t.source,
        address: address, // null => pendiente (offline)
        verificationCode: code,
        fileSha256: fileHash,
        inspectionId: inspectionId,
        heading: heading,
        activity: activity,
        segmentId: segmentId,
        pointRole: segmentId == null ? null : (pointRole ?? 'intermedio'),
      );
      await repository.insert(record);
      lastRecord.value = record;
      return record;
    } finally {
      if (rawShot != null) _safeDelete(rawShot.path); // la foto sin marca no se conserva
      if (status == CaptureStatus.capturing) _set(CaptureStatus.ready);
    }
  }

  // ───────────────────────── Utilidades ─────────────────────────

  /// Código corto de 12 caracteres impreso en la foto. Se deriva de los
  /// datos de captura: si alguien edita las coordenadas o la hora en la
  /// imagen, el código ya no corresponde al registro.
  String _verificationCode(String id, GeoFix f, TrustedTime t) {
    final payload = '$id|${f.latitude.toStringAsFixed(6)}|'
        '${f.longitude.toStringAsFixed(6)}|${t.utc.toIso8601String()}|${t.source.name}';
    return sha256.convert(utf8.encode(payload)).toString().substring(0, 12).toUpperCase();
  }

  Future<Directory> _capturesDir() async {
    final base = await getApplicationDocumentsDirectory();
    return Directory(p.join(base.path, 'captures')).create(recursive: true);
  }

  void _safeDelete(String path) {
    File(path).delete().then((_) {}, onError: (_) {});
  }

  void _set(CaptureStatus s) {
    status = s;
    if (s != CaptureStatus.error) errorMessage = null;
    notifyListeners();
  }

  void _fail(String msg) {
    errorMessage = msg;
    status = CaptureStatus.error;
    notifyListeners();
  }

  @override
  void dispose() {
    camera?.dispose();
    location.live.removeListener(_onLivePosition);
    location.dispose();
    liveAddress.dispose();
    lastRecord.dispose();
    super.dispose();
  }
}
