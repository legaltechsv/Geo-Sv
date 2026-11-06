import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app_services.dart';
import '../../../core/ui/glass.dart';
import '../../capture/domain/capture_record.dart';
import '../../capture/presentation/camera_screen.dart';
import '../../capture/presentation/preview_screen.dart';
import '../../reports/pdf_preview_screen.dart';
import '../../share/share_service.dart';
import '../domain/checklist_templates.dart';
import '../domain/inspection.dart';
import 'signature_sheet.dart';

/// Ejecución de una inspección: checklist, hallazgos, fotos, notas y cierre
/// con firma. Una inspección finalizada queda en solo lectura.
class InspectionDetailScreen extends StatefulWidget {
  const InspectionDetailScreen({super.key, required this.inspectionId});
  final String inspectionId;

  @override
  State<InspectionDetailScreen> createState() => _InspectionDetailScreenState();
}

class _InspectionDetailScreenState extends State<InspectionDetailScreen> {
  Inspection? _insp;
  List<ChecklistItem> _items = [];
  List<CaptureRecord> _photos = [];
  final _notes = TextEditingController();
  Timer? _saveNotes;
  Timer? _ticker; // actualiza la duración en vivo
  bool _generating = false;

  bool get _locked => _insp?.status == InspectionStatus.finalizada;

  @override
  void initState() {
    super.initState();
    _load();
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted && !_locked) setState(() {});
    });
  }

  @override
  void dispose() {
    _saveNotes?.cancel();
    _ticker?.cancel();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final i = await services.inspections.byId(widget.inspectionId);
    if (i == null) return;
    final items = await services.inspections.items(i.id);
    final photos = await services.captures.byInspection(i.id);
    if (!mounted) return;
    setState(() {
      _insp = i;
      _items = items;
      _photos = photos;
      if (_notes.text != i.generalNotes) _notes.text = i.generalNotes;
    });
  }

  Future<void> _setResult(ChecklistItem item, ItemResult r) async {
    if (_locked) return;
    HapticFeedback.selectionClick();
    setState(() {
      item.result = r;
      if (r == ItemResult.noCumple) {
        item.severity ??= Severity.media;
      } else {
        item.severity = null;
      }
    });
    await services.inspections.updateItem(item);
  }

  Future<void> _addPhoto() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CameraScreen(
          controller: services.camera,
          templates: services.templates,
          inspectionId: widget.inspectionId,
        ),
      ),
    );
    _photos = await services.captures.byInspection(widget.inspectionId);
    if (mounted) setState(() {});
  }

  Future<void> _finish() async {
    final insp = _insp!;
    final pending = ComplianceSummary(_items).pendientes;
    if (pending > 0) {
      final go = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Quedan puntos sin evaluar'),
          content: Text('Hay $pending puntos pendientes. ¿Finalizar de todos modos?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Revisar')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Finalizar')),
          ],
        ),
      );
      if (go != true) return;
    }
    if (!mounted) return;
    final sig = await showSignatureSheet(context, inspectionId: insp.id);
    if (sig == null) return;
    insp
      ..signaturePath = sig
      ..endedAtUtc = DateTime.now().toUtc()
      ..status = InspectionStatus.finalizada
      ..generalNotes = _notes.text;
    await services.inspections.update(insp);
    setState(() {});
    await _openReport();
  }

  Future<void> _openReport() async {
    setState(() => _generating = true);
    try {
      final logo = await services.logo.bytes();
      final insp = _insp!;
      final bytes = await services.reports.inspectionReport(
        inspection: insp,
        items: _items,
        photos: _photos,
        settings: services.settings.value,
        logo: logo,
      );
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PdfPreviewScreen(
            title: 'Informe ${insp.folio}',
            fileName: 'Informe_${insp.folio}.pdf',
            bytes: bytes,
            shareText: 'Informe ${insp.folio} · ${insp.siteName}\n'
                '📍 ${ShareService.shortMapsUrl(insp.latitude, insp.longitude)}',
            buildDocx: () => services.reports.inspectionDocx(
              inspection: insp,
              items: _items,
              photos: _photos,
              settings: services.settings.value,
              logo: logo,
            ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final insp = _insp;
    if (insp == null) {
      return const AuroraBackground(
          child: Scaffold(body: Center(child: CircularProgressIndicator())));
    }
    final t = ChecklistTemplates.byKey(insp.templateKey);
    final sum = ComplianceSummary(_items);
    final sections = <String, List<ChecklistItem>>{};
    for (final i in _items) {
      sections.putIfAbsent(i.section, () => []).add(i);
    }
    final bottom = MediaQuery.paddingOf(context).bottom;

    return AuroraBackground(
      child: Scaffold(
        appBar: AppBar(
          title: Text(insp.folio, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          actions: [
            IconButton(
              tooltip: 'Abrir en Maps',
              icon: const Icon(Icons.map_outlined),
              onPressed: () =>
                  launchUrl(Uri.parse(insp.mapsUrl), mode: LaunchMode.externalApplication),
            ),
            IconButton(
              tooltip: 'Vista previa PDF',
              icon: const Icon(Icons.picture_as_pdf_outlined),
              onPressed: _generating ? null : _openReport,
            ),
          ],
        ),
        body: ListView(
          padding: EdgeInsets.fromLTRB(16, 4, 16, bottom + 110),
          children: [
            // Encabezado de la visita
            FadeSlideIn(
              child: GlassCard(
                padding: const EdgeInsets.all(18),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Icon(t.icon, color: AppColors.cyan),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Text(t.name, style: const TextStyle(color: AppColors.textMuted))),
                    StatusPill(label: insp.status.label, color: insp.status.color),
                  ]),
                  const SizedBox(height: 10),
                  Text(insp.siteName,
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  _info(Icons.place_outlined, insp.address ?? insp.coordsText),
                  _info(Icons.schedule,
                      'Llegada ${DateFormat('dd/MM/yyyy HH:mm').format(insp.startedAtUtc.toLocal())} · ${_dur(insp.duration)}'),
                  if (insp.attendedBy.isNotEmpty) _info(Icons.badge_outlined, 'Atendido por ${insp.attendedBy}'),
                  const SizedBox(height: 14),
                  Row(children: [
                    ProgressRing(value: sum.percent, size: 70),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Avance ${(sum.progress * 100).round()}%',
                            style: const TextStyle(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: LinearProgressIndicator(
                            value: sum.progress,
                            minHeight: 7,
                            backgroundColor: Colors.white12,
                            color: AppColors.cyan,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(spacing: 6, runSpacing: 6, children: [
                          StatusPill(label: '${sum.cumple} cumple', color: ItemResult.cumple.color),
                          StatusPill(label: '${sum.noCumple} no cumple', color: ItemResult.noCumple.color),
                          if (sum.criticos > 0)
                            StatusPill(label: '${sum.criticos} críticos', color: Severity.critica.color),
                        ]),
                      ]),
                    ),
                  ]),
                ]),
              ),
            ),
            const SizedBox(height: 18),

            // Evidencias
            _sectionHeader('Evidencias fotográficas', '${_photos.length}'),
            SizedBox(
              height: 108,
              child: ListView(scrollDirection: Axis.horizontal, children: [
                if (!_locked)
                  GlassCard(
                    onTap: _addPhoto,
                    padding: EdgeInsets.zero,
                    radius: 18,
                    margin: const EdgeInsets.only(right: 10),
                    child: const SizedBox(
                      width: 100,
                      height: 108,
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(Icons.add_a_photo_outlined, color: AppColors.cyan),
                        SizedBox(height: 6),
                        Text('Agregar', style: TextStyle(fontSize: 12)),
                      ]),
                    ),
                  ),
                for (final ph in _photos)
                  GestureDetector(
                    onTap: () => Navigator.push(
                        context, MaterialPageRoute(builder: (_) => PreviewScreen(record: ph))),
                    child: Container(
                      width: 100,
                      margin: const EdgeInsets.only(right: 10),
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: Image.file(File(ph.filePath), fit: BoxFit.cover, cacheWidth: 260),
                    ),
                  ),
              ]),
            ),
            const SizedBox(height: 18),

            // Checklist
            for (final e in sections.entries) ...[
              _sectionHeader(e.key,
                  '${e.value.where((i) => i.result != ItemResult.pendiente).length}/${e.value.length}'),
              for (final item in e.value)
                _ChecklistCard(
                  item: item,
                  locked: _locked,
                  onResult: (r) => _setResult(item, r),
                  onSeverity: (s) async {
                    setState(() => item.severity = s);
                    await services.inspections.updateItem(item);
                  },
                  onNote: (n) {
                    item.note = n;
                    services.inspections.updateItem(item);
                  },
                ),
              const SizedBox(height: 10),
            ],

            // Observaciones generales
            _sectionHeader('Observaciones generales', ''),
            GlassCard(
              padding: const EdgeInsets.all(4),
              child: TextField(
                controller: _notes,
                enabled: !_locked,
                minLines: 3,
                maxLines: 8,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  hintText: 'Recomendaciones, acuerdos, plazos de corrección…',
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  fillColor: Colors.transparent,
                ),
                onChanged: (v) {
                  _saveNotes?.cancel();
                  _saveNotes = Timer(const Duration(milliseconds: 600), () {
                    insp.generalNotes = v;
                    services.inspections.update(insp);
                  });
                },
              ),
            ),
          ],
        ),
        bottomNavigationBar: Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, bottom + 12),
          child: _locked
              ? GradientButton(
                  label: 'Ver informe PDF',
                  icon: Icons.picture_as_pdf,
                  busy: _generating,
                  onPressed: _openReport,
                )
              : GradientButton(
                  label: 'Finalizar y firmar',
                  icon: Icons.draw_outlined,
                  busy: _generating,
                  onPressed: _finish,
                ),
        ),
      ),
    );
  }

  static String _dur(Duration d) =>
      d.inHours > 0 ? '${d.inHours} h ${d.inMinutes % 60} min' : '${d.inMinutes} min';

  Widget _info(IconData icon, String text) => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 16, color: AppColors.textMuted),
          const SizedBox(width: 6),
          Expanded(child: Text(text, style: const TextStyle(color: AppColors.textMuted, fontSize: 13))),
        ]),
      );

  Widget _sectionHeader(String title, String trailing) => Padding(
        padding: const EdgeInsets.only(bottom: 10, left: 4, right: 4),
        child: Row(children: [
          Expanded(
              child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
          Text(trailing, style: const TextStyle(color: AppColors.textMuted)),
        ]),
      );
}

class _ChecklistCard extends StatelessWidget {
  const _ChecklistCard({
    required this.item,
    required this.locked,
    required this.onResult,
    required this.onSeverity,
    required this.onNote,
  });

  final ChecklistItem item;
  final bool locked;
  final ValueChanged<ItemResult> onResult;
  final ValueChanged<Severity> onSeverity;
  final ValueChanged<String> onNote;

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      child: GlassCard(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        tint: item.result == ItemResult.pendiente ? null : item.result.color,
        opacity: 0.06,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(item.result.icon, size: 20, color: item.result.color),
            const SizedBox(width: 10),
            Expanded(
                child: Text(item.question,
                    style: const TextStyle(fontWeight: FontWeight.w600, height: 1.3))),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            for (final r in const [ItemResult.cumple, ItemResult.noCumple, ItemResult.noAplica])
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: _ResultButton(
                    result: r,
                    selected: item.result == r,
                    onTap: locked ? null : () => onResult(r),
                  ),
                ),
              ),
          ]),
          if (item.result == ItemResult.noCumple) ...[
            const SizedBox(height: 12),
            const Text('Gravedad', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
            const SizedBox(height: 6),
            Wrap(spacing: 6, children: [
              for (final s in Severity.values)
                ChoiceChip(
                  label: Text(s.label),
                  selected: item.severity == s,
                  onSelected: locked ? null : (_) => onSeverity(s),
                  selectedColor: s.color.withValues(alpha: 0.35),
                  backgroundColor: Colors.white.withValues(alpha: 0.04),
                  side: BorderSide(color: s.color.withValues(alpha: 0.5)),
                  visualDensity: VisualDensity.compact,
                ),
            ]),
            const SizedBox(height: 8),
            TextFormField(
              initialValue: item.note,
              enabled: !locked,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'Describe el hallazgo y la medida correctiva',
                isDense: true,
              ),
              onChanged: onNote,
            ),
          ],
        ]),
      ),
    );
  }
}

class _ResultButton extends StatelessWidget {
  const _ResultButton({required this.result, required this.selected, this.onTap});
  final ItemResult result;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: selected ? result.color.withValues(alpha: 0.28) : Colors.white.withValues(alpha: 0.05),
          border: Border.all(
              color: selected ? result.color : Colors.white.withValues(alpha: 0.12), width: selected ? 1.4 : 1),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 9),
              child: Center(
                child: Text(result.label,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                        color: selected ? result.color : AppColors.text)),
              ),
            ),
          ),
        ),
      );
}
