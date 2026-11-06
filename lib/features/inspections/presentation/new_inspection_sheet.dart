import 'package:flutter/material.dart';

import '../../../app_services.dart';
import '../../../core/permissions/permission_service.dart';
import '../../../core/ui/glass.dart';
import '../domain/checklist_templates.dart';
import '../domain/inspection.dart';

/// Formulario de nueva inspección. Al crearla registra automáticamente
/// la ubicación GPS y la hora de llegada (inicio de la visita).
Future<Inspection?> showNewInspectionSheet(BuildContext context) =>
    showGlassSheet<Inspection>(context, builder: (_) => const _NewInspectionForm());

class _NewInspectionForm extends StatefulWidget {
  const _NewInspectionForm();

  @override
  State<_NewInspectionForm> createState() => _NewInspectionFormState();
}

class _NewInspectionFormState extends State<_NewInspectionForm> {
  final _form = GlobalKey<FormState>();
  final _site = TextEditingController();
  final _attended = TextEditingController();
  ChecklistTemplate _template = ChecklistTemplates.all.first;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _site.dispose();
    _attended.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final perm = await services.permissions.ensureLocation();
      if (perm != PermissionOutcome.granted) {
        throw Exception('Se necesita la ubicación precisa para registrar la visita.');
      }
      final fix = await services.location.getFixAtShutter();
      if (fix.isMocked) throw Exception('Ubicación simulada detectada.');
      final address = await services.geocoding.reverse(fix.latitude, fix.longitude);
      final s = services.settings.value;
      final insp = await services.inspections.create(
        template: _template,
        siteName: _site.text,
        attendedBy: _attended.text,
        inspectorName: s.inspectorName,
        institution: s.institution,
        latitude: fix.latitude,
        longitude: fix.longitude,
        accuracy: fix.accuracy,
        address: address,
      );
      // La marca de agua de las fotos de esta inspección lleva el lugar.
      services.templates.update(services.templates.value.copyWith(projectName: insp.siteName));
      if (mounted) Navigator.pop(context, insp);
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Form(
        key: _form,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Nueva inspección',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          const Text('La ubicación y la hora de llegada se registran al crearla.',
              style: TextStyle(color: AppColors.textMuted)),
          const SizedBox(height: 18),
          const Text('Tipo de inspección', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final t in ChecklistTemplates.all)
                ChoiceChip(
                  avatar: Icon(t.icon, size: 18),
                  label: Text('${t.name} · ${t.itemCount}'),
                  selected: t.key == _template.key,
                  onSelected: (_) => setState(() => _template = t),
                  selectedColor: AppColors.violet.withValues(alpha: 0.35),
                  backgroundColor: Colors.white.withValues(alpha: 0.05),
                  side: BorderSide(color: Colors.white.withValues(alpha: 0.14)),
                ),
            ],
          ),
          const SizedBox(height: 18),
          TextFormField(
            controller: _site,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
                labelText: 'Lugar inspeccionado *',
                hintText: 'Mercado municipal, Escuela Central…',
                prefixIcon: Icon(Icons.place_outlined)),
            validator: (v) => (v ?? '').trim().isEmpty ? 'Escribe el nombre del lugar' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _attended,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
                labelText: 'Atendido por',
                hintText: 'Nombre del responsable en el sitio',
                prefixIcon: Icon(Icons.badge_outlined)),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: AppColors.danger)),
          ],
          const SizedBox(height: 22),
          GradientButton(
            label: _busy ? 'Obteniendo GPS…' : 'Iniciar inspección',
            icon: Icons.play_arrow_rounded,
            busy: _busy,
            onPressed: _create,
          ),
        ]),
      ),
    );
  }
}
