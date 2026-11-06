import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Datos de la institución que usa la app. Aparecen en el encabezado de
/// todos los reportes PDF, así una alcaldía, ministerio o empresa privada
/// usa la misma app con su propio nombre.
@immutable
class AppSettings {
  const AppSettings({
    this.institution = '',
    this.department = '',
    this.inspectorName = '',
    this.inspectorRole = '',
  });

  final String institution;
  final String department;
  final String inspectorName;
  final String inspectorRole;

  bool get isConfigured => institution.isNotEmpty && inspectorName.isNotEmpty;

  AppSettings copyWith({
    String? institution,
    String? department,
    String? inspectorName,
    String? inspectorRole,
  }) =>
      AppSettings(
        institution: institution ?? this.institution,
        department: department ?? this.department,
        inspectorName: inspectorName ?? this.inspectorName,
        inspectorRole: inspectorRole ?? this.inspectorRole,
      );
}

class SettingsService extends ValueNotifier<AppSettings> {
  SettingsService() : super(const AppSettings());

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    value = AppSettings(
      institution: p.getString('institution') ?? '',
      department: p.getString('department') ?? '',
      inspectorName: p.getString('inspectorName') ?? '',
      inspectorRole: p.getString('inspectorRole') ?? '',
    );
  }

  Future<void> save(AppSettings s) async {
    final p = await SharedPreferences.getInstance();
    await p.setString('institution', s.institution.trim());
    await p.setString('department', s.department.trim());
    await p.setString('inspectorName', s.inspectorName.trim());
    await p.setString('inspectorRole', s.inspectorRole.trim());
    value = s;
  }
}
