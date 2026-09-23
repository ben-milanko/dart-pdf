import 'dart:typed_data';

/// Builds a one-page PDF whose AcroForm holds two list boxes:
///
/// - "toppings": a multi-select (/Ff 2097152, bit 22) list box at
///   [72 600 272 700] with /Opt [(Cheese) (Ham) [(pep) (Pepperoni)]
///   (Olives) (Onion)] and a /V array [(Ham) (Olives)] written by another
///   tool, with no /I.
/// - "crust": a single-select list box at [72 500 272 560], /Opt [(Thin)
///   (Deep) (Stuffed)], no value.
///
/// Both use /DA (/Helv 10 Tf 0 g); /DR maps /Helv to Helvetica. Byte
/// offsets are computed, never hand-written.
Uint8List buildListBoxFormPdf() {
  final objects = <String>[
    '<< /Type /Catalog /Pages 2 0 R /AcroForm << /Fields [6 0 R 7 0 R] '
        '/DA (/Helv 0 Tf 0 g) /DR << /Font << /Helv 5 0 R >> >> >> >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] '
        '/Contents 4 0 R /Annots [6 0 R 7 0 R] >>',
    '<< /Length 0 >>\nstream\n\nendstream',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica '
        '/Encoding /WinAnsiEncoding >>',
    '<< /Type /Annot /Subtype /Widget /FT /Ch /T (toppings) /Ff 2097152 '
        '/DA (/Helv 10 Tf 0 g) /P 3 0 R '
        '/Opt [(Cheese) (Ham) [(pep) (Pepperoni)] (Olives) (Onion)] '
        '/V [(Ham) (Olives)] /Rect [72 600 272 700] >>',
    '<< /Type /Annot /Subtype /Widget /FT /Ch /T (crust) '
        '/DA (/Helv 10 Tf 0 g) /P 3 0 R /Opt [(Thin) (Deep) (Stuffed)] '
        '/Rect [72 500 272 560] >>',
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
