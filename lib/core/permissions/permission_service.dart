import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

/// Resultado normalizado de una solicitud de permiso, para que la UI
/// muestre el mensaje correcto (pedir de nuevo vs. ir a Ajustes).
enum PermissionOutcome { granted, denied, permanentlyDenied, serviceDisabled }

/// Centraliza los permisos de Cámara y Ubicación.
///
/// Nota de diseño: la ubicación se pide con `geolocator` (no con
/// permission_handler) para que un solo plugin controle el estado de
/// ubicación y su precisión (exacta vs. aproximada).
class PermissionService {
  /// Clave definida en Info.plist -> NSLocationTemporaryUsageDescriptionDictionary
  static const iosPreciseKey = 'PreciseCapture';

  Future<PermissionOutcome> ensureCamera() async {
    var status = await Permission.camera.status;
    if (status.isGranted) return PermissionOutcome.granted;

    status = await Permission.camera.request();
    if (status.isGranted) return PermissionOutcome.granted;
    if (status.isPermanentlyDenied || status.isRestricted) {
      return PermissionOutcome.permanentlyDenied;
    }
    return PermissionOutcome.denied;
  }

  Future<PermissionOutcome> ensureLocation() async {
    // 1. El GPS del teléfono debe estar encendido.
    if (!await Geolocator.isLocationServiceEnabled()) {
      return PermissionOutcome.serviceDisabled;
    }

    // 2. Permiso "mientras se usa la app" (no necesitamos segundo plano).
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.deniedForever) {
      return PermissionOutcome.permanentlyDenied;
    }
    if (perm == LocationPermission.denied) return PermissionOutcome.denied;

    // 3. iOS 14+/Android 12+ permiten "ubicación aproximada" (~3 km).
    //    Eso invalida la evidencia, así que pedimos precisión exacta.
    final accuracy = await Geolocator.getLocationAccuracy();
    if (accuracy == LocationAccuracyStatus.reduced) {
      // En iOS muestra un diálogo temporal; en Android no tiene efecto
      // y el usuario debe elegir "Precisa" en el diálogo del sistema.
      final upgraded = await Geolocator.requestTemporaryFullAccuracy(
        purposeKey: iosPreciseKey,
      );
      if (upgraded == LocationAccuracyStatus.reduced) {
        return PermissionOutcome.denied;
      }
    }
    return PermissionOutcome.granted;
  }

  Future<bool> openSettings() => openAppSettings();
  Future<bool> openLocationSettings() => Geolocator.openLocationSettings();
}
