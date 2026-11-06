/// Construcción de enlaces universales de Google Maps.
///
/// Se usa la "Maps URLs API" (https://www.google.com/maps/...?api=1):
/// - En Android/iOS con Google Maps instalado, el SO abre la app directamente.
/// - Sin la app, abre Google Maps en el navegador.
/// - No requiere API key y funciona igual dentro de un QR.
class MapsLink {
  MapsLink._();

  /// 6 decimales ≈ 11 cm de resolución; más decimales no aportan precisión real.
  static String _c(double v) => v.toStringAsFixed(6);

  /// Pin en el punto exacto (este es el que va dentro del QR).
  static String search(double lat, double lng) =>
      'https://www.google.com/maps/search/?api=1&query=${_c(lat)},${_c(lng)}';

  /// Ruta "Cómo llegar" desde la ubicación actual del receptor.
  static String directions(double lat, double lng) =>
      'https://www.google.com/maps/dir/?api=1&destination=${_c(lat)},${_c(lng)}';

  /// Texto legible "13.698765, -89.191234".
  static String coordsText(double lat, double lng) => '${_c(lat)}, ${_c(lng)}';
}
