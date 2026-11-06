import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app_services.dart';
import '../../core/location/compass_service.dart';
import '../../core/permissions/permission_service.dart';
import '../../core/ui/glass.dart';
import '../../core/utils/maps_link.dart';
import '../capture/domain/capture_record.dart';
import '../capture/presentation/camera_screen.dart';
import '../share/share_service.dart';
import 'channel_backend.dart';

/// Sala de un canal: mapa con los miembros en vivo y las fotos, chat con
/// fotos geolocalizadas, y compartir ubicación.
class ChannelRoomScreen extends StatefulWidget {
  const ChannelRoomScreen({super.key, required this.channel});
  final Channel channel;

  @override
  State<ChannelRoomScreen> createState() => _ChannelRoomScreenState();
}

class _ChannelRoomScreenState extends State<ChannelRoomScreen> {
  ChannelBackend get b => services.channels;
  late final ChannelRoom _room = b.openRoom(widget.channel.id);
  final _map = MapController();
  final _text = TextEditingController();
  final _messages = <ChannelMessage>[];
  StreamSubscription<ChannelMessage>? _msgSub;
  StreamSubscription<Position>? _posSub;
  Position? _me;
  DateTime _lastTrack = DateTime.fromMillisecondsSinceEpoch(0);
  bool _shareLive = true;
  bool _sending = false;
  bool _mapReady = false;

  String get _myName {
    final n = services.settings.value.inspectorName.trim();
    return n.isEmpty ? 'Usuario' : n;
  }

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      await b.ensureReady();
      final recent = await b.recentMessages(widget.channel.id);
      if (!mounted) return;
      setState(() => _messages.addAll(recent));
      _msgSub = _room.messages.listen((m) {
        if (_messages.any((x) => x.id == m.id)) return;
        setState(() => _messages.add(m));
        if (m.userId != b.myId) HapticFeedback.lightImpact();
      });
      _room.connected.addListener(_onConnected);
      _room.connect();
    } catch (e) {
      _toast(e.toString());
    }

    // Ubicación en vivo
    if (await services.permissions.ensureLocation() == PermissionOutcome.granted) {
      services.compass.start();
      _posSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 5),
      ).listen((p) {
        _me = p;
        _publishMe();
      });
    }
  }

  void _onConnected() {
    if (_room.connected.value) _publishMe(force: true);
  }

  /// Envía mi posición a los demás como máximo cada 5 s.
  void _publishMe({bool force = false}) {
    final p = _me;
    if (!_shareLive || p == null) return;
    if (!force && DateTime.now().difference(_lastTrack) < const Duration(seconds: 5)) return;
    _lastTrack = DateTime.now();
    _room.shareMyLocation(LiveMember(
      userId: b.myId ?? '',
      name: _myName,
      lat: p.latitude,
      lng: p.longitude,
      heading: services.compass.heading.value,
      accuracy: p.accuracy,
      updatedAt: DateTime.now(),
    ));
  }

  @override
  void dispose() {
    _msgSub?.cancel();
    _posSub?.cancel();
    services.compass.stop();
    _room.connected.removeListener(_onConnected);
    _room.close();
    _text.dispose();
    super.dispose();
  }

  void _toast(String m) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _guard(Future<void> Function() action) async {
    if (_sending) return;
    setState(() => _sending = true);
    try {
      await action();
    } catch (e) {
      _toast('No se pudo enviar: $e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _sendText() async {
    final t = _text.text.trim();
    if (t.isEmpty) return;
    _text.clear();
    await _guard(() => b.sendText(widget.channel.id, _myName, t, lat: _me?.latitude, lng: _me?.longitude));
  }

  Future<void> _sendPhoto() async {
    final record = await Navigator.push<CaptureRecord>(
      context,
      MaterialPageRoute(
        builder: (_) => CameraScreen(
          controller: services.camera,
          templates: services.templates,
          returnOnCapture: true,
        ),
      ),
    );
    if (record == null) return;
    await _guard(() => b.sendPhoto(widget.channel.id, _myName, record));
  }

  Future<void> _sendLocation() async {
    final p = _me ?? await Geolocator.getLastKnownPosition();
    if (p == null) return _toast('Aún no hay señal GPS');
    await _guard(() => b.sendLocation(widget.channel.id, _myName,
        lat: p.latitude, lng: p.longitude, heading: services.compass.heading.value, note: 'Estoy aquí'));
  }

  void _focus(double lat, double lng) {
    if (_mapReady) _map.move(LatLng(lat, lng), 17);
  }

  Future<void> _leave() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('¿Salir del canal?'),
        content: const Text('Dejarás de ver sus mensajes. Puedes volver a entrar con el código.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Salir')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await b.leave(widget.channel.id);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      _toast(e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return AuroraBackground(
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        appBar: AppBar(
          titleSpacing: 0,
          title: ValueListenableBuilder<List<LiveMember>>(
            valueListenable: _room.members,
            builder: (_, members, __) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(widget.channel.name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              Text('${members.length} en línea · código ${widget.channel.code}',
                  style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
            ]),
          ),
          actions: [
            IconButton(
              tooltip: 'Invitar por WhatsApp',
              icon: const Icon(Icons.person_add_alt_1_outlined),
              onPressed: () => ShareService.openWhatsAppText(
                  'Únete a mi canal "${widget.channel.name}" en GeoMark.\nCódigo: ${widget.channel.code}'),
            ),
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'live') {
                  setState(() => _shareLive = !_shareLive);
                  if (_shareLive) _publishMe(force: true);
                }
                if (v == 'leave') _leave();
              },
              itemBuilder: (_) => [
                CheckedPopupMenuItem(value: 'live', checked: _shareLive, child: const Text('Compartir mi ubicación en vivo')),
                const PopupMenuItem(value: 'leave', child: Text('Salir del canal')),
              ],
            ),
          ],
        ),
        body: Column(children: [
          // Mapa con miembros y fotos
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: GlassCard(
              padding: const EdgeInsets.all(5),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: SizedBox(height: 240, child: _buildMap()),
              ),
            ),
          ),
          // Miembros en línea
          SizedBox(
            height: 46,
            child: ValueListenableBuilder<List<LiveMember>>(
              valueListenable: _room.members,
              builder: (_, members, __) => ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                children: [
                  for (final m in members)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ActionChip(
                        avatar: CircleAvatar(
                          backgroundColor: m.isStale ? Colors.grey : _colorFor(m.userId),
                          child: Text(m.name.characters.first.toUpperCase(),
                              style: const TextStyle(fontSize: 11, color: Colors.black)),
                        ),
                        label: Text(m.userId == b.myId ? '${m.name} (tú)' : m.name),
                        onPressed: m.hasLocation ? () => _focus(m.lat!, m.lng!) : null,
                      ),
                    ),
                ],
              ),
            ),
          ),
          // Mensajes
          Expanded(
            child: _messages.isEmpty
                ? const Center(
                    child: Text('Sin mensajes. Envía una foto o tu ubicación.',
                        style: TextStyle(color: AppColors.textMuted)))
                : ListView.builder(
                    reverse: true,
                    padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
                    itemCount: _messages.length,
                    itemBuilder: (_, i) {
                      final m = _messages[_messages.length - 1 - i];
                      return _Bubble(
                        message: m,
                        mine: m.userId == b.myId,
                        color: _colorFor(m.userId),
                        onLocate: m.hasLocation ? () => _focus(m.lat!, m.lng!) : null,
                      );
                    },
                  ),
          ),
          // Barra de envío
          Padding(
            padding: EdgeInsets.fromLTRB(10, 4, 10, bottom + 8),
            child: GlassCard(
              radius: 26,
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Row(children: [
                IconButton(
                  tooltip: 'Foto',
                  icon: const Icon(Icons.photo_camera, color: AppColors.cyan),
                  onPressed: _sending ? null : _sendPhoto,
                ),
                IconButton(
                  tooltip: 'Enviar mi ubicación',
                  icon: const Icon(Icons.my_location, color: AppColors.teal),
                  onPressed: _sending ? null : _sendLocation,
                ),
                Expanded(
                  child: TextField(
                    controller: _text,
                    minLines: 1,
                    maxLines: 4,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      hintText: 'Mensaje',
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      fillColor: Colors.transparent,
                      isDense: true,
                    ),
                    onSubmitted: (_) => _sendText(),
                  ),
                ),
                _sending
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
                    : IconButton(
                        icon: const Icon(Icons.send_rounded, color: AppColors.violet),
                        onPressed: _sendText,
                      ),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _buildMap() {
    return ValueListenableBuilder<List<LiveMember>>(
      valueListenable: _room.members,
      builder: (_, members, __) {
        final geoMsgs = _messages.where((m) => m.hasLocation).toList();
        final recent = geoMsgs.length > 60 ? geoMsgs.sublist(geoMsgs.length - 60) : geoMsgs;
        final center = _me != null
            ? LatLng(_me!.latitude, _me!.longitude)
            : (members.where((m) => m.hasLocation).map((m) => LatLng(m.lat!, m.lng!)).firstOrNull ??
                (recent.isNotEmpty ? LatLng(recent.last.lat!, recent.last.lng!) : LatLng(13.7, -89.2)));
        return FlutterMap(
          mapController: _map,
          options: MapOptions(
            initialCenter: center,
            initialZoom: 15,
            onMapReady: () => _mapReady = true,
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.geomark.app',
            ),
            // Fotos y ubicaciones enviadas
            MarkerLayer(markers: [
              for (final m in recent)
                Marker(
                  point: LatLng(m.lat!, m.lng!),
                  width: 26,
                  height: 26,
                  child: GestureDetector(
                    onTap: () => m.photoUrl == null ? null : _showPhoto(m),
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white,
                        border: Border.all(color: _colorFor(m.userId), width: 2),
                      ),
                      child: Icon(m.kind == 'photo' ? Icons.photo_camera : Icons.place,
                          size: 14, color: Colors.black87),
                    ),
                  ),
                ),
            ]),
            // Miembros en vivo (con flecha si comparten rumbo)
            MarkerLayer(markers: [
              for (final m in members.where((m) => m.hasLocation))
                Marker(
                  point: LatLng(m.lat!, m.lng!),
                  width: 90,
                  height: 58,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Transform.rotate(
                      angle: (m.heading ?? 0) * math.pi / 180,
                      child: Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: m.isStale ? Colors.grey : _colorFor(m.userId),
                          border: Border.all(color: Colors.white, width: 2.5),
                          boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 6)],
                        ),
                        child: Icon(m.heading == null ? Icons.person : Icons.navigation,
                            size: 18, color: Colors.black),
                      ),
                    ),
                    Container(
                      margin: const EdgeInsets.only(top: 2),
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(6)),
                      child: Text(m.name.split(' ').first,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white, fontSize: 10)),
                    ),
                  ]),
                ),
            ]),
            const SimpleAttributionWidget(source: Text('OpenStreetMap')),
          ],
        );
      },
    );
  }

  void _showPhoto(ChannelMessage m) => showDialog<void>(
        context: context,
        builder: (c) => Dialog(
          backgroundColor: Colors.black,
          insetPadding: const EdgeInsets.all(12),
          child: InteractiveViewer(child: Image.network(m.photoUrl!)),
        ),
      );

  static const _palette = [
    Color(0xFF22D3EE), Color(0xFFFFB020), Color(0xFF2EE6A6), Color(0xFFFF5C9A),
    Color(0xFF7C5CFF), Color(0xFF9BE15D), Color(0xFFFF8A3D), Color(0xFF5AC8FA),
  ];

  /// Color estable por usuario.
  static Color _colorFor(String userId) =>
      _palette[userId.codeUnits.fold<int>(0, (a, c) => a + c) % _palette.length];
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message, required this.mine, required this.color, this.onLocate});
  final ChannelMessage message;
  final bool mine;
  final Color color;
  final VoidCallback? onLocate;

  @override
  Widget build(BuildContext context) {
    final m = message;
    final maxW = MediaQuery.sizeOf(context).width * 0.78;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxW),
        child: GlassCard(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(10),
          radius: 18,
          tint: mine ? AppColors.violet : null,
          onTap: onLocate,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (!mine)
              Text(m.userName, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12)),
            if (m.photoUrl != null) ...[
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  m.photoUrl!,
                  height: 190,
                  width: maxW,
                  fit: BoxFit.cover,
                  cacheWidth: 700,
                  loadingBuilder: (_, child, p) => p == null
                      ? child
                      : const SizedBox(height: 190, child: Center(child: CircularProgressIndicator())),
                  errorBuilder: (_, __, ___) =>
                      const SizedBox(height: 60, child: Center(child: Icon(Icons.broken_image))),
                ),
              ),
            ],
            if (m.kind == 'location')
              const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.place, size: 16, color: AppColors.teal),
                SizedBox(width: 4),
                Text('Ubicación compartida', style: TextStyle(fontWeight: FontWeight.w600)),
              ]),
            if (m.body != null && m.body!.isNotEmpty)
              Padding(padding: const EdgeInsets.only(top: 4), child: Text(m.body!)),
            const SizedBox(height: 4),
            Row(mainAxisSize: MainAxisSize.min, children: [
              Text(DateFormat('HH:mm').format(m.createdAt),
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
              if (m.heading != null) ...[
                const SizedBox(width: 6),
                Text('🧭 ${CompassService.cardinal(m.heading!)}',
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
              ],
              if (m.hasLocation) ...[
                const SizedBox(width: 8),
                InkWell(
                  onTap: () => launchUrl(Uri.parse(MapsLink.directions(m.lat!, m.lng!)),
                      mode: LaunchMode.externalApplication),
                  child: const Text('Cómo llegar',
                      style: TextStyle(color: AppColors.cyan, fontSize: 11, fontWeight: FontWeight.w700)),
                ),
              ],
            ]),
          ]),
        ),
      ),
    );
  }
}
