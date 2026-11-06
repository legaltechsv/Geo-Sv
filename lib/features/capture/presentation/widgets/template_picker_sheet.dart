import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../app_services.dart';
import '../../../branding/logo_service.dart';

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
    isScrollControlled: true,
    backgroundColor: const Color(0xFF1C1C1E),
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (ctx) => ValueListenableBuilder<WatermarkConfig>(
      valueListenable: templates,
      builder: (ctx, cfg, _) => SafeArea(
        child: SingleChildScrollView(
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
            const Divider(color: Colors.white12, height: 1),
            _LogoSection(templates: templates, cfg: cfg),
            const Divider(color: Colors.white12, height: 1),
            _MapSection(templates: templates, cfg: cfg),
            const SizedBox(height: 12),
          ],
        ),
        ),
      ),
    ),
  );
}

/// Selector de esquina (2×2) para logo o mapa. [blocked] = esquina ocupada.
class _CornerPicker extends StatelessWidget {
  const _CornerPicker({required this.value, required this.onChanged, this.blocked});
  final OverlayPosition value;
  final ValueChanged<OverlayPosition> onChanged;
  final OverlayPosition? blocked;

  @override
  Widget build(BuildContext context) => Wrap(spacing: 8, runSpacing: 8, children: [
        for (final p in OverlayPosition.values)
          ChoiceChip(
            avatar: Icon(p.icon, size: 16),
            label: Text(p == blocked ? '${p.label} (ocupada)' : p.label),
            selected: p == value,
            onSelected: p == blocked ? null : (_) => onChanged(p),
            selectedColor: const Color(0xFF7C5CFF).withValues(alpha: 0.4),
            backgroundColor: Colors.white.withValues(alpha: 0.05),
            side: BorderSide(color: Colors.white.withValues(alpha: 0.14)),
          ),
      ]);
}

class _LogoSection extends StatefulWidget {
  const _LogoSection({required this.templates, required this.cfg});
  final TemplateController templates;
  final WatermarkConfig cfg;

  @override
  State<_LogoSection> createState() => _LogoSectionState();
}

class _LogoSectionState extends State<_LogoSection> {
  bool _busy = false;

  Future<void> _upload() async {
    setState(() => _busy = true);
    try {
      await services.logo.pickFile();
    } on LogoException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('No se pudo cargar el logotipo: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cfg = widget.cfg;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      child: ValueListenableBuilder<String?>(
        valueListenable: services.logo,
        builder: (_, path, __) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Expanded(
              child: Text('Logotipo en la foto',
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
            ),
            if (path != null)
              Container(
                height: 40,
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
                child: Image.file(File(path), fit: BoxFit.contain),
              ),
          ]),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              icon: _busy
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.upload_file),
              label: Text(path == null ? 'Subir logotipo (PNG, JPG o PDF)' : 'Cambiar logotipo (PNG, JPG o PDF)'),
              onPressed: _busy ? null : _upload,
            ),
          ),
          if (path != null) ...[
            const SizedBox(height: 12),
            const Text('¿Dónde lo coloco?', style: TextStyle(color: Colors.white70)),
            const SizedBox(height: 8),
            _CornerPicker(
              value: cfg.logoPosition,
              blocked: cfg.showMap ? cfg.mapPosition : null,
              onChanged: (p) => widget.templates.update(cfg.copyWith(logoPosition: p)),
            ),
            TextButton.icon(
              icon: const Icon(Icons.delete_outline, size: 18),
              label: const Text('Quitar logotipo'),
              onPressed: services.logo.remove,
            ),
          ],
        ]),
      ),
    );
  }
}

class _MapSection extends StatelessWidget {
  const _MapSection({required this.templates, required this.cfg});
  final TemplateController templates;
  final WatermarkConfig cfg;

  @override
  Widget build(BuildContext context) {
    final hasLogo = services.logo.value != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Mini mapa en la foto',
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
          subtitle: const Text(
              'Norte arriba, tu ubicación y un cono que muestra hacia dónde apunta el teléfono',
              style: TextStyle(color: Colors.white60)),
          value: cfg.showMap,
          onChanged: (v) {
            var next = cfg.copyWith(showMap: v);
            // Si el mapa caería en la misma esquina que el logo, moverlo.
            if (v && hasLogo && next.mapPosition == next.logoPosition) {
              next = next.copyWith(
                  mapPosition: OverlayPosition.values.firstWhere((p) => p != next.logoPosition));
            }
            templates.update(next);
          },
        ),
        if (cfg.showMap) ...[
          const Text('¿Dónde coloco el mapa?', style: TextStyle(color: Colors.white70)),
          const SizedBox(height: 8),
          _CornerPicker(
            value: cfg.mapPosition,
            blocked: hasLogo ? cfg.logoPosition : null,
            onChanged: (p) => templates.update(cfg.copyWith(mapPosition: p)),
          ),
          const SizedBox(height: 6),
          const Text('Con internet se ven las calles; sin conexión el mapa queda en blanco pero conserva el punto, la dirección y el norte.',
              style: TextStyle(color: Colors.white38, fontSize: 12)),
        ],
      ]),
    );
  }
}
