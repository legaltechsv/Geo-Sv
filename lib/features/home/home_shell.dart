import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app_services.dart';
import '../../core/ui/glass.dart';
import '../capture/presentation/camera_screen.dart';
import '../inspections/presentation/inspections_screen.dart';
import '../settings/settings_screen.dart';
import '../visits/visits_screen.dart';
import 'dashboard_screen.dart';

/// Estructura principal: fondo aurora + 4 secciones + botón central de cámara
/// sobre una barra de navegación de vidrio flotante.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  /// Se incrementa al volver de la cámara o de una inspección para que las
  /// pantallas recarguen sus datos.
  final ValueNotifier<int> refresh = ValueNotifier(0);

  void _go(int i) {
    HapticFeedback.selectionClick();
    setState(() => _index = i);
    refresh.value++;
  }

  Future<void> _openCamera() async {
    HapticFeedback.mediumImpact();
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => CameraScreen(controller: services.camera, templates: services.templates),
    ));
    refresh.value++;
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      DashboardScreen(refresh: refresh, onNavigate: _go, onCamera: _openCamera),
      InspectionsScreen(refresh: refresh),
      VisitsScreen(refresh: refresh),
      const SettingsScreen(),
    ];
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: AuroraBackground(
        child: Scaffold(
          extendBody: true,
          body: AnimatedSwitcher(
            duration: const Duration(milliseconds: 280),
            switchInCurve: Curves.easeOutCubic,
            transitionBuilder: (c, a) => FadeTransition(
              opacity: a,
              child: SlideTransition(
                position: Tween(begin: const Offset(0, 0.02), end: Offset.zero).animate(a),
                child: c,
              ),
            ),
            child: KeyedSubtree(key: ValueKey(_index), child: pages[_index]),
          ),
          bottomNavigationBar: _GlassNavBar(
            index: _index,
            onTap: _go,
            onCamera: _openCamera,
          ),
        ),
      ),
    );
  }
}

class _GlassNavBar extends StatelessWidget {
  const _GlassNavBar({required this.index, required this.onTap, required this.onCamera});
  final int index;
  final ValueChanged<int> onTap;
  final VoidCallback onCamera;

  static const _items = [
    (Icons.space_dashboard_outlined, Icons.space_dashboard, 'Panel'),
    (Icons.fact_check_outlined, Icons.fact_check, 'Inspecciones'),
    (Icons.map_outlined, Icons.map, 'Mapa'),
    (Icons.tune_outlined, Icons.tune, 'Ajustes'),
  ];

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    Widget item(int i) {
      final (icon, active, label) = _items[i];
      final sel = i == index;
      return Expanded(
        child: InkResponse(
          onTap: () => onTap(i),
          radius: 32,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                color: sel ? Colors.white.withValues(alpha: 0.12) : Colors.transparent,
              ),
              child: Icon(sel ? active : icon,
                  color: sel ? AppColors.cyan : AppColors.textMuted, size: 23),
            ),
            const SizedBox(height: 2),
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
                child: Row(children: [
                  item(0),
                  item(1),
                  const SizedBox(width: 72), // espacio del botón de cámara
                  item(2),
                  item(3),
                ]),
              ),
            ),
          ),
          // Botón central de cámara con halo
          Positioned(
            top: -22,
            child: GestureDetector(
              onTap: onCamera,
              child: Container(
                width: 66,
                height: 66,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: AppColors.accentGradient,
                  border: Border.all(color: Colors.white.withValues(alpha: 0.6), width: 2),
                  boxShadow: [
                    BoxShadow(
                        color: AppColors.cyan.withValues(alpha: 0.55),
                        blurRadius: 26,
                        spreadRadius: 1),
                  ],
                ),
                child: const Icon(Icons.photo_camera_rounded, color: Colors.white, size: 30),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
