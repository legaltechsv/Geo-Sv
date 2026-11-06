import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Base de datos local única (offline-first) con migraciones.
///
/// v1: captures
/// v2: + captures.inspection_id, inspections, checklist_items
/// v3: + captures.heading (rumbo de la cámara), captures.activity
/// v4: + captures.segment_id, captures.point_role, segments (tramos)
/// v5: + captures.support (foto de apoyo: solo coordenadas, sin QR)
class AppDatabase {
  AppDatabase._();
  static final instance = AppDatabase._();

  Database? _db;

  Future<Database> get db async => _db ??= await openDatabase(
        p.join(await getDatabasesPath(), 'geomark.db'),
        version: 5,
        onCreate: (d, _) async {
          await _createCaptures(d);
          await _createInspections(d);
          await _createSegments(d);
        },
        onUpgrade: (d, oldV, _) async {
          if (oldV < 2) {
            await d.execute('ALTER TABLE captures ADD COLUMN inspection_id TEXT');
            await d.execute(
                'CREATE INDEX idx_captures_inspection ON captures(inspection_id)');
            await _createInspections(d);
          }
          if (oldV < 3) {
            await d.execute('ALTER TABLE captures ADD COLUMN heading REAL');
            await d.execute('ALTER TABLE captures ADD COLUMN activity TEXT');
          }
          if (oldV < 4) {
            await d.execute('ALTER TABLE captures ADD COLUMN segment_id TEXT');
            await d.execute('ALTER TABLE captures ADD COLUMN point_role TEXT');
            await _createSegments(d);
          }
          if (oldV < 5) {
            await d.execute('ALTER TABLE captures ADD COLUMN support INTEGER NOT NULL DEFAULT 0');
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
        inspection_id TEXT,
        heading REAL,
        activity TEXT,
        segment_id TEXT,
        point_role TEXT,
        support INTEGER NOT NULL DEFAULT 0
      )''');
    await d.execute('CREATE INDEX idx_captures_pending ON captures(address_pending)');
    await d.execute('CREATE INDEX idx_captures_inspection ON captures(inspection_id)');
  }

  static Future<void> _createSegments(Database d) async {
    await d.execute('''
      CREATE TABLE segments(
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        mark_interval_m REAL NOT NULL DEFAULT 10,
        width_m REAL,
        notes TEXT NOT NULL DEFAULT '',
        created_at_utc TEXT NOT NULL,
        closed INTEGER NOT NULL DEFAULT 0
      )''');
    await d.execute('CREATE INDEX idx_captures_segment ON captures(segment_id)');
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
