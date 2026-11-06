import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app_services.dart';
import '../../../core/location/compass_service.dart';
import '../../../core/ui/glass.dart';
import '../../share/share_service.dart';
import '../domain/capture_record.dart';

/// Vista posterior al disparo: foto final, mapa con la dirección en que se
/// tomó (cono de visión) y botones para compartir.
class PreviewScreen extends StatelessWidget {
  PreviewScreen({super.key, required this.record, ShareService? share})
      : share = share ?? ShareService(); // inyectable para tests
  final CaptureRecord record;
  final ShareService share;

  Rect? _originOf(BuildContext ctx) {
    final box = ctx.findRenderObject() as RenderBox?;
    return box == null ? null : box.localToGlobal(Offset.zero) & box.size;
  }

  @override
  Widget build(BuildContext context) {
    final compact = services.settings.value.compactShare;
    final r = record;
    final bottom = MediaQuery.paddingOf(context).bottom;
    return AuroraBackground(
      child: Scaffold(
        appBar: AppBar(title: const Text('Evidencia', style: TextStyle(fontSize: 20))),
        body: ListView(
          padding: EdgeInsets.fromLTRB(16, 0, 16, bottom + 24),
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: InteractiveViewer(child: Image.file(File(r.filePath))),
            ),
            const SizedBox(height: 12),
            if (r.addressPending)
              const GlassCard(
                margin: EdgeInsets.only(bottom: 12),
                child: Row(children: [
                  Icon(Icons.cloud_off, color: AppColors.amber),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text('Sin conexión: la dirección se completará al recuperar internet. '
                        'El QR y el enlace ya funcionan.'),
                  ),
                ]),
              ),

            // Mapa con la dirección de la toma
            GlassCard(
              padding: const EdgeInsets.all(6),
              child: Column(children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: SizedBox(height: 210, child: _DirectionMap(record: r)),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
                  child: Row(children: [
                    const Icon(Icons.explore_outlined, color: AppColors.cyan, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        r.heading == null
                            ? 'Sin brújula: no se registró la dirección'
                            : 'Foto tomada hacia el ${CompassService.label(r.heading!)}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ]),
                ),
              ]),
            ),
            const SizedBox(height: 12),
            GlassCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (r.activity != null) _row(Icons.work_outline, r.activity!),
                _row(Icons.place_outlined, r.address ?? r.coordsText),
                _row(Icons.schedule, r.time.display),
                _row(Icons.gps_fixed, '±${r.accuracy.toStringAsFixed(0)} m · Código ${r.verificationCode}'),
              ]),
            ),
            const SizedBox(height: 16),

            // Compartir
            Builder(
              builder: (b) => _WhatsAppButton(
                label: 'Enviar foto por WhatsApp',
                onPressed: () => share.shareCapture(r, compact: compact, origin: _originOf(b)),
              ),
            ),
            const SizedBox(height: 10),
            _WhatsAppButton(
              label: 'Enviar solo ubicación',
              outlined: true,
              onPressed: () => share.whatsappLocation(r, compact: compact),
            ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.map),
                  label: const Text('Ver en Maps'),
                  onPressed: () => launchUrl(Uri.parse(r.mapsUrl), mode: LaunchMode.externalApplication),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.copy),
                  label: const Text('Copiar enlace'),
                  onPressed: () async {
                    await share.copyLink(r);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context)
                          .showSnackBar(const SnackBar(content: Text('Enlace copiado')));
                    }
                  },
                ),
              ),
            ]),
            const SizedBox(height: 14),
            // Vista previa exacta del mensaje que se enviará
            GlassCard(
              opacity: 0.04,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(compact ? 'Mensaje corto que se enviará' : 'Mensaje que se enviará',
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                const SizedBox(height: 6),
                SelectableText(ShareService.payload(r, compact: compact),
                    style: const TextStyle(fontSize: 13, height: 1.4)),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(IconData icon, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 18, color: AppColors.textMuted),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ]),
      );
}

/// Botón verde de WhatsApp (relleno o con borde).
class _WhatsAppButton extends StatelessWidget {
  const _WhatsAppButton({required this.label, required this.onPressed, this.outlined = false});
  final String label;
  final VoidCallback onPressed;
  final bool outlined;

  static const green = Color(0xFF25D366);

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 52,
        child: Material(
          color: outlined ? Colors.transparent : green,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: outlined ? const BorderSide(color: green, width: 1.5) : BorderSide.none,
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onPressed,
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.chat, color: outlined ? green : Colors.white),
              const SizedBox(width: 10),
              Text(label,
                  style: TextStyle(
                      color: outlined ? green : Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 15)),
            ]),
          ),
        ),
      );
}

/// Mini mapa: punto de la foto + cono que muestra hacia dónde se tomó.
class _DirectionMap extends StatelessWidget {
  const _DirectionMap({required this.record});
  final CaptureRecord record;

  @override
  Widget build(BuildContext context) {
    final here = LatLng(record.latitude, record.longitude);
    final h = record.heading;
    final dist = Distance();
    // Cono de ~50° de apertura y 60 m de alcance en la dirección de la toma.
    final cone = h == null
        ? null
        : [
            here,
            for (var a = -25; a <= 25; a += 5) dist.offset(here, 60, h + a),
            here,
          ];
    return FlutterMap(
      options: MapOptions(
        initialCenter: h == null ? here : dist.offset(here, 22, h),
        initialZoom: 17.5,
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.geomark.app',
        ),
        if (cone != null)
          PolygonLayer(polygons: [
            Polygon(
              points: cone,
              color: AppColors.cyan.withValues(alpha: 0.28),
              borderColor: AppColors.cyan,
              borderStrokeWidth: 1.5,
            ),
          ]),
        MarkerLayer(markers: [
          Marker(
            point: here,
            width: 40,
            height: 40,
            child: h == null
                ? const Icon(Icons.location_on, color: Colors.redAccent, size: 38)
                : Transform.rotate(
                    angle: h * math.pi / 180,
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white,
                        boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 6)],
                        border: Border.all(color: AppColors.cyan, width: 2),
                      ),
                      child: const Icon(Icons.navigation, color: Color(0xFF2563EB), size: 24),
                    ),
                  ),
          ),
        ]),
        const SimpleAttributionWidget(source: Text('OpenStreetMap')),
      ],
    );
  }
}
