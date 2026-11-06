import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import '../../app_services.dart';
import '../../core/ui/glass.dart';
import '../capture/presentation/camera_screen.dart';
import '../capture/presentation/preview_screen.dart';
import '../reports/pdf_preview_screen.dart';
import '../share/share_service.dart';
import 'point_role_sheet.dart';
import 'segment.dart';

/// Levantamiento de un tramo: mapa con el trazado, estaciones cada N m,
/// distancias entre fotos, longitud total y área; reporte PDF/Word.
class SegmentDetailScreen extends StatefulWidget {
  const SegmentDetailScreen({super.key, required this.segmentId});
  final String segmentId;

  @override
  State<SegmentDetailScreen> createState() => _SegmentDetailScreenState();
}

class _SegmentDetailScreenState extends State<SegmentDetailScreen> {
  Segment? _s;
  SegmentGeometry? _g;
  final _map = MapController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = await services.segments.byId(widget.segmentId);
    if (s == null) return;
    final photos = await services.captures.bySegment(s.id);
    if (!mounted) return;
    setState(() {
      _s = s;
      _g = SegmentGeometry(photos, s.markIntervalM);
    });
  }

  Future<void> _takePhoto() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CameraScreen(
          controller: services.camera,
          templates: services.templates,
          segmentId: widget.segmentId,
        ),
      ),
    );
    await _load();
    // Si se marcó un punto "final", el tramo queda cerrado.
    final s = _s, g = _g;
    if (s != null && g != null && g.points.isNotEmpty && g.points.last.role == PointRole.fin && !s.closed) {
      s.closed = true;
      await services.segments.update(s);
      setState(() {});
    }
  }

  Future<void> _changeRole(StationPoint p) async {
    final role = await askPointRole(context);
    if (role == null) return;
    await services.captures.updatePointRole(p.photo.id, role);
    await _load();
  }

  Future<void> _report() async {
    final s = _s!, g = _g!;
    setState(() => _busy = true);
    try {
      final logo = await services.logo.bytes();
      final settings = services.settings.value;
      final bytes = await services.reports.segmentReport(segment: s, geo: g, settings: settings, logo: logo);
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PdfPreviewScreen(
            title: 'Tramo ${s.name}',
            fileName: 'Tramo_${s.name.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_')}.pdf',
            bytes: bytes,
            shareText: _summaryText(s, g),
            buildDocx: () => services.reports.segmentDocx(segment: s, geo: g, settings: settings, logo: logo),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Resumen corto para WhatsApp: largo, área y enlaces a inicio y final.
  static String _summaryText(Segment s, SegmentGeometry g) {
    final b = StringBuffer('🛣️ ${s.name}\n📏 ${g.length.toStringAsFixed(1)} m');
    if (s.widthM != null) b.write(' · ${(g.length * s.widthM!).toStringAsFixed(1)} m²');
    if (g.points.isNotEmpty) {
      final a = g.points.first.photo, z = g.points.last.photo;
      b.write('\nInicio: ${ShareService.shortMapsUrl(a.latitude, a.longitude)}');
      if (g.points.length > 1) b.write('\nFinal: ${ShareService.shortMapsUrl(z.latitude, z.longitude)}');
    }
    return b.toString();
  }

  @override
  Widget build(BuildContext context) {
    final s = _s, g = _g;
    if (s == null || g == null) {
      return const AuroraBackground(child: Scaffold(body: Center(child: CircularProgressIndicator())));
    }
    final bottom = MediaQuery.paddingOf(context).bottom;
    final pts = [for (final p in g.points) p.latLng];
    return AuroraBackground(
      child: Scaffold(
        appBar: AppBar(
          title: Text(s.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          actions: [
            IconButton(
              tooltip: 'Enviar resumen por WhatsApp',
              icon: const Icon(Icons.chat),
              onPressed: g.points.isEmpty ? null : () => ShareService.openWhatsAppText(_summaryText(s, g)),
            ),
            IconButton(
              tooltip: 'Reporte PDF / Word',
              icon: _busy
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.picture_as_pdf_outlined),
              onPressed: g.points.isEmpty || _busy ? null : _report,
            ),
          ],
        ),
        body: ListView(
          padding: EdgeInsets.fromLTRB(16, 0, 16, bottom + 110),
          children: [
            // Mapa del trazado
            GlassCard(
              padding: const EdgeInsets.all(6),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: SizedBox(
                  height: 300,
                  child: pts.isEmpty
                      ? const Center(
                          child: Text('Toma la primera foto en el inicio del tramo',
                              style: TextStyle(color: AppColors.textMuted)))
                      : FlutterMap(
                          mapController: _map,
                          options: MapOptions(
                            initialCenter: pts.first,
                            initialZoom: 18,
                            initialCameraFit: pts.length < 2
                                ? null
                                : CameraFit.bounds(
                                    bounds: LatLngBounds.fromPoints(pts),
                                    padding: const EdgeInsets.all(36),
                                    maxZoom: 19,
                                  ),
                          ),
                          children: [
                            TileLayer(
                              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                              userAgentPackageName: 'com.geomark.app',
                            ),
                            PolylineLayer(polylines: [
                              Polyline(points: pts, strokeWidth: 6, color: AppColors.violet.withValues(alpha: 0.85)),
                            ]),
                            // Estaciones cada N metros
                            MarkerLayer(markers: [
                              for (final m in g.marks)
                                Marker(
                                  point: m.position,
                                  width: 70,
                                  height: 22,
                                  child: Center(
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(color: AppColors.violet),
                                      ),
                                      child: Text(SegmentGeometry.station(m.station),
                                          style: const TextStyle(
                                              fontSize: 10, color: Colors.black, fontWeight: FontWeight.w700)),
                                    ),
                                  ),
                                ),
                            ]),
                            // Fotos (inicio verde, final rojo, intermedios azules)
                            MarkerLayer(markers: [
                              for (final (i, p) in g.points.indexed)
                                Marker(
                                  point: p.latLng,
                                  width: 30,
                                  height: 30,
                                  child: Container(
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: switch (p.role) {
                                        PointRole.inicio => AppColors.teal,
                                        PointRole.fin => AppColors.pink,
                                        PointRole.intermedio => AppColors.cyan,
                                      },
                                      border: Border.all(color: Colors.white, width: 2),
                                    ),
                                    child: Text('${i + 1}',
                                        style: const TextStyle(
                                            color: Colors.black, fontWeight: FontWeight.w800, fontSize: 12)),
                                  ),
                                ),
                            ]),
                            const SimpleAttributionWidget(source: Text('OpenStreetMap')),
                          ],
                        ),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Totales
            Row(children: [
              _Metric(value: '${g.length.toStringAsFixed(1)} m', label: 'Longitud'),
              const SizedBox(width: 10),
              _Metric(
                  value: s.widthM == null ? '—' : '${(g.length * s.widthM!).toStringAsFixed(1)} m²',
                  label: s.widthM == null ? 'Área (sin ancho)' : 'Área (ancho ${s.widthM} m)'),
              const SizedBox(width: 10),
              _Metric(value: '${g.points.length}', label: 'Fotos'),
            ]),
            if (g.points.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8, left: 4),
                child: Text(
                  'Precisión GPS del peor punto: ±${g.worstAccuracy.toStringAsFixed(0)} m. '
                  'Para medidas exactas, toma las fotos con el indicador GPS en verde.',
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                ),
              ),
            const SizedBox(height: 16),

            // Lista de puntos con estación
            for (final (i, p) in g.points.indexed)
              GlassCard(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(10),
                child: Row(children: [
                  GestureDetector(
                    onTap: () => Navigator.push(
                        context, MaterialPageRoute(builder: (_) => PreviewScreen(record: p.photo))),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.file(File(p.photo.filePath),
                          width: 62, height: 62, fit: BoxFit.cover, cacheWidth: 180),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${i + 1}. Est. ${SegmentGeometry.station(p.station)}',
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                      Text(
                        i == 0
                            ? 'Punto de partida'
                            : '+${p.partial.toStringAsFixed(1)} m desde el punto ${i}',
                        style: const TextStyle(color: AppColors.cyan, fontSize: 13),
                      ),
                      Text(
                        '${DateFormat('HH:mm').format(p.photo.time.local)} · ±${p.photo.accuracy.toStringAsFixed(0)} m'
                        '${p.photo.activity == null ? '' : ' · ${p.photo.activity}'}',
                        style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                      ),
                    ]),
                  ),
                  ActionChip(
                    label: Text(switch (p.role) {
                      PointRole.inicio => 'Inicio',
                      PointRole.fin => 'Final',
                      PointRole.intermedio => 'Intermedio',
                    }),
                    onPressed: () => _changeRole(p),
                  ),
                ]),
              ),
          ],
        ),
        bottomNavigationBar: Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, bottom + 12),
          child: GradientButton(
            label: g.points.isEmpty ? 'Foto de inicio del tramo' : (s.closed ? 'Agregar foto (tramo cerrado)' : 'Siguiente foto del tramo'),
            icon: Icons.add_a_photo,
            onPressed: _takePhoto,
          ),
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.value, required this.label});
  final String value, label;

  @override
  Widget build(BuildContext context) => Expanded(
        child: GlassCard(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(value, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
            Text(label, style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
          ]),
        ),
      );
}
