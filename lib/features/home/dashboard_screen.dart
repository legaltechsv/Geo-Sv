import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app_services.dart';
import '../../core/ui/glass.dart';
import '../inspections/domain/checklist_templates.dart';
import '../inspections/domain/inspection.dart';
import '../inspections/presentation/inspection_detail_screen.dart';
import '../inspections/presentation/new_inspection_sheet.dart';
import '../visits/visits_service.dart';

class _DashboardData {
  _DashboardData({
    required this.monthInspections,
    required this.openFindings,
    required this.places,
    required this.photos,
    required this.avgCompliance,
    required this.recent,
    required this.compliance,
  });
  final int monthInspections, openFindings, places, photos;
  final double avgCompliance;
  final List<Inspection> recent;
  final Map<String, ComplianceSummary> compliance;
}

/// Panel de inicio: saludo, indicadores del mes, accesos rápidos y
/// últimas inspecciones.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({
    super.key,
    required this.refresh,
    required this.onNavigate,
    required this.onCamera,
  });
  final ValueNotifier<int> refresh;
  final ValueChanged<int> onNavigate;
  final VoidCallback onCamera;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late Future<_DashboardData> _data = _load();

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

  Future<_DashboardData> _load() async {
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month).toUtc();
    final month = await services.inspections.all(sinceUtc: monthStart);
    final recent = (await services.inspections.all()).take(5).toList();
    final items = await services.inspections
        .itemsFor({...month.map((e) => e.id), ...recent.map((e) => e.id)}.toList());
    final compliance = {for (final e in items.entries) e.key: ComplianceSummary(e.value)};
    final monthSums = month.map((m) => compliance[m.id]).whereType<ComplianceSummary>();
    final evaluated = monthSums.where((s) => s.evaluados > 0).toList();
    final places = await services.visits.places(VisitRange.mes);
    return _DashboardData(
      monthInspections: month.length,
      openFindings: monthSums.fold(0, (a, s) => a + s.noCumple),
      places: places.length,
      photos: places.fold(0, (a, p) => a + p.photos.length),
      avgCompliance: evaluated.isEmpty
          ? 0
          : evaluated.fold<double>(0, (a, s) => a + s.percent) / evaluated.length,
      recent: recent,
      compliance: compliance,
    );
  }

  String get _greeting {
    final h = DateTime.now().hour;
    return h < 12 ? 'Buenos días' : (h < 19 ? 'Buenas tardes' : 'Buenas noches');
  }

  Future<void> _newInspection() async {
    final created = await showNewInspectionSheet(context);
    if (created != null && mounted) {
      await Navigator.push(context,
          MaterialPageRoute(builder: (_) => InspectionDetailScreen(inspectionId: created.id)));
      _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = services.settings.value;
    final top = MediaQuery.paddingOf(context).top;
    return FutureBuilder<_DashboardData>(
      future: _data,
      builder: (context, snap) {
        final d = snap.data;
        return RefreshIndicator(
          onRefresh: () async => _reload(),
          child: ListView(
            padding: EdgeInsets.fromLTRB(18, top + 14, 18, 130),
            children: [
              // Encabezado
              FadeSlideIn(
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(DateFormat("EEEE d 'de' MMMM", 'es').format(DateTime.now()),
                          style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
                      const SizedBox(height: 2),
                      Text(
                          '$_greeting${s.inspectorName.isEmpty ? '' : ', ${s.inspectorName.split(' ').first}'}',
                          style: const TextStyle(
                              fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
                      if (s.institution.isNotEmpty)
                        Text(s.institution,
                            style: const TextStyle(color: AppColors.cyan, fontSize: 13)),
                    ]),
                  ),
                  GlassCard(
                    radius: 16,
                    padding: const EdgeInsets.all(10),
                    onTap: () => widget.onNavigate(3),
                    child: const Icon(Icons.person_outline),
                  ),
                ]),
              ),
              if (!s.isConfigured) ...[
                const SizedBox(height: 14),
                FadeSlideIn(
                  index: 1,
                  child: GlassCard(
                    tint: AppColors.amber,
                    onTap: () => widget.onNavigate(3),
                    child: const Row(children: [
                      Icon(Icons.info_outline, color: AppColors.amber),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                            'Configura el nombre de tu institución e inspector para que salgan en los reportes.'),
                      ),
                      Icon(Icons.chevron_right),
                    ]),
                  ),
                ),
              ],
              const SizedBox(height: 18),

              // Tarjeta principal: cumplimiento promedio del mes
              FadeSlideIn(
                index: 1,
                child: GlassCard(
                  padding: const EdgeInsets.all(20),
                  child: Row(children: [
                    ProgressRing(value: d?.avgCompliance ?? 0, size: 86),
                    const SizedBox(width: 18),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('Cumplimiento promedio',
                            style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
                        const Text('Este mes',
                            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 8),
                        Text('${d?.openFindings ?? 0} hallazgos registrados',
                            style: TextStyle(
                                color: (d?.openFindings ?? 0) > 0
                                    ? AppColors.danger
                                    : AppColors.teal,
                                fontWeight: FontWeight.w600)),
                      ]),
                    ),
                  ]),
                ),
              ),
              const SizedBox(height: 12),

              // Indicadores
              Row(children: [
                _Kpi(index: 2, icon: Icons.fact_check, color: AppColors.cyan,
                    value: '${d?.monthInspections ?? '–'}', label: 'Inspecciones'),
                const SizedBox(width: 12),
                _Kpi(index: 3, icon: Icons.place, color: AppColors.violet,
                    value: '${d?.places ?? '–'}', label: 'Lugares'),
                const SizedBox(width: 12),
                _Kpi(index: 4, icon: Icons.photo_library, color: AppColors.teal,
                    value: '${d?.photos ?? '–'}', label: 'Fotos'),
              ]),
              const SizedBox(height: 22),

              // Accesos rápidos
              const Text('Acciones rápidas',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              FadeSlideIn(
                index: 5,
                child: Row(children: [
                  _QuickAction(
                      icon: Icons.add_task, label: 'Nueva\ninspección', onTap: _newInspection),
                  const SizedBox(width: 10),
                  _QuickAction(
                      icon: Icons.photo_camera_outlined, label: 'Foto\nrápida', onTap: widget.onCamera),
                  const SizedBox(width: 10),
                  _QuickAction(
                      icon: Icons.summarize_outlined,
                      label: 'Reporte de\nvisitas',
                      onTap: () => widget.onNavigate(2)),
                ]),
              ),
              const SizedBox(height: 22),

              // Recientes
              Row(children: [
                const Text('Recientes',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                const Spacer(),
                TextButton(onPressed: () => widget.onNavigate(1), child: const Text('Ver todas')),
              ]),
              if (d != null && d.recent.isEmpty)
                const GlassCard(
                  child: Text('Aún no hay inspecciones. Crea la primera con "Nueva inspección".',
                      style: TextStyle(color: AppColors.textMuted)),
                ),
              if (d != null)
                ...d.recent.indexed.map((e) => FadeSlideIn(
                    index: 6 + e.$1,
                    child: InspectionTile(
                      inspection: e.$2,
                      summary: d.compliance[e.$2.id],
                      onTap: () async {
                        await Navigator.push(context,
                            MaterialPageRoute(
                                builder: (_) => InspectionDetailScreen(inspectionId: e.$2.id)));
                        _reload();
                      },
                    ),
                  )),
            ],
          ),
        );
      },
    );
  }
}

class _Kpi extends StatelessWidget {
  const _Kpi({
    required this.index,
    required this.icon,
    required this.color,
    required this.value,
    required this.label,
  });
  final int index;
  final IconData icon;
  final Color color;
  final String value, label;

  @override
  Widget build(BuildContext context) => Expanded(
        child: FadeSlideIn(
          index: index,
          child: GlassCard(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 18, color: color),
              ),
              const SizedBox(height: 10),
              Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
              Text(label, style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
            ]),
          ),
        ),
      );
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Expanded(
        child: GlassCard(
          onTap: onTap,
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 10),
          child: Column(children: [
            ShaderMask(
              shaderCallback: (r) => AppColors.accentGradient.createShader(r),
              child: Icon(icon, size: 28, color: Colors.white),
            ),
            const SizedBox(height: 8),
            Text(label,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, height: 1.2)),
          ]),
        ),
      );
}

/// Tarjeta de inspección reutilizada en Panel e Inspecciones.
class InspectionTile extends StatelessWidget {
  const InspectionTile({super.key, required this.inspection, this.summary, this.onTap});
  final Inspection inspection;
  final ComplianceSummary? summary;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = ChecklistTemplates.byKey(inspection.templateKey);
    final s = summary;
    return GlassCard(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      onTap: onTap,
      child: Row(children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: LinearGradient(colors: [
              inspection.status.color.withValues(alpha: 0.35),
              inspection.status.color.withValues(alpha: 0.08),
            ]),
          ),
          child: Icon(t.icon, color: inspection.status.color),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(inspection.siteName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            const SizedBox(height: 2),
            Text(
                '${inspection.folio} · ${DateFormat('dd/MM/yy HH:mm').format(inspection.startedAtUtc.toLocal())}',
                style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
            const SizedBox(height: 6),
            Row(children: [
              StatusPill(label: inspection.status.label, color: inspection.status.color),
              if (s != null && s.noCumple > 0) ...[
                const SizedBox(width: 6),
                StatusPill(
                    label: '${s.noCumple} hallazgos',
                    color: AppColors.danger,
                    icon: Icons.warning_amber_rounded),
              ],
            ]),
          ]),
        ),
        if (s != null) ProgressRing(value: s.percent, size: 46),
      ]),
    );
  }
}
