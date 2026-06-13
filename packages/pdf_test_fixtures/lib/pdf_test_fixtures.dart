import 'dart:typed_data';

export 'src/encrypted.dart';
export 'src/icc_profiles.dart';
export 'src/signer_identity.dart';

Uint8List ascii(String s) => Uint8List.fromList(s.codeUnits);

/// Builds a minimal one-page PDF with a classic cross-reference table.
Uint8List buildClassicPdf() {
  const content = 'BT /F1 24 Tf 72 720 Td (Hello, world!) Tj ET';
  final objects = <String>[
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R '
        '/Resources << /Font << /F1 5 0 R >> >> >>',
    '<< /Length ${content.length} >>\nstream\n$content\nendstream',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
  ];
  final buffer = StringBuffer('%PDF-1.4\n');
  final offsets = <int>[];
  for (var i = 0; i < objects.length; i++) {
    offsets.add(buffer.length);
    buffer.write('${i + 1} 0 obj\n${objects[i]}\nendobj\n');
  }
  final xrefOffset = buffer.length;
  buffer
    ..write('xref\n0 ${objects.length + 1}\n')
    ..write('0000000000 65535 f \n');
  for (final offset in offsets) {
    buffer.write('${offset.toString().padLeft(10, '0')} 00000 n \n');
  }
  buffer
    ..write('trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\n')
    ..write('startxref\n$xrefOffset\n%%EOF\n');
  return ascii(buffer.toString());
}

/// Builds a PDF in the "modern" 1.5+ layout: an uncompressed cross-reference
/// stream, with the catalog and page tree packed into an object stream.
Uint8List buildXrefStreamPdf() {
  // objects 1 (catalog), 2 (pages), 3 (page) live inside object stream 4
  final inner = <(int, String)>[
    (1, '<< /Type /Catalog /Pages 2 0 R >>'),
    (2, '<< /Type /Pages /Kids [3 0 R] /Count 1 >>'),
    (3, '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] >>'),
  ];
  var header = '';
  var payload = '';
  for (final (number, source) in inner) {
    header += '$number ${payload.length} ';
    payload += '$source ';
  }
  final objStmData = header + payload;
  final first = header.length;

  final out = StringBuffer('%PDF-1.5\n');
  final objStmOffset = out.length;
  out.write('4 0 obj\n<< /Type /ObjStm /N ${inner.length} /First $first '
      '/Length ${objStmData.length} >>\nstream\n$objStmData\nendstream\n'
      'endobj\n');

  final xrefOffset = out.length;
  // /W [1 4 2]: 1-byte type, 4-byte offset, 2-byte generation/index
  final rows = <List<int>>[
    [0, 0, 0xFFFF], // 0: head of the free list
    [2, 4, 0], // 1: in object stream 4, index 0
    [2, 4, 1],
    [2, 4, 2],
    [1, objStmOffset, 0], // 4: the object stream itself
    [1, xrefOffset, 0], // 5: this xref stream
  ];
  final xrefData = <int>[];
  for (final row in rows) {
    xrefData
      ..add(row[0])
      ..addAll([
        (row[1] >> 24) & 0xFF,
        (row[1] >> 16) & 0xFF,
        (row[1] >> 8) & 0xFF,
        row[1] & 0xFF,
      ])
      ..addAll([(row[2] >> 8) & 0xFF, row[2] & 0xFF]);
  }
  out.write('5 0 obj\n<< /Type /XRef /Size 6 /W [1 4 2] /Root 1 0 R '
      '/Length ${xrefData.length} >>\nstream\n');

  return (BytesBuilder()
        ..add(ascii(out.toString()))
        ..add(xrefData)
        ..add(ascii('\nendstream\nendobj\nstartxref\n$xrefOffset\n%%EOF\n')))
      .takeBytes();
}

/// Builds a [pageCount]-page PDF; page N shows the text "Page N".
Uint8List buildMultiPagePdf(int pageCount) {
  final objects = <String>[];
  final kids = [
    for (var i = 0; i < pageCount; i++) '${3 + i * 2} 0 R',
  ].join(' ');
  final fontNumber = 3 + pageCount * 2;
  objects.add('<< /Type /Catalog /Pages 2 0 R >>');
  objects.add('<< /Type /Pages /Kids [$kids] /Count $pageCount >>');
  for (var i = 0; i < pageCount; i++) {
    final content = 'BT /F1 24 Tf 72 720 Td (Page ${i + 1}) Tj ET';
    objects.add('<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] '
        '/Contents ${4 + i * 2} 0 R '
        '/Resources << /Font << /F1 $fontNumber 0 R >> >> >>');
    objects.add('<< /Length ${content.length} >>\nstream\n$content\nendstream');
  }
  objects.add('<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>');

  final buffer = StringBuffer('%PDF-1.4\n');
  final offsets = <int>[];
  for (var i = 0; i < objects.length; i++) {
    offsets.add(buffer.length);
    buffer.write('${i + 1} 0 obj\n${objects[i]}\nendobj\n');
  }
  final xrefOffset = buffer.length;
  buffer
    ..write('xref\n0 ${objects.length + 1}\n')
    ..write('0000000000 65535 f \n');
  for (final offset in offsets) {
    buffer.write('${offset.toString().padLeft(10, '0')} 00000 n \n');
  }
  buffer
    ..write('trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\n')
    ..write('startxref\n$xrefOffset\n%%EOF\n');
  return ascii(buffer.toString());
}

/// Builds a [pageCount]-page PDF whose page heights cycle 792, 396,
/// 1008 pt (all 612 wide); page N shows the text "Page N" near its top.
/// Mixed sizes defeat any uniform-extent estimate, exercising viewers
/// that must place far-away pages exactly (search jumps, links).
Uint8List buildVariedHeightPdf(int pageCount) {
  const heights = [792, 396, 1008];
  final objects = <String>[];
  final kids = [
    for (var i = 0; i < pageCount; i++) '${3 + i * 2} 0 R',
  ].join(' ');
  final fontNumber = 3 + pageCount * 2;
  objects.add('<< /Type /Catalog /Pages 2 0 R >>');
  objects.add('<< /Type /Pages /Kids [$kids] /Count $pageCount >>');
  for (var i = 0; i < pageCount; i++) {
    final height = heights[i % heights.length];
    final content = 'BT /F1 24 Tf 72 ${height - 72} Td (Page ${i + 1}) Tj ET';
    objects.add('<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 $height] '
        '/Contents ${4 + i * 2} 0 R '
        '/Resources << /Font << /F1 $fontNumber 0 R >> >> >>');
    objects.add('<< /Length ${content.length} >>\nstream\n$content\nendstream');
  }
  objects.add('<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>');

  final buffer = StringBuffer('%PDF-1.4\n');
  final offsets = <int>[];
  for (var i = 0; i < objects.length; i++) {
    offsets.add(buffer.length);
    buffer.write('${i + 1} 0 obj\n${objects[i]}\nendobj\n');
  }
  final xrefOffset = buffer.length;
  buffer
    ..write('xref\n0 ${objects.length + 1}\n')
    ..write('0000000000 65535 f \n');
  for (final offset in offsets) {
    buffer.write('${offset.toString().padLeft(10, '0')} 00000 n \n');
  }
  buffer
    ..write('trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\n')
    ..write('startxref\n$xrefOffset\n%%EOF\n');
  return ascii(buffer.toString());
}

/// Builds a 3-page PDF with a nested page tree exercising attribute
/// inheritance (§7.7.3.4):
///
/// - the root /Pages node carries /MediaBox [0 0 612 792] and the shared
///   /Resources (/F1 Helvetica)
/// - an inner /Pages node holds pages 1 and 2 and overrides
///   /MediaBox [0 0 400 400] and /Rotate 90
/// - page 3 sits directly under the root
///
/// No page dictionary carries any inheritable attribute of its own. Page N
/// shows the text "Page N". The trailer has an /Info with /Title (Nested).
Uint8List buildNestedPageTreePdf() {
  final objects = <String>[
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R 6 0 R] /Count 3 '
        '/MediaBox [0 0 612 792] '
        '/Resources << /Font << /F1 10 0 R >> >> >>',
    '<< /Type /Pages /Parent 2 0 R /Kids [4 0 R 5 0 R] /Count 2 '
        '/MediaBox [0 0 400 400] /Rotate 90 >>',
    '<< /Type /Page /Parent 3 0 R /Contents 7 0 R >>',
    '<< /Type /Page /Parent 3 0 R /Contents 8 0 R >>',
    '<< /Type /Page /Parent 2 0 R /Contents 9 0 R >>',
  ];
  for (var i = 0; i < 3; i++) {
    final content = 'BT /F1 24 Tf 72 320 Td (Page ${i + 1}) Tj ET';
    objects.add('<< /Length ${content.length} >>\nstream\n$content\nendstream');
  }
  objects.add('<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>');
  objects.add('<< /Title (Nested) >>');

  final buffer = StringBuffer('%PDF-1.4\n');
  final offsets = <int>[];
  for (var i = 0; i < objects.length; i++) {
    offsets.add(buffer.length);
    buffer.write('${i + 1} 0 obj\n${objects[i]}\nendobj\n');
  }
  final xrefOffset = buffer.length;
  buffer
    ..write('xref\n0 ${objects.length + 1}\n')
    ..write('0000000000 65535 f \n');
  for (final offset in offsets) {
    buffer.write('${offset.toString().padLeft(10, '0')} 00000 n \n');
  }
  buffer
    ..write('trailer\n<< /Size ${objects.length + 1} /Root 1 0 R '
        '/Info ${objects.length} 0 R >>\n')
    ..write('startxref\n$xrefOffset\n%%EOF\n');
  return ascii(buffer.toString());
}

/// Builds a 3-page PDF whose first page carries interactive annotations:
///
/// - a URI link at rect (72,640)-(200,664) → `app://invoice/42`
/// - a GoTo link at (72,600)-(200,624) → page 3, /XYZ top
/// - a named-destination link at (72,560)-(200,584) → "Target", resolved
///   through the /Names → /Dests name tree to page 2, /FitH 700
/// - a Widget push button "actions.launch" at (72,520)-(200,544) with a
///   JavaScript action
/// - a Named-action link at (300,640)-(400,664) → /NextPage
/// - a hidden (/F 2) URI link at (300,600)-(400,624)
///
/// Page N shows the text "Page N" at 72,720 (24pt Helvetica), as in
/// [buildMultiPagePdf].
Uint8List buildAnnotatedPdf() {
  // objects: 1 catalog, 2 pages, 3/5/7 page 1..3, 4/6/8 contents, 9 font,
  // 10 the button's parent field (exercises the /Parent name chain)
  const annots = '/Annots [ '
      '<< /Type /Annot /Subtype /Link /Rect [72 640 200 664] '
      '/A << /S /URI /URI (app://invoice/42) >> >> '
      '<< /Type /Annot /Subtype /Link /Rect [72 600 200 624] '
      '/A << /S /GoTo /D [7 0 R /XYZ 0 792 0] >> >> '
      '<< /Type /Annot /Subtype /Link /Rect [72 560 200 584] '
      '/Dest (Target) >> '
      '<< /Type /Annot /Subtype /Widget /FT /Btn /T (launch) '
      '/Parent 10 0 R /Rect [72 520 200 544] '
      '/A << /S /JavaScript /JS (app.alert\\(42\\)) >> >> '
      '<< /Type /Annot /Subtype /Link /Rect [300 640 400 664] '
      '/A << /S /Named /N /NextPage >> >> '
      '<< /Type /Annot /Subtype /Link /Rect [300 600 400 624] /F 2 '
      '/A << /S /URI /URI (app://hidden) >> >> '
      ']';
  final objects = <String>[
    '<< /Type /Catalog /Pages 2 0 R '
        '/Names << /Dests << /Names [ (Target) [5 0 R /FitH 700] ] >> >> >>',
    '<< /Type /Pages /Kids [3 0 R 5 0 R 7 0 R] /Count 3 >>',
  ];
  for (var i = 0; i < 3; i++) {
    final content = 'BT /F1 24 Tf 72 720 Td (Page ${i + 1}) Tj ET';
    objects.add('<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] '
        '/Contents ${4 + i * 2} 0 R '
        '/Resources << /Font << /F1 9 0 R >> >> '
        '${i == 0 ? annots : ''}>>');
    objects.add('<< /Length ${content.length} >>\nstream\n$content\nendstream');
  }
  objects.add('<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>');
  objects.add('<< /T (actions) >>');

  final buffer = StringBuffer('%PDF-1.4\n');
  final offsets = <int>[];
  for (var i = 0; i < objects.length; i++) {
    offsets.add(buffer.length);
    buffer.write('${i + 1} 0 obj\n${objects[i]}\nendobj\n');
  }
  final xrefOffset = buffer.length;
  buffer
    ..write('xref\n0 ${objects.length + 1}\n')
    ..write('0000000000 65535 f \n');
  for (final offset in offsets) {
    buffer.write('${offset.toString().padLeft(10, '0')} 00000 n \n');
  }
  buffer
    ..write('trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\n')
    ..write('startxref\n$xrefOffset\n%%EOF\n');
  return ascii(buffer.toString());
}

/// Builds a one-page PDF whose annotations carry appearance streams:
///
/// - a Square at /Rect [100 100 200 150], /AP BBox [0 0 10 10] filling
///   itself green — exercises the BBox → Rect scaling (×10, ×5)
/// - a Stamp at /Rect [300 100 350 200] whose /AP has a 90°-rotation
///   /Matrix and fills its BBox red
/// - a Widget checkbox "agree" at /Rect [400 100 420 120] with /AS /On
///   selecting between /On (fills 0.5 gray) and /Off (empty) states
/// - a hidden (/F 2) Square at [100 300 200 350] whose /AP fills magenta —
///   must not be drawn
/// - a Popup at [300 300 400 400] whose /AP fills yellow — must not be
///   drawn during page rendering
///
/// The page content itself fills a blue square at (10,10)-(60,60).
Uint8List buildAppearanceAnnotationsPdf() {
  String form(String bbox, String content, {String? matrix}) =>
      '<< /Type /XObject /Subtype /Form /BBox $bbox '
      '${matrix == null ? '' : '/Matrix $matrix '}'
      '/Length ${content.length} >>\nstream\n$content\nendstream';

  const annots = '/Annots [ '
      '<< /Type /Annot /Subtype /Square /Rect [100 100 200 150] '
      '/AP << /N 5 0 R >> >> '
      '<< /Type /Annot /Subtype /Stamp /Rect [300 100 350 200] '
      '/AP << /N 6 0 R >> >> '
      '<< /Type /Annot /Subtype /Widget /FT /Btn /T (agree) '
      '/Rect [400 100 420 120] /AS /On '
      '/AP << /N << /On 7 0 R /Off 8 0 R >> >> >> '
      '<< /Type /Annot /Subtype /Square /Rect [100 300 200 350] /F 2 '
      '/AP << /N 9 0 R >> >> '
      '<< /Type /Annot /Subtype /Popup /Rect [300 300 400 400] '
      '/AP << /N 10 0 R >> >> '
      ']';
  const content = '0 0 1 rg 10 10 50 50 re f';
  final objects = <String>[
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] '
        '/Contents 4 0 R $annots >>',
    '<< /Length ${content.length} >>\nstream\n$content\nendstream',
    form('[0 0 10 10]', '0 1 0 rg 0 0 10 10 re f'),
    form('[0 0 10 10]', '1 0 0 rg 0 0 10 10 re f', matrix: '[0 1 -1 0 0 0]'),
    form('[0 0 1 1]', '0.5 g 0 0 1 1 re f'),
    form('[0 0 1 1]', ''),
    form('[0 0 10 10]', '1 0 1 rg 0 0 10 10 re f'),
    form('[0 0 10 10]', '1 1 0 rg 0 0 10 10 re f'),
  ];

  final buffer = StringBuffer('%PDF-1.4\n');
  final offsets = <int>[];
  for (var i = 0; i < objects.length; i++) {
    offsets.add(buffer.length);
    buffer.write('${i + 1} 0 obj\n${objects[i]}\nendobj\n');
  }
  final xrefOffset = buffer.length;
  buffer
    ..write('xref\n0 ${objects.length + 1}\n')
    ..write('0000000000 65535 f \n');
  for (final offset in offsets) {
    buffer.write('${offset.toString().padLeft(10, '0')} 00000 n \n');
  }
  buffer
    ..write('trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\n')
    ..write('startxref\n$xrefOffset\n%%EOF\n');
  return ascii(buffer.toString());
}

/// Builds a one-page PDF with an interactive AcroForm:
///
/// - text field "name" (merged widget) at [72 700 300 724], own
///   /DA (/Helv 12 Tf 0 g), prefilled value "prefilled"
/// - multiline (/Ff 4096) text field "address" at [72 600 300 680],
///   inheriting the form-wide auto-size /DA (/Helv 0 Tf 0 g)
/// - check box "agree" at [72 540 92 560] with /Yes and /Off appearance
///   states, currently /Off
/// - radio group "color" with two kid widgets at [72 500 92 520] (/Red)
///   and [120 500 140 520] (/Blue), currently /Off
/// - combo box (/Ff 131072) "size" at [72 460 200 484], centered (/Q 1),
///   /Opt [(Small) (Medium) [(L) (Large)]], value "Medium"
/// - read-only (/Ff 1) text field "serial" at [72 420 200 444],
///   value "A-1000"
///
/// The /AcroForm dictionary carries /NeedAppearances true so fillers can
/// prove they cleared it, and /DR with /Helv → Helvetica.
Uint8List buildAcroFormPdf() {
  const widgets = '6 0 R 7 0 R 8 0 R 10 0 R 11 0 R 12 0 R 13 0 R';
  const onState = '0.5 g 0 0 20 20 re f';
  final objects = <String>[
    '<< /Type /Catalog /Pages 2 0 R /AcroForm << '
        '/Fields [6 0 R 7 0 R 8 0 R 9 0 R 12 0 R 13 0 R] '
        '/DA (/Helv 0 Tf 0 g) /DR << /Font << /Helv 5 0 R >> >> '
        '/NeedAppearances true >> >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] '
        '/Annots [$widgets] >>',
    '<< /Length 0 >>\nstream\n\nendstream',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica '
        '/Encoding /WinAnsiEncoding >>',
    '<< /Type /Annot /Subtype /Widget /FT /Tx /T (name) '
        '/Rect [72 700 300 724] /DA (/Helv 12 Tf 0 g) /V (prefilled) >>',
    '<< /Type /Annot /Subtype /Widget /FT /Tx /T (address) /Ff 4096 '
        '/Rect [72 600 300 680] >>',
    '<< /Type /Annot /Subtype /Widget /FT /Btn /T (agree) /V /Off /AS /Off '
        '/Rect [72 540 92 560] '
        '/AP << /N << /Yes 14 0 R /Off 15 0 R >> >> >>',
    '<< /FT /Btn /T (color) /Ff 32768 /V /Off /Kids [10 0 R 11 0 R] >>',
    '<< /Type /Annot /Subtype /Widget /Parent 9 0 R /Rect [72 500 92 520] '
        '/AS /Off /AP << /N << /Red 14 0 R /Off 15 0 R >> >> >>',
    '<< /Type /Annot /Subtype /Widget /Parent 9 0 R /Rect [120 500 140 520] '
        '/AS /Off /AP << /N << /Blue 14 0 R /Off 15 0 R >> >> >>',
    '<< /Type /Annot /Subtype /Widget /FT /Ch /T (size) /Ff 131072 /Q 1 '
        '/Opt [(Small) (Medium) [(L) (Large)]] /V (Medium) '
        '/Rect [72 460 200 484] >>',
    '<< /Type /Annot /Subtype /Widget /FT /Tx /T (serial) /Ff 1 '
        '/V (A-1000) /Rect [72 420 200 444] >>',
    '<< /Type /XObject /Subtype /Form /BBox [0 0 20 20] '
        '/Length ${onState.length} >>\nstream\n$onState\nendstream',
    '<< /Type /XObject /Subtype /Form /BBox [0 0 20 20] /Length 0 '
        '>>\nstream\n\nendstream',
  ];

  final buffer = StringBuffer('%PDF-1.4\n');
  final offsets = <int>[];
  for (var i = 0; i < objects.length; i++) {
    offsets.add(buffer.length);
    buffer.write('${i + 1} 0 obj\n${objects[i]}\nendobj\n');
  }
  final xrefOffset = buffer.length;
  buffer
    ..write('xref\n0 ${objects.length + 1}\n')
    ..write('0000000000 65535 f \n');
  for (final offset in offsets) {
    buffer.write('${offset.toString().padLeft(10, '0')} 00000 n \n');
  }
  buffer
    ..write('trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\n')
    ..write('startxref\n$xrefOffset\n%%EOF\n');
  return ascii(buffer.toString());
}

/// Builds a minimal TrueType font, unitsPerEm 1000, three glyphs:
/// 0 = .notdef (empty), 1 = 'A' (triangle, advance 600),
/// 2 = 'B' (square, advance 1000). The cmap is a (3,1) format 4 table.
///
/// Set [includeCmap] false to omit the cmap (a cmap-less embedded subset),
/// and [includePost] true to add a `post` format 2.0 table naming gid 1 'A'
/// and gid 2 'B' — together they exercise name-based glyph selection.
Uint8List buildTestTrueTypeFont(
    {bool includeCmap = true, bool includePost = false}) {
  final out = BytesBuilder();

  Uint8List u16(int v) => Uint8List.fromList([(v >> 8) & 0xFF, v & 0xFF]);
  Uint8List s16(int v) => u16(v & 0xFFFF);
  Uint8List u32(int v) => Uint8List.fromList(
      [(v >> 24) & 0xFF, (v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF]);
  Uint8List join(List<Uint8List> parts) {
    final b = BytesBuilder();
    for (final part in parts) {
      b.add(part);
    }
    return b.takeBytes();
  }

  final head = join([
    u32(0x00010000), u32(0), u32(0), u32(0x5F0F3CF5),
    u16(0), u16(1000), // flags, unitsPerEm
    u32(0), u32(0), u32(0), u32(0), // created/modified
    s16(0), s16(0), s16(1000), s16(1000), // bbox
    u16(0), u16(8), s16(2), s16(0), s16(0), // style..glyphDataFormat
  ]);
  final hhea = join([
    u32(0x00010000),
    s16(800),
    s16(-200),
    s16(0),
    u16(1000),
    s16(0),
    s16(0),
    s16(1000),
    s16(1),
    s16(0),
    s16(0),
    s16(0),
    s16(0),
    s16(0),
    s16(0),
    s16(0),
    u16(3),
  ]);
  final maxp = join([
    u32(0x00010000),
    u16(3),
    for (var i = 0; i < 13; i++) u16(0),
  ]);
  final hmtx = join([
    u16(500),
    s16(0),
    u16(600),
    s16(0),
    u16(1000),
    s16(0),
  ]);
  // glyph 1: triangle (0,0) (500,1000) (1000,0); all points on-curve
  final glyphA = join([
    s16(1), s16(0), s16(0), s16(1000), s16(1000),
    u16(2), u16(0), // endPts, instructions
    Uint8List.fromList([0x01, 0x01, 0x01]),
    s16(0), s16(500), s16(500), // x deltas
    s16(0), s16(1000), s16(-1000), // y deltas
    Uint8List.fromList([0]), // pad to even length
  ]);
  // glyph 2: square (0,0) (1000,0) (1000,1000) (0,1000)
  final glyphB = join([
    s16(1),
    s16(0),
    s16(0),
    s16(1000),
    s16(1000),
    u16(3),
    u16(0),
    Uint8List.fromList([0x01, 0x01, 0x01, 0x01]),
    s16(0),
    s16(1000),
    s16(0),
    s16(-1000),
    s16(0),
    s16(0),
    s16(1000),
    s16(0),
  ]);
  final glyf = join([glyphA, glyphB]);
  final loca = join([
    u16(0), u16(0), // glyph 0 empty
    u16(glyphA.length ~/ 2),
    u16((glyphA.length + glyphB.length) ~/ 2),
  ]);
  // cmap: format 4, segments [65..66 -> gid 1..2] and the 0xFFFF terminator
  final cmapTable = join([
    u16(4), u16(32), u16(0), // format, length, language
    u16(4), u16(4), u16(1), u16(0), // segCountX2, search params
    u16(66), u16(0xFFFF), u16(0), // endCodes, pad
    u16(65), u16(0xFFFF), // startCodes
    s16(1 - 65), s16(1), // idDelta
    u16(0), u16(0), // idRangeOffset
  ]);
  final cmap = join([
    u16(0), u16(1), // version, one table
    u16(3), u16(1), u32(12), // (3,1) at offset 12
    cmapTable,
  ]);

  // post format 2.0: gid 0 = .notdef (mac index 0), gid 1 = 'A' (index 36),
  // gid 2 = 'B' (index 37) — all standard Mac names, no Pascal strings.
  final post = join([
    u32(0x00020000), u32(0), // version, italicAngle
    s16(0), s16(0), u32(0), // underline pos/thick, isFixedPitch
    u32(0), u32(0), u32(0), u32(0), // mem usage
    u16(3), // numberOfGlyphs
    u16(0), u16(36), u16(37), // glyphNameIndex
  ]);

  final tables = <(String, Uint8List)>[
    if (includeCmap) ('cmap', cmap),
    ('glyf', glyf),
    ('head', head),
    ('hhea', hhea),
    ('hmtx', hmtx),
    ('loca', loca),
    ('maxp', maxp),
    if (includePost) ('post', post),
  ];
  out.add(u32(0x00010000));
  out.add(u16(tables.length));
  out.add(u16(64)); // searchRange
  out.add(u16(2)); // entrySelector
  out.add(u16(tables.length * 16 - 64)); // rangeShift
  var offset = 12 + tables.length * 16;
  final bodies = BytesBuilder();
  for (final (tag, data) in tables) {
    out.add(ascii(tag));
    out.add(u32(0)); // checksum unverified
    out.add(u32(offset));
    out.add(u32(data.length));
    bodies.add(data);
    final padding = (4 - data.length % 4) % 4;
    bodies.add(Uint8List(padding));
    offset += data.length + padding;
  }
  out.add(bodies.takeBytes());
  return out.takeBytes();
}

/// One-page PDF whose text uses an embedded TrueType font (see
/// [buildTestTrueTypeFont]); the page shows "AB" at 24pt.
Uint8List buildEmbeddedFontPdf() {
  final font = buildTestTrueTypeFont();
  const content = 'BT /F1 24 Tf 72 700 Td (AB) Tj ET';

  // bodies of objects 1..6, as bytes (object 6 carries the binary font)
  final bodies = <Uint8List>[
    ascii('<< /Type /Catalog /Pages 2 0 R >>'),
    ascii('<< /Type /Pages /Kids [3 0 R] /Count 1 >>'),
    ascii('<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] '
        '/Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>'),
    ascii('<< /Length ${content.length} >>\nstream\n$content\nendstream'),
    ascii('<< /Type /Font /Subtype /TrueType /BaseFont /TestFont '
        '/FirstChar 65 /LastChar 66 /Widths [600 1000] '
        '/Encoding /WinAnsiEncoding /FontDescriptor 7 0 R >>'),
    (BytesBuilder()
          ..add(ascii('<< /Length ${font.length} /Length1 ${font.length} >>'
              '\nstream\n'))
          ..add(font)
          ..add(ascii('\nendstream')))
        .takeBytes(),
    ascii('<< /Type /FontDescriptor /FontName /TestFont /Flags 32 '
        '/FontBBox [0 0 1000 1000] /ItalicAngle 0 /Ascent 800 '
        '/Descent -200 /CapHeight 800 /StemV 80 /FontFile2 6 0 R >>'),
  ];

  final out = BytesBuilder()..add(ascii('%PDF-1.4\n'));
  final offsets = <int>[];
  for (var i = 0; i < bodies.length; i++) {
    offsets.add(out.length);
    out.add(ascii('${i + 1} 0 obj\n'));
    out.add(bodies[i]);
    out.add(ascii('\nendobj\n'));
  }
  final xrefOffset = out.length;
  final buffer = StringBuffer()
    ..write('xref\n0 ${bodies.length + 1}\n')
    ..write('0000000000 65535 f \n');
  for (final offset in offsets) {
    buffer.write('${offset.toString().padLeft(10, '0')} 00000 n \n');
  }
  buffer
    ..write('trailer\n<< /Size ${bodies.length + 1} /Root 1 0 R >>\n')
    ..write('startxref\n$xrefOffset\n%%EOF\n');
  out.add(ascii(buffer.toString()));
  return out.takeBytes();
}

/// Builds a minimal CFF (Type1C) font: glyph 0 = .notdef, glyph 1 = an
/// 800x800 square at the origin, mapped to character code 65 ('A') with
/// advance width 660 (via nominalWidthX 600 + leading operand 60).
Uint8List buildTestCffFont() {
  Uint8List u8(int v) => Uint8List.fromList([v & 0xFF]);
  Uint8List u16(int v) => Uint8List.fromList([(v >> 8) & 0xFF, v & 0xFF]);
  Uint8List int5(int v) => Uint8List.fromList([
        29,
        (v >> 24) & 0xFF,
        (v >> 16) & 0xFF,
        (v >> 8) & 0xFF,
        v & 0xFF,
      ]);
  Uint8List joinAll(List<Uint8List> parts) {
    final b = BytesBuilder();
    for (final part in parts) {
      b.add(part);
    }
    return b.takeBytes();
  }

  Uint8List index(List<Uint8List> items) {
    if (items.isEmpty) return u16(0);
    final out = BytesBuilder()
      ..add(u16(items.length))
      ..add(u8(2)); // offSize 2
    var offset = 1;
    out.add(u16(offset));
    for (final item in items) {
      offset += item.length;
      out.add(u16(offset));
    }
    for (final item in items) {
      out.add(item);
    }
    return out.takeBytes();
  }

  // charstrings: .notdef = endchar; square = 60 width, then contour
  final notdef = Uint8List.fromList([14]);
  final square = Uint8List.fromList([
    139 + 60, // width delta 60 over nominalWidthX
    139, 139, 21, // 0 0 rmoveto
    249, 180, 6, // 800 hlineto
    249, 180, 7, // 800 vlineto
    253, 180, 6, // -800 hlineto
    14, // endchar
  ]);

  final header = Uint8List.fromList([1, 0, 4, 2]);
  final nameIndex = index([ascii('Test')]);
  final stringIndex = u16(0);
  final gsubrIndex = u16(0);

  // encoding: format 0, one code: 65 -> gid 1
  final encoding = Uint8List.fromList([0, 1, 65]);
  final charstringsIndex = index([notdef, square]);
  // private dict: defaultWidthX 500 (20), nominalWidthX 600 (21)
  final privateDict = joinAll([int5(500), u8(20), int5(600), u8(21)]);

  // top dict (fixed-size operands so offsets are computable):
  // CharStrings (17), Encoding (16), Private (18)
  Uint8List topDictWith(int charstringsAt, int encodingAt, int privateAt) =>
      joinAll([
        int5(charstringsAt),
        u8(17),
        int5(encodingAt),
        u8(16),
        int5(privateDict.length),
        int5(privateAt),
        u8(18),
      ]);

  final topDictSize = topDictWith(0, 0, 0).length;
  final topDictIndexSize = index([Uint8List(topDictSize)]).length;
  final fixedPrefix = header.length +
      nameIndex.length +
      topDictIndexSize +
      stringIndex.length +
      gsubrIndex.length;
  final encodingAt = fixedPrefix;
  final charstringsAt = encodingAt + encoding.length;
  final privateAt = charstringsAt + charstringsIndex.length;

  return joinAll([
    header,
    nameIndex,
    index([topDictWith(charstringsAt, encodingAt, privateAt)]),
    stringIndex,
    gsubrIndex,
    encoding,
    charstringsIndex,
    privateDict,
  ]);
}

/// A real, decodable 8x8 solid-red JPEG (CoreGraphics, quality 1.0).
/// Decodes to r=254, g=0, b=0 within codec tolerance.
Uint8List buildTestJpeg() => Uint8List.fromList(const [
      0xFF,
      0xD8,
      0xFF,
      0xE0,
      0x00,
      0x10,
      0x4A,
      0x46,
      0x49,
      0x46,
      0x00,
      0x01,
      0x01,
      0x00,
      0x00,
      0x48,
      0x00,
      0x48,
      0x00,
      0x00,
      0xFF,
      0xE1,
      0x00,
      0x40,
      0x45,
      0x78,
      0x69,
      0x66,
      0x00,
      0x00,
      0x4D,
      0x4D,
      0x00,
      0x2A,
      0x00,
      0x00,
      0x00,
      0x08,
      0x00,
      0x01,
      0x87,
      0x69,
      0x00,
      0x04,
      0x00,
      0x00,
      0x00,
      0x01,
      0x00,
      0x00,
      0x00,
      0x1A,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x02,
      0xA0,
      0x02,
      0x00,
      0x04,
      0x00,
      0x00,
      0x00,
      0x01,
      0x00,
      0x00,
      0x00,
      0x08,
      0xA0,
      0x03,
      0x00,
      0x04,
      0x00,
      0x00,
      0x00,
      0x01,
      0x00,
      0x00,
      0x00,
      0x08,
      0x00,
      0x00,
      0x00,
      0x00,
      0xFF,
      0xED,
      0x00,
      0x38,
      0x50,
      0x68,
      0x6F,
      0x74,
      0x6F,
      0x73,
      0x68,
      0x6F,
      0x70,
      0x20,
      0x33,
      0x2E,
      0x30,
      0x00,
      0x38,
      0x42,
      0x49,
      0x4D,
      0x04,
      0x04,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x38,
      0x42,
      0x49,
      0x4D,
      0x04,
      0x25,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x10,
      0xD4,
      0x1D,
      0x8C,
      0xD9,
      0x8F,
      0x00,
      0xB2,
      0x04,
      0xE9,
      0x80,
      0x09,
      0x98,
      0xEC,
      0xF8,
      0x42,
      0x7E,
      0xFF,
      0xC0,
      0x00,
      0x11,
      0x08,
      0x00,
      0x08,
      0x00,
      0x08,
      0x03,
      0x01,
      0x11,
      0x00,
      0x02,
      0x11,
      0x01,
      0x03,
      0x11,
      0x01,
      0xFF,
      0xC4,
      0x00,
      0x1F,
      0x00,
      0x00,
      0x01,
      0x05,
      0x01,
      0x01,
      0x01,
      0x01,
      0x01,
      0x01,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x01,
      0x02,
      0x03,
      0x04,
      0x05,
      0x06,
      0x07,
      0x08,
      0x09,
      0x0A,
      0x0B,
      0xFF,
      0xC4,
      0x00,
      0xB5,
      0x10,
      0x00,
      0x02,
      0x01,
      0x03,
      0x03,
      0x02,
      0x04,
      0x03,
      0x05,
      0x05,
      0x04,
      0x04,
      0x00,
      0x00,
      0x01,
      0x7D,
      0x01,
      0x02,
      0x03,
      0x00,
      0x04,
      0x11,
      0x05,
      0x12,
      0x21,
      0x31,
      0x41,
      0x06,
      0x13,
      0x51,
      0x61,
      0x07,
      0x22,
      0x71,
      0x14,
      0x32,
      0x81,
      0x91,
      0xA1,
      0x08,
      0x23,
      0x42,
      0xB1,
      0xC1,
      0x15,
      0x52,
      0xD1,
      0xF0,
      0x24,
      0x33,
      0x62,
      0x72,
      0x82,
      0x09,
      0x0A,
      0x16,
      0x17,
      0x18,
      0x19,
      0x1A,
      0x25,
      0x26,
      0x27,
      0x28,
      0x29,
      0x2A,
      0x34,
      0x35,
      0x36,
      0x37,
      0x38,
      0x39,
      0x3A,
      0x43,
      0x44,
      0x45,
      0x46,
      0x47,
      0x48,
      0x49,
      0x4A,
      0x53,
      0x54,
      0x55,
      0x56,
      0x57,
      0x58,
      0x59,
      0x5A,
      0x63,
      0x64,
      0x65,
      0x66,
      0x67,
      0x68,
      0x69,
      0x6A,
      0x73,
      0x74,
      0x75,
      0x76,
      0x77,
      0x78,
      0x79,
      0x7A,
      0x83,
      0x84,
      0x85,
      0x86,
      0x87,
      0x88,
      0x89,
      0x8A,
      0x92,
      0x93,
      0x94,
      0x95,
      0x96,
      0x97,
      0x98,
      0x99,
      0x9A,
      0xA2,
      0xA3,
      0xA4,
      0xA5,
      0xA6,
      0xA7,
      0xA8,
      0xA9,
      0xAA,
      0xB2,
      0xB3,
      0xB4,
      0xB5,
      0xB6,
      0xB7,
      0xB8,
      0xB9,
      0xBA,
      0xC2,
      0xC3,
      0xC4,
      0xC5,
      0xC6,
      0xC7,
      0xC8,
      0xC9,
      0xCA,
      0xD2,
      0xD3,
      0xD4,
      0xD5,
      0xD6,
      0xD7,
      0xD8,
      0xD9,
      0xDA,
      0xE1,
      0xE2,
      0xE3,
      0xE4,
      0xE5,
      0xE6,
      0xE7,
      0xE8,
      0xE9,
      0xEA,
      0xF1,
      0xF2,
      0xF3,
      0xF4,
      0xF5,
      0xF6,
      0xF7,
      0xF8,
      0xF9,
      0xFA,
      0xFF,
      0xC4,
      0x00,
      0x1F,
      0x01,
      0x00,
      0x03,
      0x01,
      0x01,
      0x01,
      0x01,
      0x01,
      0x01,
      0x01,
      0x01,
      0x01,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x01,
      0x02,
      0x03,
      0x04,
      0x05,
      0x06,
      0x07,
      0x08,
      0x09,
      0x0A,
      0x0B,
      0xFF,
      0xC4,
      0x00,
      0xB5,
      0x11,
      0x00,
      0x02,
      0x01,
      0x02,
      0x04,
      0x04,
      0x03,
      0x04,
      0x07,
      0x05,
      0x04,
      0x04,
      0x00,
      0x01,
      0x02,
      0x77,
      0x00,
      0x01,
      0x02,
      0x03,
      0x11,
      0x04,
      0x05,
      0x21,
      0x31,
      0x06,
      0x12,
      0x41,
      0x51,
      0x07,
      0x61,
      0x71,
      0x13,
      0x22,
      0x32,
      0x81,
      0x08,
      0x14,
      0x42,
      0x91,
      0xA1,
      0xB1,
      0xC1,
      0x09,
      0x23,
      0x33,
      0x52,
      0xF0,
      0x15,
      0x62,
      0x72,
      0xD1,
      0x0A,
      0x16,
      0x24,
      0x34,
      0xE1,
      0x25,
      0xF1,
      0x17,
      0x18,
      0x19,
      0x1A,
      0x26,
      0x27,
      0x28,
      0x29,
      0x2A,
      0x35,
      0x36,
      0x37,
      0x38,
      0x39,
      0x3A,
      0x43,
      0x44,
      0x45,
      0x46,
      0x47,
      0x48,
      0x49,
      0x4A,
      0x53,
      0x54,
      0x55,
      0x56,
      0x57,
      0x58,
      0x59,
      0x5A,
      0x63,
      0x64,
      0x65,
      0x66,
      0x67,
      0x68,
      0x69,
      0x6A,
      0x73,
      0x74,
      0x75,
      0x76,
      0x77,
      0x78,
      0x79,
      0x7A,
      0x82,
      0x83,
      0x84,
      0x85,
      0x86,
      0x87,
      0x88,
      0x89,
      0x8A,
      0x92,
      0x93,
      0x94,
      0x95,
      0x96,
      0x97,
      0x98,
      0x99,
      0x9A,
      0xA2,
      0xA3,
      0xA4,
      0xA5,
      0xA6,
      0xA7,
      0xA8,
      0xA9,
      0xAA,
      0xB2,
      0xB3,
      0xB4,
      0xB5,
      0xB6,
      0xB7,
      0xB8,
      0xB9,
      0xBA,
      0xC2,
      0xC3,
      0xC4,
      0xC5,
      0xC6,
      0xC7,
      0xC8,
      0xC9,
      0xCA,
      0xD2,
      0xD3,
      0xD4,
      0xD5,
      0xD6,
      0xD7,
      0xD8,
      0xD9,
      0xDA,
      0xE2,
      0xE3,
      0xE4,
      0xE5,
      0xE6,
      0xE7,
      0xE8,
      0xE9,
      0xEA,
      0xF2,
      0xF3,
      0xF4,
      0xF5,
      0xF6,
      0xF7,
      0xF8,
      0xF9,
      0xFA,
      0xFF,
      0xDB,
      0x00,
      0x43,
      0x00,
      0x01,
      0x01,
      0x01,
      0x01,
      0x01,
      0x01,
      0x01,
      0x01,
      0x01,
      0x01,
      0x01,
      0x01,
      0x01,
      0x01,
      0x01,
      0x01,
      0x01,
      0x01,
      0x01,
      0x01,
      0x01,
      0x01,
      0x01,
      0x01,
      0x01,
      0x01,
      0x01,
      0x01,
      0x01,
      0x01,
      0x01,
      0x01,
      0x01,
      0x01,
      0x01,
      0x01,
      0x01,
      0x01,
      0x01,
      0x01,
      0x01,
      0x01,
      0x01,
      0x01,
      0x01,
      0x01,
      0x01,
      0x01,
      0x01,
      0x01,
      0x01,
      0x01,
      0x01,
      0x01,
      0x01,
      0x01,
      0x01,
      0x01,
      0x01,
      0x01,
      0x01,
      0x01,
      0x01,
      0x01,
      0xFF,
      0xDB,
      0x00,
      0x43,
      0x01,
      0x01,
      0x01,
      0x01,
      0x01,
      0x01,
      0x01,
      0x01,
      0x01,
      0x01,
      0x01,
      0x01,
      0x01,
      0x01,
      0x01,
      0x01,
      0x01,
      0x01,
      0x01,
      0x01,
      0x01,
      0x01,
      0x01,
      0x01,
      0x01,
      0x01,
      0x01,
      0x01,
      0x01,
      0x01,
      0x01,
      0x01,
      0x01,
      0x01,
      0x01,
      0x01,
      0x01,
      0x01,
      0x01,
      0x01,
      0x01,
      0x01,
      0x01,
      0x01,
      0x01,
      0x01,
      0x01,
      0x01,
      0x01,
      0x01,
      0x01,
      0x01,
      0x01,
      0x01,
      0x01,
      0x01,
      0x01,
      0x01,
      0x01,
      0x01,
      0x01,
      0x01,
      0x01,
      0x01,
      0x01,
      0xFF,
      0xDD,
      0x00,
      0x04,
      0x00,
      0x01,
      0xFF,
      0xDA,
      0x00,
      0x0C,
      0x03,
      0x01,
      0x00,
      0x02,
      0x11,
      0x03,
      0x11,
      0x00,
      0x3F,
      0x00,
      0xF8,
      0x5E,
      0xBF,
      0xC3,
      0xF3,
      0xFE,
      0xE0,
      0x0F,
      0xFF,
      0xD9,
    ]);
