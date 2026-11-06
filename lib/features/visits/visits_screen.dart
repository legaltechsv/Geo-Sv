import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app_services.dart';
import '../../core/ui/glass.dart';
import '../../core/utils/maps_link.dart';
import '../inspections/domain/inspection.dart';
import '../inspections/presentation/inspection_detail_screen.dart';
import '../reports/pdf_preview_screen.dart';
import 'visits_service.dart';

/// Reporte de lugares visitados: mapa con todos los puntos + lista por lugar
/// (visitas, fotos, tiempo en sitio, última visita) y exportación a PDF.
class VisitsScreen extends StatefulWidget {
  const VisitsScreen({super.key, required this.refresh});
  final ValueNotifier<int> refresh;

  @override
  State<VisitsScreen> createState() => _VisitsScreenState();
}

class _VisitsScreenState extends State<VisitsScreen> {
  VisitRange _range = VisitRange.mes;
  late Future<List<VisitedPlace>> _data = services.visits.places(_range);
  final _map = MapController();
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    widget.refresh.addListener(_reload);
  }

  @override
  void dispose() {
    widget.refresh.removeListener(_reload);
    super.dispose();
  }

  void _reload() => setState(() => _data = services.visits.places(_range));

  Future<void> _export(List<VisitedPlace> places) async {
    setState(() => _exporting = true);
    try {
      final logo = await services.logo.bytes();
      final range = _range;
      final bytes = await services.reports.visitsReport(
        places: places,
        range: range,
        settings: services.settings.value,
        logo: logo,
      );
      if (!mounted) return;
      final stamp = DateFormat('yyyyMMdd').format(DateTime.now());
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PdfPreviewScreen(
            title: 'Lugares visitados',
            fileName: 'Visitas_${_range.label.replaceAll(' ', '')}_$stamp.pdf',
            bytes: bytes,
            shareText: 'Reporte de lugares visitados · ${range.label}',
            buildDocx: () => services.reports.visitsDocx(
              places: places,
              range: range,
              settings: services.settings.value,
              logo: logo,
            ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  void _focus(VisitedPlace p) =>
      _map.move(LatLng(p.latitude, p.longitude), 16);

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return FutureBuilder<List<VisitedPlace>>(
      future: _data,
      builder: (context, snap) {
        final places = snap.data ?? const <VisitedPlace>[];
        final visits = places.fold<int>(0, (a, p) => a + p.visits.length);
        final photos = places.fold<int>(0, (a, p) => a + p.photos.length);
        final time = places.fold<Duration>(Duration.zero, (a, p) => a + p.totalTime);

        return ListView(
          padding: EdgeInsets.fromLTRB(18, top + 14, 18, 130),
          children: [
            Row(children: [
              const Expanded(
                child: Text('Lugares visitados',
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
              ),
              IconButton.filledTonal(
                tooltip: 'Exportar PDF',
                onPressed: places.isEmpty || _exporting ? null : () => _export(places),
                icon: _exporting
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.picture_as_pdf_outlined),
              ),
            ]),
            const SizedBox(height: 12),
            SegmentedButton<VisitRange>(
              segments: [
                for (final r in VisitRange.values) ButtonSegment(value: r, label: Text(r.label)),
              ],
              selected: {_range},
              showSelectedIcon: false,
              onSelectionChanged: (s) {
                _range = s.first;
                _reload();
              },
            ),
            const SizedBox(height: 14),

            // Mapa en tarjeta de vidrio
            GlassCard(
              padding: const EdgeInsets.all(6),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: SizedBox(
                  height: 260,
                  child: places.isEmpty
                      ? const Center(
                          child: Text('Sin visitas en este periodo',
                              style: TextStyle(color: AppColors.textMuted)))
                      : _VisitsMap(controller: _map, places: places),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(children: [
              _Stat('${places.length}', 'Lugares'),
              _Stat('$visits', 'Visitas'),
              _Stat('$photos', 'Fotos'),
              _Stat(time.inHours > 0 ? '${time.inHours} h' : '${time.inMinutes} m', 'En sitio'),
            ]),
            const SizedBox(height: 18),
            for (final (n, p) in places.indexed)
              FadeSlideIn(
                index: n.clamp(0, 8),
                child: _PlaceCard(place: p, number: n + 1, onFocus: () => _focus(p), onChanged: _reload),
              ),
          ],
        );
      },
    );
  }
}

class _VisitsMap extends StatelessWidget {
  const _VisitsMap({required this.controller, required this.places});
  final MapController controller;
  final List<VisitedPlace> places;

  @override
  Widget build(BuildContext context) {
    final points = [for (final p in places) LatLng(p.latitude, p.longitude)];
    final single = points.length == 1;
    return FlutterMap(
      mapController: controller,
      options: MapOptions(
        initialCenter: points.first,
        initialZoom: 15,
        initialCameraFit: single
            ? null
            : CameraFit.bounds(
                bounds: LatLngBounds.fromPoints(points),
                padding: const EdgeInsets.all(40),
                maxZoom: 16,
              ),
      ),
      children: [
        // OpenStreetMap: gratuito y sin API key. Para uso intensivo en
        // producción, usar un proveedor de teselas con plan (MapTiler, etc.).
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.geomark.app',
        ),
        MarkerLayer(markers: [
          for (final (n, p) in places.indexed)
            Marker(
              point: LatLng(p.latitude, p.longitude),
              width: 34,
              height: 34,
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: AppColors.accentGradient,
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 6)],
                ),
                alignment: Alignment.center,
                child: Text('${n + 1}',
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
              ),
            ),
        ]),
        const SimpleAttributionWidget(source: Text('OpenStreetMap')),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.value, this.label);
  final String value, label;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(children: [
          Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          Text(label, style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
        ]),
      );
}

class _PlaceCard extends StatelessWidget {
  const _PlaceCard({
    required this.place,
    required this.number,
    required this.onFocus,
    required this.onChanged,
  });
  final VisitedPlace place;
  final int number;
  final VoidCallback onFocus;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('dd/MM/yy HH:mm');
    final t = place.totalTime;
    return GlassCard(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
      onTap: onFocus,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: const BoxDecoration(shape: BoxShape.circle, gradient: AppColors.accentGradient),
            child: Text('$number', style: const TextStyle(fontWeight: FontWeight.w800)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(place.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              Text(place.address ?? MapsLink.coordsText(place.latitude, place.longitude),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
            ]),
          ),
          IconButton(
            tooltip: 'Cómo llegar',
            icon: const Icon(Icons.directions, color: AppColors.cyan),
            onPressed: () => launchUrl(
              Uri.parse(MapsLink.directions(place.latitude, place.longitude)),
              mode: LaunchMode.externalApplication,
            ),
          ),
        ]),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, children: [
          StatusPill(label: '${place.visits.length} visitas', color: AppColors.cyan, icon: Icons.event_available),
          StatusPill(label: '${place.photos.length} fotos', color: AppColors.teal, icon: Icons.photo),
          if (t > Duration.zero)
            StatusPill(
                label: t.inHours > 0 ? '${t.inHours} h ${t.inMinutes % 60} m' : '${t.inMinutes} min',
                color: AppColors.violet,
                icon: Icons.timer_outlined),
        ]),
        const SizedBox(height: 6),
        Text('Última visita: ${fmt.format(place.lastVisit.toLocal())}',
            style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
        // Detalle de cada visita (inspección) en este lugar
        for (final v in place.visits)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.circle, size: 10, color: v.status.color),
            title: Text('${v.folio} · ${fmt.format(v.startedAtUtc.toLocal())}'),
            subtitle: Text('${v.status.label}${v.attendedBy.isEmpty ? '' : ' · ${v.attendedBy}'}'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              await Navigator.push(context,
                  MaterialPageRoute(builder: (_) => InspectionDetailScreen(inspectionId: v.id)));
              onChanged();
            },
          ),
      ]),
    );
  }
}
