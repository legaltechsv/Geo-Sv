import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Estilos de marca de agua (equivalentes a las "plantillas" de Timemark).
/// El mismo estilo se usa en la vista previa en vivo y en el render final,
/// así lo que el usuario ve en el visor es lo que queda en la foto.
enum WatermarkStyle { clasico, obra, reporte, minimo }

extension WatermarkStyleInfo on WatermarkStyle {
  String get label => switch (this) {
        WatermarkStyle.clasico => 'Clásico',
        WatermarkStyle.obra => 'Obra',
        WatermarkStyle.reporte => 'Reporte',
        WatermarkStyle.minimo => 'Mínimo',
      };

  String get description => switch (this) {
        WatermarkStyle.clasico => 'Hora grande, fecha, ubicación y QR',
        WatermarkStyle.obra => 'Encabezado de proyecto para construcción',
        WatermarkStyle.reporte => 'Formato de informe con nota de trabajo',
        WatermarkStyle.minimo => 'Solo hora, coordenadas y QR',
      };

  IconData get icon => switch (this) {
        WatermarkStyle.clasico => Icons.access_time_filled,
        WatermarkStyle.obra => Icons.construction,
        WatermarkStyle.reporte => Icons.assignment,
        WatermarkStyle.minimo => Icons.crop_square,
      };

  /// Color de acento (barra lateral / encabezado).
  Color get accent => switch (this) {
        WatermarkStyle.clasico => const Color(0xFFFFC107),
        WatermarkStyle.obra => const Color(0xFFFFD600),
        WatermarkStyle.reporte => const Color(0xFF2196F3),
        WatermarkStyle.minimo => const Color(0xFFFFFFFF),
      };
}

/// Configuración elegida por el usuario para las próximas fotos.
@immutable
class WatermarkConfig {
  const WatermarkConfig({
    this.style = WatermarkStyle.clasico,
    this.projectName = '',
    this.note = '',
    this.showAddress = true,
    this.showAccuracy = true,
  });

  final WatermarkStyle style;
  final String projectName;
  final String note;
  final bool showAddress;
  final bool showAccuracy;

  bool get hasProject => projectName.trim().isNotEmpty;
  bool get hasNote => note.trim().isNotEmpty;

  WatermarkConfig copyWith({
    WatermarkStyle? style,
    String? projectName,
    String? note,
    bool? showAddress,
    bool? showAccuracy,
  }) =>
      WatermarkConfig(
        style: style ?? this.style,
        projectName: projectName ?? this.projectName,
        note: note ?? this.note,
        showAddress: showAddress ?? this.showAddress,
        showAccuracy: showAccuracy ?? this.showAccuracy,
      );
}

/// Estado de la plantilla activa. (Para recordarla entre sesiones,
/// persistir con shared_preferences en una siguiente iteración.)
class TemplateController extends ValueNotifier<WatermarkConfig> {
  TemplateController() : super(const WatermarkConfig());

  void setStyle(WatermarkStyle s) => value = value.copyWith(style: s);
  void update(WatermarkConfig c) => value = c;
}
