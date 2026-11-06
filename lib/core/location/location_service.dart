import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

/// Lectura GPS inmutable tomada en el instante del obturador.
@immutable
class GeoFix {
  const GeoFix({
    required this.latitude,
    required this.longitude,
    required this.accuracy,
    required this.altitude,
    required this.timestamp,
    required this.isMocked,
  });

  factory GeoFix.fromPosition(Position p) => GeoFix(
        latitude: p.latitude,
        longitude: p.longitude,
        accuracy: p.accuracy,
        altitude: p.altitude,
        timestamp: p.timestamp.toUtc(),
        isMocked: p.isMocked,
      );

  final double latitude;
  final double longitude;

  /// Radio de error horizontal en metros (68 % de confianza).
  final double accuracy;
  final double altitude;

  /// Hora del fix entregada por el proveedor de ubicación.
  final DateTime timestamp;

  /// true si Android detecta una app de "ubicación falsa" (mock).
  final bool isMocked;
}

/// GPS de alta precisión con "precalentamiento".
///
/// Problema: un `getCurrentPosition` en frío puede tardar 5-30 s o devolver
/// un punto impreciso. Solución: mientras el visor de cámara está abierto
/// mantenemos un stream activo (el chip GPS converge) y, al presionar el
/// obturador, forzamos una lectura NUEVA y nos quedamos con la mejor.
class LocationService {
  StreamSubscription<Position>? _warmup;

  /// Última posición del stream; la UI la escucha para mostrar "±5 m".
  final ValueNotifier<Position?> live = ValueNotifier<Position?>(null);

  LocationSettings _settings({Duration? timeLimit}) {
    if (Platform.isAndroid) {
      return AndroidSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 0,
        intervalDuration: const Duration(seconds: 1),
        timeLimit: timeLimit,
      );
    }
    if (Platform.isIOS) {
      return AppleSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 0,
        activityType: ActivityType.other,
        pauseLocationUpdatesAutomatically: false,
        timeLimit: timeLimit,
      );
    }
    return LocationSettings(
      accuracy: LocationAccuracy.best,
      timeLimit: timeLimit,
    );
  }

  /// Arranca el stream al abrir el visor.
  void startWarmup() {
    _warmup ??= Geolocator.getPositionStream(locationSettings: _settings())
        .listen((p) => live.value = p, onError: (_) {});
  }

  Future<void> stopWarmup() async {
    await _warmup?.cancel();
    _warmup = null;
  }

  /// Lectura forzada en el momento del disparo.
  ///
  /// 1. Pide una posición nueva (no cacheada) con timeout.
  /// 2. Si el stream tiene una muestra MÁS precisa de hace < [maxAge],
  ///    usa esa (el usuario no se ha movido en ese lapso).
  /// 3. Si la lectura nueva expira, cae a la muestra del stream solo si
  ///    es reciente; si no, lanza error: sin GPS no hay evidencia.
  Future<GeoFix> getFixAtShutter({
    Duration timeout = const Duration(seconds: 8),
    Duration maxAge = const Duration(seconds: 3),
  }) async {
    final cached = live.value;
    bool isFresh(Position p) =>
        DateTime.now().toUtc().difference(p.timestamp.toUtc()).abs() < maxAge;

    try {
      final fresh = await Geolocator.getCurrentPosition(
        locationSettings: _settings(timeLimit: timeout),
      );
      if (cached != null && isFresh(cached) && cached.accuracy < fresh.accuracy) {
        return GeoFix.fromPosition(cached);
      }
      return GeoFix.fromPosition(fresh);
    } on TimeoutException {
      if (cached != null &&
          DateTime.now().toUtc().difference(cached.timestamp.toUtc()) <
              const Duration(seconds: 15)) {
        return GeoFix.fromPosition(cached);
      }
      rethrow;
    }
  }

  void dispose() {
    stopWarmup();
    live.dispose();
  }
}
