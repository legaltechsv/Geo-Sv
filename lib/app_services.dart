import 'core/geocoding/geocoding_service.dart';
import 'core/location/compass_service.dart';
import 'core/location/location_service.dart';
import 'core/permissions/permission_service.dart';
import 'core/time/trusted_time_service.dart';
import 'features/branding/logo_service.dart';
import 'features/capture/application/capture_controller.dart';
import 'features/channels/channel_backend.dart';
import 'features/capture/data/capture_repository.dart';
import 'features/inspections/data/inspection_repository.dart';
import 'features/reports/report_service.dart';
import 'features/segments/segment.dart';
import 'features/settings/settings_service.dart';
import 'features/sync/offline_sync_service.dart';
import 'features/templates/watermark_template.dart';
import 'features/visits/visits_service.dart';
import 'features/watermark/exif_writer.dart';
import 'features/watermark/watermark_service.dart';

/// Contenedor único de servicios (composition root).
/// Simple a propósito; en un equipo grande se reemplaza por Riverpod/get_it.
class AppServices {
  AppServices._();
  static final instance = AppServices._();

  final permissions = PermissionService();
  final time = TrustedTimeService();
  final geocoding = GeocodingService();
  final captures = CaptureRepository();
  final inspections = InspectionRepository();
  final settings = SettingsService();
  final templates = TemplateController();
  final reports = ReportService();
  final compass = CompassService();
  final logo = LogoService();
  final segments = SegmentRepository();
  final channels = ChannelBackend();

  late final location = LocationService();
  late final camera = CaptureController(
    permissions: permissions,
    location: location,
    time: time,
    geocoding: geocoding,
    watermark: WatermarkService(),
    exif: ExifWriter(),
    repository: captures,
  );
  late final visits = VisitsService(inspections: inspections, captures: captures);
  late final sync = OfflineSyncService(repository: captures, geocoding: geocoding, time: time);

  Future<void> init() async {
    await settings.load();
    await logo.load();
    await templates.load();
    await channels.loadConfig();
    sync.start();
  }
}

AppServices get services => AppServices.instance;
