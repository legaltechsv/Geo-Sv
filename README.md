# GEO CUSCA SUR — Evidencia fotográfica, inspecciones y visitas con GPS

## Instalar en Android sin instalar nada en tu computadora

1. Sube este proyecto a un repositorio de GitHub (rama `main`).
2. GitHub Actions compila solo (pestaña **Actions**, ~8–12 min).
3. Abre la pestaña **Releases** → descarga `app-release.apk` desde el teléfono → instalar
   (acepta "instalar apps de origen desconocido").
4. Cada vez que se sube un cambio a `main` se genera una versión nueva.

Si la compilación falla, el error aparece en Actions → último run → paso "Compilar APK".

## Módulos

| Módulo | Qué hace |
|---|---|
| Panel | Cumplimiento promedio del mes, hallazgos, lugares, fotos, accesos rápidos, recientes |
| Inspecciones | 5 plantillas (general, obra, seguridad ocupacional, protección civil, sanitaria); folio automático; GPS y hora de llegada; Cumple / No cumple / N/A; gravedad y nota por hallazgo; fotos vinculadas; firma; cierre en solo lectura |
| Informe PDF | Datos generales + QR al lugar, resumen, hallazgos ordenados por gravedad, checklist, fotos con coordenadas y código, firmas |
| Visitas | Mapa con todos los lugares, filtro Hoy/7/30 días/Todo, visitas, fotos, tiempo en sitio, "Cómo llegar", reporte PDF |
| Cámara | Marca de agua en vivo con QR, EXIF GPS, anti-ubicación falsa, hora de red |
| Ajustes | Institución, unidad, inspector y cargo (encabezado de los PDF) |

---


> "La foto te lleva al lugar": cada evidencia lleva 3 rutas hacia Google Maps
> (QR visible, EXIF GPS y enlace en el texto compartido).

## 1. Stack recomendado: Flutter

| Criterio | Flutter | React Native |
|---|---|---|
| Dibujar texto + QR sobre una foto de 12 MP | Canvas nativo (Skia/Impeller) integrado | Requiere librerías nativas extra (Skia/ViewShot) |
| Plugins clave (camera, geolocator, exif) | Oficiales o muy maduros | Fragmentados entre Expo / bare |
| Un solo código de render para iOS y Android | Sí, píxel a píxel | Depende del módulo nativo |

## 2. Arquitectura (feature-first + capas)

```
lib/
├── main.dart                         # Composition root (inyección de dependencias)
├── core/                             # Servicios de plataforma, sin UI
│   ├── permissions/permission_service.dart   # Cámara + ubicación PRECISA
│   ├── location/location_service.dart        # GPS precalentado + lectura al disparo + anti-mock
│   ├── time/trusted_time_service.dart        # NTP con reloj monotónico (NTP > GPS > dispositivo)
│   ├── geocoding/geocoding_service.dart      # lat/lng -> dirección (nativo, sin API key)
│   └── utils/maps_link.dart                  # URLs universales de Google Maps
└── features/
    ├── capture/
    │   ├── domain/capture_record.dart        # Entidad de evidencia
    │   ├── data/capture_repository.dart      # SQLite (offline-first)
    │   ├── application/capture_controller.dart # Orquesta el flujo del obturador
    │   └── presentation/
    │       ├── camera_screen.dart            # Visor a pantalla completa (flash, temporizador, zoom)
    │       ├── preview_screen.dart           # Foto final + compartir
    │       ├── gallery_screen.dart           # Galería interna por días
    │       └── widgets/                      # Marca en vivo, selector de plantillas, editor
    ├── templates/watermark_template.dart     # Plantillas: Clásico, Obra, Reporte, Mínimo
    ├── watermark/
    │   ├── watermark_service.dart            # Canvas: panel + texto + QR -> JPEG (isolate)
    │   └── exif_writer.dart                  # GPS en EXIF
    ├── share/share_service.dart              # Smart Share Payload
    └── sync/offline_sync_service.dart        # Al volver la red: NTP + direcciones pendientes
```

Reglas: `presentation` → `application` → (`domain`, `data`, `core`). Ningún
servicio de `core` conoce la UI. Todo se inyecta por constructor, así cada
pieza se puede probar con dobles.

## 3. Flujo del obturador

```
Abrir visor ─► permisos (cámara + ubicación precisa) ─► GPS stream "warm-up" + NTP sync
                                                             │
[Obturador] ─► takePicture() ║ getFixAtShutter()  (en paralelo)
                    │
                    ├─ ¿ubicación simulada? ──► BLOQUEAR
                    ├─ hora confiable (NTP / GPS / dispositivo, etiquetada)
                    ├─ reverse geocoding (null si offline → "pendiente")
                    ├─ marca de agua: coords, ±m, dirección, fecha/hora, QR, código
                    ├─ guardar JPEG en almacenamiento privado
                    ├─ escribir EXIF GPS
                    ├─ SHA-256 del archivo final
                    └─ SQLite ─► Vista previa ─► Compartir
```

## 4. Modo offline

| Elemento | Sin internet |
|---|---|
| GPS | Funciona (el GPS es satelital, no usa datos). Arranque en frío más lento. |
| QR | Se genera igual: es solo el texto de la URL. Funciona al escanearlo con red. |
| EXIF | Funciona. |
| Hora | Cae a hora GPS o del dispositivo, **y lo dice en la foto**. |
| Dirección | Queda "pendiente"; `OfflineSyncService` la completa al volver la red. La foto no se re-renderiza (es la evidencia); la dirección nueva va en el texto compartido. |

## 5. Limitaciones reales (importante para el producto)

1. **Tocar la foto no abre Maps.** WhatsApp/Telegram abren la imagen en su
   visor; ninguna app permite que una imagen sea un enlace. Lo que el
   receptor toca es el **enlace del texto** o **escanea el QR**. Por eso se
   envían los tres métodos juntos.
2. **WhatsApp borra el EXIF** al enviar como "foto" (y la recomprime).
   El QR y el enlace sobreviven; el EXIF solo llega si se envía como
   *documento*, por correo o Drive.
3. **WhatsApp en iOS a veces descarta el texto** cuando va junto a una imagen.
   Para eso existe el botón "Solo enlace".
4. **"Inalterable" requiere servidor.** El código de verificación y el
   SHA-256 detectan ediciones si se comparan con el registro, pero quien
   controle el teléfono podría falsificar ambos. Para validez legal: subir
   el hash a un backend que lo firme con su propia hora (siguiente iteración).
5. La detección de mock (`isMocked`) es confiable en Android; en iOS es
   limitada (jailbreak / simuladores).

## 6. Puesta en marcha

```bash
flutter create --org com.tuempresa geomark_app
# copiar lib/ y pubspec.yaml de este paquete sobre el proyecto
flutter pub get
# aplicar platform_config/android y platform_config/ios
flutter run
```

## 7. Siguientes iteraciones sugeridas

- Backend de verificación (página `verificar.tudominio/CODIGO`) y firma del hash.
- Galería interna de evidencias con filtros por proyecto/fecha y exportación PDF.
- Campos personalizados en la marca de agua (proyecto, cliente, responsable).
- Logo de la empresa en la marca de agua y plantillas.
