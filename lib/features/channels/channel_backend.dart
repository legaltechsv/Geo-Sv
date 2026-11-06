import 'dart:async';
import 'dart:isolate';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../capture/domain/capture_record.dart';

/// Canal (grupo de trabajo) compartido entre usuarios de la app.
class Channel {
  Channel({required this.id, required this.name, required this.code});
  final String id, name, code;

  factory Channel.fromMap(Map<String, dynamic> m) =>
      Channel(id: m['id'] as String, name: m['name'] as String, code: m['code'] as String);
}

/// Mensaje del canal: texto, foto o ubicación.
class ChannelMessage {
  ChannelMessage({
    required this.id,
    required this.userId,
    required this.userName,
    required this.kind,
    required this.createdAt,
    this.body,
    this.photoUrl,
    this.lat,
    this.lng,
    this.heading,
  });

  final String id, userId, userName, kind;
  final DateTime createdAt;
  final String? body, photoUrl;
  final double? lat, lng, heading;

  bool get hasLocation => lat != null && lng != null;

  factory ChannelMessage.fromMap(Map<String, dynamic> m) => ChannelMessage(
        id: m['id'] as String,
        userId: m['user_id'] as String,
        userName: m['user_name'] as String,
        kind: m['kind'] as String,
        createdAt: DateTime.parse(m['created_at'] as String).toLocal(),
        body: m['body'] as String?,
        photoUrl: m['photo_url'] as String?,
        lat: (m['lat'] as num?)?.toDouble(),
        lng: (m['lng'] as num?)?.toDouble(),
        heading: (m['heading'] as num?)?.toDouble(),
      );
}

/// Ubicación en vivo de un miembro (vía "presence" de Supabase Realtime:
/// no se guarda en la base de datos, solo viaja mientras está conectado).
class LiveMember {
  LiveMember({
    required this.userId,
    required this.name,
    this.lat,
    this.lng,
    this.heading,
    this.accuracy,
    required this.updatedAt,
  });

  final String userId, name;
  final double? lat, lng, heading, accuracy;
  final DateTime updatedAt;

  bool get hasLocation => lat != null && lng != null;
  bool get isStale => DateTime.now().difference(updatedAt) > const Duration(minutes: 2);

  Map<String, dynamic> toPayload() => {
        'user_id': userId,
        'name': name,
        'lat': lat,
        'lng': lng,
        'heading': heading,
        'accuracy': accuracy,
        'updated_at': updatedAt.toUtc().toIso8601String(),
      };

  static LiveMember? fromPayload(Map<String, dynamic> p) {
    final id = p['user_id'];
    if (id is! String) return null;
    return LiveMember(
      userId: id,
      name: (p['name'] as String?) ?? 'Usuario',
      lat: (p['lat'] as num?)?.toDouble(),
      lng: (p['lng'] as num?)?.toDouble(),
      heading: (p['heading'] as num?)?.toDouble(),
      accuracy: (p['accuracy'] as num?)?.toDouble(),
      updatedAt: DateTime.tryParse(p['updated_at'] as String? ?? '')?.toLocal() ?? DateTime.now(),
    );
  }
}

class ChannelException implements Exception {
  ChannelException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Conexión con el servidor de canales (Supabase).
///
/// Cada institución usa SU PROPIO proyecto de Supabase: la URL y la clave
/// pública se configuran dentro de la app (pestaña Canales), así los datos
/// de una alcaldía nunca se mezclan con los de otra.
class ChannelBackend extends ChangeNotifier {
  String? url;
  String? anonKey;
  String? _initializedFor;

  bool get configured => (url ?? '').isNotEmpty && (anonKey ?? '').isNotEmpty;
  SupabaseClient get _db => Supabase.instance.client;
  String? get myId => _initializedFor == null ? null : _db.auth.currentUser?.id;

  Future<void> loadConfig() async {
    final p = await SharedPreferences.getInstance();
    url = p.getString('sbUrl');
    anonKey = p.getString('sbKey');
    notifyListeners();
  }

  Future<void> saveConfig(String newUrl, String newKey) async {
    final u = newUrl.trim().replaceAll(RegExp(r'/+$'), '');
    final k = newKey.trim();
    if (!u.startsWith('https://')) throw ChannelException('La URL debe empezar con https://');
    if (k.length < 20) throw ChannelException('La clave pública parece incompleta.');
    url = u;
    anonKey = k;
    final p = await SharedPreferences.getInstance();
    await p.setString('sbUrl', u);
    await p.setString('sbKey', k);
    await ensureReady(); // valida conectando
    notifyListeners();
  }

  /// Inicializa Supabase e inicia sesión anónima (sin correo ni contraseña).
  Future<void> ensureReady() async {
    if (!configured) throw ChannelException('Configura el servidor de canales primero.');
    final sig = '$url|$anonKey';
    if (_initializedFor != sig) {
      if (_initializedFor != null) {
        await Supabase.instance.dispose();
      }
      await Supabase.initialize(url: url!, anonKey: anonKey!);
      _initializedFor = sig;
    }
    if (_db.auth.currentUser == null) {
      try {
        await _db.auth.signInAnonymously();
      } on AuthException catch (e) {
        throw ChannelException(e.message.contains('Anonymous')
            ? 'Activa "Anonymous sign-ins" en Supabase → Authentication → Sign In / Providers.'
            : 'No se pudo iniciar sesión: ${e.message}');
      }
    }
  }

  dynamic _single(dynamic r) => r is List ? (r.isEmpty ? null : r.first) : r;

  Future<Channel> create(String name, String displayName) async {
    await ensureReady();
    try {
      final r = _single(await _db.rpc('create_channel', params: {'p_name': name, 'p_display': displayName}));
      return Channel.fromMap(Map<String, dynamic>.from(r as Map));
    } on PostgrestException catch (e) {
      throw ChannelException(_friendly(e));
    }
  }

  Future<Channel> join(String code, String displayName) async {
    await ensureReady();
    try {
      final r = _single(await _db.rpc('join_channel', params: {'p_code': code, 'p_display': displayName}));
      return Channel.fromMap(Map<String, dynamic>.from(r as Map));
    } on PostgrestException catch (e) {
      throw ChannelException(_friendly(e));
    }
  }

  Future<void> leave(String channelId) async {
    await ensureReady();
    await _db.from('channel_members').delete().eq('channel_id', channelId).eq('user_id', myId!);
  }

  /// Canales donde soy miembro (la seguridad del servidor filtra el resto).
  Future<List<Channel>> myChannels() async {
    await ensureReady();
    try {
      final rows = await _db.from('channels').select().order('created_at', ascending: false);
      return [for (final r in rows) Channel.fromMap(r)];
    } on PostgrestException catch (e) {
      throw ChannelException(_friendly(e));
    }
  }

  Future<List<ChannelMessage>> recentMessages(String channelId, {int limit = 120}) async {
    final rows = await _db
        .from('channel_messages')
        .select()
        .eq('channel_id', channelId)
        .order('created_at', ascending: false)
        .limit(limit);
    return [for (final r in rows) ChannelMessage.fromMap(r)].reversed.toList();
  }

  Future<void> sendText(String channelId, String userName, String text,
      {double? lat, double? lng}) async {
    await _db.from('channel_messages').insert({
      'channel_id': channelId,
      'user_name': userName,
      'kind': 'text',
      'body': text,
      'lat': lat,
      'lng': lng,
    });
  }

  Future<void> sendLocation(String channelId, String userName,
      {required double lat, required double lng, double? heading, String? note}) async {
    await _db.from('channel_messages').insert({
      'channel_id': channelId,
      'user_name': userName,
      'kind': 'location',
      'body': note,
      'lat': lat,
      'lng': lng,
      'heading': heading,
    });
  }

  /// Sube la foto (reducida a 1600 px para ahorrar datos) y la publica.
  Future<void> sendPhoto(String channelId, String userName, CaptureRecord r) async {
    final raw = await File(r.filePath).readAsBytes();
    final small = await Isolate.run(() {
      final im = img.decodeJpg(raw);
      if (im == null) return raw;
      final s = im.width > 1600 ? img.copyResize(im, width: 1600) : im;
      return Uint8List.fromList(img.encodeJpg(s, quality: 80));
    });
    final path = '$channelId/${const Uuid().v4()}.jpg';
    await _db.storage.from('channel-photos').uploadBinary(
          path,
          small,
          fileOptions: const FileOptions(contentType: 'image/jpeg'),
        );
    final publicUrl = _db.storage.from('channel-photos').getPublicUrl(path);
    await _db.from('channel_messages').insert({
      'channel_id': channelId,
      'user_name': userName,
      'kind': 'photo',
      'body': r.activity,
      'photo_url': publicUrl,
      'lat': r.latitude,
      'lng': r.longitude,
      'heading': r.heading,
    });
  }

  /// Sala en vivo: mensajes nuevos + ubicación de los miembros conectados.
  ChannelRoom openRoom(String channelId) => ChannelRoom._(this, channelId);

  String _friendly(PostgrestException e) {
    final m = e.message;
    if (m.contains('no válido')) return 'Código de canal no válido.';
    if (m.contains('does not exist') || e.code == 'PGRST202') {
      return 'El servidor no está preparado. Ejecuta el script supabase/instalar_canales.sql.';
    }
    return m;
  }
}

/// Conexión en tiempo real a un canal.
class ChannelRoom {
  ChannelRoom._(this._backend, this.channelId);

  final ChannelBackend _backend;
  final String channelId;
  RealtimeChannel? _rt;

  final _messages = StreamController<ChannelMessage>.broadcast();
  final members = ValueNotifier<List<LiveMember>>(const []);
  final connected = ValueNotifier<bool>(false);

  Stream<ChannelMessage> get messages => _messages.stream;

  SupabaseClient get _db => Supabase.instance.client;

  void connect() {
    final me = _backend.myId ?? '';
    final ch = _db.channel(
      'room:$channelId',
      opts: RealtimeChannelConfig(self: true, key: me),
    );
    ch.onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'channel_messages',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'channel_id',
        value: channelId,
      ),
      callback: (payload) {
        try {
          _messages.add(ChannelMessage.fromMap(payload.newRecord));
        } catch (_) {}
      },
    );
    ch.onPresenceSync((_) => _syncPresence());
    ch.subscribe((status, error) {
      connected.value = status == RealtimeSubscribeStatus.subscribed;
    });
    _rt = ch;
  }

  void _syncPresence() {
    final ch = _rt;
    if (ch == null) return;
    final byUser = <String, LiveMember>{};
    for (final state in ch.presenceState()) {
      for (final p in state.presences) {
        final m = LiveMember.fromPayload(Map<String, dynamic>.from(p.payload));
        if (m == null) continue;
        final prev = byUser[m.userId];
        if (prev == null || m.updatedAt.isAfter(prev.updatedAt)) byUser[m.userId] = m;
      }
    }
    members.value = byUser.values.toList()..sort((a, b) => a.name.compareTo(b.name));
  }

  /// Publica mi ubicación en vivo a los demás miembros conectados.
  Future<void> shareMyLocation(LiveMember me) async {
    final ch = _rt;
    if (ch == null || !connected.value) return;
    await ch.track(me.toPayload());
  }

  Future<void> close() async {
    final ch = _rt;
    _rt = null;
    if (ch != null) {
      try {
        await ch.untrack();
      } catch (_) {}
      await _db.removeChannel(ch);
    }
    await _messages.close();
    members.dispose();
    connected.dispose();
  }
}
