import 'package:flutter/material.dart';

import '../../../../core/time/trusted_time_service.dart';
import '../../../templates/watermark_template.dart';
import 'live_watermark_overlay.dart';
import 'watermark_editor_sheet.dart';

/// Hoja inferior "Marcas de agua": carrusel de plantillas con miniatura
/// en vivo de cada una + acceso al editor de datos.
Future<void> showTemplatePicker(
  BuildContext context, {
  required TemplateController templates,
  required TrustedTime Function() clock,
}) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: const Color(0xFF1C1C1E),
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (ctx) => ValueListenableBuilder<WatermarkConfig>(
      valueListenable: templates,
      builder: (ctx, cfg, _) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(children: [
                const Text('Marcas de agua',
                    style: TextStyle(
                        color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
                const Spacer(),
                TextButton.icon(
                  icon: const Icon(Icons.edit, size: 18),
                  label: const Text('Editar datos'),
                  onPressed: () => showWatermarkEditor(ctx, templates: templates),
                ),
              ]),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 190,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                scrollDirection: Axis.horizontal,
                itemCount: WatermarkStyle.values.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (_, i) {
                  final style = WatermarkStyle.values[i];
                  final selected = style == cfg.style;
                  return GestureDetector(
                    onTap: () => templates.setStyle(style),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      width: 150,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: selected ? style.accent : Colors.white12,
                          width: selected ? 2.5 : 1,
                        ),
                        // Fondo tipo "foto" para que la miniatura se lea como en el visor
                        gradient: const LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0xFF5B7A99), Color(0xFF3E5641)],
                        ),
                      ),
                      child: Column(children: [
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.all(6),
                            child: Align(
                              alignment: Alignment.bottomLeft,
                              child: LiveWatermarkOverlay(
                                compact: true,
                                config: cfg.copyWith(style: style),
                                position: null,
                                address: 'Av. Principal, Municipio',
                                clock: clock,
                              ),
                            ),
                          ),
                        ),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: const BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.vertical(bottom: Radius.circular(12)),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(style.icon, size: 16, color: style.accent),
                              const SizedBox(width: 6),
                              Text(style.label,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                                  )),
                            ],
                          ),
                        ),
                      ]),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              child: Text(cfg.style.description,
                  style: const TextStyle(color: Colors.white60)),
            ),
          ],
        ),
      ),
    ),
  );
}
