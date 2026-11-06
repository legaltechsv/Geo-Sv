import 'package:flutter/material.dart';

import '../../../templates/watermark_template.dart';

/// Editor de los datos personalizados de la marca (proyecto, nota y
/// campos visibles). Coordenadas, hora y QR NO son editables: son la
/// parte "inalterable" de la evidencia.
Future<void> showWatermarkEditor(
  BuildContext context, {
  required TemplateController templates,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true, // sube con el teclado
    backgroundColor: const Color(0xFF1C1C1E),
    showDragHandle: true,
    builder: (ctx) => _EditorBody(templates: templates),
  );
}

class _EditorBody extends StatefulWidget {
  const _EditorBody({required this.templates});
  final TemplateController templates;

  @override
  State<_EditorBody> createState() => _EditorBodyState();
}

class _EditorBodyState extends State<_EditorBody> {
  late final _project = TextEditingController(text: widget.templates.value.projectName);
  late final _note = TextEditingController(text: widget.templates.value.note);
  late bool _showAddress = widget.templates.value.showAddress;
  late bool _showAccuracy = widget.templates.value.showAccuracy;

  @override
  void dispose() {
    _project.dispose();
    _note.dispose();
    super.dispose();
  }

  void _save() {
    widget.templates.update(widget.templates.value.copyWith(
      projectName: _project.text,
      note: _note.text,
      showAddress: _showAddress,
      showAccuracy: _showAccuracy,
    ));
    Navigator.pop(context);
  }

  InputDecoration _deco(String label, IconData icon) => InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        filled: true,
        fillColor: Colors.white10,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      );

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 0, 20, MediaQuery.viewInsetsOf(context).bottom + 20),
      child: Theme(
        data: ThemeData.dark(useMaterial3: true),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Align(
            alignment: Alignment.centerLeft,
            child: Text('Datos de la marca',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _project,
            maxLength: 40,
            textCapitalization: TextCapitalization.sentences,
            decoration: _deco('Proyecto / cliente', Icons.business),
          ),
          TextField(
            controller: _note,
            maxLength: 80,
            textCapitalization: TextCapitalization.sentences,
            decoration: _deco('Nota (ej. Avance de colado de losa)', Icons.notes),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Mostrar dirección'),
            value: _showAddress,
            onChanged: (v) => setState(() => _showAddress = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Mostrar precisión GPS'),
            value: _showAccuracy,
            onChanged: (v) => setState(() => _showAccuracy = v),
          ),
          const ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.lock, size: 20),
            title: Text('Hora, coordenadas, QR y código siempre se incluyen',
                style: TextStyle(fontSize: 13, color: Colors.white60)),
          ),
          const SizedBox(height: 8),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
            onPressed: _save,
            child: const Text('Guardar'),
          ),
        ]),
      ),
    );
  }
}
