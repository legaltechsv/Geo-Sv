import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Base de datos local única (offline-first) con migraciones.
///
/// v1: captures
/// v2: + captures.inspection_id, inspections, checklist_items
class AppDatabase {
  AppDatabase._();
  static final instance = AppDatabase._();

  Database? _db;

  Future<Database> get db async => _db ??= await openDatabase(
        p.join(await getDatabasesPath(), 'geomark.db'),
        version: 2,
        onCreate: (d, _) async {
          await _createCaptures(d);
          await _createInspections(d);
        },
        onUpgrade: (d, oldV, _) async {
          if (oldV < 2) {
            await d.execute('ALTER TABLE captures ADD COLUMN inspection_id TEXT');
            await d.execute(
                'CREATE INDEX idx_captures_inspection ON captures(inspection_id)');
            await _createInspections(d);
          }
        },
      );

  static Future<void> _createCaptures(Database d) async {
    await d.execute('''
      CREATE TABLE captures(
        id TEXT PRIMARY KEY,
        file_path TEXT NOT NULL,
        lat REAL NOT NULL,
        lng REAL NOT NULL,
        accuracy REAL NOT NULL,
        altitude REAL,
        captured_at_utc TEXT NOT NULL,
        tz_offset_min INTEGER NOT NULL,
        time_source TEXT NOT NULL,
        address TEXT,
        address_pending INTEGER NOT NULL,
        verification_code TEXT NOT NULL,
        file_sha256 TEXT NOT NULL,
        inspection_id TEXT
      )''');
    await d.execute('CREATE INDEX idx_captures_pending ON captures(address_pending)');
    await d.execute('CREATE INDEX idx_captures_inspection ON captures(inspection_id)');
  }

  static Future<void> _createInspections(Database d) async {
    await d.execute('''
      CREATE TABLE inspections(
        id TEXT PRIMARY KEY,
        folio TEXT NOT NULL UNIQUE,
        template_key TEXT NOT NULL,
        site_name TEXT NOT NULL,
        attended_by TEXT NOT NULL DEFAULT '',
        inspector_name TEXT NOT NULL DEFAULT '',
        institution TEXT NOT NULL DEFAULT '',
        lat REAL NOT NULL,
        lng REAL NOT NULL,
        accuracy REAL NOT NULL,
        address TEXT,
        started_at_utc TEXT NOT NULL,
        ended_at_utc TEXT,
        status TEXT NOT NULL,
        general_notes TEXT NOT NULL DEFAULT '',
        signature_path TEXT
      )''');
    await d.execute('CREATE INDEX idx_inspections_started ON inspections(started_at_utc)');
    await d.execute('''
      CREATE TABLE checklist_items(
        id TEXT PRIMARY KEY,
        inspection_id TEXT NOT NULL REFERENCES inspections(id) ON DELETE CASCADE,
        section TEXT NOT NULL,
        question TEXT NOT NULL,
        sort_order INTEGER NOT NULL,
        result TEXT NOT NULL,
        severity TEXT,
        note TEXT NOT NULL DEFAULT ''
      )''');
    await d.execute('CREATE INDEX idx_items_inspection ON checklist_items(inspection_id)');
  }
}
