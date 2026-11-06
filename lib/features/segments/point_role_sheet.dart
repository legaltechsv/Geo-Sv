import 'package:flutter/material.dart';

import '../../core/ui/glass.dart';
import 'segment.dart';

/// "¿Este punto es inicio, intermedio o final del tramo?"
/// Devuelve la clave ('inicio' / 'intermedio' / 'final').
Future<String?> askPointRole(BuildContext context) => showGlassSheet<String>(
      context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('¿Qué punto del tramo es?',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          const Text('La distancia se mide entre fotos en el orden en que se toman.',
              style: TextStyle(color: AppColors.textMuted)),
          const SizedBox(height: 16),
          for (final (role, icon, color) in const [
            (PointRole.inicio, Icons.flag_outlined, AppColors.teal),
            (PointRole.intermedio, Icons.more_horiz, AppColors.cyan),
            (PointRole.fin, Icons.sports_score, AppColors.pink),
          ])
            GlassCard(
              margin: const EdgeInsets.only(bottom: 10),
              onTap: () => Navigator.pop(ctx, role.key),
              child: Row(children: [
                Icon(icon, color: color),
                const SizedBox(width: 14),
                Expanded(
                    child: Text(role.label,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
                const Icon(Icons.chevron_right),
              ]),
            ),
        ]),
      ),
    );
