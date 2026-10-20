import 'dart:typed_data';

/// Builds a two-page form for keyboard (Tab) traversal tests.
///
/// Page 0 carries `/Tabs /[firstPageTabs]` (omitted when null) and lists its
/// widgets in /Annots in a deliberately scrambled order:
///
/// | /Annots | field    | kind                  | rect               |
/// |---------|----------|-----------------------|--------------------|
/// | 0       | `city`   | text                  | 320 700 540 724    |
/// | 1       | `first`  | text                  | 72 700 300 724     |
/// | 2       | `agree`  | check box             | 72 640 92 660      |
/// | 3       | `ro`     | text, read-only       | 320 640 540 664    |
/// | 4       | `hidden` | text, /F hidden       | 72 600 300 624     |
/// | 5       | `submit` | push button           | 320 600 400 624    |
/// | 6       | `sig`    | signature             | 72 560 300 590     |
/// | 7, 8    | `color`  | radio (Red, Blue)     | 72/120 520 +20     |
///
/// So /Annots order is city, first, agree, color#0, color#1; row order
/// (/R) is first, city, agree, color#0, color#1; column order (/C) is
/// first, agree, color#0, color#1, city. The structure tree tags page 0's
/// widgets as color#1, agree, first, city, color#0 - structure order (/S).
///
/// Page 1 has no /Tabs: `notes` (multi-line text, 72 600 540 700) then
/// `size` (a combo box, 72 540 200 564) in /Annots order.
Uint8List buildTabOrderFormPdf({String? firstPageTabs = 'R'}) {
  const onState = '0.5 g 0 0 20 20 re f';
  final tabs = firstPageTabs == null ? '' : '/Tabs /$firstPageTabs ';
  final objects = <String>[
    // 1
    '<< /Type /Catalog /Pages 2 0 R /AcroForm << '
        '/Fields [6 0 R 7 0 R 8 0 R 9 0 R 10 0 R 11 0 R 12 0 R 13 0 R '
        '16 0 R 17 0 R] '
        '/DA (/Helv 0 Tf 0 g) /DR << /Font << /Helv 5 0 R >> >> >> '
        '/StructTreeRoot 20 0 R >>',
    // 2
    '<< /Type /Pages /Kids [3 0 R 4 0 R] /Count 2 >>',
    // 3: page 0
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] $tabs'
        '/Annots [6 0 R 7 0 R 8 0 R 9 0 R 10 0 R 11 0 R 12 0 R 14 0 R '
        '15 0 R] >>',
    // 4: page 1
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] '
        '/Annots [16 0 R 17 0 R] >>',
    // 5
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica '
        '/Encoding /WinAnsiEncoding >>',
    // 6
    '<< /Type /Annot /Subtype /Widget /FT /Tx /T (city) /P 3 0 R '
        '/Rect [320 700 540 724] /DA (/Helv 12 Tf 0 g) >>',
    // 7
    '<< /Type /Annot /Subtype /Widget /FT /Tx /T (first) /P 3 0 R '
        '/Rect [72 700 300 724] /DA (/Helv 12 Tf 0 g) >>',
    // 8
    '<< /Type /Annot /Subtype /Widget /FT /Btn /T (agree) /P 3 0 R '
        '/V /Off /AS /Off /Rect [72 640 92 660] '
        '/AP << /N << /Yes 18 0 R /Off 19 0 R >> >> >>',
    // 9
    '<< /Type /Annot /Subtype /Widget /FT /Tx /T (ro) /Ff 1 /P 3 0 R '
        '/V (fixed) /Rect [320 640 540 664] /DA (/Helv 12 Tf 0 g) >>',
    // 10
    '<< /Type /Annot /Subtype /Widget /FT /Tx /T (hidden) /F 2 /P 3 0 R '
        '/Rect [72 600 300 624] /DA (/Helv 12 Tf 0 g) >>',
    // 11
    '<< /Type /Annot /Subtype /Widget /FT /Btn /Ff 65536 /T (submit) '
        '/P 3 0 R /Rect [320 600 400 624] >>',
    // 12
    '<< /Type /Annot /Subtype /Widget /FT /Sig /T (sig) /P 3 0 R '
        '/Rect [72 560 300 590] >>',
    // 13: radio parent
    '<< /FT /Btn /T (color) /Ff 32768 /V /Off /Kids [14 0 R 15 0 R] >>',
    // 14
    '<< /Type /Annot /Subtype /Widget /Parent 13 0 R /P 3 0 R '
        '/Rect [72 520 92 540] /AS /Off '
        '/AP << /N << /Red 18 0 R /Off 19 0 R >> >> >>',
    // 15
    '<< /Type /Annot /Subtype /Widget /Parent 13 0 R /P 3 0 R '
        '/Rect [120 520 140 540] /AS /Off '
        '/AP << /N << /Blue 18 0 R /Off 19 0 R >> >> >>',
    // 16: page 1, multi-line text
    '<< /Type /Annot /Subtype /Widget /FT /Tx /T (notes) /Ff 4096 '
        '/P 4 0 R /Rect [72 600 540 700] /DA (/Helv 12 Tf 0 g) >>',
    // 17: page 1, combo box
    '<< /Type /Annot /Subtype /Widget /FT /Ch /T (size) /Ff 131072 '
        '/P 4 0 R /Opt [(Small) (Medium) (Large)] /V (Small) '
        '/Rect [72 540 200 564] /DA (/Helv 12 Tf 0 g) >>',
    // 18, 19: check/radio on and off appearances
    '<< /Type /XObject /Subtype /Form /BBox [0 0 20 20] '
        '/Length ${onState.length} >>\nstream\n$onState\nendstream',
    '<< /Type /XObject /Subtype /Form /BBox [0 0 20 20] /Length 0 '
        '>>\nstream\n\nendstream',
    // 20, 21: structure tree tagging page 0's widgets out of /Annots order
    '<< /Type /StructTreeRoot /K 21 0 R >>',
    '<< /Type /StructElem /S /Form /P 20 0 R /Pg 3 0 R /K ['
        '<< /Type /OBJR /Obj 15 0 R >> << /Type /OBJR /Obj 8 0 R >> '
        '<< /Type /OBJR /Obj 7 0 R >> << /Type /OBJR /Obj 6 0 R >> '
        '<< /Type /OBJR /Obj 14 0 R >>] >>',
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
  return Uint8List.fromList(buffer.toString().codeUnits);
}
