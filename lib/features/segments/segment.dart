import 'package:latlong2/latlong.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../core/db/app_database.dart';
import '../capture/domain/capture_record.dart';

/// Rol de una foto dentro del tramo.
enum PointRole { inicio, intermedio, fin }

extension PointRoleInfo on PointRole {
  String get key => switch (this) {
        PointRole.inicio => 'inicio',
        PointRole.intermedio => 'intermedio',
        PointRole.fin => 'final',
      };
  String get label => switch (this) {
        PointRole.inicio => 'Inicio del tramo',
        PointRole.intermedio => 'Punto intermedio',
        PointRole.fin => 'Final del tramo',
      };
  static PointRole fromKey(String? k) => switch (k) {
        'inicio' => PointRole.inicio,
        'final' => PointRole.fin,
        _ => PointRole.intermedio,
      };
}

/// Tramo de calle (o ruta) levantado con fotos geolocalizadas.
class Segment {
  Segment({
    required this.id,
    required this.name,
    required this.createdAtUtc,
    this.markIntervalM = 10,
    this.widthM,
    this.notes = '',
    this.closed = false,
  });

  final String id;
  String name;

  /// Cada cuántos metros se marca una estación en el trazado (10, 20, 25, 50…).
  double markIntervalM;

  /// Ancho promedio (m) para calcular el área (ej. bacheo / recarpeteo).
  double? widthM;
  String notes;
  final DateTime createdAtUtc;
  bool closed;

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'mark_interval_m': markIntervalM,
        'width_m': widthM,
        'notes': notes,
        'created_at_utc': createdAtUtc.toIso8601String(),
        'closed': closed ? 1 : 0,
      };

  factory Segment.fromMap(Map<String, Object?> m) => Segment(
        id: m['id']! as String,
        name: m['name']! as String,
        markIntervalM: (m['mark_interval_m']! as num).toDouble(),
        widthM: (m['width_m'] as num?)?.toDouble(),
        notes: m['notes'] as String? ?? '',
        createdAtUtc: DateTime.parse(m['created_at_utc']! as String).toUtc(),
        closed: (m['closed'] as int? ?? 0) == 1,
      );
}

/// Un punto del trazado con su estación (distancia acumulada desde el inicio).
class StationPoint {
  StationPoint(this.photo, this.station, this.partial);
  final CaptureRecord photo;

  /// Metros acumulados desde el primer punto.
  final double station;

  /// Metros desde el punto anterior.
  final double partial;

  LatLng get latLng => LatLng(photo.latitude, photo.longitude);
  PointRole get role => PointRoleInfo.fromKey(photo.pointRole);
}

/// Marca de estación cada N metros sobre la línea (0+010, 0+020…).
class StationMark {
  StationMark(this.position, this.station);
  final LatLng position;
  final double station;
}

/// Geometría del tramo: distancias, estaciones, marcas y área.
class SegmentGeometry {
  SegmentGeometry(List<CaptureRecord> photos, double interval) {
    final d = Distance();
    var acc = 0.0;
    for (var i = 0; i < photos.length; i++) {
      final partial = i == 0
          ? 0.0
          : d.as(LengthUnit.Meter, LatLng(photos[i - 1].latitude, photos[i - 1].longitude),
              LatLng(photos[i].latitude, photos[i].longitude));
      acc += partial;
      points.add(StationPoint(photos[i], acc, partial));
    }
    length = acc;
    // Interpolar marcas a lo largo de la polilínea.
    if (interval > 0 && points.length > 1) {
      var next = interval;
      for (var i = 1; i < points.length; i++) {
        final a = points[i - 1], b = points[i];
        while (next <= b.station && b.partial > 0) {
          final t = (next - a.station) / b.partial;
          marks.add(StationMark(
            LatLng(
              a.latLng.latitude + (b.latLng.latitude - a.latLng.latitude) * t,
              a.latLng.longitude + (b.latLng.longitude - a.latLng.longitude) * t,
            ),
            next,
          ));
          next += interval;
        }
      }
    }
  }

  final points = <StationPoint>[];
  final marks = <StationMark>[];
  late final double length;

  /// Precisión del GPS acumulada aproximada (peor punto), en metros.
  double get worstAccuracy =>
      points.fold(0.0, (m, p) => p.photo.accuracy > m ? p.photo.accuracy : m);

  /// Estación en formato de ingeniería: 1234.5 -> "1+234.5"
  static String station(double m) {
    final km = m ~/ 1000;
    final rest = m - km * 1000;
    return '$km+${rest.toStringAsFixed(1).padLeft(5, '0')}';
  }
}

class SegmentRepository {
  Future<Database> get _db => AppDatabase.instance.db;

  Future<Segment> create({required String name, double interval = 10, double? width}) async {
    final s = Segment(
      id: const Uuid().v4(),
      name: name.trim(),
      markIntervalM: interval,
      widthM: width,
      createdAtUtc: DateTime.now().toUtc(),
    );
    await (await _db).insert('segments', s.toMap());
    return s;
  }

  Future<List<Segment>> all() async {
    final rows = await (await _db).query('segments', orderBy: 'created_at_utc DESC');
    return rows.map(Segment.fromMap).toList();
  }

  Future<Segment?> byId(String id) async {
    final rows = await (await _db).query('segments', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : Segment.fromMap(rows.first);
  }

  Future<void> update(Segment s) async =>
      (await _db).update('segments', s.toMap(), where: 'id = ?', whereArgs: [s.id]);

  Future<void> delete(String id) async {
    final db = await _db;
    await db.transaction((tx) async {
      await tx.update('captures', {'segment_id': null, 'point_role': null},
          where: 'segment_id = ?', whereArgs: [id]);
      await tx.delete('segments', where: 'id = ?', whereArgs: [id]);
    });
  }
}
