import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:test/test.dart';

/// #1255: a fake SSN hidden in every place a PDF can carry text - page
/// text, invisible OCR text, a form field, a Form XObject, an image's
/// samples, marked-content /ActualText, a bookmark, the structure tree,
/// an attachment, the document info, XMP, a page thumbnail, XFA - each
/// ending in its own marker. After the burn none may survive anywhere in
/// the saved file, raw or decoded, while the CONTROL words outside every
/// box must.

/// A PDF from object bodies (object i+1 = bodies[i]); `stream(...)` bodies
/// get a correct /Length.
Uint8List _pdf(List<String> bodies, {int? info}) {
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
  buffer
    ..write('trailer\n<< /Size ${bodies.length + 1} /Root 1 0 R')
    ..write(info != null ? ' /Info $info 0 R' : '')
    ..write(' >>\nstartxref\n$xref\n%%EOF\n');
  return Uint8List.fromList(latin1.encode(buffer.toString()));
}

String _stream(String dict, String data) =>
    '<< $dict /Length ${data.length} >>\nstream\n$data\nendstream';

/// Every marker ends in a unique number: 123-45-67NN.
String ssn(int n) => '123-45-67${n.toString().padLeft(2, '0')}';

const _pageContent = [
  // page text
  'BT /F1 12 Tf 72 700 Td (SSN 123-45-6701) Tj ET',
  // invisible OCR text
  'BT 3 Tr /F1 12 Tf 72 650 Td (123-45-6702) Tj ET',
  // marked-content replacement text around a few covered glyphs
  '/Span << /ActualText (123-45-6709) >> BDC '
      'BT /F1 12 Tf 72 550 Td (XXXX) Tj ET EMC',
  // a control line no box touches
  'BT /F1 12 Tf 72 600 Td (CONTROLA) Tj ET',
  // an image whose left half is covered (22x1 gray samples)
  'q 220 0 0 10 300 700 cm /Im1 Do Q',
  // an image wholly covered
  'q 110 0 0 10 300 400 cm /Im2 Do Q',
  // a form XObject drawing a covered marker and an uncovered control
  '/Fm1 Do',
];

List<String> _objects({
  String infoTitle = 'Patient 123-45-6711',
  String xmpText = '123-45-6710',
  String attachmentText = 'SSN 123-45-6707',
}) {
  final content = _pageContent.join('\n');
  const formContent = 'BT /F1 12 Tf 72 500 Td (123-45-6704) Tj ET\n'
      'BT /F1 12 Tf 72 450 Td (CONTROLB) Tj ET';
  const fieldAp = 'BT /F1 12 Tf 2 5 Td (123-45-6705) Tj ET';
  const xmp = '<?xpacket begin=""?><x:xmpmeta xmlns:x="adobe:ns:meta/">'
      '<dc:title>XMPTEXT</dc:title></x:xmpmeta><?xpacket end="w"?>';
  return [
    // 1 catalog
    '<< /Type /Catalog /Pages 2 0 R /Outlines 11 0 R '
        '/AcroForm << /Fields [10 0 R] /XFA 20 0 R >> '
        '/Names << /EmbeddedFiles << /Names [(a.txt) 14 0 R (b.txt) 24 0 R] >> '
        '/JavaScript << /Names [(js) << /S /JavaScript '
        '/JS (var ssn = "123-45-6706";) >>] >> >> '
        '/Metadata 15 0 R /StructTreeRoot 22 0 R >>',
    // 2 pages
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    // 3 page
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R '
        '/Resources << /Font << /F1 5 0 R >> '
        '/XObject << /Im1 6 0 R /Im2 7 0 R /Fm1 8 0 R >> >> '
        '/Annots [10 0 R 16 0 R 23 0 R] /Thumb 18 0 R >>',
    // 4 content
    _stream('', content),
    // 5 font
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
    // 6 partially covered image: marker pixels, then control pixels
    _stream(
        '/Type /XObject /Subtype /Image /Width 22 /Height 1 '
            '/ColorSpace /DeviceGray /BitsPerComponent 8',
        '123-45-6703CONTROLIMG!'),
    // 7 wholly covered image
    _stream(
        '/Type /XObject /Subtype /Image /Width 11 /Height 1 '
            '/ColorSpace /DeviceGray /BitsPerComponent 8',
        '123-45-6708'),
    // 8 form XObject
    _stream(
        '/Type /XObject /Subtype /Form /BBox [0 0 612 792] '
        '/Resources << /Font << /F1 5 0 R >> >>',
        formContent),
    // 9 (unused)
    '<< >>',
    // 10 text field (merged widget)
    '<< /Type /Annot /Subtype /Widget /FT /Tx /T (ssn) /V (123-45-6705) '
        '/Rect [72 300 200 320] /P 3 0 R /AP << /N 12 0 R >> >>',
    // 11 outlines
    '<< /Type /Outlines /First 17 0 R /Last 21 0 R /Count 2 >>',
    // 12 field appearance
    _stream(
        '/Type /XObject /Subtype /Form /BBox [0 0 128 20] '
        '/Resources << /Font << /F1 5 0 R >> >>',
        fieldAp),
    // 13 (unused)
    '<< >>',
    // 14 attachment carrying the redacted text
    '<< /Type /Filespec /F (a.txt) /EF << /F 19 0 R >> >>',
    // 15 XMP
    _stream(
        '/Type /Metadata /Subtype /XML', xmp.replaceAll('XMPTEXT', xmpText)),
    // 16 free text comment over a box
    '<< /Type /Annot /Subtype /FreeText /Rect [300 300 400 320] '
        '/Contents (123-45-6712) /DA (/Helv 10 Tf 0 g) /Popup 23 0 R >>',
    // 17 bookmark naming the redacted page text
    '<< /Title (Record SSN 123-45-6701) /Parent 11 0 R /Next 21 0 R '
        '/Dest [3 0 R /Fit] >>',
    // 18 page thumbnail
    _stream('/Width 11 /Height 1 /ColorSpace /DeviceGray /BitsPerComponent 8',
        '123-45-6713'),
    // 19 embedded file
    _stream('/Type /EmbeddedFile', attachmentText),
    // 20 XFA
    _stream('', '<xdp><field>123-45-6705</field></xdp>'),
    // 21 bookmark that must survive, and the document info (also 21 is
    //    reused below as /Info when asked)
    '<< /Title (Chapter CONTROLC) /Parent 11 0 R /Prev 17 0 R '
        '/Dest [3 0 R /Fit] >>',
    // 22 structure tree
    '<< /Type /StructTreeRoot /K [25 0 R] >>',
    // 23 the comment's popup, outside every box
    '<< /Type /Annot /Subtype /Popup /Rect [450 500 550 600] /Parent 16 0 R >>',
    // 24 unrelated attachment
    '<< /Type /Filespec /F (b.txt) /EF << /F 26 0 R >> >>',
    // 25 figure whose alternate text repeats the page text
    '<< /Type /StructElem /S /Figure /P 22 0 R /Alt (card SSN 123-45-6701) '
        '/K [<< /Type /OBJR /Obj 16 0 R /Pg 3 0 R >>] >>',
    // 26 unrelated embedded file
    _stream('/Type /EmbeddedFile', 'CONTROLFILE'),
    // 27 info
    '<< /Title ($infoTitle) /Author (CONTROLAUTHOR) /Producer (gen) >>',
  ];
}

const _boxes = [
  PdfRect(70, 695, 170, 715), // page text
  PdfRect(70, 645, 150, 665), // OCR text
  PdfRect(70, 545, 110, 565), // ActualText run
  PdfRect(300, 695, 410, 715), // left half of Im1
  PdfRect(290, 390, 420, 420), // all of Im2
  PdfRect(70, 495, 150, 515), // form text
  PdfRect(70, 295, 210, 325), // field
  PdfRect(290, 290, 410, 330), // comment
];

/// The raw file plus every stream it holds, decoded, as Latin-1 text.
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

Uint8List _burn(List<String> objects, {bool removeHiddenInformation = true}) {
  final editor = PdfEditor(PdfDocument.open(_pdf(objects, info: 27)))
    ..addRedaction(0, _boxes);
  return editor.burnRedactions(
      removeHiddenInformation: removeHiddenInformation);
}

void main() {
  test('no marker survives anywhere in the saved file', () {
    final before = _everything(_pdf(_objects(), info: 27));
    for (var n = 1; n <= 13; n++) {
      expect(before, contains(ssn(n)), reason: 'fixture lacks ${ssn(n)}');
    }

    final burned = _burn(_objects());
    final all = _everything(burned);
    for (var n = 1; n <= 13; n++) {
      expect(all, isNot(contains(ssn(n))), reason: '${ssn(n)} leaked');
    }
    // the controls outside every box survive
    for (final control in [
      'CONTROLA', // page text
      'CONTROLB', // form text
      'CONTROLIMG!', // uncovered image samples
      'CONTROLC', // bookmark
    ]) {
      expect(all, contains(control), reason: '$control was lost');
    }
    // and the result still opens as one page
    expect(PdfDocument.open(burned).pageCount, 1);
  });

  test('a partially covered image keeps only its uncovered pixels', () {
    final out = PdfDocument.open(_burn(_objects()));
    final page = out.page(0);
    final content = latin1.decode(page.contentBytes());
    expect(content, isNot(contains('/Im1 Do')));
    expect(content, isNot(contains('/Im2 Do')));
    final xobjects =
        out.cos.resolve(page.resources['XObject']) as CosDictionary;
    expect(xobjects.containsKey('Im1'), isFalse);
    expect(xobjects.containsKey('Im2'), isFalse);
    final name = RegExp(r'/(RdXO\d+) Do').firstMatch(content)!.group(1)!;
    final image = out.cos.resolve(xobjects[name]) as CosStream;
    final samples = out.cos.decodeStreamData(image);
    expect(samples.sublist(0, 11), everyElement(0));
    expect(latin1.decode(samples.sublist(11)), 'CONTROLIMG!');
  });

  test('the form field and its popup-bearing comment leave the file', () {
    final out = PdfDocument.open(_burn(_objects()));
    expect(out.page(0).annotations, isEmpty);
    final catalog = out.cos.resolve(out.cos.trailer['Root']) as CosDictionary;
    final form = out.cos.resolve(catalog['AcroForm']) as CosDictionary;
    expect((out.cos.resolve(form['Fields']) as CosArray).items, isEmpty);
    expect(form.containsKey('XFA'), isFalse);
  });

  test('marked-content replacement text is stripped from the burned run', () {
    final out = PdfDocument.open(_burn(_objects()));
    final content = latin1.decode(out.page(0).contentBytes());
    expect(content, contains('/Span'));
    expect(content, isNot(contains('ActualText')));
  });

  test('hidden copies are scrubbed when hidden information is kept', () {
    final burned = _burn(
      _objects(
        infoTitle: 'File 123-45-6701',
        xmpText: 'about 123-45-6701',
        attachmentText: 'copy of 123-45-6701',
      ),
      removeHiddenInformation: false,
    );
    final all = _everything(burned);
    expect(all, isNot(contains(ssn(1))));
    final out = PdfDocument.open(burned);
    final info = out.cos.resolve(out.cos.trailer['Info']) as CosDictionary;
    expect(
        latin1.decode((info['Title'] as CosString).bytes), 'File [redacted]');
    expect(latin1.decode((info['Author'] as CosString).bytes), 'CONTROLAUTHOR');
    // the attachment mentioning it went; the unrelated one stayed
    expect(all, isNot(contains('a.txt')));
    expect(all, contains('CONTROLFILE'));
    expect(all, contains('about [redacted]'));
  });

  test('removeHiddenInformation drops metadata and attachments', () {
    final all = _everything(_burn(_objects()));
    expect(all, isNot(contains('CONTROLFILE')));
    expect(all, isNot(contains('CONTROLAUTHOR')));
    expect(all, contains('gen')); // /Producer is kept
  });

  test('a compressed Form XObject with a nested image is burned too', () {
    final inner = Uint8List.fromList(const ZLibEncoder()
        .encode(latin1.encode('q 100 0 0 10 0 0 cm /Im Do Q')));
    final objects = <String>[
      '<< /Type /Catalog /Pages 2 0 R >>',
      '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
      '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R '
          '/Resources << /XObject << /Fm 5 0 R >> >> >>',
      _stream('', 'q 1 0 0 1 100 100 cm /Fm Do Q'),
      '<< /Type /XObject /Subtype /Form /BBox [0 0 200 20] '
          '/Filter /FlateDecode /Resources << /XObject << /Im 6 0 R >> >> '
          '/Length ${inner.length} >>\nstream\n'
          '${latin1.decode(inner)}\nendstream',
      _stream(
          '/Type /XObject /Subtype /Image /Width 10 /Height 1 '
              '/ColorSpace /DeviceGray /BitsPerComponent 8',
          '6714_KEEP!'),
    ];
    final editor = PdfEditor(PdfDocument.open(_pdf(objects)))
      // the left half of the image: x 100..150 on the page
      ..addRedaction(0, [const PdfRect(95, 95, 150, 115)]);
    final all = _everything(editor.applyRedactions());
    expect(all, isNot(contains('6714')));
    expect(all, contains('KEEP!'));
  });
}
