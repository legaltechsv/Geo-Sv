import 'dart:convert';
import 'dart:math' as math;

import 'package:geocoding/geocoding.dart';
import 'package:http/http.dart' as http;

/// Resultado de la detección de calles alrededor de un punto.
class StreetGuess {
  StreetGuess({required this.main, required this.cross, this.area});

  /// Calle más cercana al punto.
  final String? main;

  /// Otras calles a menos de ~40 m (posibles intersecciones), de la más
  /// cercana a la más lejana.
  final List<String> cross;

  /// Barrio / colonia y municipio (ej. "Barrio San José, Cojutepeque").
  final String? area;

  bool get isEmpty => main == null && area == null;

  /// Sugerencias para el nombre del tramo, de la más útil a la más simple.
  List<String> suggestions() {
    final out = <String>[];
    final m = main;
    if (m != null) {
      if (cross.length >= 2) out.add('$m entre ${cross[0]} y ${cross[1]}');
      if (cross.isNotEmpty) out.add('$m y ${cross[0]} (intersección)');
      out.add(area == null ? m : '$m, $area');
      out.add(m);
    } else if (area != null) {
      out.add(area!);
    }
    return out.toSet().toList();
  }
}

/// Detecta la calle donde está el usuario y las calles que la cruzan.
///
/// 1. OpenStreetMap (Overpass): calles con nombre a menos de 40 m, ordenadas
///    por distancia real al punto → calle principal + intersecciones.
///    En El Salvador OSM suele tener mejores nombres de calles que el
///    geocoder del teléfono (que muchas veces solo da un "Plus Code").
/// 2. Geocoder del teléfono: barrio/colonia y municipio, y la calle si OSM
///    no respondió.
/// Todo es "mejor esfuerzo": sin internet devuelve lo que pueda.
class StreetDetector {
  static const _radius = 40; // metros

  Future<StreetGuess> detect(double lat, double lng) async {
    final results = await Future.wait([
      _osmStreets(lat, lng).catchError((_) => <String>[]),
      _placemark(lat, lng).catchError((_) => null),
    ]);
    final streets = results[0] as List<String>;
    final pm = results[1] as Placemark?;

    String? clean(String? s) {
      final t = s?.trim() ?? '';
      if (t.isEmpty || t.contains('+') || RegExp(r'^\d+$').hasMatch(t) || t == 'Unnamed Road') return null;
      return t;
    }

    final phoneStreet = clean(pm?.thoroughfare) ?? clean(pm?.street);
    final main = streets.isNotEmpty ? streets.first : phoneStreet;
    final cross = streets.where((s) => s != main).take(2).toList();
    final areaParts = <String>{
      if (clean(pm?.subLocality) != null) clean(pm?.subLocality)!,
      if (clean(pm?.locality) != null) clean(pm?.locality)!,
    }.where((p) => p != main).toList();
    return StreetGuess(
      main: main,
      cross: cross,
      area: areaParts.isEmpty ? null : areaParts.join(', '),
    );
  }

  Future<Placemark?> _placemark(double lat, double lng) async {
    final list = await placemarkFromCoordinates(lat, lng).timeout(const Duration(seconds: 5));
    return list.isEmpty ? null : list.first;
  }

  /// Calles con nombre cerca del punto, ordenadas por distancia.
  Future<List<String>> _osmStreets(double lat, double lng) async {
    final query = '[out:json][timeout:10];'
        'way(around:$_radius,$lat,$lng)[highway][name];'
        'out tags geom;';
    final res = await http
        .post(
          Uri.parse('https://overpass-api.de/api/interpreter'),
          headers: {'User-Agent': 'GEO-CUSCA-SUR/1.0 (app de evidencia en campo)'},
          body: {'data': query},
        )
        .timeout(const Duration(seconds: 12));
    if (res.statusCode != 200) return [];
    final data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final best = <String, double>{};
    for (final e in (data['elements'] as List? ?? const [])) {
      final m = e as Map<String, dynamic>;
      final name = (m['tags'] as Map?)?['name'] as String?;
      final geom = m['geometry'] as List?;
      if (name == null || geom == null || geom.length < 2) continue;
      var d = double.infinity;
      for (var i = 1; i < geom.length; i++) {
        final a = geom[i - 1] as Map, b = geom[i] as Map;
        d = math.min(
            d,
            _distToSegment(lat, lng, (a['lat'] as num).toDouble(), (a['lon'] as num).toDouble(),
                (b['lat'] as num).toDouble(), (b['lon'] as num).toDouble()));
      }
      if (d < (best[name] ?? double.infinity)) best[name] = d;
    }
    final names = best.keys.toList()..sort((x, y) => best[x]!.compareTo(best[y]!));
    return names;
  }

  /// Distancia (m) del punto P al segmento AB, en proyección local plana
  /// (precisa a estas distancias cortas).
  static double _distToSegment(double pLat, double pLng, double aLat, double aLng, double bLat, double bLng) {
    const mPerDegLat = 111320.0;
    final mPerDegLng = 111320.0 * math.cos(pLat * math.pi / 180);
    final ax = (aLng - pLng) * mPerDegLng, ay = (aLat - pLat) * mPerDegLat;
    final bx = (bLng - pLng) * mPerDegLng, by = (bLat - pLat) * mPerDegLat;
    final dx = bx - ax, dy = by - ay;
    final len2 = dx * dx + dy * dy;
    var t = len2 == 0 ? 0.0 : -(ax * dx + ay * dy) / len2;
    t = t.clamp(0.0, 1.0);
    final cx = ax + t * dx, cy = ay + t * dy;
    return math.sqrt(cx * cx + cy * cy);
  }
}
