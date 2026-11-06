import 'package:geocoding/geocoding.dart';

/// Reverse geocoding: lat/lng -> "Calle, Colonia, Municipio, Depto., País".
///
/// Usa el geocoder nativo (Android Geocoder / iOS CLGeocoder): gratis y sin
/// API key, pero NECESITA internet. Offline devuelve null y el registro
/// queda marcado como "dirección pendiente" para el OfflineSyncService.
class GeocodingService {
  GeocodingService({String locale = 'es_SV'}) {
    setLocaleIdentifier(locale);
  }

  Future<String?> reverse(double lat, double lng) async {
    try {
      final places = await placemarkFromCoordinates(lat, lng)
          .timeout(const Duration(seconds: 4));
      if (places.isEmpty) return null;
      final p = places.first;
      final parts = <String?>[
        p.street,
        p.subLocality,
        p.locality,
        p.subAdministrativeArea,
        p.administrativeArea,
        p.country,
      ].whereType<String>().map((s) => s.trim()).where((s) => s.isNotEmpty);
      // toSet() elimina duplicados (a veces locality == subAdministrativeArea).
      final text = parts.toSet().join(', ');
      return text.isEmpty ? null : text;
    } catch (_) {
      return null; // offline, timeout o sin resultados
    }
  }
}
