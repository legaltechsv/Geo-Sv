import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:signature/signature.dart';

import '../../../core/ui/glass.dart';

/// Captura la firma del inspector y la guarda como PNG.
/// Devuelve la ruta del archivo o null si se canceló.
Future<String?> showSignatureSheet(BuildContext context, {required String inspectionId}) =>
    showGlassSheet<String>(context, builder: (_) => _SignaturePad(inspectionId: inspectionId));

class _SignaturePad extends StatefulWidget {
  const _SignaturePad({required this.inspectionId});
  final String inspectionId;

  @override
  State<_SignaturePad> createState() => _SignaturePadState();
}

class _SignaturePadState extends State<_SignaturePad> {
  final _c = SignatureController(
    penStrokeWidth: 3,
    penColor: Colors.black,
    exportBackgroundColor: Colors.white,
  );
  bool _saving = false;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_c.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Firma antes de continuar')));
      return;
    }
    setState(() => _saving = true);
    final Uint8List? png = await _c.toPngBytes();
    if (png == null) return setState(() => _saving = false);
    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, 'signatures', '${widget.inspectionId}.png');
    await File(path).create(recursive: true);
    await File(path).writeAsBytes(png, flush: true);
    if (mounted) Navigator.pop(context, path);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Firma del inspector',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        const Text('Al firmar, la inspección se cierra y ya no se puede editar.',
            style: TextStyle(color: AppColors.textMuted)),
        const SizedBox(height: 16),
        ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Signature(controller: _c, height: 220, backgroundColor: Colors.white),
        ),
        const SizedBox(height: 10),
        Row(children: [
          TextButton.icon(
            onPressed: _c.clear,
            icon: const Icon(Icons.refresh),
            label: const Text('Borrar'),
          ),
          const Spacer(),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        ]),
        const SizedBox(height: 8),
        GradientButton(
          label: 'Firmar y finalizar',
          icon: Icons.verified_outlined,
          busy: _saving,
          onPressed: _save,
        ),
      ]),
    );
  }
}
