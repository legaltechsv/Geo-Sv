import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../../core/ui/glass.dart';
import '../../../templates/watermark_template.dart';

/// Configuración global de la toma: tamaño y transparencia de cada elemento
/// (panel de datos, mini mapa, logotipo y brújula).
///
/// La hoja es baja y sin oscurecer el fondo, para ver el efecto EN VIVO en
/// el visor mientras se mueven los controles. Se guarda automáticamente y
/// aplica igual en la pantalla y en la foto final.
Future<void> showLookSheet(BuildContext context, {required TemplateController templates}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.transparent,
    builder: (ctx) => ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.55),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            color: const Color(0xFF0E1426).withValues(alpha: 0.78),
            child: SafeArea(
              top: false,
              child: ValueListenableBuilder<WatermarkConfig>(
                valueListenable: templates,
                builder: (_, cfg, __) => ListView(
                  padding: const EdgeInsets.fromLTRB(18, 10, 18, 16),
                  shrinkWrap: true,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(children: [
                      const Expanded(
                        child: Text('Tamaño y transparencia',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white)),
                      ),
                      TextButton.icon(
                        icon: const Icon(Icons.restart_alt, size: 18),
                        label: const Text('Restablecer'),
                        onPressed: () => templates.update(cfg.resetLook()),
                      ),
                    ]),
                    const Text('Se ve en vivo en el visor y se aplica igual en la foto.',
                        style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                    _Group(
                      icon: Icons.notes,
                      title: 'Panel de datos',
                      children: [
                        _Slide(
                          label: 'Tamaño',
                          value: cfg.panelScale,
                          min: 0.5,
                          max: 1.6,
                          percent: true,
                          onChanged: (v) => templates.update(cfg.copyWith(panelScale: v)),
                        ),
                        _Slide(
                          label: 'Fondo',
                          value: cfg.panelOpacity,
                          min: 0.0,
                          max: 1.0,
                          percent: true,
                          onChanged: (v) => templates.update(cfg.copyWith(panelOpacity: v)),
                        ),
                      ],
                    ),
                    _Group(
                      icon: Icons.map_outlined,
                      title: cfg.showMap ? 'Mini mapa' : 'Mini mapa (desactivado en Marcas)',
                      children: [
                        _Slide(
                          label: 'Tamaño',
                          value: cfg.mapScale,
                          min: 0.5,
                          max: 1.8,
                          percent: true,
                          onChanged: (v) => templates.update(cfg.copyWith(mapScale: v)),
                        ),
                        _Slide(
                          label: 'Opacidad',
                          value: cfg.mapOpacity,
                          min: 0.1,
                          max: 1.0,
                          percent: true,
                          onChanged: (v) => templates.update(cfg.copyWith(mapOpacity: v)),
                        ),
                      ],
                    ),
                    _Group(
                      icon: Icons.branding_watermark_outlined,
                      title: 'Logotipo',
                      children: [
                        _Slide(
                          label: 'Tamaño',
                          value: cfg.logoScale,
                          min: 0.5,
                          max: 1.8,
                          percent: true,
                          onChanged: (v) => templates.update(cfg.copyWith(logoScale: v)),
                        ),
                        _Slide(
                          label: 'Opacidad',
                          value: cfg.logoOpacity,
                          min: 0.1,
                          max: 1.0,
                          percent: true,
                          onChanged: (v) => templates.update(cfg.copyWith(logoOpacity: v)),
                        ),
                      ],
                    ),
                    _Group(
                      icon: Icons.explore_outlined,
                      title: 'Brújula (pantalla)',
                      children: [
                        _Slide(
                          label: 'Tamaño',
                          value: cfg.compassScale,
                          min: 0.5,
                          max: 1.8,
                          percent: true,
                          onChanged: (v) => templates.update(cfg.copyWith(compassScale: v)),
                        ),
                        _Slide(
                          label: 'Opacidad',
                          value: cfg.compassOpacity,
                          min: 0.0,
                          max: 1.0,
                          percent: true,
                          onChanged: (v) => templates.update(cfg.copyWith(compassOpacity: v)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _Group extends StatelessWidget {
  const _Group({required this.icon, required this.title, required this.children});
  final IconData icon;
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, size: 18, color: AppColors.cyan),
            const SizedBox(width: 8),
            Flexible(
              child: Text(title,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.white)),
            ),
          ]),
          ...children,
        ]),
      );
}

class _Slide extends StatelessWidget {
  const _Slide({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.percent = false,
  });
  final String label;
  final double value, min, max;
  final bool percent;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) => Row(children: [
        SizedBox(
          width: 72,
          child: Text(label, style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
        ),
        Expanded(
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: ((max - min) / 0.05).round(),
            activeColor: AppColors.cyan,
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 44,
          child: Text('${(value * 100).round()}%',
              textAlign: TextAlign.right, style: const TextStyle(color: Colors.white, fontSize: 12)),
        ),
      ]);
}
