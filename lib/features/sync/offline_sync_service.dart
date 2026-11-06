import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

import '../../core/geocoding/geocoding_service.dart';
import '../../core/time/trusted_time_service.dart';
import '../capture/data/capture_repository.dart';

/// Modo offline: cuando vuelve la red,
///   1. re-sincroniza la hora NTP,
///   2. completa la dirección de las capturas tomadas sin internet.
///
/// Decisión de diseño: la foto NO se vuelve a renderizar con la dirección.
/// La imagen es la evidencia y se mantiene tal cual se tomó (su SHA-256 no
/// cambia). La dirección nueva se usa en el texto al compartir.
class OfflineSyncService {
  OfflineSyncService({
    required this.repository,
    required this.geocoding,
    required this.time,
  });

  final CaptureRepository repository;
  final GeocodingService geocoding;
  final TrustedTimeService time;
  StreamSubscription<List<ConnectivityResult>>? _sub;
  bool _running = false;

  void start() {
    _sub ??= Connectivity().onConnectivityChanged.listen((results) {
      final online = results.any((r) => r != ConnectivityResult.none);
      if (online) unawaited(runOnce());
    });
    unawaited(runOnce()); // por si ya hay red al abrir la app
  }

  Future<void> runOnce() async {
    if (_running) return;
    _running = true;
    try {
      if (!time.isSynced) await time.sync();
      for (final r in await repository.pendingAddress()) {
        final address = await geocoding.reverse(r.latitude, r.longitude);
        if (address == null) break; // seguimos sin red real; reintentar luego
        await repository.updateAddress(r.id, address);
      }
    } finally {
      _running = false;
    }
  }

  Future<void> dispose() async => _sub?.cancel();
}
