import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_compass/flutter_compass.dart';

/// Brújula del teléfono (magnetómetro).
///
/// [heading] = grados respecto al Norte magnético hacia donde apunta la
/// parte superior del teléfono; con el teléfono vertical apuntando la
/// cámara, equivale a la dirección en la que se toma la foto.
/// Precisión típica ±5–15°; mejora calibrando (mover el teléfono en "8").
class CompassService {
  final ValueNotifier<double?> heading = ValueNotifier<double?>(null);
  StreamSubscription<CompassEvent>? _sub;

  /// false en teléfonos sin magnetómetro (algunos de gama baja).
  bool get available => FlutterCompass.events != null;

  void start() {
    _sub ??= FlutterCompass.events?.listen((e) {
      final h = e.heading;
      if (h != null) heading.value = (h + 360) % 360;
    });
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
  }

  /// 0° -> N, 45° -> NE, 90° -> E … (8 rumbos, en español).
  static String cardinal(double deg) {
    const names = ['N', 'NE', 'E', 'SE', 'S', 'SO', 'O', 'NO'];
    return names[((deg % 360) + 22.5) % 360 ~/ 45];
  }

  static String label(double deg) => '${deg.round()}° ${cardinal(deg)}';
}
