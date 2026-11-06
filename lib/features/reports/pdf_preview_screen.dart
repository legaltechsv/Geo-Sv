import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../../core/ui/glass.dart';
import '../share/share_service.dart';

/// Vista previa del reporte con 3 acciones:
///  - WhatsApp: envía el PDF (con un mensaje corto).
///  - Word: genera la versión .docx editable y la comparte/guarda.
///  - Imprimir: diálogo de impresión del sistema (o "Guardar como PDF").
class PdfPreviewScreen extends StatefulWidget {
  const PdfPreviewScreen({
    super.key,
    required this.title,
    required this.fileName,
    required this.bytes,
    this.buildDocx,
    this.shareText,
  });

  final String title;

  /// Nombre del PDF; el Word usa el mismo nombre con extensión .docx.
  final String fileName;
  final Uint8List bytes;

  /// Genera la versión Word bajo demanda (null = sin opción Word).
  final Future<Uint8List> Function()? buildDocx;

  /// Texto que acompaña al archivo en WhatsApp.
  final String? shareText;

  @override
  State<PdfPreviewScreen> createState() => _PdfPreviewScreenState();
}

class _PdfPreviewScreenState extends State<PdfPreviewScreen> {
  final _share = ShareService();
  bool _wordBusy = false;

  Rect? _origin(BuildContext ctx) {
    final box = ctx.findRenderObject() as RenderBox?;
    return box == null ? null : box.localToGlobal(Offset.zero) & box.size;
  }

  Future<void> _sendPdf(BuildContext ctx) => _share.shareFile(
        bytes: widget.bytes,
        fileName: widget.fileName,
        mimeType: 'application/pdf',
        text: widget.shareText,
        origin: _origin(ctx),
      );

  Future<void> _sendWord(BuildContext ctx) async {
    final build = widget.buildDocx;
    if (build == null) return;
    final origin = _origin(ctx);
    setState(() => _wordBusy = true);
    try {
      final docx = await build();
      await _share.shareFile(
        bytes: docx,
        fileName: widget.fileName.replaceAll(RegExp(r'\.pdf$'), '.docx'),
        mimeType: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        text: widget.shareText,
        origin: origin,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('No se pudo generar el Word: $e')));
      }
    } finally {
      if (mounted) setState(() => _wordBusy = false);
    }
  }

  Future<void> _print() => Printing.layoutPdf(
        name: widget.fileName,
        onLayout: (_) async => widget.bytes,
      );

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return AuroraBackground(
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        ),
        body: PdfPreview(
          build: (_) async => widget.bytes,
          pdfFileName: widget.fileName,
          useActions: false,
          canChangeOrientation: false,
          canChangePageFormat: false,
          canDebug: false,
          scrollViewDecoration: const BoxDecoration(color: Colors.transparent),
          pdfPreviewPageDecoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(6),
            boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 20)],
          ),
          loadingWidget: const CircularProgressIndicator(),
        ),
        bottomNavigationBar: Padding(
          padding: EdgeInsets.fromLTRB(14, 8, 14, bottom + 12),
          child: GlassCard(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
            child: Row(children: [
              Builder(
                builder: (b) => _Action(
                  icon: Icons.chat,
                  color: const Color(0xFF25D366),
                  label: 'WhatsApp',
                  onTap: () => _sendPdf(b),
                ),
              ),
              if (widget.buildDocx != null)
                Builder(
                  builder: (b) => _Action(
                    icon: Icons.description,
                    color: const Color(0xFF2B579A),
                    label: 'Word',
                    busy: _wordBusy,
                    onTap: () => _sendWord(b),
                  ),
                ),
              _Action(icon: Icons.print, color: AppColors.cyan, label: 'Imprimir', onTap: _print),
              Builder(
                builder: (b) => _Action(
                  icon: Icons.ios_share,
                  color: AppColors.violet,
                  label: 'PDF',
                  onTap: () => _sendPdf(b),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
    this.busy = false,
  });
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) => Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: busy ? null : onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(14)),
                child: busy
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Icon(icon, color: Colors.white),
              ),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              ),
            ]),
          ),
        ),
      );
}
