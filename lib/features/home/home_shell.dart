import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app_services.dart';
import '../../core/ui/glass.dart';
import '../capture/presentation/camera_screen.dart';
import '../inspections/presentation/inspection_detail_screen.dart';
import '../inspections/presentation/inspections_screen.dart';
import '../inspections/presentation/new_inspection_sheet.dart';
import '../segments/segment_detail_screen.dart';
import '../segments/segments_list.dart';
import '../settings/settings_screen.dart';
import '../visits/visits_screen.dart';
import 'dashboard_screen.dart';

/// Estructura principal: fondo aurora + 4 secciones + botón central de cámara
/// sobre una barra de navegación de vidrio flotante.
///
/// Interacciones:
///  - Tocar la cámara: foto rápida.
///  - Mantener presionada la cámara: menú flotante (foto, inspección, tramo).
///  - El indicador de la pestaña activa se desliza con rebote.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  bool _showHint = false;

  /// Se incrementa al volver de la cámara o de una inspección para que las
  /// pantallas recarguen sus datos.
  final ValueNotifier<int> refresh = ValueNotifier(0);

  @override
  void initState() {
    super.initState();
    _maybeShowHint();
  }

  /// Pista de una sola vez: "mantén presionada la cámara".
  Future<void> _maybeShowHint() async {
    final p = await SharedPreferences.getInstance();
    if (p.getBool('hintQuickMenu') ?? false) return;
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;
    setState(() => _showHint = true);
    await Future<void>.delayed(const Duration(seconds: 6));
    if (mounted) setState(() => _showHint = false);
    await p.setBool('hintQuickMenu', true);
  }

  void _go(int i) {
    if (i == _index) return;
    HapticFeedback.selectionClick();
    setState(() => _index = i);
    refresh.value++;
  }

  Future<void> _openCamera() async {
    HapticFeedback.mediumImpact();
    await Navigator.of(context).push(_route(
      CameraScreen(controller: services.camera, templates: services.templates),
    ));
    refresh.value++;
  }

  Future<void> _newInspection() async {
    final i = await showNewInspectionSheet(context);
    if (i == null || !mounted) return;
    await Navigator.push(context, _route(InspectionDetailScreen(inspectionId: i.id)));
    refresh.value++;
  }

  Future<void> _newSegment() async {
    final s = await showNewSegmentSheet(context);
    if (s == null || !mounted) return;
    await Navigator.push(context, _route(SegmentDetailScreen(segmentId: s.id)));
    refresh.value++;
  }

  /// Transición: la pantalla nueva crece y aparece (sensación de profundidad).
  static PageRoute<T> _route<T>(Widget page) => PageRouteBuilder<T>(
        transitionDuration: const Duration(milliseconds: 380),
        reverseTransitionDuration: const Duration(milliseconds: 280),
        pageBuilder: (_, __, ___) => page,
        transitionsBuilder: (_, a, __, child) {
          final c = CurvedAnimation(parent: a, curve: Curves.easeOutCubic);
          return FadeTransition(
            opacity: c,
            child: ScaleTransition(scale: Tween(begin: 0.94, end: 1.0).animate(c), child: child),
          );
        },
      );

  Future<void> _quickMenu() async {
    HapticFeedback.heavyImpact();
    setState(() => _showHint = false);
    final choice = await showGeneralDialog<int>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Cerrar',
      barrierColor: Colors.black.withValues(alpha: 0.35),
      transitionDuration: const Duration(milliseconds: 320),
      pageBuilder: (_, __, ___) => const _QuickMenu(),
      transitionBuilder: (_, a, __, child) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8 * a.value, sigmaY: 8 * a.value),
        child: FadeTransition(opacity: a, child: child),
      ),
    );
    switch (choice) {
      case 0:
        await _openCamera();
      case 1:
        await _newInspection();
      case 2:
        await _newSegment();
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      DashboardScreen(refresh: refresh, onNavigate: _go, onCamera: _openCamera),
      InspectionsScreen(refresh: refresh),
      VisitsScreen(refresh: refresh),
      const SettingsScreen(),
    ];
    final bottom = MediaQuery.paddingOf(context).bottom;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: AuroraBackground(
        child: Scaffold(
          extendBody: true,
          body: Stack(children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 320),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (c, a) => FadeTransition(
                opacity: a,
                child: ScaleTransition(
                  scale: Tween(begin: 0.97, end: 1.0).animate(a),
                  child: c,
                ),
              ),
              child: KeyedSubtree(key: ValueKey(_index), child: pages[_index]),
            ),
            // Pista flotante sobre el botón de cámara
            Positioned(
              left: 0,
              right: 0,
              bottom: bottom + 112,
              child: IgnorePointer(
                ignoring: !_showHint,
                child: AnimatedOpacity(
                  opacity: _showHint ? 1 : 0,
                  duration: const Duration(milliseconds: 300),
                  child: AnimatedSlide(
                    offset: _showHint ? Offset.zero : const Offset(0, 0.3),
                    duration: const Duration(milliseconds: 400),
                    curve: Curves.easeOutBack,
                    child: Center(
                      child: GestureDetector(
                        onTap: () => setState(() => _showHint = false),
                        child: const GlassCard(
                          radius: 16,
                          padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          tint: AppColors.cyan,
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.touch_app, size: 18, color: AppColors.cyan),
                            SizedBox(width: 8),
                            Text('Mantén presionada la cámara para más acciones',
                                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                          ]),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ]),
          bottomNavigationBar: _GlassNavBar(
            index: _index,
            onTap: _go,
            onCamera: _openCamera,
            onCameraLong: _quickMenu,
          ),
        ),
      ),
    );
  }
}

/// Menú flotante de acciones rápidas (burbujas de vidrio que suben en abanico).
class _QuickMenu extends StatelessWidget {
  const _QuickMenu();

  static const _items = [
    (Icons.photo_camera_rounded, 'Foto', AppColors.cyan),
    (Icons.fact_check_rounded, 'Inspección', AppColors.violet),
    (Icons.timeline_rounded, 'Tramo', AppColors.teal),
  ];

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Stack(children: [
      for (var i = 0; i < _items.length; i++)
        _Bubble(index: i, bottom: bottom, item: _items[i]),
    ]);
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.index, required this.bottom, required this.item});
  final int index;
  final double bottom;
  final (IconData, String, Color) item;

  @override
  Widget build(BuildContext context) {
    // Abanico de -50° a 50° sobre el botón de cámara.
    final angle = (-50 + index * 50) * math.pi / 180;
    const radius = 118.0;
    final dx = math.sin(angle) * radius;
    final dy = math.cos(angle) * radius;
    final (icon, label, color) = item;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 380 + index * 70),
      curve: Curves.easeOutBack,
      builder: (_, t, child) => Positioned(
        left: MediaQuery.sizeOf(context).width / 2 - 38 + dx * t,
        bottom: bottom + 46 + dy * t,
        child: Opacity(opacity: t.clamp(0, 1), child: Transform.scale(scale: 0.6 + 0.4 * t, child: child)),
      ),
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          Navigator.pop(context, index);
        },
        child: Tilt3D(
          maxAngle: 0.25,
          pressScale: 0.9,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [color.withValues(alpha: 0.95), color.withValues(alpha: 0.55)],
                ),
                border: Border.all(color: Colors.white.withValues(alpha: 0.7), width: 1.5),
                boxShadow: [BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 24)],
              ),
              child: Icon(icon, color: Colors.white, size: 32),
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(10)),
              child: Text(label,
                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
            ),
          ]),
        ),
      ),
    );
  }
}

class _GlassNavBar extends StatelessWidget {
  const _GlassNavBar({
    required this.index,
    required this.onTap,
    required this.onCamera,
    required this.onCameraLong,
  });
  final int index;
  final ValueChanged<int> onTap;
  final VoidCallback onCamera;
  final VoidCallback onCameraLong;

  static const _items = [
    (Icons.space_dashboard_outlined, Icons.space_dashboard, 'Panel'),
    (Icons.fact_check_outlined, Icons.fact_check, 'Inspecciones'),
    (Icons.map_outlined, Icons.map, 'Mapa'),
    (Icons.tune_outlined, Icons.tune, 'Ajustes'),
  ];
  static const _gap = 76.0; // espacio del botón de cámara

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(14, 0, 14, bottom + 10),
      child: SizedBox(
        height: 74,
        child: Stack(clipBehavior: Clip.none, alignment: Alignment.center, children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(26),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF0E1426).withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
                ),
                child: LayoutBuilder(builder: (context, c) {
                  final w = (c.maxWidth - _gap) / 4;
                  final left = index < 2 ? index * w : _gap + index * w;
                  return Stack(children: [
                    // Indicador que se desliza con rebote
                    AnimatedPositioned(
                      duration: const Duration(milliseconds: 420),
                      curve: Curves.easeOutBack,
                      left: left + w * 0.14,
                      top: 8,
                      width: w * 0.72,
                      height: 34,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          gradient: LinearGradient(colors: [
                            AppColors.violet.withValues(alpha: 0.45),
                            AppColors.cyan.withValues(alpha: 0.35),
                          ]),
                          boxShadow: [
                            BoxShadow(color: AppColors.cyan.withValues(alpha: 0.35), blurRadius: 14),
                          ],
                        ),
                      ),
                    ),
                    Row(children: [
                      _item(0, w),
                      _item(1, w),
                      const SizedBox(width: _gap),
                      _item(2, w),
                      _item(3, w),
                    ]),
                  ]);
                }),
              ),
            ),
          ),
          Positioned(
            top: -24,
            child: _CameraButton(onTap: onCamera, onLongPress: onCameraLong),
          ),
        ]),
      ),
    );
  }

  Widget _item(int i, double w) {
    final (icon, active, label) = _items[i];
    final sel = i == index;
    return SizedBox(
      width: w,
      child: InkResponse(
        onTap: () => onTap(i),
        radius: 32,
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          AnimatedScale(
            scale: sel ? 1.12 : 1,
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutBack,
            child: Icon(sel ? active : icon, color: sel ? Colors.white : AppColors.textMuted, size: 23),
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(label,
                maxLines: 1,
                style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                    color: sel ? AppColors.text : AppColors.textMuted)),
          ),
        ]),
      ),
    );
  }
}

/// Botón central con halo que "respira" y relieve 3D al presionarlo.
class _CameraButton extends StatefulWidget {
  const _CameraButton({required this.onTap, required this.onLongPress});
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  State<_CameraButton> createState() => _CameraButtonState();
}

class _CameraButtonState extends State<_CameraButton> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2200))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: Tilt3D(
        maxAngle: 0.3,
        pressScale: 0.9,
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, child) => Container(
            width: 70,
            height: 70,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF8B6CFF), AppColors.cyan],
              ),
              border: Border.all(color: Colors.white.withValues(alpha: 0.65), width: 2),
              boxShadow: [
                BoxShadow(
                  color: AppColors.cyan.withValues(alpha: 0.35 + 0.25 * _c.value),
                  blurRadius: 18 + 14 * _c.value,
                  spreadRadius: 1 + 2 * _c.value,
                ),
                const BoxShadow(color: Colors.black45, blurRadius: 10, offset: Offset(0, 6)),
              ],
            ),
            child: child,
          ),
          // Brillo superior para efecto de relieve
          child: Stack(alignment: Alignment.center, children: [
            Positioned(
              top: 6,
              child: Container(
                width: 40,
                height: 16,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.white.withValues(alpha: 0.45), Colors.white.withValues(alpha: 0)],
                  ),
                ),
              ),
            ),
            const Icon(Icons.photo_camera_rounded, color: Colors.white, size: 30),
          ]),
        ),
      ),
    );
  }
}

/// Acceso a Ajustes como página (desde el Panel u otros lugares).
class SettingsRoute {
  static Route<void> build() => MaterialPageRoute(builder: (_) => const SettingsPage());
}
