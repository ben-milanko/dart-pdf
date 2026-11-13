import 'dart:convert';
import 'dart:typed_data';

import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:test/test.dart';

/// Image-replacement redaction: a page replaced by its picture keeps nothing
/// else - no text, fonts, annotations, fields or structure text - and keeps
/// its displayed size and its place in the page tree.

Uint8List _pdf(List<String> bodies) {
  final buffer = StringBuffer('%PDF-1.7\n');
  final offsets = <int>[];
  for (var i = 0; i < bodies.length; i++) {
    offsets.add(buffer.length);
    buffer.write('${i + 1} 0 obj\n${bodies[i]}\nendobj\n');
  }
  final xref = buffer.length;
  buffer
    ..write('xref\n0 ${bodies.length + 1}\n')
    ..write('0000000000 65535 f \n');
  for (final o in offsets) {
    buffer.write('${o.toString().padLeft(10, '0')} 00000 n \n');
  }
  buffer.write('trailer\n<< /Size ${bodies.length + 1} /Root 1 0 R >>\n'
      'startxref\n$xref\n%%EOF\n');
  return Uint8List.fromList(latin1.encode(buffer.toString()));
}

String _stream(String dict, String data) =>
    '<< $dict /Length ${data.length} >>\nstream\n$data\nendstream';

String _everything(Uint8List bytes) {
  final out = StringBuffer(latin1.decode(bytes));
  final cos = PdfDocument.open(bytes).cos;
  for (final n in cos.objectNumbers) {
    final o = cos.resolve(CosReference(n, 0));
    if (o is! CosStream) continue;
    try {
      out.write(latin1.decode(cos.decodeStreamData(o)));
    } on Object {
      // left raw
    }
  }
  return out.toString();
}

/// A flat-colour RGBA picture.
PdfPageRaster _raster(int w, int h, {int r = 10, int g = 20, int b = 30}) {
  final rgba = Uint8List(w * h * 4);
  for (var p = 0; p < rgba.length; p += 4) {
    rgba
      ..[p] = r
      ..[p + 1] = g
      ..[p + 2] = b
      ..[p + 3] = 255;
  }
  return PdfPageRaster(width: w, height: h, rgba: rgba);
}

Uint8List _twoPages({String rotate = ''}) => _pdf([
      '<< /Type /Catalog /Pages 2 0 R /StructTreeRoot 9 0 R '
          '/AcroForm << /Fields [8 0 R] >> >>',
      '<< /Type /Pages /Kids [3 0 R 4 0 R] /Count 2 >>',
      '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] '
          '/CropBox [10 20 410 620] $rotate /Contents 5 0 R '
          '/Resources << /Font << /F1 7 0 R >> >> /Annots [8 0 R] >>',
      '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 6 0 R '
          '/Resources << /Font << /F1 7 0 R >> >> >>',
      _stream('', 'BT /F1 12 Tf 72 500 Td (VISIBLETEXT) Tj ET'),
      _stream('', 'BT /F1 12 Tf 72 500 Td (OTHERPAGE) Tj ET'),
      '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
      '<< /Type /Annot /Subtype /Widget /FT /Tx /T (f) /V (FIELDVALUE) '
          '/Rect [100 100 200 120] /P 3 0 R >>',
      '<< /Type /StructTreeRoot /K [10 0 R] >>',
      '<< /Type /StructElem /S /P /P 9 0 R /Pg 3 0 R '
          '/ActualText (STRUCTTEXT) /K 0 >>',
    ]);

void main() {
  test('a replaced page holds only its picture', () {
    final editor = PdfEditor(PdfDocument.open(_twoPages()));
    final out = editor.replacePagesWithImages({0: _raster(40, 60)});
    final all = _everything(out);
    for (final gone in [
      'VISIBLETEXT',
      'FIELDVALUE',
      'STRUCTTEXT',
    ]) {
      expect(all, isNot(contains(gone)), reason: '$gone survived');
    }
    // the other page is untouched (and still has its font)
    expect(all, contains('OTHERPAGE'));

    final doc = PdfDocument.open(out);
    expect(doc.pageCount, 2);
    final page = doc.page(0);
    // the displayed crop box, upright
    expect(page.cropBox.width, closeTo(400, 0.01));
    expect(page.cropBox.height, closeTo(600, 0.01));
    expect(page.rotation, 0);
    expect(page.annotations, isEmpty);
    // only the picture: no fonts or other resources left
    expect(page.resources.entries.keys, ['XObject']);
    final xobjects =
        doc.cos.resolve(page.resources['XObject']) as CosDictionary;
    final image = doc.cos.resolve(xobjects['RdPage']) as CosStream;
    final samples = doc.cos.decodeStreamData(image);
    expect(samples.length, 40 * 60 * 3);
    expect(samples.sublist(0, 3), [10, 20, 30]);
  });

  test('a rotated page becomes its displayed, upright size', () {
    final editor = PdfEditor(PdfDocument.open(_twoPages(rotate: '/Rotate 90')));
    final doc =
        PdfDocument.open(editor.replacePagesWithImages({0: _raster(60, 40)}));
    final page = doc.page(0);
    expect(page.rotation, 0);
    expect(page.cropBox.width, closeTo(600, 0.01));
    expect(page.cropBox.height, closeTo(400, 0.01));
  });

  test('premultiplied and straight alpha both land on white paper', () {
    final premultiplied = PdfPageRaster(
        width: 1, height: 1, rgba: Uint8List.fromList([0, 0, 0, 0]));
    expect(premultiplied.toRgbOnWhite(), [255, 255, 255]);
    final straight = PdfPageRaster(
        width: 1,
        height: 1,
        rgba: Uint8List.fromList([0, 0, 0, 128]),
        premultiplied: false);
    expect(straight.toRgbOnWhite(), everyElement(closeTo(127, 1)));
  });

  test('burn then replace: the redacted text is gone either way', () {
    final burned = (PdfEditor(PdfDocument.open(_twoPages()))
          ..addRedaction(0, [const PdfRect(60, 490, 300, 520)]))
        .burnRedactions();
    final out = PdfEditor(PdfDocument.open(burned))
        .replacePagesWithImages({0: _raster(40, 60)});
    expect(_everything(out), isNot(contains('VISIBLETEXT')));
  });

  test('structure text reached through a reference or a parent goes', () {
    final pdf = _pdf([
      '<< /Type /Catalog /Pages 2 0 R /StructTreeRoot 6 0 R >>',
      '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
      '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R '
          '/Resources << /Font << /F1 5 0 R >> >> /StructParents 0 >>',
      _stream(
          '', '/P <</MCID 0>> BDC BT /F1 12 Tf 72 700 Td (Hello) Tj ET EMC'),
      '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
      '<< /Type /StructTreeRoot /K [7 0 R 9 0 R] /ParentTree 8 0 R >>',
      // the page only on the marked-content reference
      '<< /Type /StructElem /S /P /P 6 0 R /ActualText (MCRTEXT) '
          '/K << /Type /MCR /Pg 3 0 R /MCID 0 >> >>',
      '<< /Nums [0 [7 0 R]] >>',
      // the page only on the parent; the parent's summary goes too
      '<< /Type /StructElem /S /Div /P 6 0 R /Pg 3 0 R /Alt (PARENTALT) '
          '/K [10 0 R] >>',
      '<< /Type /StructElem /S /Span /P 9 0 R /K 1 /Alt (CHILDALT) >>',
    ]);
    final out = PdfEditor(PdfDocument.open(pdf))
        .replacePagesWithImages({0: _raster(2, 2)});
    final all = _everything(out);
    for (final gone in ['MCRTEXT', 'PARENTALT', 'CHILDALT']) {
      expect(all, isNot(contains(gone)), reason: '$gone survived');
    }
  });
}
