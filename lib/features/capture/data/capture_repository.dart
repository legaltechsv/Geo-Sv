import 'package:sqflite/sqflite.dart';

import '../../../core/db/app_database.dart';
import '../domain/capture_record.dart';

/// Persistencia local de las fotos de evidencia.
class CaptureRepository {
  Future<Database> get _database => AppDatabase.instance.db;

  Future<void> insert(CaptureRecord r) async =>
      (await _database).insert('captures', r.toMap(),
          conflictAlgorithm: ConflictAlgorithm.abort);

  Future<List<CaptureRecord>> all() async {
    final rows = await (await _database)
        .query('captures', orderBy: 'captured_at_utc DESC');
    return rows.map(CaptureRecord.fromMap).toList();
  }

  Future<List<CaptureRecord>> byInspection(String inspectionId) async {
    final rows = await (await _database).query('captures',
        where: 'inspection_id = ?',
        whereArgs: [inspectionId],
        orderBy: 'captured_at_utc ASC');
    return rows.map(CaptureRecord.fromMap).toList();
  }

  Future<int> count() async {
    final r = await (await _database).rawQuery('SELECT COUNT(*) c FROM captures');
    return Sqflite.firstIntValue(r) ?? 0;
  }

  Future<List<CaptureRecord>> pendingAddress() async {
    final rows = await (await _database)
        .query('captures', where: 'address_pending = 1');
    return rows.map(CaptureRecord.fromMap).toList();
  }

  /// Único campo mutable: la dirección resuelta cuando vuelve la red.
  Future<void> updateAddress(String id, String address) async =>
      (await _database).update(
        'captures',
        {'address': address, 'address_pending': 0},
        where: 'id = ?',
        whereArgs: [id],
      );
}
