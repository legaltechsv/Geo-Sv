import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

/// Esquina de la foto donde va un elemento (logotipo o mini mapa).
/// Las esquinas inferiores quedan justo encima del panel de datos.
enum OverlayPosition { supIzq, supDer, infIzq, infDer }

extension OverlayPositionInfo on OverlayPosition {
  String get label => switch (this) {
        OverlayPosition.supIzq => 'Arriba izquierda',
        OverlayPosition.supDer => 'Arriba derecha',
        OverlayPosition.infIzq => 'Abajo izquierda',
        OverlayPosition.infDer => 'Abajo derecha',
      };
  IconData get icon => switch (this) {
        OverlayPosition.supIzq => Icons.north_west,
        OverlayPosition.supDer => Icons.north_east,
        OverlayPosition.infIzq => Icons.south_west,
        OverlayPosition.infDer => Icons.south_east,
      };
  bool get isTop => this == OverlayPosition.supIzq || this == OverlayPosition.supDer;
  bool get isLeft => this == OverlayPosition.supIzq || this == OverlayPosition.infIzq;
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
    this.logoPosition = OverlayPosition.supDer,
    this.showMap = false,
    this.mapPosition = OverlayPosition.supIzq,
  });

  final WatermarkStyle style;
  final String projectName;
  final String note;
  final bool showAddress;
  final bool showAccuracy;

  /// Dónde va el logotipo en la foto.
  final OverlayPosition logoPosition;

  /// Mini mapa (norte arriba, con cono hacia donde apunta la cámara).
  final bool showMap;
  final OverlayPosition mapPosition;

  bool get hasProject => projectName.trim().isNotEmpty;
  bool get hasNote => note.trim().isNotEmpty;

  WatermarkConfig copyWith({
    WatermarkStyle? style,
    String? projectName,
    String? note,
    bool? showAddress,
    bool? showAccuracy,
    OverlayPosition? logoPosition,
    bool? showMap,
    OverlayPosition? mapPosition,
  }) =>
      WatermarkConfig(
        style: style ?? this.style,
        projectName: projectName ?? this.projectName,
        note: note ?? this.note,
        showAddress: showAddress ?? this.showAddress,
        showAccuracy: showAccuracy ?? this.showAccuracy,
        logoPosition: logoPosition ?? this.logoPosition,
        showMap: showMap ?? this.showMap,
        mapPosition: mapPosition ?? this.mapPosition,
      );

  Map<String, Object?> toJson() => {
        'style': style.name,
        'projectName': projectName,
        'note': note,
        'showAddress': showAddress,
        'showAccuracy': showAccuracy,
        'logoPosition': logoPosition.name,
        'showMap': showMap,
        'mapPosition': mapPosition.name,
      };

  factory WatermarkConfig.fromJson(Map<String, dynamic> j) {
    T pick<T extends Enum>(List<T> values, Object? name, T fallback) =>
        values.where((v) => v.name == name).firstOrNull ?? fallback;
    return WatermarkConfig(
      style: pick(WatermarkStyle.values, j['style'], WatermarkStyle.clasico),
      projectName: j['projectName'] as String? ?? '',
      note: j['note'] as String? ?? '',
      showAddress: j['showAddress'] as bool? ?? true,
      showAccuracy: j['showAccuracy'] as bool? ?? true,
      logoPosition: pick(OverlayPosition.values, j['logoPosition'], OverlayPosition.supDer),
      showMap: j['showMap'] as bool? ?? false,
      mapPosition: pick(OverlayPosition.values, j['mapPosition'], OverlayPosition.supIzq),
    );
  }
}

/// Estado de la plantilla activa. (Para recordarla entre sesiones,
/// persistir con shared_preferences en una siguiente iteración.)
class TemplateController extends ValueNotifier<WatermarkConfig> {
  TemplateController() : super(const WatermarkConfig());

  static const _key = 'watermarkConfig';

  /// Recupera la plantilla elegida la última vez.
  Future<void> load() async {
    final raw = (await SharedPreferences.getInstance()).getString(_key);
    if (raw == null) return;
    try {
      value = WatermarkConfig.fromJson(Map<String, dynamic>.from(jsonDecode(raw) as Map));
    } catch (_) {}
  }

  void setStyle(WatermarkStyle s) => update(value.copyWith(style: s));

  void update(WatermarkConfig c) {
    value = c;
    SharedPreferences.getInstance().then((p) => p.setString(_key, jsonEncode(c.toJson())));
  }
}
