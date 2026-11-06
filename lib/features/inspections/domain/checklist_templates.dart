import 'package:flutter/material.dart';

/// Plantilla de checklist: secciones -> preguntas.
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

/// Formularios de supervisión municipal.
///
/// Basados en prácticas y documentos de referencia de El Salvador y la
/// región: bitácora y control de obra (BID, FISDL), inspección ambiental
/// (MARN / unidades ambientales municipales), evaluación de riesgo por
/// deslizamientos (MOP / Protección Civil), centros de mediación municipal
/// (p. ej. reglamento de Ciudad Delgado), normas de asistencia, puntualidad
/// y permanencia (p. ej. ISSS), verificación catastral de linderos (CNR) y
/// listas de chequeo de flota vehicular.
class ChecklistTemplates {
  ChecklistTemplates._();

  /// Busca por clave también entre plantillas anteriores, para que las
  /// inspecciones viejas sigan mostrando su nombre correcto.
  static ChecklistTemplate byKey(String key) =>
      [...all, ..._legacy].firstWhere((t) => t.key == key, orElse: () => all.first);

  /// Plantillas que se muestran al crear una inspección.
  static const all = <ChecklistTemplate>[
    ChecklistTemplate(
      key: 'infraestructura',
      name: 'Obras, calles e infraestructura',
      icon: Icons.add_road,
      sections: {
        'Documentación y control': [
          'Bitácora de obra actualizada y firmada por supervisor y contratista',
          'Planos, especificaciones y carpeta técnica disponibles en el sitio',
          'Avance físico conforme al programa de ejecución',
          'Órdenes de cambio u obras adicionales autorizadas por escrito',
          'Rótulo del proyecto instalado (monto, plazo, fuente de fondos)',
        ],
        'Calidad de la obra': [
          'Trazo, niveles y pendientes conforme a planos',
          'Materiales con calidad verificada (pruebas o certificados)',
          'Compactación de terracería y base verificada',
          'Espesores de concreto o asfalto según especificaciones',
          'Drenajes funcionando (cunetas, tragantes, alcantarillas)',
          'Acabados, juntas y bordes sin defectos visibles',
        ],
        'Seguridad y señalización': [
          'Señalización vial y desvíos durante la obra',
          'Personal con equipo de protección personal',
          'Zanjas y excavaciones protegidas y señalizadas',
          'Maquinaria y equipo en buen estado',
        ],
        'Entorno y comunidad': [
          'Sitio limpio y ripio retirado o almacenado adecuadamente',
          'Acceso de vecinos y peatones garantizado',
          'Sin daños a servicios (agua, energía, telecomunicaciones)',
        ],
      },
    ),
    ChecklistTemplate(
      key: 'medio_ambiente',
      name: 'Medio ambiente',
      icon: Icons.eco_outlined,
      sections: {
        'Permisos y compromisos': [
          'Permiso ambiental vigente o resolución del MARN que no requiere EIA',
          'Medidas del programa de manejo o adecuación ambiental en ejecución',
        ],
        'Desechos sólidos': [
          'Desechos separados y almacenados en recipientes adecuados',
          'Sin botaderos a cielo abierto ni quema de basura',
          'Recolección y disposición final autorizadas',
        ],
        'Agua': [
          'Sin descarga de aguas residuales a quebradas, ríos o calles',
          'Fosa séptica o planta de tratamiento funcionando',
          'Protección de nacimientos y zonas de recarga',
        ],
        'Aire y ruido': [
          'Control de polvo, humo y malos olores',
          'Ruido dentro de horarios y niveles permitidos',
        ],
        'Recursos naturales': [
          'Sin tala ni poda de árboles sin autorización',
          'Zonas verdes y áreas naturales protegidas',
          'Sin ocupación de zonas de protección (riberas, quebradas)',
        ],
      },
    ),
    ChecklistTemplate(
      key: 'riesgos',
      name: 'Gestión de riesgos',
      icon: Icons.warning_amber_rounded,
      sections: {
        'Amenazas del entorno': [
          'Talud o ladera estable (sin grietas, escarpes ni árboles inclinados)',
          'Sin evidencia de deslizamiento o erosión activa',
          'Distancia segura a quebrada o río (sin riesgo de inundación)',
          'Drenaje pluvial adecuado, sin escorrentía hacia el inmueble',
          'Árboles, postes o muros sin riesgo de caída',
        ],
        'Estado de la estructura': [
          'Paredes sin rajaduras ni desplomes',
          'Techo y estructura de soporte en buen estado',
          'Cimentación sin socavación',
          'Instalaciones eléctricas seguras',
        ],
        'Preparación ante emergencias': [
          'Familia o institución cuenta con plan de emergencia',
          'Rutas de evacuación y punto de encuentro definidos',
          'Comunicación con Protección Civil o comisión comunal',
        ],
        'Seguimiento': [
          'Medidas de mitigación recomendadas al responsable',
          'Se notificó a la autoridad competente cuando el riesgo es alto',
        ],
      },
    ),
    ChecklistTemplate(
      key: 'mediacion',
      name: 'Mediación',
      icon: Icons.handshake_outlined,
      sections: {
        'Expediente': [
          'Solicitud registrada con número único de expediente',
          'Entrevista inicial y criterios de mediabilidad aplicados',
          'Convocatorias entregadas con comprobante',
          'Compromiso de confidencialidad firmado por las partes',
        ],
        'Sesión de mediación': [
          'Mediador acreditado y habilitado',
          'Espacio privado y adecuado para la sesión',
          'Partes informadas del procedimiento y sus principios',
          'Plazos del procedimiento cumplidos',
        ],
        'Resultado y seguimiento': [
          'Acta de mediación (con o sin acuerdo) firmada',
          'Acuerdos claros, concretos y por escrito',
          'Seguimiento al cumplimiento de los acuerdos',
          'Expediente archivado y resguardado',
        ],
      },
    ),
    ChecklistTemplate(
      key: 'social',
      name: 'Área social',
      icon: Icons.groups_outlined,
      sections: {
        'Programa y beneficiarios': [
          'Padrón de beneficiarios actualizado',
          'Beneficiario cumple criterios de elegibilidad',
          'Beneficiario verificado en visita domiciliar',
        ],
        'Entrega de apoyos': [
          'Acta o recibo de entrega firmado por el beneficiario',
          'Apoyo entregado en la cantidad y calidad establecidas',
          'Entrega realizada en la fecha programada',
        ],
        'Atención a la población': [
          'Espacio accesible (personas mayores, con discapacidad)',
          'Trato digno y confidencialidad de los datos',
          'Mecanismo de quejas y sugerencias disponible',
        ],
        'Coordinación comunitaria': [
          'Coordinación con ADESCO o líderes comunitarios',
          'Actividad documentada con lista de asistencia y fotografías',
        ],
      },
    ),
    ChecklistTemplate(
      key: 'rrhh',
      name: 'Recursos humanos y asistencia',
      icon: Icons.badge_outlined,
      sections: {
        'Asistencia y puntualidad': [
          'Personal presente según planilla o rol de turnos',
          'Marcación de entrada registrada (biométrico o listado)',
          'Llegadas tardías documentadas',
          'Ausencias justificadas con permiso o incapacidad',
        ],
        'Permanencia': [
          'Personal permanece en su área durante la jornada',
          'Salidas autorizadas por la jefatura',
          'Personal de campo ubicado en la zona asignada',
        ],
        'Presentación y desempeño': [
          'Uso de uniforme e identificación (carné)',
          'Funciones conforme al perfil del puesto',
          'Atención adecuada al público',
        ],
        'Documentación': [
          'Expediente de personal actualizado',
          'Horas extra autorizadas y registradas',
        ],
      },
    ),
    ChecklistTemplate(
      key: 'catastro',
      name: 'Catastro',
      icon: Icons.home_work_outlined,
      sections: {
        'Identificación del inmueble': [
          'Inmueble identificado con número catastral o cuenta',
          'Propietario o poseedor entrevistado e identificado',
          'Ubicación coincide con el mapa catastral',
        ],
        'Terreno y construcción': [
          'Medidas y linderos verificados en campo',
          'Colindantes identificados',
          'Área construida coincide con el registro',
          'Nuevas construcciones o ampliaciones detectadas',
          'Uso del inmueble (habitacional, comercial, mixto) coincide con el registro',
        ],
        'Servicios y tributos': [
          'Servicios municipales disponibles (alumbrado, aseo, pavimento)',
          'Actividad económica registrada o con licencia',
          'Solvencia municipal al día',
        ],
        'Evidencia': [
          'Fotografía de fachada tomada',
          'Croquis o ficha catastral actualizada',
        ],
      },
    ),
    ChecklistTemplate(
      key: 'flota',
      name: 'Flota vehicular',
      icon: Icons.directions_car_outlined,
      sections: {
        'Documentos': [
          'Tarjeta de circulación vigente',
          'Licencia de conducir vigente del motorista',
          'Seguro del vehículo vigente',
          'Bitácora u orden de misión del vehículo',
        ],
        'Estado mecánico': [
          'Frenos y freno de mano funcionando',
          'Dirección y suspensión en buen estado',
          'Niveles de aceite, refrigerante y líquido de frenos',
          'Llantas con presión y desgaste adecuados, y repuesto',
          'Batería y sistema eléctrico',
        ],
        'Luces y seguridad': [
          'Luces delanteras, traseras, direccionales y de freno',
          'Cinturones, espejos, parabrisas y limpiaparabrisas',
          'Extintor, botiquín, triángulos y herramientas',
        ],
        'Uso y control': [
          'Kilometraje registrado',
          'Consumo de combustible justificado (vales o bitácora)',
          'Vehículo rotulado como institucional',
          'Carrocería limpia y sin daños nuevos',
          'Uso dentro de horario y misión autorizada',
        ],
      },
    ),
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
  ];

  /// Plantillas anteriores: ya no se ofrecen, pero las inspecciones viejas
  /// conservan su nombre e ícono (sus preguntas ya están guardadas).
  static const _legacy = <ChecklistTemplate>[
    ChecklistTemplate(key: 'obra', name: 'Supervisión de obra', icon: Icons.construction, sections: {}),
    ChecklistTemplate(
        key: 'seguridad', name: 'Seguridad y salud ocupacional', icon: Icons.health_and_safety_outlined, sections: {}),
    ChecklistTemplate(
        key: 'proteccion_civil', name: 'Protección civil / riesgo', icon: Icons.warning_amber_rounded, sections: {}),
    ChecklistTemplate(key: 'sanitaria', name: 'Inspección sanitaria', icon: Icons.sanitizer_outlined, sections: {}),
  ];
}
