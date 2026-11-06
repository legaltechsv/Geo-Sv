import '../capture/data/capture_repository.dart';
import '../capture/domain/capture_record.dart';
import '../inspections/data/inspection_repository.dart';
import '../inspections/domain/inspection.dart';

/// Un lugar visitado, agregando todas sus visitas (inspecciones) y fotos.
class VisitedPlace {
  VisitedPlace({required this.name, required this.latitude, required this.longitude});

  final String name;
  final double latitude;
  final double longitude;
  String? address;
  final List<Inspection> visits = [];
  final List<CaptureRecord> photos = [];

  DateTime get lastVisit {
    final dates = [
      ...visits.map((v) => v.startedAtUtc),
      ...photos.map((p) => p.capturedAtUtc),
    ];
    return dates.reduce((a, b) => a.isAfter(b) ? a : b);
  }

  Duration get totalTime => visits.fold(Duration.zero, (a, v) => a + v.duration);
}

enum VisitRange { hoy, semana, mes, todo }

extension VisitRangeInfo on VisitRange {
  String get label => switch (this) {
        VisitRange.hoy => 'Hoy',
        VisitRange.semana => '7 días',
        VisitRange.mes => '30 días',
        VisitRange.todo => 'Todo',
      };

  DateTime? get sinceUtc {
    final now = DateTime.now();
    return switch (this) {
      VisitRange.hoy => DateTime(now.year, now.month, now.day).toUtc(),
      VisitRange.semana => now.subtract(const Duration(days: 7)).toUtc(),
      VisitRange.mes => now.subtract(const Duration(days: 30)).toUtc(),
      VisitRange.todo => null,
    };
  }
}

/// Construye el reporte de lugares visitados:
/// - Las inspecciones se agrupan por nombre de sitio.
/// - Las fotos sueltas (sin inspección) se agrupan por cercanía (~110 m).
class VisitsService {
  VisitsService({required this.inspections, required this.captures});

  final InspectionRepository inspections;
  final CaptureRepository captures;

  Future<List<VisitedPlace>> places(VisitRange range) async {
    final since = range.sinceUtc;
    final insp = await inspections.all(sinceUtc: since);
    final photos = (await captures.all())
        .where((c) => since == null || !c.capturedAtUtc.isBefore(since))
        .toList();

    final byKey = <String, VisitedPlace>{};

    for (final i in insp) {
      final key = 'site:${i.siteName.trim().toLowerCase()}';
      final place = byKey.putIfAbsent(
          key, () => VisitedPlace(name: i.siteName, latitude: i.latitude, longitude: i.longitude));
      place.address ??= i.address;
      place.visits.add(i);
    }
    final inspById = {for (final i in insp) i.id: i};

    for (final c in photos) {
      final owner = c.inspectionId == null ? null : inspById[c.inspectionId];
      if (owner != null) {
        byKey['site:${owner.siteName.trim().toLowerCase()}']!.photos.add(c);
        continue;
      }
      // Foto suelta: agrupar por coordenadas redondeadas a 3 decimales.
      final key = 'geo:${c.latitude.toStringAsFixed(3)},${c.longitude.toStringAsFixed(3)}';
      final place = byKey.putIfAbsent(
        key,
        () => VisitedPlace(
          name: c.address?.split(',').first ?? 'Punto ${c.coordsText}',
          latitude: c.latitude,
          longitude: c.longitude,
        ),
      );
      place.address ??= c.address;
      place.photos.add(c);
    }

    final list = byKey.values.toList()
      ..sort((a, b) => b.lastVisit.compareTo(a.lastVisit));
    return list;
  }
}
