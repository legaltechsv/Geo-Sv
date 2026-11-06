import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/location/compass_service.dart';
import '../capture/domain/capture_record.dart';
import '../segments/segment.dart';
import 'docx_builder.dart';
import '../inspections/domain/checklist_templates.dart';
import '../inspections/domain/inspection.dart';
import '../settings/settings_service.dart';
import '../visits/visits_service.dart';

/// Genera los reportes PDF (formato carta), 100 % offline.
///
/// - Informe de inspección: datos generales + QR al lugar, resumen de
///   cumplimiento, hallazgos, checklist, observaciones, fotos y firma.
/// - Reporte de lugares visitados: resumen, tabla por lugar con enlace
///   a Google Maps y detalle cronológico de visitas.
class ReportService {
  static final _dt = DateFormat('dd/MM/yyyy HH:mm');
  static final _d = DateFormat('dd/MM/yyyy');

  static const _ink = PdfColor.fromInt(0xFF0B1020);
  static const _muted = PdfColor.fromInt(0xFF5B6478);
  static const _line = PdfColor.fromInt(0xFFDDE1EA);
  static const _soft = PdfColor.fromInt(0xFFF3F5F9);
  static const _accent = PdfColor.fromInt(0xFF2563EB);

  static PdfColor _resultColor(ItemResult r) => switch (r) {
        ItemResult.cumple => const PdfColor.fromInt(0xFF16A34A),
        ItemResult.noCumple => const PdfColor.fromInt(0xFFDC2626),
        ItemResult.noAplica => _muted,
        ItemResult.pendiente => const PdfColor.fromInt(0xFFD97706),
      };

  static String _dur(Duration d) =>
      d.inHours > 0 ? '${d.inHours} h ${d.inMinutes % 60} min' : '${d.inMinutes} min';

  static DateTime _local(DateTime utc) => utc.toLocal();

  // ───────────────────────── Informe de inspección ─────────────────────────

  Future<Uint8List> inspectionReport({
    required Inspection inspection,
    required List<ChecklistItem> items,
    required List<CaptureRecord> photos,
    required AppSettings settings,
    Uint8List? logo,
  }) async {
    final t = ChecklistTemplates.byKey(inspection.templateKey);
    final logoImg = logo == null ? null : pw.MemoryImage(logo);
    final sum = ComplianceSummary(items);
    final findings = items.where((i) => i.isFinding).toList()
      ..sort((a, b) => (b.severity?.index ?? 0).compareTo(a.severity?.index ?? 0));

    // Fotos reducidas a ~900 px para que el PDF pese poco (WhatsApp/correo).
    final thumbs = <(CaptureRecord, pw.MemoryImage)>[];
    for (final p in photos) {
      final f = File(p.filePath);
      if (!await f.exists()) continue;
      final small = await _downscale(await f.readAsBytes());
      thumbs.add((p, pw.MemoryImage(small)));
    }

    pw.MemoryImage? signature;
    if (inspection.signaturePath != null && await File(inspection.signaturePath!).exists()) {
      signature = pw.MemoryImage(await File(inspection.signaturePath!).readAsBytes());
    }

    final doc = pw.Document(
      title: 'Informe ${inspection.folio}',
      author: settings.inspectorName,
      creator: 'GEO CUSCA SUR',
    );

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.letter,
        margin: const pw.EdgeInsets.fromLTRB(36, 32, 36, 32),
        header: (ctx) => _header(settings, 'INFORME DE INSPECCIÓN', inspection.folio, logoImg),
        footer: _footer,
        build: (ctx) => [
          // Datos generales + QR
          pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Expanded(
              child: _kvTable([
                ('Tipo', t.name),
                ('Lugar', inspection.siteName),
                ('Dirección', inspection.address ?? 'No disponible (capturado sin conexión)'),
                ('Coordenadas', '${inspection.coordsText}  (±${inspection.accuracy.toStringAsFixed(0)} m)'),
                ('Atendido por', inspection.attendedBy.isEmpty ? '—' : inspection.attendedBy),
                ('Inspector', inspection.inspectorName.isEmpty ? settings.inspectorName : inspection.inspectorName),
                ('Inicio', _dt.format(_local(inspection.startedAtUtc))),
                ('Fin', inspection.endedAtUtc == null ? 'En curso' : _dt.format(_local(inspection.endedAtUtc!))),
                ('Duración', _dur(inspection.duration)),
              ]),
            ),
            pw.SizedBox(width: 16),
            pw.Column(children: [
              pw.BarcodeWidget(
                barcode: pw.Barcode.qrCode(),
                data: inspection.mapsUrl,
                width: 92,
                height: 92,
              ),
              pw.SizedBox(height: 4),
              pw.UrlLink(
                destination: inspection.mapsUrl,
                child: pw.Text('Abrir en Google Maps',
                    style: const pw.TextStyle(fontSize: 8, color: _accent)),
              ),
            ]),
          ]),
          pw.SizedBox(height: 16),

          // Resumen
          _sectionTitle('Resumen de cumplimiento'),
          pw.Row(children: [
            _metric('${(sum.percent * 100).toStringAsFixed(0)} %', 'Cumplimiento'),
            _metric('${sum.cumple}', 'Cumple'),
            _metric('${sum.noCumple}', 'No cumple'),
            _metric('${sum.noAplica}', 'No aplica'),
            _metric('${sum.criticos}', 'Críticos'),
          ]),
          pw.SizedBox(height: 16),

          // Hallazgos
          if (findings.isNotEmpty) ...[
            _sectionTitle('Hallazgos (${findings.length})'),
            ...findings.map((f) => pw.Container(
                  margin: const pw.EdgeInsets.only(bottom: 6),
                  padding: const pw.EdgeInsets.all(8),
                  decoration: pw.BoxDecoration(
                    border: pw.Border(
                        left: pw.BorderSide(
                            color: _resultColor(ItemResult.noCumple), width: 3)),
                    color: _soft,
                  ),
                  child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                    pw.Text('${f.section} · ${f.question}',
                        style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                    pw.Text('Gravedad: ${f.severity?.label ?? 'Sin clasificar'}',
                        style: const pw.TextStyle(fontSize: 9, color: _muted)),
                    if (f.note.isNotEmpty)
                      pw.Text(f.note, style: const pw.TextStyle(fontSize: 9)),
                    // Fotos de este hallazgo
                    if (thumbs.any((t) => t.$1.itemId == f.id)) ...[
                      pw.SizedBox(height: 5),
                      pw.Wrap(spacing: 6, runSpacing: 6, children: [
                        for (final t in thumbs.where((t) => t.$1.itemId == f.id))
                          pw.ClipRRect(
                            horizontalRadius: 3,
                            verticalRadius: 3,
                            child: pw.Image(t.$2, height: 78, width: 104, fit: pw.BoxFit.cover),
                          ),
                      ]),
                    ],
                  ]),
                )),
            pw.SizedBox(height: 10),
          ],

          // Checklist completo por sección
          _sectionTitle('Lista de verificación'),
          ..._checklistTables(items),
          pw.SizedBox(height: 12),

          if (inspection.generalNotes.trim().isNotEmpty) ...[
            _sectionTitle('Observaciones generales'),
            pw.Text(inspection.generalNotes, style: const pw.TextStyle(fontSize: 10)),
            pw.SizedBox(height: 12),
          ],

          // Evidencias fotográficas
          if (thumbs.isNotEmpty) ...[
            _sectionTitle('Evidencias fotográficas (${thumbs.length})'),
            pw.Wrap(
              spacing: 10,
              runSpacing: 10,
              children: thumbs
                  .map((e) => pw.SizedBox(
                        width: 165,
                        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                          pw.ClipRRect(
                            horizontalRadius: 4,
                            verticalRadius: 4,
                            child: pw.Image(e.$2, height: 124, width: 165, fit: pw.BoxFit.cover),
                          ),
                          pw.SizedBox(height: 3),
                          pw.Text(_dt.format(_local(e.$1.capturedAtUtc)),
                              style: const pw.TextStyle(fontSize: 8)),
                          pw.UrlLink(
                            destination: e.$1.mapsUrl,
                            child: pw.Text(e.$1.coordsText,
                                style: const pw.TextStyle(fontSize: 8, color: _accent)),
                          ),
                          if (e.$1.activity != null || e.$1.heading != null)
                            pw.Text(
                                [
                                  if (e.$1.activity != null) e.$1.activity!,
                                  if (e.$1.heading != null) 'Hacia ${CompassService.label(e.$1.heading!)}',
                                ].join(' · '),
                                style: const pw.TextStyle(fontSize: 7)),
                          pw.Text('Código ${e.$1.verificationCode}',
                              style: const pw.TextStyle(fontSize: 7, color: _muted)),
                        ]),
                      ))
                  .toList(),
            ),
            pw.SizedBox(height: 16),
          ],

          // Firmas
          _sectionTitle('Firmas'),
          pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
            pw.Expanded(
              child: _signatureBlock(
                signature,
                inspection.inspectorName.isEmpty ? settings.inspectorName : inspection.inspectorName,
                settings.inspectorRole.isEmpty ? 'Inspector' : settings.inspectorRole,
              ),
            ),
            pw.SizedBox(width: 30),
            pw.Expanded(
              child: _signatureBlock(null,
                  inspection.attendedBy.isEmpty ? ' ' : inspection.attendedBy, 'Atendido por'),
            ),
          ]),
        ],
      ),
    );
    return doc.save();
  }

  List<pw.Widget> _checklistTables(List<ChecklistItem> items) {
    final sections = <String, List<ChecklistItem>>{};
    for (final i in items) {
      sections.putIfAbsent(i.section, () => []).add(i);
    }
    return [
      for (final e in sections.entries) ...[
        pw.Padding(
          padding: const pw.EdgeInsets.only(top: 6, bottom: 4),
          child: pw.Text(e.key,
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10, color: _ink)),
        ),
        pw.Table(
          border: const pw.TableBorder(
              horizontalInside: pw.BorderSide(color: _line, width: 0.5),
              bottom: pw.BorderSide(color: _line, width: 0.5)),
          columnWidths: const {
            0: pw.FlexColumnWidth(5),
            1: pw.FlexColumnWidth(1.4),
            2: pw.FlexColumnWidth(3),
          },
          children: [
            for (final i in e.value)
              pw.TableRow(
                verticalAlignment: pw.TableCellVerticalAlignment.middle,
                children: [
                  pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(vertical: 4),
                      child: pw.Text(i.question, style: const pw.TextStyle(fontSize: 9))),
                  pw.Text(i.result.label,
                      style: pw.TextStyle(
                          fontSize: 9,
                          fontWeight: pw.FontWeight.bold,
                          color: _resultColor(i.result))),
                  pw.Text(
                      [if (i.severity != null && i.isFinding) i.severity!.label, if (i.note.isNotEmpty) i.note]
                          .join(' · '),
                      style: const pw.TextStyle(fontSize: 8, color: _muted)),
                ],
              ),
          ],
        ),
      ],
    ];
  }

  // ───────────────────────── Reporte de lugares visitados ─────────────────────────

  Future<Uint8List> visitsReport({
    required List<VisitedPlace> places,
    required VisitRange range,
    required AppSettings settings,
    Uint8List? logo,
  }) async {
    final logoImg = logo == null ? null : pw.MemoryImage(logo);
    final totalVisits = places.fold<int>(0, (a, p) => a + p.visits.length);
    final totalPhotos = places.fold<int>(0, (a, p) => a + p.photos.length);
    final totalTime = places.fold<Duration>(Duration.zero, (a, p) => a + p.totalTime);
    final allVisits = [for (final p in places) ...p.visits]
      ..sort((a, b) => a.startedAtUtc.compareTo(b.startedAtUtc));

    final doc = pw.Document(title: 'Reporte de lugares visitados', creator: 'GEO CUSCA SUR');
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.letter,
        margin: const pw.EdgeInsets.fromLTRB(36, 32, 36, 32),
        header: (ctx) => _header(settings, 'REPORTE DE LUGARES VISITADOS',
            'Periodo: ${range.label} · ${_d.format(DateTime.now())}', logoImg),
        footer: _footer,
        build: (ctx) => [
          pw.Row(children: [
            _metric('${places.length}', 'Lugares'),
            _metric('$totalVisits', 'Visitas'),
            _metric('$totalPhotos', 'Fotos'),
            _metric(_dur(totalTime), 'Tiempo en sitio'),
          ]),
          pw.SizedBox(height: 16),
          _sectionTitle('Lugares'),
          pw.TableHelper.fromTextArray(
            headers: ['#', 'Lugar', 'Visitas', 'Fotos', 'Tiempo', 'Última visita', 'Mapa'],
            data: [
              for (var i = 0; i < places.length; i++)
                [
                  '${i + 1}',
                  '${places[i].name}${places[i].address == null ? '' : '\n${places[i].address}'}',
                  '${places[i].visits.length}',
                  '${places[i].photos.length}',
                  _dur(places[i].totalTime),
                  _dt.format(_local(places[i].lastVisit)),
                  '${places[i].latitude.toStringAsFixed(5)},\n${places[i].longitude.toStringAsFixed(5)}',
                ],
            ],
            headerStyle: pw.TextStyle(
                fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
            headerDecoration: const pw.BoxDecoration(color: _ink),
            cellStyle: const pw.TextStyle(fontSize: 8),
            oddRowDecoration: const pw.BoxDecoration(color: _soft),
            columnWidths: const {
              0: pw.FixedColumnWidth(18),
              1: pw.FlexColumnWidth(4),
              2: pw.FlexColumnWidth(1.2),
              3: pw.FlexColumnWidth(1),
              4: pw.FlexColumnWidth(1.6),
              5: pw.FlexColumnWidth(2),
              6: pw.FlexColumnWidth(2),
            },
            cellAlignments: {
              0: pw.Alignment.center,
              2: pw.Alignment.center,
              3: pw.Alignment.center,
            },
          ),
          pw.SizedBox(height: 6),
          // Enlaces tocables a cada lugar (el PDF los abre en Maps)
          pw.Wrap(spacing: 8, runSpacing: 4, children: [
            for (var i = 0; i < places.length; i++)
              pw.UrlLink(
                destination:
                    'https://www.google.com/maps/search/?api=1&query=${places[i].latitude},${places[i].longitude}',
                child: pw.Text('[${i + 1}] Ver en Maps',
                    style: const pw.TextStyle(fontSize: 8, color: _accent)),
              ),
          ]),
          if (allVisits.isNotEmpty) ...[
            pw.SizedBox(height: 16),
            _sectionTitle('Detalle cronológico de visitas'),
            pw.TableHelper.fromTextArray(
              headers: ['Folio', 'Fecha', 'Lugar', 'Tipo', 'Duración', 'Estado'],
              data: [
                for (final v in allVisits)
                  [
                    v.folio,
                    _dt.format(_local(v.startedAtUtc)),
                    v.siteName,
                    ChecklistTemplates.byKey(v.templateKey).name,
                    _dur(v.duration),
                    v.status.label,
                  ],
              ],
              headerStyle:
                  pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
              headerDecoration: const pw.BoxDecoration(color: _ink),
              cellStyle: const pw.TextStyle(fontSize: 8),
              oddRowDecoration: const pw.BoxDecoration(color: _soft),
            ),
          ],
        ],
      ),
    );
    return doc.save();
  }

  // ───────────────────────── Versiones Word (.docx) ─────────────────────────

  Future<Uint8List> inspectionDocx({
    required Inspection inspection,
    required List<ChecklistItem> items,
    required List<CaptureRecord> photos,
    required AppSettings settings,
    Uint8List? logo,
  }) async {
    final t = ChecklistTemplates.byKey(inspection.templateKey);
    final sum = ComplianceSummary(items);
    final d = DocxBuilder();
    _docxHeader(d, settings, 'INFORME DE INSPECCIÓN', inspection.folio, logo);

    d.table([
      ['Dato', 'Detalle'],
      ['Tipo', t.name],
      ['Lugar', inspection.siteName],
      ['Dirección', inspection.address ?? 'No disponible (capturado sin conexión)'],
      ['Coordenadas', '${inspection.coordsText} (±${inspection.accuracy.toStringAsFixed(0)} m)'],
      ['Atendido por', inspection.attendedBy.isEmpty ? '—' : inspection.attendedBy],
      ['Inspector', inspection.inspectorName.isEmpty ? settings.inspectorName : inspection.inspectorName],
      ['Inicio', _dt.format(_local(inspection.startedAtUtc))],
      ['Fin', inspection.endedAtUtc == null ? 'En curso' : _dt.format(_local(inspection.endedAtUtc!))],
      ['Duración', _dur(inspection.duration)],
    ], widths: [28, 72]);
    d.link('Abrir ubicación en Google Maps', inspection.mapsUrl);

    d.heading('Resumen de cumplimiento', size: 24);
    d.table([
      ['Cumplimiento', 'Cumple', 'No cumple', 'No aplica', 'Críticos'],
      [
        '${(sum.percent * 100).toStringAsFixed(0)} %',
        '${sum.cumple}',
        '${sum.noCumple}',
        '${sum.noAplica}',
        '${sum.criticos}',
      ],
    ]);

    final findings = items.where((i) => i.isFinding).toList()
      ..sort((a, b) => (b.severity?.index ?? 0).compareTo(a.severity?.index ?? 0));
    if (findings.isNotEmpty) {
      d.heading('Hallazgos (${findings.length})', size: 24);
      d.table([
        ['Punto', 'Gravedad', 'Descripción / medida correctiva'],
        for (final f in findings)
          ['${f.section} · ${f.question}', f.severity?.label ?? 'Sin clasificar', f.note],
      ], widths: [45, 15, 40], headerFill: 'B91C1C');
      // Fotos de cada hallazgo
      for (final f in findings) {
        final own = photos.where((p) => p.itemId == f.id).toList();
        if (own.isEmpty) continue;
        d.paragraph('Evidencia: ${f.question}', bold: true, size: 18);
        for (final p in own) {
          final file = File(p.filePath);
          if (!await file.exists()) continue;
          final (bytes, w, h) = await _downscaleSized(await file.readAsBytes());
          d.image(bytes, widthPx: 260, heightPx: 260 * h / w,
              caption: '${_dt.format(_local(p.capturedAtUtc))} · ${p.coordsText}');
        }
      }
    }

    d.heading('Lista de verificación', size: 24);
    final sections = <String, List<ChecklistItem>>{};
    for (final i in items) {
      sections.putIfAbsent(i.section, () => []).add(i);
    }
    for (final e in sections.entries) {
      d.paragraph(e.key, bold: true, size: 21);
      d.table([
        ['Punto', 'Resultado', 'Observación'],
        for (final i in e.value)
          [
            i.question,
            i.result.label,
            [if (i.severity != null && i.isFinding) i.severity!.label, if (i.note.isNotEmpty) i.note]
                .join(' · '),
          ],
      ], widths: [55, 15, 30]);
    }

    if (inspection.generalNotes.trim().isNotEmpty) {
      d.heading('Observaciones generales', size: 24);
      d.paragraph(inspection.generalNotes);
    }

    if (photos.isNotEmpty) {
      d.heading('Evidencias fotográficas (${photos.length})', size: 24);
      for (final p in photos) {
        final f = File(p.filePath);
        if (!await f.exists()) continue;
        final (bytes, w, h) = await _downscaleSized(await f.readAsBytes());
        const maxW = 430.0;
        d.image(bytes, widthPx: maxW, heightPx: maxW * h / w);
        d.paragraph(
          [
            _dt.format(_local(p.capturedAtUtc)),
            p.coordsText,
            if (p.activity != null) p.activity!,
            if (p.heading != null) 'Hacia ${CompassService.label(p.heading!)}',
            'Código ${p.verificationCode}',
          ].join(' · '),
          size: 16,
          color: '5B6478',
        );
        d.link('Ver punto en Google Maps', p.mapsUrl);
      }
    }

    d.heading('Firmas', size: 24);
    if (inspection.signaturePath != null && await File(inspection.signaturePath!).exists()) {
      d.image(await File(inspection.signaturePath!).readAsBytes(),
          widthPx: 200, heightPx: 80, ext: 'png');
    } else {
      d.spacer();
      d.spacer();
    }
    d.paragraph('_______________________________');
    d.paragraph(inspection.inspectorName.isEmpty ? settings.inspectorName : inspection.inspectorName,
        bold: true);
    d.paragraph(settings.inspectorRole.isEmpty ? 'Inspector' : settings.inspectorRole, size: 18);
    d.spacer();
    d.paragraph('_______________________________');
    d.paragraph(inspection.attendedBy.isEmpty ? 'Atendido por' : inspection.attendedBy, bold: true);
    d.paragraph('Atendido por', size: 18);
    _docxFooter(d);
    return d.build();
  }

  Future<Uint8List> visitsDocx({
    required List<VisitedPlace> places,
    required VisitRange range,
    required AppSettings settings,
    Uint8List? logo,
  }) async {
    final d = DocxBuilder();
    _docxHeader(d, settings, 'REPORTE DE LUGARES VISITADOS',
        'Periodo: ${range.label} · ${_d.format(DateTime.now())}', logo);
    final totalVisits = places.fold<int>(0, (a, p) => a + p.visits.length);
    final totalPhotos = places.fold<int>(0, (a, p) => a + p.photos.length);
    final totalTime = places.fold<Duration>(Duration.zero, (a, p) => a + p.totalTime);
    d.table([
      ['Lugares', 'Visitas', 'Fotos', 'Tiempo en sitio'],
      ['${places.length}', '$totalVisits', '$totalPhotos', _dur(totalTime)],
    ]);
    d.heading('Lugares', size: 24);
    d.table([
      ['#', 'Lugar', 'Visitas', 'Fotos', 'Tiempo', 'Última visita'],
      for (var i = 0; i < places.length; i++)
        [
          '${i + 1}',
          '${places[i].name}${places[i].address == null ? '' : '\n${places[i].address}'}',
          '${places[i].visits.length}',
          '${places[i].photos.length}',
          _dur(places[i].totalTime),
          _dt.format(_local(places[i].lastVisit)),
        ],
    ], widths: [6, 40, 10, 10, 14, 20]);
    for (var i = 0; i < places.length; i++) {
      d.link('${places[i].name}: ver en Google Maps',
          'https://www.google.com/maps/search/?api=1&query=${places[i].latitude},${places[i].longitude}',
          prefix: '[${i + 1}] ');
    }
    final allVisits = [for (final p in places) ...p.visits]
      ..sort((a, b) => a.startedAtUtc.compareTo(b.startedAtUtc));
    if (allVisits.isNotEmpty) {
      d.heading('Detalle cronológico de visitas', size: 24);
      d.table([
        ['Folio', 'Fecha', 'Lugar', 'Tipo', 'Duración', 'Estado'],
        for (final v in allVisits)
          [
            v.folio,
            _dt.format(_local(v.startedAtUtc)),
            v.siteName,
            ChecklistTemplates.byKey(v.templateKey).name,
            _dur(v.duration),
            v.status.label,
          ],
      ], widths: [15, 17, 24, 20, 12, 12]);
    }
    _docxFooter(d);
    return d.build();
  }

  void _docxHeader(DocxBuilder d, AppSettings s, String title, String right, Uint8List? logo) {
    if (logo != null) {
      final im = img.decodePng(logo);
      if (im != null) {
        const h = 60.0;
        d.image(logo, widthPx: h * im.width / im.height, heightPx: h, ext: 'png');
      }
    }
    d.paragraph(s.institution.isEmpty ? 'Institución' : s.institution.toUpperCase(),
        bold: true, size: 22);
    if (s.department.isNotEmpty) d.paragraph(s.department, size: 18, color: '5B6478');
    d.heading(title, size: 32, color: '2563EB');
    d.paragraph(right, bold: true);
    d.spacer();
  }

  void _docxFooter(DocxBuilder d) {
    d.spacer();
    d.paragraph('Generado con GEO CUSCA SUR · ${_dt.format(DateTime.now())}',
        size: 14, color: '5B6478', italic: true);
  }

  static Future<(Uint8List, int, int)> _downscaleSized(Uint8List jpeg) => Isolate.run(() {
        final im = img.decodeJpg(jpeg);
        if (im == null) return (jpeg, 4, 3);
        final r = im.width > 900 ? img.copyResize(im, width: 900) : im;
        return (Uint8List.fromList(img.encodeJpg(r, quality: 72)), r.width, r.height);
      });

  // ───────────────────────── Reporte de tramo (PDF y Word) ─────────────────────────

  /// Enlace de Google Maps con la ruta del tramo (inicio → final, hasta 8 puntos intermedios).
  static String segmentRouteUrl(SegmentGeometry g) {
    String c(StationPoint p) =>
        '${p.photo.latitude.toStringAsFixed(6)},${p.photo.longitude.toStringAsFixed(6)}';
    final pts = g.points;
    if (pts.isEmpty) return '';
    if (pts.length == 1) return pts.first.photo.mapsUrl;
    final mid = pts.sublist(1, pts.length - 1);
    final step = mid.length <= 8 ? 1 : (mid.length / 8).ceil();
    final way = [for (var i = 0; i < mid.length; i += step) c(mid[i])].join('|');
    return 'https://www.google.com/maps/dir/?api=1&travelmode=walking'
        '&origin=${c(pts.first)}&destination=${c(pts.last)}'
        '${way.isEmpty ? '' : '&waypoints=${Uri.encodeComponent(way)}'}';
  }

  static String _roleLabel(PointRole r) => switch (r) {
        PointRole.inicio => 'Inicio',
        PointRole.fin => 'Final',
        PointRole.intermedio => 'Intermedio',
      };

  Future<Uint8List> segmentReport({
    required Segment segment,
    required SegmentGeometry geo,
    required AppSettings settings,
    Uint8List? logo,
  }) async {
    final logoImg = logo == null ? null : pw.MemoryImage(logo);
    final thumbs = <(StationPoint, pw.MemoryImage)>[];
    for (final p in geo.points) {
      final f = File(p.photo.filePath);
      if (await f.exists()) thumbs.add((p, pw.MemoryImage(await _downscale(await f.readAsBytes()))));
    }
    final area = segment.widthM == null ? null : geo.length * segment.widthM!;
    final route = segmentRouteUrl(geo);
    final doc = pw.Document(title: 'Tramo ${segment.name}', creator: 'GEO CUSCA SUR');
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.letter,
      margin: const pw.EdgeInsets.fromLTRB(36, 32, 36, 32),
      header: (ctx) => _header(settings, 'LEVANTAMIENTO DE TRAMO', segment.name, logoImg),
      footer: _footer,
      build: (ctx) => [
        pw.Row(children: [
          _metric('${geo.length.toStringAsFixed(1)} m', 'Longitud total'),
          _metric(area == null ? '—' : '${area.toStringAsFixed(1)} m²',
              area == null ? 'Área (sin ancho)' : 'Área (ancho ${segment.widthM} m)'),
          _metric('${geo.points.length}', 'Puntos / fotos'),
          _metric('±${geo.worstAccuracy.toStringAsFixed(0)} m', 'Precisión GPS (peor)'),
        ]),
        pw.SizedBox(height: 10),
        if (route.isNotEmpty)
          pw.Row(children: [
            pw.BarcodeWidget(barcode: pw.Barcode.qrCode(), data: route, width: 70, height: 70),
            pw.SizedBox(width: 10),
            pw.Expanded(
              child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                pw.Text('Recorrido en Google Maps', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                pw.UrlLink(
                  destination: route,
                  child: pw.Text('Abrir ruta del tramo (inicio → final)',
                      style: const pw.TextStyle(fontSize: 9, color: _accent)),
                ),
                pw.Text('Estaciones marcadas cada ${segment.markIntervalM.toStringAsFixed(0)} m.',
                    style: const pw.TextStyle(fontSize: 8, color: _muted)),
              ]),
            ),
          ]),
        pw.SizedBox(height: 14),
        _sectionTitle('Puntos del tramo'),
        pw.TableHelper.fromTextArray(
          headers: ['#', 'Punto', 'Estación', 'Parcial', 'Coordenadas', 'Hora', 'Actividad'],
          data: [
            for (final (i, p) in geo.points.indexed)
              [
                '${i + 1}',
                _roleLabel(p.role),
                SegmentGeometry.station(p.station),
                i == 0 ? '—' : '${p.partial.toStringAsFixed(1)} m',
                p.photo.coordsText,
                _dt.format(_local(p.photo.capturedAtUtc)),
                p.photo.activity ?? '',
              ],
          ],
          headerStyle: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
          headerDecoration: const pw.BoxDecoration(color: _ink),
          cellStyle: const pw.TextStyle(fontSize: 8),
          oddRowDecoration: const pw.BoxDecoration(color: _soft),
        ),
        if (geo.marks.isNotEmpty) ...[
          pw.SizedBox(height: 14),
          _sectionTitle('Estaciones cada ${segment.markIntervalM.toStringAsFixed(0)} m'),
          pw.TableHelper.fromTextArray(
            headers: ['Estación', 'Coordenadas'],
            data: [
              for (final m in geo.marks)
                [
                  SegmentGeometry.station(m.station),
                  '${m.position.latitude.toStringAsFixed(6)}, ${m.position.longitude.toStringAsFixed(6)}',
                ],
            ],
            headerStyle: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
            headerDecoration: const pw.BoxDecoration(color: _ink),
            cellStyle: const pw.TextStyle(fontSize: 8),
            oddRowDecoration: const pw.BoxDecoration(color: _soft),
          ),
        ],
        if (segment.notes.trim().isNotEmpty) ...[
          pw.SizedBox(height: 12),
          _sectionTitle('Observaciones'),
          pw.Text(segment.notes, style: const pw.TextStyle(fontSize: 10)),
        ],
        if (thumbs.isNotEmpty) ...[
          pw.SizedBox(height: 14),
          _sectionTitle('Fotografías por estación'),
          pw.Wrap(spacing: 10, runSpacing: 10, children: [
            for (final (p, im) in thumbs)
              pw.SizedBox(
                width: 165,
                child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                  pw.Image(im, height: 124, width: 165, fit: pw.BoxFit.cover),
                  pw.Text('Est. ${SegmentGeometry.station(p.station)} · ${_roleLabel(p.role)}',
                      style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
                  pw.UrlLink(
                    destination: p.photo.mapsUrl,
                    child: pw.Text(p.photo.coordsText, style: const pw.TextStyle(fontSize: 7, color: _accent)),
                  ),
                ]),
              ),
          ]),
        ],
      ],
    ));
    return doc.save();
  }

  Future<Uint8List> segmentDocx({
    required Segment segment,
    required SegmentGeometry geo,
    required AppSettings settings,
    Uint8List? logo,
  }) async {
    final d = DocxBuilder();
    _docxHeader(d, settings, 'LEVANTAMIENTO DE TRAMO', segment.name, logo);
    final area = segment.widthM == null ? null : geo.length * segment.widthM!;
    d.table([
      ['Longitud total', 'Área', 'Puntos', 'Estaciones cada', 'Precisión GPS (peor)'],
      [
        '${geo.length.toStringAsFixed(1)} m',
        area == null ? '—' : '${area.toStringAsFixed(1)} m² (ancho ${segment.widthM} m)',
        '${geo.points.length}',
        '${segment.markIntervalM.toStringAsFixed(0)} m',
        '±${geo.worstAccuracy.toStringAsFixed(0)} m',
      ],
    ]);
    final route = segmentRouteUrl(geo);
    if (route.isNotEmpty) d.link('Abrir ruta del tramo en Google Maps', route);
    d.heading('Puntos del tramo', size: 24);
    d.table([
      ['#', 'Punto', 'Estación', 'Parcial', 'Coordenadas', 'Hora', 'Actividad'],
      for (final (i, p) in geo.points.indexed)
        [
          '${i + 1}',
          _roleLabel(p.role),
          SegmentGeometry.station(p.station),
          i == 0 ? '—' : '${p.partial.toStringAsFixed(1)} m',
          p.photo.coordsText,
          _dt.format(_local(p.photo.capturedAtUtc)),
          p.photo.activity ?? '',
        ],
    ], widths: [5, 12, 12, 10, 27, 17, 17], size: 16);
    if (geo.marks.isNotEmpty) {
      d.heading('Estaciones cada ${segment.markIntervalM.toStringAsFixed(0)} m', size: 24);
      d.table([
        ['Estación', 'Coordenadas'],
        for (final m in geo.marks)
          [
            SegmentGeometry.station(m.station),
            '${m.position.latitude.toStringAsFixed(6)}, ${m.position.longitude.toStringAsFixed(6)}',
          ],
      ], widths: [30, 70]);
    }
    if (segment.notes.trim().isNotEmpty) {
      d.heading('Observaciones', size: 24);
      d.paragraph(segment.notes);
    }
    if (geo.points.isNotEmpty) {
      d.heading('Fotografías por estación', size: 24);
      for (final p in geo.points) {
        final f = File(p.photo.filePath);
        if (!await f.exists()) continue;
        final (bytes, w, h) = await _downscaleSized(await f.readAsBytes());
        d.image(bytes, widthPx: 400, heightPx: 400 * h / w);
        d.paragraph('Est. ${SegmentGeometry.station(p.station)} · ${_roleLabel(p.role)} · ${p.photo.coordsText}',
            size: 16, color: '5B6478');
      }
    }
    _docxFooter(d);
    return d.build();
  }

  // ───────────────────────── Piezas comunes ─────────────────────────

  pw.Widget _header(AppSettings s, String title, String right, [pw.MemoryImage? logo]) =>
      pw.Container(
        margin: const pw.EdgeInsets.only(bottom: 14),
        padding: const pw.EdgeInsets.only(bottom: 8),
        decoration: const pw.BoxDecoration(
            border: pw.Border(bottom: pw.BorderSide(color: _ink, width: 1.5))),
        child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
          if (logo != null) ...[
            pw.SizedBox(height: 46, width: 90, child: pw.Image(logo, fit: pw.BoxFit.contain)),
            pw.SizedBox(width: 12),
          ],
          pw.Expanded(
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text(s.institution.isEmpty ? 'Institución' : s.institution.toUpperCase(),
                  style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: _ink)),
              if (s.department.isNotEmpty)
                pw.Text(s.department, style: const pw.TextStyle(fontSize: 9, color: _muted)),
              pw.SizedBox(height: 4),
              pw.Text(title,
                  style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold, color: _accent)),
            ]),
          ),
          pw.Text(right, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
        ]),
      );

  pw.Widget _footer(pw.Context ctx) => pw.Container(
        margin: const pw.EdgeInsets.only(top: 10),
        child: pw.Row(children: [
          pw.Text('Generado con GEO CUSCA SUR · ${_dt.format(DateTime.now())}',
              style: const pw.TextStyle(fontSize: 7, color: _muted)),
          pw.Spacer(),
          pw.Text('Página ${ctx.pageNumber} de ${ctx.pagesCount}',
              style: const pw.TextStyle(fontSize: 7, color: _muted)),
        ]),
      );

  pw.Widget _sectionTitle(String t) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 6),
        child: pw.Text(t,
            style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: _ink)),
      );

  pw.Widget _metric(String value, String label) => pw.Expanded(
        child: pw.Container(
          margin: const pw.EdgeInsets.only(right: 6),
          padding: const pw.EdgeInsets.all(8),
          decoration: const pw.BoxDecoration(
              color: _soft, borderRadius: pw.BorderRadius.all(pw.Radius.circular(4))),
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text(value, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
            pw.Text(label, style: const pw.TextStyle(fontSize: 8, color: _muted)),
          ]),
        ),
      );

  pw.Widget _kvTable(List<(String, String)> rows) => pw.Table(
        columnWidths: const {0: pw.FixedColumnWidth(80), 1: pw.FlexColumnWidth()},
        children: [
          for (final r in rows)
            pw.TableRow(children: [
              pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 2.5),
                  child: pw.Text(r.$1, style: const pw.TextStyle(fontSize: 9, color: _muted))),
              pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 2.5),
                  child: pw.Text(r.$2, style: const pw.TextStyle(fontSize: 9))),
            ]),
        ],
      );

  pw.Widget _signatureBlock(pw.MemoryImage? img, String name, String role) =>
      pw.Column(children: [
        pw.SizedBox(
            height: 60,
            child: img == null ? pw.SizedBox() : pw.Image(img, fit: pw.BoxFit.contain)),
        pw.Container(height: 0.8, color: _ink),
        pw.SizedBox(height: 3),
        pw.Text(name, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
        pw.Text(role, style: const pw.TextStyle(fontSize: 8, color: _muted)),
      ]);

  static Future<Uint8List> _downscale(Uint8List jpeg) => Isolate.run(() {
        final im = img.decodeJpg(jpeg);
        if (im == null) return jpeg;
        final r = im.width > 900 ? img.copyResize(im, width: 900) : im;
        return img.encodeJpg(r, quality: 72);
      });
}
