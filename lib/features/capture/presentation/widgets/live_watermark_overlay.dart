import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../../core/time/trusted_time_service.dart';
import '../../../../core/utils/maps_link.dart';
import '../../../templates/watermark_template.dart';

/// Marca de agua "en vivo" sobre el visor (lo más característico de
/// Timemark): el reloj avanza cada segundo y las coordenadas se actualizan
/// con el GPS. Replica el layout de WatermarkService, así lo que se ve es
/// lo que queda estampado. Tocarla abre el editor de plantilla.
class LiveWatermarkOverlay extends StatefulWidget {
  const LiveWatermarkOverlay({
    super.key,
    required this.config,
    required this.position,
    required this.address,
    required this.clock,
    this.onTap,
    this.compact = false,
  });

  final WatermarkConfig config;
  final Position? position;
  final String? address;

  /// Fuente de hora confiable (NTP/GPS/dispositivo).
  final TrustedTime Function() clock;
  final VoidCallback? onTap;

  /// Versión reducida para las miniaturas del selector de plantillas.
  final bool compact;

  @override
  State<LiveWatermarkOverlay> createState() => _LiveWatermarkOverlayState();
}

class _LiveWatermarkOverlayState extends State<LiveWatermarkOverlay> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    if (!widget.compact) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  static const _days = ['lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado', 'domingo'];

  @override
  Widget build(BuildContext context) {
    final cfg = widget.config;
    final style = cfg.style;
    final minimal = style == WatermarkStyle.minimo;
    final t = widget.clock();
    final p = widget.position;
    final scale = widget.compact ? 0.45 : 1.0;
    final showHeader = cfg.hasProject || style == WatermarkStyle.obra;

    final small = TextStyle(
      color: Colors.white,
      fontSize: 12 * scale,
      height: 1.35,
      fontWeight: FontWeight.w500,
      shadows: const [Shadow(blurRadius: 2, color: Colors.black54)],
    );

    final lines = <String>[
      p == null ? 'Buscando GPS…' : MapsLink.coordsText(p.latitude, p.longitude),
      if (cfg.showAccuracy && !minimal && p != null)
        'Precisión GPS: ±${p.accuracy.toStringAsFixed(0)} m',
      if (cfg.showAddress && !minimal)
        widget.address ?? 'Obteniendo dirección…',
      if (cfg.hasNote && !minimal) 'Nota: ${cfg.note.trim()}',
      if (!minimal) '${t.tzLabel} · ${t.source.label}',
    ];

    final card = ClipRRect(
      borderRadius: BorderRadius.circular(10 * scale),
      child: Container(
        color: Colors.black.withValues(alpha: 0.55),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showHeader)
              Container(
                color: style == WatermarkStyle.obra
                    ? style.accent
                    : style.accent.withValues(alpha: 0.85),
                padding: EdgeInsets.symmetric(horizontal: 10 * scale, vertical: 5 * scale),
                child: Text(
                  cfg.hasProject ? cfg.projectName.trim().toUpperCase() : 'REGISTRO DE OBRA',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: style == WatermarkStyle.obra ? Colors.black : Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 13 * scale,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            Padding(
              padding: EdgeInsets.all(10 * scale),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (!minimal)
                    Container(
                      width: 3.5 * scale,
                      height: 74 * scale,
                      margin: EdgeInsets.only(right: 9 * scale),
                      color: style.accent,
                    ),
                  Flexible(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          DateFormat('HH:mm').format(t.local),
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: (minimal ? 30 : 40) * scale,
                            fontWeight: FontWeight.w800,
                            height: 1.0,
                          ),
                        ),
                        Text(
                          '${DateFormat('dd/MM/yyyy').format(t.local)}  ${_days[t.local.weekday - 1]}',
                          style: small.copyWith(
                              fontSize: 13 * scale, fontWeight: FontWeight.w600),
                        ),
                        SizedBox(height: 4 * scale),
                        Text(lines.join('\n'),
                            style: small, maxLines: 6, overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                  SizedBox(width: 10 * scale),
                  // QR de muestra (en la foto final se genera con el punto exacto)
                  Container(
                    padding: EdgeInsets.all(3 * scale),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(4 * scale),
                    ),
                    child: QrImageView(
                      data: p == null
                          ? 'https://www.google.com/maps'
                          : MapsLink.search(p.latitude, p.longitude),
                      size: 64 * scale,
                      padding: EdgeInsets.zero,
                      errorCorrectionLevel: QrErrorCorrectLevel.M,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    return GestureDetector(
      onTap: widget.onTap,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 360 * scale),
        child: card,
      ),
    );
  }
}
