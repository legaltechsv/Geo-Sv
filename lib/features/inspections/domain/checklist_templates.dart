import 'package:flutter/material.dart';

/// Plantilla de checklist: secciones -> preguntas.
/// Para que la use cualquier institución, en una siguiente iteración se
/// pueden importar plantillas propias desde JSON (mismo formato).
class ChecklistTemplate {
  const ChecklistTemplate({
    required this.key,
    required this.name,
    required this.icon,
    required this.sections,
  });

  final String key;
  final String name;
  final IconData icon;
  final Map<String, List<String>> sections;

  int get itemCount => sections.values.fold(0, (a, b) => a + b.length);
}

class ChecklistTemplates {
  ChecklistTemplates._();

  static ChecklistTemplate byKey(String key) =>
      all.firstWhere((t) => t.key == key, orElse: () => all.first);

  static const all = <ChecklistTemplate>[
    ChecklistTemplate(
      key: 'general',
      name: 'Inspección general',
      icon: Icons.fact_check_outlined,
      sections: {
        'Instalaciones': [
          'Accesos y rutas de circulación libres',
          'Iluminación adecuada en áreas de trabajo',
          'Ventilación adecuada',
          'Orden y limpieza general',
        ],
        'Documentación': [
          'Permisos de funcionamiento vigentes y visibles',
          'Registros y bitácoras al día',
        ],
        'Seguridad': [
          'Extintores vigentes, señalizados y accesibles',
          'Salidas de emergencia señalizadas y despejadas',
          'Botiquín de primeros auxilios completo',
        ],
      },
    ),
    ChecklistTemplate(
      key: 'obra',
      name: 'Supervisión de obra',
      icon: Icons.construction,
      sections: {
        'Avance y calidad': [
          'Avance físico conforme a programa',
          'Trabajos conforme a planos y especificaciones',
          'Calidad de materiales (certificados / pruebas)',
          'Bitácora de obra actualizada y firmada',
        ],
        'Seguridad en obra': [
          'Personal con EPP (casco, chaleco, calzado)',
          'Perímetro y señalización de obra',
          'Andamios y trabajos en altura seguros',
          'Excavaciones protegidas',
        ],
        'Ambiental y entorno': [
          'Manejo adecuado de ripio y desechos',
          'Control de polvo y ruido',
          'Sin afectación a vías o vecinos',
        ],
      },
    ),
    ChecklistTemplate(
      key: 'seguridad',
      name: 'Seguridad y salud ocupacional',
      icon: Icons.health_and_safety_outlined,
      sections: {
        'Organización': [
          'Comité de seguridad y salud conformado',
          'Programa de gestión de riesgos vigente',
          'Capacitaciones registradas',
        ],
        'Condiciones': [
          'Equipo de protección personal disponible y en uso',
          'Instalaciones eléctricas en buen estado',
          'Almacenamiento seguro de sustancias químicas',
          'Maquinaria con guardas de protección',
        ],
        'Emergencias': [
          'Plan de emergencia y evacuación',
          'Brigadas identificadas',
          'Simulacros documentados',
        ],
      },
    ),
    ChecklistTemplate(
      key: 'proteccion_civil',
      name: 'Protección civil / riesgo',
      icon: Icons.warning_amber_rounded,
      sections: {
        'Estructura': [
          'Sin grietas o daños estructurales visibles',
          'Muros y taludes estables',
          'Techos y cubiertas en buen estado',
        ],
        'Entorno': [
          'Drenajes y cunetas libres',
          'Sin riesgo de inundación o deslizamiento',
          'Árboles o postes sin riesgo de caída',
        ],
        'Preparación': [
          'Rutas de evacuación y punto de encuentro',
          'Alarmas o sistema de alerta',
        ],
      },
    ),
    ChecklistTemplate(
      key: 'sanitaria',
      name: 'Inspección sanitaria',
      icon: Icons.sanitizer_outlined,
      sections: {
        'Higiene': [
          'Superficies y utensilios limpios',
          'Lavamanos con jabón y papel',
          'Servicios sanitarios limpios y funcionales',
        ],
        'Alimentos y agua': [
          'Cadena de frío controlada',
          'Agua potable apta',
          'Alimentos rotulados y protegidos',
        ],
        'Plagas y desechos': [
          'Sin evidencia de plagas',
          'Control de plagas documentado',
          'Desechos en recipientes con tapa',
        ],
      },
    ),
  ];
}
