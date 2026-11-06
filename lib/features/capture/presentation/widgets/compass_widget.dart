import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../core/location/compass_service.dart';

/// Brújula del visor: la rosa gira con el teléfono y la flecha fija de
/// arriba indica hacia dónde apunta la cámara (ej. "47° NE").
class CompassWidget extends StatelessWidget {
  const CompassWidget({super.key, required this.heading, this.size = 64});
  final ValueListenable<double?> heading;
  final double size;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double?>(
      valueListenable: heading,
      builder: (_, h, __) {
        if (h == null) return const SizedBox.shrink();
        return Column(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(
            width: size,
            height: size,
            child: Stack(alignment: Alignment.center, children: [
              // La rosa gira al contrario del rumbo: el "N" queda apuntando al norte real.
              TweenAnimationBuilder<double>(
                tween: Tween(end: -h * math.pi / 180),
                duration: const Duration(milliseconds: 250),
                builder: (_, a, __) => Transform.rotate(
                  angle: a,
                  child: CustomPaint(size: Size.square(size), painter: _RosePainter()),
                ),
              ),
              // Indicador fijo de la dirección de la cámara
              Positioned(
                top: 0,
                child: Icon(Icons.arrow_drop_down, color: Colors.amberAccent, size: size * 0.32),
              ),
            ]),
          ),
          const SizedBox(height: 2),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(10)),
            child: Text(CompassService.label(h),
                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
          ),
        ]);
      },
    );
  }
}

class _RosePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    final c = s.center(Offset.zero);
    final r = s.width / 2;
    canvas.drawCircle(c, r - 1, Paint()..color = Colors.black.withValues(alpha: 0.45));
    canvas.drawCircle(
        c,
        r - 1,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = Colors.white54);
    // Marcas cada 30°
    for (var i = 0; i < 12; i++) {
      final a = i * math.pi / 6;
      final p1 = c + Offset(math.sin(a), -math.cos(a)) * (r - 3);
      final p2 = c + Offset(math.sin(a), -math.cos(a)) * (r - (i % 3 == 0 ? 9 : 6));
      canvas.drawLine(p1, p2, Paint()..color = Colors.white70..strokeWidth = 1.2);
    }
    // Aguja: roja al norte, blanca al sur
    final n = Path()
      ..moveTo(c.dx, c.dy - r * 0.62)
      ..lineTo(c.dx - r * 0.13, c.dy)
      ..lineTo(c.dx + r * 0.13, c.dy)
      ..close();
    final so = Path()
      ..moveTo(c.dx, c.dy + r * 0.62)
      ..lineTo(c.dx - r * 0.13, c.dy)
      ..lineTo(c.dx + r * 0.13, c.dy)
      ..close();
    canvas.drawPath(n, Paint()..color = const Color(0xFFFF4D5E));
    canvas.drawPath(so, Paint()..color = Colors.white70);
    final tp = TextPainter(
      text: TextSpan(
          text: 'N',
          style: TextStyle(color: Colors.white, fontSize: r * 0.3, fontWeight: FontWeight.w800)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(c.dx - tp.width / 2, c.dy - r + r * 0.22));
  }

  @override
  bool shouldRepaint(_RosePainter old) => false;
}
