import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';

import '../../../core/permissions/permission_service.dart';
import '../../templates/watermark_template.dart';
import '../application/capture_controller.dart';
import '../domain/capture_record.dart';
import 'gallery_screen.dart';
import 'preview_screen.dart';
import 'widgets/live_watermark_overlay.dart';
import 'widgets/template_picker_sheet.dart';

/// Visor principal estilo "cámara con marca de agua":
///
///  ┌───────────────────────────────┐
///  │ ⚡  ⏱  [GPS ±4 m]          ⋮  │  barra superior
///  │                               │
///  │        (vista de cámara)      │  pellizcar = zoom
///  │                               │
///  │ ┌──────────────────┐          │
///  │ │ 21:34  05/11/2026 │  [QR]   │  marca EN VIVO (tocar = editar)
///  │ └──────────────────┘          │
///  │        FOTO                   │
///  │  [galería]   ( ◉ )   [Marcas] │  barra inferior
///  └───────────────────────────────┘
///
/// Sin acceso a la galería del teléfono: toda evidencia nace aquí.
class CameraScreen extends StatefulWidget {
  const CameraScreen({
    super.key,
    required this.controller,
    required this.templates,
    this.inspectionId,
  });
  final CaptureController controller;
  final TemplateController templates;

  /// Si viene, las fotos se vinculan a esa inspección y el visor se queda
  /// abierto para tomar varias seguidas.
  final String? inspectionId;

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> with WidgetsBindingObserver {
  CaptureController get c => widget.controller;

  int _timerSeconds = 0; // 0 / 3 / 10
  int? _countdown;
  bool _flashEffect = false;

  // Zoom con pellizco
  double _zoom = 1, _zoomAtStart = 1, _minZoom = 1, _maxZoom = 1;
  bool _showZoom = false;
  Timer? _zoomHide;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    c.initialize();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _zoomHide?.cancel();
    c.pause(); // libera la cámara y el GPS al salir del visor
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) {
      c.pause();
    } else if (state == AppLifecycleState.resumed) {
      c.resume();
    }
  }

  // ─────────────── Acciones ───────────────

  Future<void> _onShutter() async {
    if (_countdown != null) return;
    // Temporizador (útil para fotos sin mover el teléfono)
    if (_timerSeconds > 0) {
      for (var s = _timerSeconds; s > 0; s--) {
        if (!mounted) return;
        setState(() => _countdown = s);
        HapticFeedback.selectionClick();
        await Future<void>.delayed(const Duration(seconds: 1));
      }
      if (mounted) setState(() => _countdown = null);
    }

    HapticFeedback.mediumImpact();
    setState(() => _flashEffect = true); // destello blanco tipo obturador
    Future.delayed(const Duration(milliseconds: 120),
        () => mounted ? setState(() => _flashEffect = false) : null);

    try {
      final record = await c.capture(
        config: widget.templates.value,
        inspectionId: widget.inspectionId,
      );
      if (!mounted) return;
      if (widget.inspectionId != null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Foto agregada a la inspección'),
          duration: Duration(seconds: 1),
        ));
      } else {
        _openPreview(record);
      }
    } on CaptureException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  void _openPreview(CaptureRecord r) => Navigator.of(context)
      .push(MaterialPageRoute(builder: (_) => PreviewScreen(record: r)));

  void _openGallery() => Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => GalleryScreen(repository: c.repository)));

  void _cycleTimer() => setState(() => _timerSeconds = switch (_timerSeconds) {
        0 => 3,
        3 => 10,
        _ => 0,
      });

  Future<void> _onScaleStart(ScaleStartDetails _) async {
    final cam = c.camera;
    if (cam == null) return;
    _zoomAtStart = _zoom;
    _minZoom = await cam.getMinZoomLevel();
    _maxZoom = (await cam.getMaxZoomLevel()).clamp(1, 10).toDouble();
  }

  Future<void> _onScaleUpdate(ScaleUpdateDetails d) async {
    final cam = c.camera;
    if (cam == null || d.pointerCount < 2) return;
    final z = (_zoomAtStart * d.scale).clamp(_minZoom, _maxZoom);
    setState(() {
      _zoom = z;
      _showZoom = true;
    });
    await cam.setZoomLevel(z);
    _zoomHide?.cancel();
    _zoomHide = Timer(const Duration(seconds: 1),
        () => mounted ? setState(() => _showZoom = false) : null);
  }

  // ─────────────── UI ───────────────

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: ListenableBuilder(
          listenable: c,
          builder: (context, _) {
            if (c.status == CaptureStatus.error) return _PermissionError(controller: c);
            final cam = c.camera;
            if (cam == null || !cam.value.isInitialized) {
              return const Center(child: CircularProgressIndicator(color: Colors.white));
            }
            final pad = MediaQuery.paddingOf(context);
            return Stack(fit: StackFit.expand, children: [
              // 1. Vista de cámara a pantalla completa (recorte tipo "cover")
              GestureDetector(
                onScaleStart: _onScaleStart,
                onScaleUpdate: _onScaleUpdate,
                child: _FullScreenPreview(camera: cam),
              ),

              // 2. Degradados para que los controles se lean sobre cualquier fondo
              const _EdgeGradients(),

              // 3. Barra superior
              Positioned(
                top: pad.top + 6,
                left: 8,
                right: 8,
                child: Row(children: [
                  _RoundIcon(icon: Icons.arrow_back, onTap: () => Navigator.maybePop(context)),
                  _RoundIcon(
                    icon: switch (c.flashMode) {
                      FlashMode.always => Icons.flash_on,
                      FlashMode.off => Icons.flash_off,
                      _ => Icons.flash_auto,
                    },
                    onTap: c.cycleFlash,
                  ),
                  _RoundIcon(
                    icon: _timerSeconds == 0 ? Icons.timer_off_outlined : Icons.timer_outlined,
                    badge: _timerSeconds == 0 ? null : '${_timerSeconds}s',
                    onTap: _cycleTimer,
                  ),
                  const Spacer(),
                  _GpsChip(position: c.livePosition),
                  const Spacer(),
                  _RoundIcon(
                    icon: Icons.tune,
                    onTap: () => showTemplatePicker(context,
                        templates: widget.templates, clock: c.nowForPreview),
                  ),
                ]),
              ),

              // 4. Indicador de zoom
              if (_showZoom)
                Center(
                  child: _Pill(text: '${_zoom.toStringAsFixed(1)}x'),
                ),

              // 5. Marca de agua EN VIVO
              Positioned(
                left: 12,
                right: 12,
                bottom: pad.bottom + 150,
                child: Align(
                  alignment: Alignment.bottomLeft,
                  child: ValueListenableBuilder<WatermarkConfig>(
                    valueListenable: widget.templates,
                    builder: (_, cfg, __) => ValueListenableBuilder<Position?>(
                      valueListenable: c.livePosition,
                      builder: (_, pos, __) => ValueListenableBuilder<String?>(
                        valueListenable: c.liveAddress,
                        builder: (_, addr, __) => LiveWatermarkOverlay(
                          config: cfg,
                          position: pos,
                          address: addr,
                          clock: c.nowForPreview,
                          onTap: () => showTemplatePicker(context,
                              templates: widget.templates, clock: c.nowForPreview),
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // 6. Cuenta regresiva del temporizador
              if (_countdown != null)
                Center(
                  child: Text('$_countdown',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 120,
                          fontWeight: FontWeight.w800,
                          shadows: [Shadow(blurRadius: 12, color: Colors.black54)])),
                ),

              // 7. Barra inferior
              Positioned(
                left: 0,
                right: 0,
                bottom: pad.bottom + 18,
                child: Column(children: [
                  const Text('FOTO',
                      style: TextStyle(
                          color: Color(0xFFFFC107),
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.5)),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _GalleryThumb(last: c.lastRecord, onTap: _openGallery),
                      _ShutterButton(
                        busy: c.status == CaptureStatus.capturing || _countdown != null,
                        onPressed: _onShutter,
                      ),
                      _LabeledButton(
                        icon: Icons.branding_watermark_outlined,
                        label: 'Marcas',
                        onTap: () => showTemplatePicker(context,
                            templates: widget.templates, clock: c.nowForPreview),
                      ),
                    ],
                  ),
                ]),
              ),

              // 8. Destello del obturador
              IgnorePointer(
                child: AnimatedOpacity(
                  opacity: _flashEffect ? 0.85 : 0,
                  duration: const Duration(milliseconds: 90),
                  child: const ColoredBox(color: Colors.white),
                ),
              ),
            ]);
          },
        ),
      ),
    );
  }
}

// ─────────────── Componentes ───────────────

/// La cámara entrega la imagen en orientación de sensor (horizontal);
/// se invierten ancho/alto y se recorta con BoxFit.cover para llenar la
/// pantalla sin deformar, como la cámara nativa.
class _FullScreenPreview extends StatelessWidget {
  const _FullScreenPreview({required this.camera});
  final CameraController camera;

  @override
  Widget build(BuildContext context) {
    final size = camera.value.previewSize;
    if (size == null) return CameraPreview(camera);
    return ClipRect(
      child: SizedBox.expand(
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(width: size.height, height: size.width, child: CameraPreview(camera)),
        ),
      ),
    );
  }
}

class _EdgeGradients extends StatelessWidget {
  const _EdgeGradients();
  @override
  Widget build(BuildContext context) => const IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x99000000), Colors.transparent, Colors.transparent, Color(0xCC000000)],
              stops: [0, 0.15, 0.7, 1],
            ),
          ),
        ),
      );
}

class _RoundIcon extends StatelessWidget {
  const _RoundIcon({required this.icon, required this.onTap, this.badge});
  final IconData icon;
  final VoidCallback onTap;
  final String? badge;

  @override
  Widget build(BuildContext context) => IconButton(
        onPressed: onTap,
        icon: Badge(
          isLabelVisible: badge != null,
          label: Text(badge ?? ''),
          backgroundColor: const Color(0xFFFFC107),
          textColor: Colors.black,
          child: Icon(icon, color: Colors.white, size: 26),
        ),
      );
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(20)),
        child: Text(text,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
      );
}

/// Calidad GPS en vivo: verde ≤10 m, ámbar ≤30 m, rojo >30 m.
class _GpsChip extends StatelessWidget {
  const _GpsChip({required this.position});
  final ValueListenable<Position?> position;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Position?>(
      valueListenable: position,
      builder: (context, p, _) {
        final acc = p?.accuracy;
        final color = acc == null
            ? Colors.grey
            : acc <= 10
                ? Colors.greenAccent
                : acc <= 30
                    ? Colors.amber
                    : Colors.redAccent;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(20)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.gps_fixed, size: 15, color: color),
            const SizedBox(width: 6),
            Text(acc == null ? 'Buscando GPS…' : 'GPS ±${acc.toStringAsFixed(0)} m',
                style: const TextStyle(color: Colors.white, fontSize: 13)),
          ]),
        );
      },
    );
  }
}

class _GalleryThumb extends StatelessWidget {
  const _GalleryThumb({required this.last, required this.onTap});
  final ValueListenable<CaptureRecord?> last;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<CaptureRecord?>(
      valueListenable: last,
      builder: (_, r, __) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white, width: 2),
            color: Colors.white12,
          ),
          clipBehavior: Clip.antiAlias,
          child: r == null
              ? const Icon(Icons.photo_library_outlined, color: Colors.white)
              : Image.file(File(r.filePath), fit: BoxFit.cover, cacheWidth: 160),
        ),
      ),
    );
  }
}

class _LabeledButton extends StatelessWidget {
  const _LabeledButton({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: SizedBox(
          width: 52,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, color: Colors.white, size: 28),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(color: Colors.white, fontSize: 12)),
          ]),
        ),
      );
}

class _ShutterButton extends StatelessWidget {
  const _ShutterButton({required this.busy, required this.onPressed});
  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: busy ? null : onPressed,
      child: Container(
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 5),
        ),
        padding: const EdgeInsets.all(5),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: busy ? Colors.white38 : Colors.white,
            shape: BoxShape.circle,
          ),
          child: busy
              ? const Padding(
                  padding: EdgeInsets.all(18),
                  child: CircularProgressIndicator(strokeWidth: 3, color: Colors.black54),
                )
              : null,
        ),
      ),
    );
  }
}

class _PermissionError extends StatelessWidget {
  const _PermissionError({required this.controller});
  final CaptureController controller;

  @override
  Widget build(BuildContext context) {
    final outcome = controller.blockingPermission;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.location_off, color: Colors.white70, size: 56),
          const SizedBox(height: 16),
          Text(controller.errorMessage ?? 'Error',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 16)),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: switch (outcome) {
              PermissionOutcome.permanentlyDenied => controller.permissions.openSettings,
              PermissionOutcome.serviceDisabled => controller.permissions.openLocationSettings,
              _ => controller.initialize,
            },
            child: Text(switch (outcome) {
              PermissionOutcome.permanentlyDenied => 'Abrir Ajustes',
              PermissionOutcome.serviceDisabled => 'Activar GPS',
              _ => 'Reintentar',
            }),
          ),
          if (outcome != null && outcome != PermissionOutcome.denied)
            TextButton(
              onPressed: controller.initialize,
              child: const Text('Ya lo activé, reintentar'),
            ),
        ]),
      ),
    );
  }
}
