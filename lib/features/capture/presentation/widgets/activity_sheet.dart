import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/ui/glass.dart';

/// Hoja "¿Qué actividad realizas?" que aparece justo después del disparo.
/// Recuerda las últimas actividades escritas para elegirlas con un toque.
/// Devuelve el texto elegido, o null si el usuario la omite.
Future<String?> askActivity(BuildContext context) async {
  final prefs = await SharedPreferences.getInstance();
  final recent = prefs.getStringList('recentActivities') ?? const [];
  if (!context.mounted) return null;
  final result = await showGlassSheet<String>(
    context,
    builder: (_) => _ActivityForm(recent: recent),
  );
  if (result != null && result.trim().isNotEmpty) {
    final updated = [result.trim(), ...recent.where((r) => r != result.trim())].take(6).toList();
    await prefs.setStringList('recentActivities', updated);
  }
  return result;
}

class _ActivityForm extends StatefulWidget {
  const _ActivityForm({required this.recent});
  final List<String> recent;

  @override
  State<_ActivityForm> createState() => _ActivityFormState();
}

class _ActivityFormState extends State<_ActivityForm> {
  final _text = TextEditingController();

  static const _presets = [
    (Icons.fact_check_outlined, 'Inspección'),
    (Icons.construction, 'Supervisión de obra'),
    (Icons.build_outlined, 'Mantenimiento'),
    (Icons.straighten, 'Levantamiento / medición'),
    (Icons.local_shipping_outlined, 'Entrega de material'),
    (Icons.handshake_outlined, 'Visita a cliente'),
    (Icons.groups_outlined, 'Reunión en sitio'),
    (Icons.warning_amber_rounded, 'Reporte de daño'),
  ];

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _done(String v) => Navigator.pop(context, v);

  @override
  Widget build(BuildContext context) {
    final presets = [
      for (final r in widget.recent) (Icons.history, r),
      for (final p in _presets)
        if (!widget.recent.contains(p.$2)) p,
    ];
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('¿Qué actividad realizas?',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        const Text('Se agrega a la marca de agua de la foto.',
            style: TextStyle(color: AppColors.textMuted)),
        const SizedBox(height: 16),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final (icon, label) in presets)
            ActionChip(
              avatar: Icon(icon, size: 18, color: AppColors.cyan),
              label: Text(label),
              onPressed: () => _done(label),
              backgroundColor: Colors.white.withValues(alpha: 0.06),
              side: BorderSide(color: Colors.white.withValues(alpha: 0.14)),
            ),
        ]),
        const SizedBox(height: 16),
        TextField(
          controller: _text,
          maxLength: 60,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            hintText: 'Otra actividad (escríbela)',
            prefixIcon: Icon(Icons.edit_note),
          ),
          onSubmitted: (v) => _done(v),
        ),
        const SizedBox(height: 8),
        Row(children: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Omitir')),
          const Spacer(),
          SizedBox(
            width: 160,
            child: GradientButton(
              label: 'Guardar',
              icon: Icons.check,
              onPressed: () => _done(_text.text),
            ),
          ),
        ]),
      ]),
    );
  }
}
