import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

/// Paleta y tema de la app (oscuro, con acentos neón suaves).
class AppColors {
  AppColors._();
  static const bg = Color(0xFF070B18);
  static const violet = Color(0xFF7C5CFF);
  static const cyan = Color(0xFF22D3EE);
  static const teal = Color(0xFF2EE6A6);
  static const pink = Color(0xFFFF5C9A);
  static const amber = Color(0xFFFFB020);
  static const danger = Color(0xFFFF5C7A);
  static const text = Color(0xFFF4F6FB);
  static const textMuted = Color(0xFF9AA4B8);

  static const accentGradient = LinearGradient(
    colors: [violet, cyan],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

ThemeData buildAppTheme() {
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.violet,
      brightness: Brightness.dark,
      primary: AppColors.cyan,
      secondary: AppColors.violet,
      surface: const Color(0xFF0E1426),
    ),
    scaffoldBackgroundColor: Colors.transparent,
  );
  return base.copyWith(
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
          fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.text, letterSpacing: -0.3),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.06),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.cyan, width: 1.4),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: const Color(0xFF1A2238),
      contentTextStyle: const TextStyle(color: AppColors.text),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
  );
}

/// Panel de vidrio esmerilado: desenfoque del fondo + relleno translúcido
/// + borde con degradado de luz (lo que da el efecto "glass" premium).
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = 22,
    this.blur = 18,
    this.opacity = 0.08,
    this.onTap,
    this.tint,
    this.margin,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final double radius;
  final double blur;
  final double opacity;
  final VoidCallback? onTap;

  /// Color sutil para resaltar (p. ej. estado de la inspección).
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(radius);
    return Container(
      margin: margin,
      child: ClipRRect(
        borderRadius: r,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              borderRadius: r,
              splashColor: Colors.white.withValues(alpha: 0.06),
              highlightColor: Colors.white.withValues(alpha: 0.03),
              child: CustomPaint(
                foregroundPainter: _GlassBorderPainter(radius),
                child: Container(
                padding: padding,
                decoration: BoxDecoration(
                  borderRadius: r,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      (tint ?? Colors.white).withValues(alpha: opacity + 0.06),
                      (tint ?? Colors.white).withValues(alpha: opacity * 0.4),
                    ],
                  ),
                ),
                child: child,
              ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Borde de 1 px con degradado (brillo arriba-izquierda, se apaga abajo).
class _GlassBorderPainter extends CustomPainter {
  const _GlassBorderPainter(this.radius);
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.white.withValues(alpha: 0.35),
          Colors.white.withValues(alpha: 0.06),
          Colors.white.withValues(alpha: 0.14),
        ],
      ).createShader(rect);
    canvas.drawRRect(
        RRect.fromRectAndRadius(rect.deflate(0.5), Radius.circular(radius)), paint);
  }

  @override
  bool shouldRepaint(_GlassBorderPainter old) => old.radius != radius;
}

/// Fondo "aurora": manchas de luz que se desplazan lentamente sobre un azul
/// casi negro. Detrás de los paneles glass crea profundidad.
/// Se pinta con gradientes radiales (sin blur real) => barato para la GPU.
class AuroraBackground extends StatefulWidget {
  const AuroraBackground({super.key, this.child});
  final Widget? child;

  @override
  State<AuroraBackground> createState() => _AuroraBackgroundState();
}

class _AuroraBackgroundState extends State<AuroraBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 24))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(fit: StackFit.expand, children: [
      const ColoredBox(color: AppColors.bg),
      RepaintBoundary(
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, __) => CustomPaint(painter: _AuroraPainter(_c.value)),
        ),
      ),
      // Grano/viñeta sutil para que no se vea "plano"
      const DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.2),
            radius: 1.2,
            colors: [Colors.transparent, Color(0x99050812)],
          ),
        ),
      ),
      if (widget.child != null) widget.child!,
    ]);
  }
}

class _AuroraPainter extends CustomPainter {
  _AuroraPainter(this.t);
  final double t;

  static const _blobs = [
    (AppColors.violet, 0.55, 0.0, 0.18, 0.12),
    (AppColors.cyan, 0.45, 1.7, 0.85, 0.28),
    (AppColors.teal, 0.35, 3.4, 0.25, 0.78),
    (AppColors.pink, 0.28, 5.0, 0.8, 0.9),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final a = t * 2 * math.pi;
    for (final (color, alpha, phase, bx, by) in _blobs) {
      final c = Offset(
        size.width * (bx + 0.12 * math.sin(a + phase)),
        size.height * (by + 0.08 * math.cos(a * 0.8 + phase)),
      );
      final r = size.shortestSide * (0.75 + 0.1 * math.sin(a * 1.3 + phase));
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = RadialGradient(colors: [
            color.withValues(alpha: alpha),
            color.withValues(alpha: 0),
          ]).createShader(Rect.fromCircle(center: c, radius: r)),
      );
    }
  }

  @override
  bool shouldRepaint(_AuroraPainter old) => old.t != t;
}

/// Botón principal con degradado de marca y brillo.
class GradientButton extends StatelessWidget {
  const GradientButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.busy = false,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: AppColors.accentGradient,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: AppColors.violet.withValues(alpha: 0.45),
              blurRadius: 24,
              offset: const Offset(0, 8)),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: busy ? null : onPressed,
          child: SizedBox(
            height: 54,
            child: Center(
              child: busy
                  ? const SizedBox(
                      width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                  : Row(mainAxisSize: MainAxisSize.min, children: [
                      if (icon != null) ...[Icon(icon, color: Colors.white), const SizedBox(width: 8)],
                      Text(label,
                          style: const TextStyle(
                              color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
                    ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// Etiqueta tipo "píldora" (estado, gravedad).
class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.label, required this.color, this.icon});
  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 13, color: color), const SizedBox(width: 4)],
          Text(label,
              style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
        ]),
      );
}

/// Anillo de progreso con degradado (cumplimiento %).
class ProgressRing extends StatelessWidget {
  const ProgressRing({super.key, required this.value, this.size = 64, this.label});
  final double value;
  final double size;
  final String? label;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: value.clamp(0, 1)),
        duration: const Duration(milliseconds: 900),
        curve: Curves.easeOutCubic,
        builder: (_, v, __) => SizedBox(
          width: size,
          height: size,
          child: CustomPaint(
            painter: _RingPainter(v),
            child: Center(
              child: Text(label ?? '${(v * 100).round()}%',
                  style: TextStyle(
                      fontWeight: FontWeight.w800, fontSize: size * 0.22, color: AppColors.text)),
            ),
          ),
        ),
      );
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.v);
  final double v;

  @override
  void paint(Canvas canvas, Size s) {
    final stroke = s.width * 0.1;
    final rect = Offset.zero & s;
    final arc = rect.deflate(stroke / 2);
    canvas.drawArc(arc, 0, 2 * math.pi, false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..color = Colors.white.withValues(alpha: 0.1));
    canvas.drawArc(
      arc,
      -math.pi / 2,
      2 * math.pi * v,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..shader = const SweepGradient(
          colors: [AppColors.cyan, AppColors.violet, AppColors.teal],
          transform: GradientRotation(-math.pi / 2),
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_RingPainter o) => o.v != v;
}

/// Hoja inferior con vidrio (para formularios y selectores).
Future<T?> showGlassSheet<T>(BuildContext context, {required WidgetBuilder builder}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black54,
    builder: (ctx) => ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF0E1426).withValues(alpha: 0.82),
            border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.18))),
          ),
          padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
          child: SafeArea(
            top: false,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const SizedBox(height: 10),
              Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: Colors.white24, borderRadius: BorderRadius.circular(2))),
              Flexible(child: builder(ctx)),
            ]),
          ),
        ),
      ),
    ),
  );
}

/// Aparición escalonada (fade + slide) para listas y tarjetas.
class FadeSlideIn extends StatelessWidget {
  const FadeSlideIn({super.key, required this.child, this.index = 0});
  final Widget child;
  final int index;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: Duration(milliseconds: 420 + index * 70),
        curve: Curves.easeOutCubic,
        builder: (_, v, c) => Opacity(
          opacity: v,
          child: Transform.translate(offset: Offset(0, 18 * (1 - v)), child: c),
        ),
        child: child,
      );
}
