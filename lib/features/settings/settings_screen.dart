import 'package:flutter/material.dart';

import '../../app_services.dart';
import '../../core/ui/glass.dart';
import '../capture/presentation/gallery_screen.dart';
import 'settings_service.dart';

/// Ajustes: datos de la institución e inspector (salen en los PDF).
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final s = services.settings.value;
  late final _inst = TextEditingController(text: s.institution);
  late final _dept = TextEditingController(text: s.department);
  late final _name = TextEditingController(text: s.inspectorName);
  late final _role = TextEditingController(text: s.inspectorRole);

  @override
  void dispose() {
    for (final c in [_inst, _dept, _name, _role]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    await services.settings.save(AppSettings(
      institution: _inst.text,
      department: _dept.text,
      inspectorName: _name.text,
      inspectorRole: _role.text,
    ));
    if (!mounted) return;
    FocusScope.of(context).unfocus();
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ajustes guardados')));
  }

  Widget _field(TextEditingController c, String label, IconData icon, String hint) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: c,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(labelText: label, hintText: hint, prefixIcon: Icon(icon)),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return ListView(
      padding: EdgeInsets.fromLTRB(18, top + 14, 18, 130),
      children: [
        const Text('Ajustes',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
        const SizedBox(height: 16),
        GlassCard(
          padding: const EdgeInsets.all(18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Institución', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 4),
            const Text('Aparece en el encabezado de todos los informes.',
                style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
            const SizedBox(height: 14),
            _field(_inst, 'Nombre de la institución', Icons.account_balance_outlined,
                'Alcaldía Municipal de…'),
            _field(_dept, 'Unidad o departamento', Icons.apartment_outlined,
                'Unidad de Medio Ambiente'),
            const SizedBox(height: 6),
            const Text('Inspector', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 14),
            _field(_name, 'Nombre completo', Icons.person_outline, 'Ana López'),
            _field(_role, 'Cargo', Icons.work_outline, 'Inspectora técnica'),
            const SizedBox(height: 6),
            GradientButton(label: 'Guardar', icon: Icons.check, onPressed: _save),
          ]),
        ),
        const SizedBox(height: 14),
        GlassCard(
          onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => GalleryScreen(repository: services.captures))),
          child: const Row(children: [
            Icon(Icons.photo_library_outlined, color: AppColors.cyan),
            SizedBox(width: 12),
            Expanded(child: Text('Todas mis evidencias fotográficas')),
            Icon(Icons.chevron_right),
          ]),
        ),
        const SizedBox(height: 10),
        const GlassCard(
          child: Row(children: [
            Icon(Icons.shield_outlined, color: AppColors.teal),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Los datos se guardan solo en este teléfono y funcionan sin internet.',
                style: TextStyle(color: AppColors.textMuted),
              ),
            ),
          ]),
        ),
      ],
    );
  }
}
