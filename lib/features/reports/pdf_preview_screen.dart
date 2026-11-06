import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../../core/ui/glass.dart';

/// Vista previa del PDF con botones para compartir (WhatsApp, correo…)
/// e imprimir, provistos por el paquete printing.
class PdfPreviewScreen extends StatelessWidget {
  const PdfPreviewScreen({super.key, required this.title, required this.fileName, required this.bytes});
  final String title;
  final String fileName;
  final Uint8List bytes;

  @override
  Widget build(BuildContext context) {
    return AuroraBackground(
      child: Scaffold(
        appBar: AppBar(
          title: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          actions: [
            IconButton(
              tooltip: 'Compartir',
              icon: const Icon(Icons.ios_share),
              onPressed: () => Printing.sharePdf(bytes: bytes, filename: fileName),
            ),
          ],
        ),
        body: PdfPreview(
          build: (_) async => bytes,
          pdfFileName: fileName,
          canChangeOrientation: false,
          canChangePageFormat: false,
          canDebug: false,
          allowPrinting: true,
          allowSharing: true,
          scrollViewDecoration: const BoxDecoration(color: Colors.transparent),
          pdfPreviewPageDecoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(6),
            boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 20)],
          ),
          loadingWidget: const CircularProgressIndicator(),
        ),
      ),
    );
  }
}
