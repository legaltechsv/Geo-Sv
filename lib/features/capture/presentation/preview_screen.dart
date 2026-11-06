import 'dart:io';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/ui/glass.dart';
import '../../share/share_service.dart';
import '../domain/capture_record.dart';

/// Vista posterior al disparo: la foto con marca de agua + acciones.
class PreviewScreen extends StatelessWidget {
  PreviewScreen({super.key, required this.record, ShareService? share})
      : share = share ?? ShareService(); // inyectable para tests
  final CaptureRecord record;
  final ShareService share;

  /// Rect del botón para anclar el popover de compartir en iPad.
  Rect? _originOf(BuildContext ctx) {
    final box = ctx.findRenderObject() as RenderBox?;
    return box == null ? null : box.localToGlobal(Offset.zero) & box.size;
  }

  @override
  Widget build(BuildContext context) {
    final s = share;
    return AuroraBackground(
      child: Scaffold(
      appBar: AppBar(title: const Text('Evidencia capturada')),
      body: Column(children: [
        Expanded(
          child: InteractiveViewer(child: Image.file(File(record.filePath))),
        ),
        if (record.addressPending)
          const ListTile(
            leading: Icon(Icons.cloud_off),
            title: Text('Sin conexión: coordenadas guardadas.'),
            subtitle: Text('La dirección se completará al recuperar internet. '
                'El QR y el enlace ya funcionan.'),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: Column(children: [
            Builder(
              builder: (b) => FilledButton.icon(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                icon: const Icon(Icons.share),
                label: const Text('Compartir foto + ubicación'),
                onPressed: () => s.shareCapture(record, origin: _originOf(b)),
              ),
            ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: Builder(
                  builder: (b) => OutlinedButton.icon(
                    icon: const Icon(Icons.link),
                    label: const Text('Solo enlace'),
                    onPressed: () => s.shareLinkOnly(record, origin: _originOf(b)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.map),
                  label: const Text('Ver en Maps'),
                  onPressed: () => launchUrl(Uri.parse(record.mapsUrl),
                      mode: LaunchMode.externalApplication),
                ),
              ),
            ]),
            TextButton.icon(
              icon: const Icon(Icons.copy),
              label: const Text('Copiar enlace'),
              onPressed: () async {
                await s.copyLink(record);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Enlace copiado')));
                }
              },
            ),
          ]),
        ),
      ]),
    ));
  }
}
