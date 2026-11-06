import 'package:flutter/material.dart';

import '../../../core/utils/maps_link.dart';

enum InspectionStatus { enCurso, finalizada }

extension InspectionStatusInfo on InspectionStatus {
  String get label => switch (this) {
        InspectionStatus.enCurso => 'En curso',
        InspectionStatus.finalizada => 'Finalizada',
      };
  Color get color => switch (this) {
        InspectionStatus.enCurso => const Color(0xFFFFB020),
        InspectionStatus.finalizada => const Color(0xFF2EE6A6),
      };
}

enum ItemResult { pendiente, cumple, noCumple, noAplica }

extension ItemResultInfo on ItemResult {
  String get label => switch (this) {
        ItemResult.pendiente => 'Pendiente',
        ItemResult.cumple => 'Cumple',
        ItemResult.noCumple => 'No cumple',
        ItemResult.noAplica => 'N/A',
      };
  Color get color => switch (this) {
        ItemResult.pendiente => const Color(0xFF8A93A6),
        ItemResult.cumple => const Color(0xFF2EE6A6),
        ItemResult.noCumple => const Color(0xFFFF5C7A),
        ItemResult.noAplica => const Color(0xFF9AA4B8),
      };
  IconData get icon => switch (this) {
        ItemResult.pendiente => Icons.radio_button_unchecked,
        ItemResult.cumple => Icons.check_circle,
        ItemResult.noCumple => Icons.cancel,
        ItemResult.noAplica => Icons.remove_circle_outline,
      };
}

/// Gravedad de un hallazgo (solo aplica a "No cumple").
enum Severity { baja, media, alta, critica }

extension SeverityInfo on Severity {
  String get label => switch (this) {
        Severity.baja => 'Baja',
        Severity.media => 'Media',
        Severity.alta => 'Alta',
        Severity.critica => 'Crítica',
      };
  Color get color => switch (this) {
        Severity.baja => const Color(0xFF5AC8FA),
        Severity.media => const Color(0xFFFFB020),
        Severity.alta => const Color(0xFFFF8A3D),
        Severity.critica => const Color(0xFFFF3B5C),
      };
}

class ChecklistItem {
  ChecklistItem({
    required this.id,
    required this.inspectionId,
    required this.section,
    required this.question,
    required this.order,
    this.result = ItemResult.pendiente,
    this.severity,
    this.note = '',
  });

  final String id;
  final String inspectionId;
  final String section;
  final String question;
  final int order;
  ItemResult result;
  Severity? severity;
  String note;

  bool get isFinding => result == ItemResult.noCumple;

  Map<String, Object?> toMap() => {
        'id': id,
        'inspection_id': inspectionId,
        'section': section,
        'question': question,
        'sort_order': order,
        'result': result.name,
        'severity': severity?.name,
        'note': note,
      };

  factory ChecklistItem.fromMap(Map<String, Object?> m) => ChecklistItem(
        id: m['id']! as String,
        inspectionId: m['inspection_id']! as String,
        section: m['section']! as String,
        question: m['question']! as String,
        order: m['sort_order']! as int,
        result: ItemResult.values.byName(m['result']! as String),
        severity: m['severity'] == null
            ? null
            : Severity.values.byName(m['severity']! as String),
        note: m['note'] as String? ?? '',
      );
}

/// Una inspección = una visita a un lugar, con checklist, fotos y firma.
class Inspection {
  Inspection({
    required this.id,
    required this.folio,
    required this.templateKey,
    required this.siteName,
    required this.latitude,
    required this.longitude,
    required this.accuracy,
    required this.startedAtUtc,
    this.attendedBy = '',
    this.inspectorName = '',
    this.institution = '',
    this.address,
    this.endedAtUtc,
    this.status = InspectionStatus.enCurso,
    this.generalNotes = '',
    this.signaturePath,
  });

  final String id;
  final String folio;
  final String templateKey;
  String siteName;
  String attendedBy;
  String inspectorName;
  String institution;
  final double latitude;
  final double longitude;
  final double accuracy;
  String? address;
  final DateTime startedAtUtc;
  DateTime? endedAtUtc;
  InspectionStatus status;
  String generalNotes;
  String? signaturePath;

  Duration get duration =>
      (endedAtUtc ?? DateTime.now().toUtc()).difference(startedAtUtc);
  String get mapsUrl => MapsLink.search(latitude, longitude);
  String get coordsText => MapsLink.coordsText(latitude, longitude);

  Map<String, Object?> toMap() => {
        'id': id,
        'folio': folio,
        'template_key': templateKey,
        'site_name': siteName,
        'attended_by': attendedBy,
        'inspector_name': inspectorName,
        'institution': institution,
        'lat': latitude,
        'lng': longitude,
        'accuracy': accuracy,
        'address': address,
        'started_at_utc': startedAtUtc.toIso8601String(),
        'ended_at_utc': endedAtUtc?.toIso8601String(),
        'status': status.name,
        'general_notes': generalNotes,
        'signature_path': signaturePath,
      };

  factory Inspection.fromMap(Map<String, Object?> m) => Inspection(
        id: m['id']! as String,
        folio: m['folio']! as String,
        templateKey: m['template_key']! as String,
        siteName: m['site_name']! as String,
        attendedBy: m['attended_by'] as String? ?? '',
        inspectorName: m['inspector_name'] as String? ?? '',
        institution: m['institution'] as String? ?? '',
        latitude: (m['lat']! as num).toDouble(),
        longitude: (m['lng']! as num).toDouble(),
        accuracy: (m['accuracy']! as num).toDouble(),
        address: m['address'] as String?,
        startedAtUtc: DateTime.parse(m['started_at_utc']! as String).toUtc(),
        endedAtUtc: m['ended_at_utc'] == null
            ? null
            : DateTime.parse(m['ended_at_utc']! as String).toUtc(),
        status: InspectionStatus.values.byName(m['status']! as String),
        generalNotes: m['general_notes'] as String? ?? '',
        signaturePath: m['signature_path'] as String?,
      );
}

/// Resumen de cumplimiento para tarjetas, PDF y panel.
class ComplianceSummary {
  ComplianceSummary(List<ChecklistItem> items)
      : total = items.length,
        cumple = items.where((i) => i.result == ItemResult.cumple).length,
        noCumple = items.where((i) => i.result == ItemResult.noCumple).length,
        noAplica = items.where((i) => i.result == ItemResult.noAplica).length,
        pendientes = items.where((i) => i.result == ItemResult.pendiente).length,
        criticos = items
            .where((i) => i.isFinding && i.severity == Severity.critica)
            .length;

  final int total, cumple, noCumple, noAplica, pendientes, criticos;

  int get evaluados => cumple + noCumple;

  /// % de cumplimiento sobre lo evaluado (N/A y pendientes no cuentan).
  double get percent => evaluados == 0 ? 0 : cumple / evaluados;

  /// Avance del llenado del checklist.
  double get progress => total == 0 ? 0 : (total - pendientes) / total;
}
