import 'dart:typed_data';

/// Builds a one-page form carrying an XFA description (/AcroForm /XFA).
///
/// - [withFields] true (the default) gives a hybrid ("static") form: one
///   AcroForm text field "name" at [72 700 300 724] (/V `stale`, /DA
///   /Helv 12 Tf) alongside the XFA packets. False gives a dynamic,
///   XFA-only form whose /Fields array is empty.
/// - [needsRendering] sets the catalog's /NeedsRendering true.
/// - [xfaAsArray] true stores /XFA as the array of named packet streams
///   (`preamble`, `template`, `datasets`, `postamble`); false stores the
///   whole XDP document as a single stream.
///
/// The /XFA entry lives in an indirect /AcroForm dictionary (object 4) so a
/// filler has to restage that object to drop it.
Uint8List buildXfaFormPdf({
  bool withFields = true,
  bool needsRendering = false,
  bool xfaAsArray = true,
}) {
  const preamble = '<xdp:xdp xmlns:xdp="http://ns.adobe.com/xdp/">';
  const template =
      '<template xmlns="http://www.xfa.org/schema/xfa-template/3.3/">'
      '<subform name="form1"><field name="name"/></subform></template>';
  const datasets =
      '<xfa:datasets xmlns:xfa="http://www.xfa.org/schema/xfa-data/1.0/">'
      '<xfa:data><form1><name>stale</name></form1></xfa:data>'
      '</xfa:datasets>';
  const postamble = '</xdp:xdp>';
  String stream(String body) =>
      '<< /Length ${body.length} >>\nstream\n$body\nendstream';

  final xfa = xfaAsArray
      ? '[(preamble) 7 0 R (template) 8 0 R (datasets) 9 0 R '
          '(postamble) 10 0 R]'
      : '7 0 R';
  final objects = <String>[
    '<< /Type /Catalog /Pages 2 0 R /AcroForm 4 0 R'
        '${needsRendering ? ' /NeedsRendering true' : ''} >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] '
        '${withFields ? '/Annots [6 0 R] ' : ''}>>',
    '<< /Fields [${withFields ? '6 0 R' : ''}] /XFA $xfa '
        '/DA (/Helv 0 Tf 0 g) /DR << /Font << /Helv 5 0 R >> >> >>',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica '
        '/Encoding /WinAnsiEncoding >>',
    '<< /Type /Annot /Subtype /Widget /FT /Tx /T (name) /P 3 0 R '
        '/Rect [72 700 300 724] /DA (/Helv 12 Tf 0 g) /V (stale) >>',
    if (xfaAsArray) ...[
      stream(preamble),
      stream(template),
      stream(datasets),
      stream(postamble),
    ] else
      stream('$preamble$template$datasets$postamble'),
  ];

  final buffer = StringBuffer('%PDF-1.7\n');
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
