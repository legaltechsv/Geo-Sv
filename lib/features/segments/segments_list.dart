import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app_services.dart';
import '../../core/geocoding/street_detector.dart';
import '../../core/permissions/permission_service.dart';
import '../../core/ui/glass.dart';
import 'segment.dart';
import 'segment_detail_screen.dart';

/// Lista de tramos (se muestra dentro de la pestaña Mapa → Tramos).
class SegmentsList extends StatefulWidget {
  const SegmentsList({super.key, required this.refresh});
  final ValueNotifier<int> refresh;

  @override
  State<SegmentsList> createState() => _SegmentsListState();
}

class _SegmentsListState extends State<SegmentsList> {
  late Future<List<(Segment, SegmentGeometry)>> _data = _load();

  @override
  void initState() {
    super.initState();
    widget.refresh.addListener(_reload);
  }

  @override
  void dispose() {
    widget.refresh.removeListener(_reload);
    super.dispose();
  }

  void _reload() => setState(() => _data = _load());

  Future<List<(Segment, SegmentGeometry)>> _load() async {
    final list = await services.segments.all();
    return [
      for (final s in list)
        (s, SegmentGeometry(await services.captures.bySegment(s.id), s.markIntervalM)),
    ];
  }

  Future<void> _open(String id) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => SegmentDetailScreen(segmentId: id)));
    _reload();
  }

  Future<void> _new() async {
    final created = await showNewSegmentSheet(context);
    if (created != null) await _open(created.id);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<(Segment, SegmentGeometry)>>(
      future: _data,
      builder: (context, snap) {
        final items = snap.data ?? const [];
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          GradientButton(label: 'Nuevo tramo', icon: Icons.add_road, onPressed: _new),
          const SizedBox(height: 14),
          if (snap.hasData && items.isEmpty)
            const GlassCard(
              child: Text(
                'Un tramo mide una calle o ruta con fotos: marca el inicio, toma fotos en el '
                'recorrido y marca el final. La app calcula distancias, estaciones cada N metros y el área.',
                style: TextStyle(color: AppColors.textMuted, height: 1.4),
              ),
            ),
          for (final (n, (s, g)) in items.indexed)
            FadeSlideIn(
              index: n.clamp(0, 8),
              child: GlassCard(
                margin: const EdgeInsets.only(bottom: 10),
                onTap: () => _open(s.id),
                child: Row(children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      gradient: AppColors.accentGradient,
                    ),
                    child: const Icon(Icons.timeline, color: Colors.white),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(s.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                      Text(
                          '${g.points.length} puntos · ${DateFormat('dd/MM/yy').format(s.createdAtUtc.toLocal())}',
                          style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                      const SizedBox(height: 6),
                      StatusPill(
                        label: s.closed ? 'Cerrado' : 'Abierto',
                        color: s.closed ? AppColors.teal : AppColors.amber,
                      ),
                    ]),
                  ),
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text('${g.length.toStringAsFixed(1)} m',
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                    if (s.widthM != null)
                      Text('${(g.length * s.widthM!).toStringAsFixed(1)} m²',
                          style: const TextStyle(color: AppColors.cyan)),
                  ]),
                ]),
              ),
            ),
        ]);
      },
    );
  }
}

/// Formulario de nuevo tramo.
Future<Segment?> showNewSegmentSheet(BuildContext context) =>
    showGlassSheet<Segment>(context, builder: (_) => const _NewSegmentForm());

class _NewSegmentForm extends StatefulWidget {
  const _NewSegmentForm();
  @override
  State<_NewSegmentForm> createState() => _NewSegmentFormState();
}

class _NewSegmentFormState extends State<_NewSegmentForm> {
  final _name = TextEditingController();
  final _width = TextEditingController();
  double _interval = 10;

  // Detección automática de la calle / intersección.
  bool _detecting = false;
  bool _userEdited = false; // si el usuario escribe, no se le pisa el texto
  bool _settingText = false;
  List<String> _suggestions = const [];
  String? _detectMsg;

  @override
  void initState() {
    super.initState();
    _name.addListener(() {
      if (!_settingText) _userEdited = true;
    });
    _detect();
  }

  Future<void> _detect() async {
    setState(() {
      _detecting = true;
      _detectMsg = null;
    });
    try {
      if (await services.permissions.ensureLocation() != PermissionOutcome.granted) {
        throw Exception('Sin permiso de ubicación');
      }
      final fix = await services.location.getFixAtShutter(timeout: const Duration(seconds: 8));
      final guess = await StreetDetector().detect(fix.latitude, fix.longitude);
      if (!mounted) return;
      final sug = guess.suggestions();
      setState(() {
        _suggestions = sug;
        _detectMsg = sug.isEmpty
            ? 'No se reconoció el nombre de la calle aquí. Escríbelo.'
            : (guess.cross.isNotEmpty
                ? 'Intersección detectada. Puedes elegir otra opción o editarla.'
                : 'Calle detectada. Puedes editarla.');
      });
      if (sug.isNotEmpty && !_userEdited) _setName(sug.first);
    } catch (_) {
      if (mounted) setState(() => _detectMsg = 'No se pudo detectar la calle (sin GPS o sin internet). Escríbela.');
    } finally {
      if (mounted) setState(() => _detecting = false);
    }
  }

  void _setName(String v) {
    _settingText = true;
    _name.text = v;
    _name.selection = TextSelection.collapsed(offset: v.length);
    _settingText = false;
  }

  @override
  void dispose() {
    _name.dispose();
    _width.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (_name.text.trim().isEmpty) return;
    final s = await services.segments.create(
      name: _name.text,
      interval: _interval,
      width: double.tryParse(_width.text.replaceAll(',', '.')),
    );
    if (mounted) Navigator.pop(context, s);
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Nuevo tramo', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 16),
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: 'Nombre del tramo / calle *',
              hintText: '4a Calle Oriente, entre 2a y 4a Av.',
              prefixIcon: const Icon(Icons.add_road),
              suffixIcon: _detecting
                  ? const Padding(
                      padding: EdgeInsets.all(14),
                      child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                    )
                  : IconButton(
                      tooltip: 'Detectar de nuevo',
                      icon: const Icon(Icons.my_location),
                      onPressed: () {
                        _userEdited = false;
                        _detect();
                      },
                    ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _detecting ? 'Detectando la calle donde estás…' : (_detectMsg ?? ''),
            style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
          ),
          if (_suggestions.length > 1) ...[
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final s in _suggestions)
                ActionChip(
                  avatar: const Icon(Icons.auto_awesome, size: 16, color: AppColors.cyan),
                  label: Text(s, overflow: TextOverflow.ellipsis),
                  onPressed: () => _setName(s),
                  backgroundColor: Colors.white.withValues(alpha: 0.06),
                  side: BorderSide(color: Colors.white.withValues(alpha: 0.14)),
                ),
            ]),
          ],
          const SizedBox(height: 16),
          const Text('Marcar estación cada', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, children: [
            for (final v in const [5.0, 10.0, 20.0, 25.0, 50.0, 100.0])
              ChoiceChip(
                label: Text('${v.toStringAsFixed(0)} m'),
                selected: _interval == v,
                onSelected: (_) => setState(() => _interval = v),
                selectedColor: AppColors.violet.withValues(alpha: 0.35),
              ),
          ]),
          const SizedBox(height: 16),
          TextField(
            controller: _width,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Ancho promedio (m) — opcional',
              hintText: '6.5',
              helperText: 'Para calcular el área (bacheo, recarpeteo, pintura)',
              prefixIcon: Icon(Icons.straighten),
            ),
          ),
          const SizedBox(height: 20),
          GradientButton(label: 'Crear y empezar', icon: Icons.play_arrow_rounded, onPressed: _create),
        ]),
      );
}
