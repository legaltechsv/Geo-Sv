import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

/// Mini mapa del visor (norte siempre arriba):
///  - punto del usuario con flecha que gira según la brújula,
///  - cono de visión de ~50° y 60 m hacia donde apunta la cámara,
///  - indicador "N" para orientarse.
/// Va dentro de un RepaintBoundary para poder "fotografiarlo" al disparar
/// y estamparlo en la foto.
class LiveMiniMap extends StatefulWidget {
  const LiveMiniMap({
    super.key,
    required this.position,
    required this.heading,
    this.size = 140,
  });

  final Position? position;
  final double? heading;
  final double size;

  @override
  State<LiveMiniMap> createState() => _LiveMiniMapState();
}

class _LiveMiniMapState extends State<LiveMiniMap> {
  final _map = MapController();
  bool _ready = false;

  @override
  void didUpdateWidget(LiveMiniMap old) {
    super.didUpdateWidget(old);
    final p = widget.position;
    if (_ready && p != null && (old.position?.latitude != p.latitude || old.position?.longitude != p.longitude)) {
      _map.move(LatLng(p.latitude, p.longitude), _map.camera.zoom);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.position;
    final h = widget.heading;
    final s = widget.size;
    return Container(
      width: s,
      height: s,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white, width: 2.5),
        boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 10)],
        color: const Color(0xFF1B2333),
      ),
      clipBehavior: Clip.antiAlias,
      child: p == null
          ? const Center(
              child: Text('Buscando GPS…', style: TextStyle(color: Colors.white70, fontSize: 11)))
          : Stack(children: [
              FlutterMap(
                mapController: _map,
                options: MapOptions(
                  initialCenter: LatLng(p.latitude, p.longitude),
                  initialZoom: 17,
                  // Norte siempre arriba; sin gestos para no interferir con la cámara.
                  interactionOptions: const InteractionOptions(flags: InteractiveFlag.none),
                  onMapReady: () => _ready = true,
                ),
                children: [
                  TileLayer(
                    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.geomark.app',
                  ),
                  if (h != null)
                    PolygonLayer(polygons: [
                      Polygon(
                        points: _cone(LatLng(p.latitude, p.longitude), h),
                        color: const Color(0x5522D3EE),
                        borderColor: const Color(0xFF22D3EE),
                        borderStrokeWidth: 1.5,
                      ),
                    ]),
                  MarkerLayer(markers: [
                    Marker(
                      point: LatLng(p.latitude, p.longitude),
                      width: 28,
                      height: 28,
                      child: Transform.rotate(
                        angle: (h ?? 0) * math.pi / 180,
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white,
                            border: Border.all(color: const Color(0xFF2563EB), width: 2),
                          ),
                          child: Icon(h == null ? Icons.person_pin_circle : Icons.navigation,
                              size: 18, color: const Color(0xFF2563EB)),
                        ),
                      ),
                    ),
                  ]),
                ],
              ),
              // Indicador de Norte
              Positioned(
                top: 5,
                right: 5,
                child: Container(
                  width: 24,
                  height: 24,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                  child: const Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.arrow_drop_up, size: 14, color: Color(0xFFE53935)),
                    Text('N', style: TextStyle(fontSize: 8, height: 0.8, fontWeight: FontWeight.w900, color: Colors.black)),
                  ]),
                ),
              ),
            ]),
    );
  }

  static List<LatLng> _cone(LatLng c, double heading) {
    final d = Distance();
    return [
      c,
      for (var a = -25; a <= 25; a += 5) d.offset(c, 60, heading + a),
      c,
    ];
  }
}
