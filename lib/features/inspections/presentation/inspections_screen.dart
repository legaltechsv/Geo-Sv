import 'package:flutter/material.dart';

import '../../../app_services.dart';
import '../../../core/ui/glass.dart';
import '../../home/dashboard_screen.dart';
import '../domain/inspection.dart';
import 'inspection_detail_screen.dart';
import 'new_inspection_sheet.dart';

/// Lista de inspecciones con búsqueda y filtro por estado.
class InspectionsScreen extends StatefulWidget {
  const InspectionsScreen({super.key, required this.refresh});
  final ValueNotifier<int> refresh;

  @override
  State<InspectionsScreen> createState() => _InspectionsScreenState();
}

class _InspectionsScreenState extends State<InspectionsScreen> {
  late Future<(List<Inspection>, Map<String, ComplianceSummary>)> _data = _load();
  InspectionStatus? _filter;
  String _query = '';

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

  Future<(List<Inspection>, Map<String, ComplianceSummary>)> _load() async {
    final list = await services.inspections.all();
    final items = await services.inspections.itemsFor(list.map((e) => e.id).toList());
    return (list, {for (final e in items.entries) e.key: ComplianceSummary(e.value)});
  }

  Future<void> _open(String id) async {
    await Navigator.push(
        context, MaterialPageRoute(builder: (_) => InspectionDetailScreen(inspectionId: id)));
    _reload();
  }

  Future<void> _new() async {
    final i = await showNewInspectionSheet(context);
    if (i != null) await _open(i.id);
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return Stack(children: [
      FutureBuilder(
        future: _data,
        builder: (context, snap) {
          final (all, sums) = snap.data ?? (<Inspection>[], <String, ComplianceSummary>{});
          final q = _query.toLowerCase();
          final list = all
              .where((i) => _filter == null || i.status == _filter)
              .where((i) =>
                  q.isEmpty ||
                  i.siteName.toLowerCase().contains(q) ||
                  i.folio.toLowerCase().contains(q) ||
                  (i.address ?? '').toLowerCase().contains(q))
              .toList();
          return ListView(
            padding: EdgeInsets.fromLTRB(18, top + 14, 18, 130),
            children: [
              const Text('Inspecciones',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
              const SizedBox(height: 14),
              TextField(
                onChanged: (v) => setState(() => _query = v),
                decoration: const InputDecoration(
                  hintText: 'Buscar por lugar, folio o dirección',
                  prefixIcon: Icon(Icons.search),
                ),
              ),
              const SizedBox(height: 12),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  _chip('Todas', null, all.length),
                  _chip('En curso', InspectionStatus.enCurso,
                      all.where((i) => i.status == InspectionStatus.enCurso).length),
                  _chip('Finalizadas', InspectionStatus.finalizada,
                      all.where((i) => i.status == InspectionStatus.finalizada).length),
                ]),
              ),
              const SizedBox(height: 14),
              if (snap.connectionState == ConnectionState.waiting && snap.data == null)
                const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator())),
              if (snap.hasData && list.isEmpty)
                const GlassCard(
                  child: Text('No hay inspecciones con este filtro.',
                      style: TextStyle(color: AppColors.textMuted)),
                ),
              for (final (n, i) in list.indexed)
                FadeSlideIn(
                  index: n.clamp(0, 8),
                  child: InspectionTile(inspection: i, summary: sums[i.id], onTap: () => _open(i.id)),
                ),
            ],
          );
        },
      ),
      Positioned(
        right: 18,
        bottom: MediaQuery.paddingOf(context).bottom + 104,
        child: SizedBox(
          width: 190,
          child: GradientButton(label: 'Nueva', icon: Icons.add, onPressed: _new),
        ),
      ),
    ]);
  }

  Widget _chip(String label, InspectionStatus? value, int count) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          label: Text('$label  $count'),
          selected: _filter == value,
          onSelected: (_) => setState(() => _filter = value),
          selectedColor: AppColors.cyan.withValues(alpha: 0.25),
          backgroundColor: Colors.white.withValues(alpha: 0.05),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.14)),
        ),
      );
}
