import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../../core/db/app_database.dart';
import '../domain/checklist_templates.dart';
import '../domain/inspection.dart';

class InspectionRepository {
  Future<Database> get _db => AppDatabase.instance.db;
  static const _uuid = Uuid();

  /// Folio correlativo por año: INS-2026-0001
  Future<String> _nextFolio(Transaction tx, int year) async {
    final r = await tx.rawQuery(
        "SELECT COUNT(*) c FROM inspections WHERE folio LIKE 'INS-$year-%'");
    final n = (Sqflite.firstIntValue(r) ?? 0) + 1;
    return 'INS-$year-${n.toString().padLeft(4, '0')}';
  }

  /// Crea la inspección y copia las preguntas de la plantilla, en una sola
  /// transacción (o se crea todo, o nada).
  Future<Inspection> create({
    required ChecklistTemplate template,
    required String siteName,
    required String attendedBy,
    required String inspectorName,
    required String institution,
    required double latitude,
    required double longitude,
    required double accuracy,
    String? address,
  }) async {
    final db = await _db;
    return db.transaction((tx) async {
      final now = DateTime.now().toUtc();
      final insp = Inspection(
        id: _uuid.v4(),
        folio: await _nextFolio(tx, now.year),
        templateKey: template.key,
        siteName: siteName.trim(),
        attendedBy: attendedBy.trim(),
        inspectorName: inspectorName.trim(),
        institution: institution.trim(),
        latitude: latitude,
        longitude: longitude,
        accuracy: accuracy,
        address: address,
        startedAtUtc: now,
      );
      await tx.insert('inspections', insp.toMap());
      var order = 0;
      for (final e in template.sections.entries) {
        for (final q in e.value) {
          await tx.insert(
            'checklist_items',
            ChecklistItem(
              id: _uuid.v4(),
              inspectionId: insp.id,
              section: e.key,
              question: q,
              order: order++,
            ).toMap(),
          );
        }
      }
      return insp;
    });
  }

  Future<List<Inspection>> all({DateTime? sinceUtc}) async {
    final rows = await (await _db).query(
      'inspections',
      where: sinceUtc == null ? null : 'started_at_utc >= ?',
      whereArgs: sinceUtc == null ? null : [sinceUtc.toIso8601String()],
      orderBy: 'started_at_utc DESC',
    );
    return rows.map(Inspection.fromMap).toList();
  }

  Future<Inspection?> byId(String id) async {
    final rows = await (await _db).query('inspections', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : Inspection.fromMap(rows.first);
  }

  Future<List<ChecklistItem>> items(String inspectionId) async {
    final rows = await (await _db).query('checklist_items',
        where: 'inspection_id = ?', whereArgs: [inspectionId], orderBy: 'sort_order');
    return rows.map(ChecklistItem.fromMap).toList();
  }

  /// Todos los ítems de varias inspecciones (para el panel), en una consulta.
  Future<Map<String, List<ChecklistItem>>> itemsFor(List<String> ids) async {
    if (ids.isEmpty) return {};
    final marks = List.filled(ids.length, '?').join(',');
    final rows = await (await _db).query('checklist_items',
        where: 'inspection_id IN ($marks)', whereArgs: ids);
    final map = <String, List<ChecklistItem>>{};
    for (final r in rows.map(ChecklistItem.fromMap)) {
      map.putIfAbsent(r.inspectionId, () => []).add(r);
    }
    return map;
  }

  Future<void> updateItem(ChecklistItem i) async => (await _db)
      .update('checklist_items', i.toMap(), where: 'id = ?', whereArgs: [i.id]);

  Future<void> update(Inspection i) async => (await _db)
      .update('inspections', i.toMap(), where: 'id = ?', whereArgs: [i.id]);

  Future<void> delete(String id) async {
    final db = await _db;
    await db.transaction((tx) async {
      await tx.delete('checklist_items', where: 'inspection_id = ?', whereArgs: [id]);
      await tx.delete('inspections', where: 'id = ?', whereArgs: [id]);
      // Las fotos se conservan como evidencia suelta.
      await tx.update('captures', {'inspection_id': null},
          where: 'inspection_id = ?', whereArgs: [id]);
    });
  }
}
