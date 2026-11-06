import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app_services.dart';
import '../../core/ui/glass.dart';
import '../share/share_service.dart';
import 'channel_backend.dart';
import 'channel_room_screen.dart';

/// Pestaña Canales: configurar el servidor, crear canal, unirse con código
/// y lista de canales del usuario.
class ChannelsScreen extends StatefulWidget {
  const ChannelsScreen({super.key, required this.refresh});
  final ValueNotifier<int> refresh;

  @override
  State<ChannelsScreen> createState() => _ChannelsScreenState();
}

class _ChannelsScreenState extends State<ChannelsScreen> {
  ChannelBackend get b => services.channels;
  Future<List<Channel>>? _list;
  String? _error;

  @override
  void initState() {
    super.initState();
    widget.refresh.addListener(_reload);
    _reload();
  }

  @override
  void dispose() {
    widget.refresh.removeListener(_reload);
    super.dispose();
  }

  void _reload() {
    if (!b.configured) return;
    setState(() {
      _error = null;
      _list = b.myChannels().catchError((Object e) {
        if (mounted) setState(() => _error = e.toString());
        return <Channel>[];
      });
    });
  }

  String get _myName {
    final n = services.settings.value.inspectorName.trim();
    return n.isEmpty ? 'Usuario' : n;
  }

  void _toast(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _open(Channel c) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => ChannelRoomScreen(channel: c)));
    _reload();
  }

  Future<void> _create() async {
    final name = await _askText('Nuevo canal', 'Nombre del canal', 'Bacheo zona norte — semana 45');
    if (name == null || name.trim().isEmpty) return;
    try {
      final c = await b.create(name, _myName);
      if (!mounted) return;
      _reload();
      await _showCode(c);
      await _open(c);
    } catch (e) {
      _toast(e.toString());
    }
  }

  Future<void> _join() async {
    final code = await _askText('Unirse a un canal', 'Código de 6 caracteres', 'A1B2C3', upper: true);
    if (code == null || code.trim().isEmpty) return;
    try {
      final c = await b.join(code, _myName);
      _reload();
      await _open(c);
    } catch (e) {
      _toast(e.toString());
    }
  }

  Future<void> _showCode(Channel c) => showGlassSheet<void>(
        context,
        builder: (ctx) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(c.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            const Text('Comparte este código con tu equipo para que se unan',
                style: TextStyle(color: AppColors.textMuted)),
            const SizedBox(height: 16),
            SelectableText(c.code,
                style: const TextStyle(fontSize: 44, fontWeight: FontWeight.w900, letterSpacing: 8)),
            const SizedBox(height: 16),
            GradientButton(
              label: 'Enviar código por WhatsApp',
              icon: Icons.chat,
              onPressed: () => ShareService.openWhatsAppText(
                  'Únete a mi canal "${c.name}" en GeoMark.\nCódigo: ${c.code}'),
            ),
            TextButton.icon(
              icon: const Icon(Icons.copy),
              label: const Text('Copiar código'),
              onPressed: () => Clipboard.setData(ClipboardData(text: c.code)),
            ),
          ]),
        ),
      );

  Future<String?> _askText(String title, String label, String hint, {bool upper = false}) {
    final ctrl = TextEditingController();
    return showGlassSheet<String>(
      context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 14),
          TextField(
            controller: ctrl,
            autofocus: true,
            textCapitalization: upper ? TextCapitalization.characters : TextCapitalization.sentences,
            decoration: InputDecoration(labelText: label, hintText: hint),
            onSubmitted: (v) => Navigator.pop(ctx, v),
          ),
          const SizedBox(height: 14),
          GradientButton(label: 'Continuar', onPressed: () => Navigator.pop(ctx, ctrl.text)),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return ListenableBuilder(
      listenable: b,
      builder: (context, _) => ListView(
        padding: EdgeInsets.fromLTRB(18, top + 14, 18, 130),
        children: [
          const Text('Canales',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
          const SizedBox(height: 4),
          const Text('Coordina con tu equipo en tiempo real: fotos, mensajes y ubicación en vivo.',
              style: TextStyle(color: AppColors.textMuted)),
          const SizedBox(height: 16),
          if (!b.configured)
            _ServerSetup(onSaved: _reload)
          else ...[
            Row(children: [
              Expanded(child: GradientButton(label: 'Crear canal', icon: Icons.add, onPressed: _create)),
              const SizedBox(width: 10),
              Expanded(
                child: SizedBox(
                  height: 54,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.vpn_key_outlined),
                    label: const Text('Unirme con código'),
                    onPressed: _join,
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 16),
            if (_error != null)
              GlassCard(
                tint: AppColors.danger,
                child: Text(_error!, style: const TextStyle(color: AppColors.text)),
              ),
            FutureBuilder<List<Channel>>(
              future: _list,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Padding(
                      padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator()));
                }
                final list = snap.data ?? const [];
                if (list.isEmpty && _error == null) {
                  return const GlassCard(
                    child: Text('Aún no estás en ningún canal. Crea uno o únete con el código que te compartan.',
                        style: TextStyle(color: AppColors.textMuted)),
                  );
                }
                return Column(children: [
                  for (final (i, c) in list.indexed)
                    FadeSlideIn(
                      index: i.clamp(0, 8),
                      child: GlassCard(
                        margin: const EdgeInsets.only(bottom: 10),
                        onTap: () => _open(c),
                        child: Row(children: [
                          Container(
                            width: 46,
                            height: 46,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(14), gradient: AppColors.accentGradient),
                            child: Text(c.name.characters.first.toUpperCase(),
                                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(c.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                              Text('Código ${c.code}',
                                  style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                            ]),
                          ),
                          IconButton(
                            tooltip: 'Invitar',
                            icon: const Icon(Icons.person_add_alt_1_outlined, color: AppColors.cyan),
                            onPressed: () => _showCode(c),
                          ),
                        ]),
                      ),
                    ),
                ]);
              },
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              icon: const Icon(Icons.dns_outlined, size: 18),
              label: const Text('Cambiar servidor de canales'),
              onPressed: () => showGlassSheet<void>(
                context,
                builder: (_) => Padding(
                  padding: const EdgeInsets.all(16),
                  child: _ServerSetup(onSaved: () {
                    Navigator.pop(context);
                    _reload();
                  }),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Configuración del servidor (URL + clave pública de Supabase).
class _ServerSetup extends StatefulWidget {
  const _ServerSetup({required this.onSaved});
  final VoidCallback onSaved;

  @override
  State<_ServerSetup> createState() => _ServerSetupState();
}

class _ServerSetupState extends State<_ServerSetup> {
  late final _url = TextEditingController(text: services.channels.url ?? '');
  late final _key = TextEditingController(text: services.channels.anonKey ?? '');
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _url.dispose();
    _key.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await services.channels.saveConfig(_url.text, _key.text);
      widget.onSaved();
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => GlassCard(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Conectar servidor de canales',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
          const SizedBox(height: 6),
          const Text(
            'Se hace una sola vez por institución (gratis):\n'
            '1. Crea un proyecto en supabase.com\n'
            '2. En SQL Editor ejecuta el archivo supabase/instalar_canales.sql\n'
            '3. Authentication → Sign In / Providers → activa "Anonymous sign-ins"\n'
            '4. Project Settings → API: copia la URL y la clave pública (anon / publishable)',
            style: TextStyle(color: AppColors.textMuted, height: 1.45, fontSize: 13),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _url,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
                labelText: 'URL del proyecto', hintText: 'https://xxxx.supabase.co', prefixIcon: Icon(Icons.link)),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _key,
            decoration: const InputDecoration(
                labelText: 'Clave pública (anon)', prefixIcon: Icon(Icons.key_outlined)),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: const TextStyle(color: AppColors.danger)),
          ],
          const SizedBox(height: 14),
          GradientButton(label: 'Conectar', icon: Icons.cloud_done_outlined, busy: _busy, onPressed: _save),
        ]),
      );
}
