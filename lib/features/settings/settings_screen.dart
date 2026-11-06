import 'dart:io';

import 'package:flutter/material.dart';

import '../../app_services.dart';
import '../../core/ui/glass.dart';
import '../branding/logo_service.dart';
import '../capture/presentation/gallery_screen.dart';
import '../capture/presentation/widgets/look_sheet.dart';
import 'settings_service.dart';

/// Ajustes como pantalla independiente (se abre desde el Panel).
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) => const AuroraBackground(
        child: Scaffold(
          appBar: _SettingsBar(),
          body: SettingsScreen(embedded: true),
        ),
      );
}

class _SettingsBar extends StatelessWidget implements PreferredSizeWidget {
  const _SettingsBar();
  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
  @override
  Widget build(BuildContext context) => AppBar(title: const Text('Ajustes'));
}

/// Ajustes: logotipo, institución, inspector y opciones de la app.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, this.embedded = false});

  /// true = dentro de SettingsPage (con barra superior propia).
  final bool embedded;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final s = services.settings.value;
  late final _inst = TextEditingController(text: s.institution);
  late final _dept = TextEditingController(text: s.department);
  late final _name = TextEditingController(text: s.inspectorName);
  late final _role = TextEditingController(text: s.inspectorRole);
  late bool _compact = s.compactShare;
  late bool _askActivity = s.askActivity;
  bool _logoBusy = false;

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
      compactShare: _compact,
      askActivity: _askActivity,
    ));
    if (!mounted) return;
    FocusScope.of(context).unfocus();
    _toast('Ajustes guardados');
  }

  /// Guarda solo los interruptores (sin pedir "Guardar").
  Future<void> _saveToggles() => services.settings.save(
      services.settings.value.copyWith(compactShare: _compact, askActivity: _askActivity));

  void _toast(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _logoFrom(Future<void> Function() action, String ok) async {
    setState(() => _logoBusy = true);
    try {
      await action();
      if (mounted && services.logo.value != null) _toast(ok);
    } on LogoException catch (e) {
      if (mounted) _toast(e.message);
    } catch (e) {
      if (mounted) _toast('No se pudo cargar el logotipo: $e');
    } finally {
      if (mounted) setState(() => _logoBusy = false);
    }
  }

  Future<void> _askUrl() async {
    final ctrl = TextEditingController();
    final url = await showGlassSheet<String>(
      context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Logotipo desde Internet',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          const Text(
            '1. Busca tu logo en Google Imágenes o en tu página/Facebook.\n'
            '2. Mantén presionada la imagen y elige "Copiar dirección de la imagen".\n'
            '3. Pégala aquí.',
            style: TextStyle(color: AppColors.textMuted, height: 1.4),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: ctrl,
            autofocus: true,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
                hintText: 'https://…/logo.png', prefixIcon: Icon(Icons.link)),
          ),
          const SizedBox(height: 14),
          GradientButton(
            label: 'Descargar logotipo',
            icon: Icons.download,
            onPressed: () => Navigator.pop(ctx, ctrl.text),
          ),
        ]),
      ),
    );
    if (url != null && url.trim().isNotEmpty) {
      await _logoFrom(() => services.logo.downloadFromUrl(url), 'Logotipo descargado');
    }
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
    final top = widget.embedded ? 0.0 : MediaQuery.paddingOf(context).top;
    return ListView(
      padding: EdgeInsets.fromLTRB(18, top + 14, 18, widget.embedded ? 40 : 130),
      children: [
        if (!widget.embedded) ...[
          const Text('Ajustes',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
          const SizedBox(height: 16),
        ],

        // ── Logotipo ──
        GlassCard(
          padding: const EdgeInsets.all(18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Logotipo', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 4),
            const Text('Aparece en las fotos, en la pantalla de inicio y en los reportes PDF y Word.',
                style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
            const SizedBox(height: 14),
            ValueListenableBuilder<String?>(
              valueListenable: services.logo,
              builder: (_, path, __) => Container(
                height: 110,
                width: double.infinity,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: path == null ? Colors.white.withValues(alpha: 0.04) : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white24),
                ),
                child: _logoBusy
                    ? const CircularProgressIndicator()
                    : path == null
                        ? const Text('Sin logotipo', style: TextStyle(color: AppColors.textMuted))
                        : Padding(
                            padding: const EdgeInsets.all(10),
                            child: Image.file(File(path), fit: BoxFit.contain),
                          ),
              ),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('Galería'),
                  onPressed: _logoBusy
                      ? null
                      : () => _logoFrom(services.logo.pickFromGallery, 'Logotipo actualizado'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.travel_explore),
                  label: const Text('Internet'),
                  onPressed: _logoBusy ? null : _askUrl,
                ),
              ),
            ]),
            ValueListenableBuilder<String?>(
              valueListenable: services.logo,
              builder: (_, path, __) => path == null
                  ? const SizedBox.shrink()
                  : TextButton.icon(
                      icon: const Icon(Icons.delete_outline, color: AppColors.danger),
                      label: const Text('Quitar logotipo', style: TextStyle(color: AppColors.danger)),
                      onPressed: services.logo.remove,
                    ),
            ),
          ]),
        ),
        const SizedBox(height: 14),

        // ── Institución e inspector ──
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

        // ── Opciones ──
        GlassCard(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Column(children: [
            SwitchListTile(
              title: const Text('Mensaje corto al compartir'),
              subtitle: const Text('Lugar, hora y enlace en 2 líneas (ideal para WhatsApp)'),
              value: _compact,
              onChanged: (v) {
                setState(() => _compact = v);
                _saveToggles();
              },
            ),
            SwitchListTile(
              title: const Text('Preguntar la actividad'),
              subtitle: const Text('Después de cada foto: "¿Qué actividad realizas?"'),
              value: _askActivity,
              onChanged: (v) {
                setState(() => _askActivity = v);
                _saveToggles();
              },
            ),
          ]),
        ),
        const SizedBox(height: 14),
        GlassCard(
          margin: const EdgeInsets.only(bottom: 10),
          onTap: () => showLookSheet(context, templates: services.templates),
          child: const Row(children: [
            Icon(Icons.tune, color: AppColors.violet),
            SizedBox(width: 12),
            Expanded(child: Text('Tamaño y transparencia de la toma')),
            Icon(Icons.chevron_right),
          ]),
        ),
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
