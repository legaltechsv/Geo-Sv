import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// Generador mínimo de documentos Word (.docx), sin dependencias nativas.
///
/// Un .docx es un ZIP con XML (Office Open XML). Este builder soporta lo que
/// necesitan los reportes: títulos, párrafos con formato, enlaces, tablas
/// con encabezado sombreado, imágenes (JPG/PNG) y salto de página.
/// El archivo abre en Microsoft Word, Google Docs, WPS y LibreOffice, y se
/// puede editar e imprimir.
class DocxBuilder {
  final _body = StringBuffer();
  final _rels = <String>[];
  final _media = <String, Uint8List>{};
  int _rid = 1;
  int _imgId = 1;

  static const _emuPerPx = 9525; // 1 px (96 dpi) = 9525 EMU

  static String _esc(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');

  static String _run(String text,
      {bool bold = false, int size = 20, String? color, bool italic = false, bool underline = false}) {
    final props = StringBuffer('<w:rPr><w:rFonts w:ascii="Calibri" w:hAnsi="Calibri" w:cs="Calibri"/>');
    if (bold) props.write('<w:b/>');
    if (italic) props.write('<w:i/>');
    if (underline) props.write('<w:u w:val="single"/>');
    if (color != null) props.write('<w:color w:val="$color"/>');
    props.write('<w:sz w:val="$size"/><w:szCs w:val="$size"/></w:rPr>');
    // Saltos de línea dentro del texto -> <w:br/>
    final parts = text.split('\n').map((t) => '<w:t xml:space="preserve">${_esc(t)}</w:t>');
    return '<w:r>$props${parts.join('<w:br/>')}</w:r>';
  }

  static String _p(String runs, {String align = 'left', int after = 80}) =>
      '<w:p><w:pPr><w:spacing w:after="$after"/><w:jc w:val="$align"/></w:pPr>$runs</w:p>';

  /// size en medios puntos (20 = 10 pt).
  void paragraph(String text,
      {bool bold = false, int size = 20, String? color, String align = 'left', bool italic = false}) {
    _body.write(_p(_run(text, bold: bold, size: size, color: color, italic: italic), align: align));
  }

  void heading(String text, {int size = 28, String color = '0B1020'}) {
    _body.write(_p(_run(text, bold: true, size: size, color: color), after: 120));
  }

  void spacer() => _body.write('<w:p/>');

  void pageBreak() => _body.write('<w:p><w:r><w:br w:type="page"/></w:r></w:p>');

  /// Párrafo con un enlace tocable.
  void link(String text, String url, {String? prefix}) {
    final id = 'rId${_rid++}';
    _rels.add('<Relationship Id="$id" '
        'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/hyperlink" '
        'Target="${_esc(url)}" TargetMode="External"/>');
    _body.write(_p(
      '${prefix == null ? '' : _run(prefix)}'
      '<w:hyperlink r:id="$id">${_run(text, color: '2563EB', underline: true)}</w:hyperlink>',
    ));
  }

  /// Tabla. [widths] en porcentajes (suman ~100). La primera fila puede ser encabezado.
  void table(List<List<String>> rows,
      {List<int>? widths, bool header = true, String headerFill = '0B1020', int size = 18}) {
    if (rows.isEmpty) return;
    final cols = rows.first.length;
    final w = widths ?? List.filled(cols, (100 / cols).floor());
    const total = 9700; // ancho útil en twips (carta con márgenes de 0.75")
    final grid = w.map((p) => '<w:gridCol w:w="${(total * p / 100).round()}"/>').join();
    final b = StringBuffer('<w:tbl><w:tblPr><w:tblW w:w="5000" w:type="pct"/>'
        '<w:tblBorders>'
        '<w:top w:val="single" w:sz="4" w:color="DDE1EA"/>'
        '<w:bottom w:val="single" w:sz="4" w:color="DDE1EA"/>'
        '<w:insideH w:val="single" w:sz="4" w:color="DDE1EA"/>'
        '</w:tblBorders>'
        '<w:tblCellMar><w:top w:w="60" w:type="dxa"/><w:left w:w="80" w:type="dxa"/>'
        '<w:bottom w:w="60" w:type="dxa"/><w:right w:w="80" w:type="dxa"/></w:tblCellMar>'
        '</w:tblPr><w:tblGrid>$grid</w:tblGrid>');
    for (var r = 0; r < rows.length; r++) {
      final isHeader = header && r == 0;
      b.write('<w:tr>');
      if (isHeader) b.write('<w:trPr><w:tblHeader/></w:trPr>');
      for (var c = 0; c < cols; c++) {
        final text = c < rows[r].length ? rows[r][c] : '';
        final width = (total * w[c] / 100).round();
        b.write('<w:tc><w:tcPr><w:tcW w:w="$width" w:type="dxa"/>');
        if (isHeader) b.write('<w:shd w:val="clear" w:color="auto" w:fill="$headerFill"/>');
        if (!isHeader && r.isEven) b.write('<w:shd w:val="clear" w:color="auto" w:fill="F3F5F9"/>');
        b.write('</w:tcPr>');
        b.write(_p(_run(text, bold: isHeader, size: size, color: isHeader ? 'FFFFFF' : null), after: 0));
        b.write('</w:tc>');
      }
      b.write('</w:tr>');
    }
    b.write('</w:tbl>');
    _body.write(b);
    spacer();
  }

  /// Imagen en línea. [widthPx]/[heightPx] = tamaño en el documento.
  void image(Uint8List bytes,
      {required double widthPx, required double heightPx, String ext = 'jpeg', String? caption}) {
    final id = _imgId++;
    final rid = 'rId${_rid++}';
    final name = 'image$id.$ext';
    _media['word/media/$name'] = bytes;
    _rels.add('<Relationship Id="$rid" '
        'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" '
        'Target="media/$name"/>');
    final cx = (widthPx * _emuPerPx).round(), cy = (heightPx * _emuPerPx).round();
    _body.write('<w:p><w:pPr><w:spacing w:after="40"/></w:pPr><w:r><w:drawing>'
        '<wp:inline distT="0" distB="0" distL="0" distR="0">'
        '<wp:extent cx="$cx" cy="$cy"/><wp:docPr id="$id" name="Imagen $id"/>'
        '<a:graphic xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main">'
        '<a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture">'
        '<pic:pic xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture">'
        '<pic:nvPicPr><pic:cNvPr id="$id" name="$name"/><pic:cNvPicPr/></pic:nvPicPr>'
        '<pic:blipFill><a:blip r:embed="$rid"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill>'
        '<pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="$cx" cy="$cy"/></a:xfrm>'
        '<a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr>'
        '</pic:pic></a:graphicData></a:graphic></wp:inline></w:drawing></w:r></w:p>');
    if (caption != null) paragraph(caption, size: 16, color: '5B6478');
  }

  Uint8List build() {
    const ct = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        '<Default Extension="jpeg" ContentType="image/jpeg"/>'
        '<Default Extension="png" ContentType="image/png"/>'
        '<Override PartName="/word/document.xml" '
        'ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
        '</Types>';
    const rootRels = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" '
        'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" '
        'Target="word/document.xml"/></Relationships>';
    final docRels = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '${_rels.join()}</Relationships>';
    final doc = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<w:document '
        'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
        'xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing">'
        '<w:body>$_body'
        '<w:sectPr><w:pgSz w:w="12240" w:h="15840"/>'
        '<w:pgMar w:top="1080" w:right="1080" w:bottom="1080" w:left="1080" '
        'w:header="720" w:footer="720" w:gutter="0"/></w:sectPr>'
        '</w:body></w:document>';

    final archive = Archive();
    void add(String name, List<int> data) => archive.addFile(ArchiveFile(name, data.length, data));
    add('[Content_Types].xml', utf8.encode(ct));
    add('_rels/.rels', utf8.encode(rootRels));
    add('word/_rels/document.xml.rels', utf8.encode(docRels));
    add('word/document.xml', utf8.encode(doc));
    _media.forEach(add);
    final out = ZipEncoder().encode(archive);
    // ignore: unnecessary_non_null_assertion, unnecessary_cast
    return Uint8List.fromList((out as List<int>?)!);
  }
}
