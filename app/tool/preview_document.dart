// The document the App Store preview tour edits: a short, ordinary-looking
// three-page proposal. It is built in code (like the example's demo document)
// so text positions are known exactly - the tour drives highlights, the form
// field and the signature to fixed page coordinates - and so nothing in the
// recording is a real customer's file.
//
// Page coordinates the tour relies on live in [PreviewLayout].

import 'dart:typed_data';

import 'package:pdf_document/pdf_document.dart';

/// Page-space anchors the preview tour aims at (PDF points, origin bottom-left,
/// on a 612 x 792 Letter page).
abstract final class PreviewLayout {
  static const pageWidth = 612.0;
  static const pageHeight = 792.0;

  /// The sentence on page 1 that gets highlighted (baseline y, x extent).
  static const highlightBaseline = 590.0;
  static const highlightFrom = 72.0;
  static const highlightTo = 470.0;

  /// The client-name form field on page 1.
  static const clientField = PdfRect(196, 214, 420, 238);

  /// The signature line on page 1 (y of the rule, x extent).
  static const signatureLineY = 132.0;
  static const signatureFrom = 72.0;
  static const signatureTo = 300.0;

  /// Text typed into [clientField].
  static const clientName = 'Northwind Studio';
}

String _n(num v) => v is int || v == v.roundToDouble()
    ? v.round().toString()
    : v.toStringAsFixed(2);

String _esc(String s) =>
    s.replaceAll(r'\', r'\\').replaceAll('(', r'\(').replaceAll(')', r'\)');

String _text(num x, num y, num size, String s, {String font = 'F1'}) =>
    'BT /$font ${_n(size)} Tf ${_n(x)} ${_n(y)} Td (${_esc(s)}) Tj ET\n';

String _para(num x, num y, num size, num leading, List<String> lines) {
  final b = StringBuffer();
  for (var i = 0; i < lines.length; i++) {
    b.write(_text(x, y - i * leading, size, lines[i]));
  }
  return b.toString();
}

String _header(String title, int page) => ''
    'q 0.07 0.45 0.82 rg 0 752 612 40 re f Q\n'
    'q 1 1 1 rg ${_text(72, 766, 12, 'NORTHWIND STUDIO', font: 'F2')}Q\n'
    'q 1 1 1 rg ${_text(470, 766, 10, 'Proposal  -  page $page of 3')}Q\n'
    'q 0.1 0.12 0.18 rg ${_text(72, 700, 26, title, font: 'F2')}Q\n';

/// Builds the three-page proposal the preview tour opens.
Uint8List buildPreviewPdf() {
  final page1 = StringBuffer()
    ..write(_header('Website redesign proposal', 1))
    ..write('q 0.35 0.38 0.45 rg ')
    ..write(
        _text(72, 674, 12, 'Prepared for Contoso Bakery  -  8 October 2026'))
    ..write('Q\n')
    ..write(_text(72, 630, 14, 'Summary', font: 'F2'))
    ..write(_para(72, 608, 11.5, 18, const [
      'We will rebuild the bakery website so customers can browse the menu,',
      'order ahead for pickup, and book celebration cakes from their phones.',
      'The new site launches in six weeks, before the holiday season.',
      'Hosting, content updates and analytics are included for a year.',
    ]))
    ..write(_text(72, 520, 14, 'Timeline', font: 'F2'));
  const phases = [
    ('Discovery', 0.0, 1.0, '0.07 0.45 0.82'),
    ('Design', 1.0, 2.5, '0.36 0.31 0.85'),
    ('Build', 2.5, 5.0, '0.93 0.55 0.13'),
    ('Launch', 5.0, 6.0, '0.18 0.64 0.38'),
  ];
  for (var i = 0; i < phases.length; i++) {
    final (label, from, to, rgb) = phases[i];
    final y = 488.0 - i * 26;
    page1
      ..write(_text(72, y + 4, 10.5, label))
      ..write(
          'q $rgb rg ${_n(160 + from * 60)} $y ${_n((to - from) * 60)} 16 re f Q\n');
  }
  page1
    ..write('q 0.6 0.62 0.68 RG 0.5 w 160 380 m 520 380 l S Q\n')
    ..write('q 0.45 0.48 0.55 rg ');
  for (var w = 0; w <= 6; w++) {
    page1.write(_text(156 + w * 60, 366, 8.5, 'wk $w'));
  }
  page1
    ..write('Q\n')
    ..write(_text(72, 320, 14, 'Acceptance', font: 'F2'))
    ..write(_para(72, 298, 11.5, 18, const [
      'Sign below to accept this proposal and the attached budget.',
      'A 30% deposit is due on signing; the balance on launch.',
    ]))
    ..write(_text(72, 222, 11.5, 'Client name'))
    ..write(_text(72, 180, 11.5, 'Total'))
    ..write(_text(196, 180, 11.5, r'$18,400 (see page 2)', font: 'F2'))
    ..write('q 0.25 0.27 0.33 RG 0.8 w '
        '${_n(PreviewLayout.signatureFrom)} ${_n(PreviewLayout.signatureLineY)} m '
        '${_n(PreviewLayout.signatureTo)} ${_n(PreviewLayout.signatureLineY)} l S Q\n')
    ..write('q 0.45 0.48 0.55 rg ')
    ..write(_text(72, 116, 9.5, 'Client signature'))
    ..write(_text(360, 116, 9.5, 'Date'))
    ..write('Q q 0.25 0.27 0.33 RG 0.8 w 360 132 m 540 132 l S Q\n');

  final page2 = StringBuffer()
    ..write(_header('Budget', 2))
    ..write(_para(72, 660, 11.5, 18, const [
      'Fixed price, invoiced in two parts. Prices exclude GST.',
    ]));
  const rows = [
    ('Discovery workshops and site map', r'$1,900'),
    ('Visual design, mobile first', r'$4,600'),
    ('Online ordering and pickup slots', r'$6,200'),
    ('Cake booking form', r'$2,100'),
    ('Content migration and photography', r'$2,400'),
    ('Hosting, updates and analytics (1 year)', r'$1,200'),
  ];
  page2
    ..write('q 0.93 0.95 0.98 rg 72 600 468 26 re f Q\n')
    ..write(_text(84, 609, 11, 'Item', font: 'F2'))
    ..write(_text(470, 609, 11, 'Cost', font: 'F2'));
  for (var i = 0; i < rows.length; i++) {
    final (item, cost) = rows[i];
    final y = 574.0 - i * 30;
    page2
      ..write(_text(84, y + 8, 11, item))
      ..write(_text(470, y + 8, 11, cost))
      ..write('q 0.85 0.87 0.9 RG 0.5 w 72 $y m 540 $y l S Q\n');
  }
  page2
    ..write(_text(84, 384, 12, 'Total', font: 'F2'))
    ..write(_text(470, 384, 12, r'$18,400', font: 'F2'))
    ..write(_text(72, 320, 14, 'Payment', font: 'F2'))
    ..write(_para(72, 298, 11.5, 18, const [
      '30% deposit on signing, 70% on launch. Invoices are due in 14 days.',
      'Change requests outside this scope are quoted separately.',
    ]));

  final page3 = StringBuffer()
    ..write(_header('Appendix: design moodboard', 3))
    ..write(_para(72, 660, 11.5, 18, const [
      'Warm, hand-made, and quick to order from. Colours and type direction:',
    ]));
  const swatches = [
    '0.96 0.87 0.74',
    '0.86 0.55 0.36',
    '0.55 0.31 0.24',
    '0.24 0.2 0.22',
    '0.98 0.97 0.94',
  ];
  for (var i = 0; i < swatches.length; i++) {
    page3
      ..write('q ${swatches[i]} rg ${72 + i * 94} 520 82 100 re f Q\n')
      ..write('q 0.8 0.8 0.82 RG 0.5 w ${72 + i * 94} 520 82 100 re S Q\n');
  }
  page3
    ..write(_text(72, 460, 30, 'Fresh every morning', font: 'F2'))
    ..write(_text(72, 428, 16, 'Order ahead, skip the queue.'))
    ..write('q 0.93 0.55 0.13 rg 72 340 180 44 re f Q\n')
    ..write(
        'q 1 1 1 rg ${_text(104, 356, 14, 'Order for pickup', font: 'F2')}Q\n');

  final objects = <String>[];
  int add(String body) {
    objects.add(body);
    return objects.length;
  }

  String stream(String content) =>
      '<< /Length ${content.length} >>\nstream\n${content}endstream';

  final f1 = add('<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica '
      '/Encoding /WinAnsiEncoding >>');
  final f2 = add('<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold '
      '/Encoding /WinAnsiEncoding >>');
  final field = PreviewLayout.clientField;
  final clientField = add('<< /Type /Annot /Subtype /Widget /F 4 /FT /Tx '
      '/T (client) /P @PG1@ 0 R '
      '/Rect [${_n(field.left)} ${_n(field.bottom)} ${_n(field.right)} ${_n(field.top)}] '
      '/DA (/Helv 12 Tf 0 g) '
      '/MK << /BC [0.6 0.65 0.75] /BG [0.95 0.97 1] >> >>');
  final fonts = '/Font << /F1 $f1 0 R /F2 $f2 0 R >>';
  final pageNumbers = <int>[];
  for (final (content, annots) in [
    (page1, '/Annots [$clientField 0 R]'),
    (page2, ''),
    (page3, ''),
  ]) {
    final contents = add(stream(content.toString()));
    pageNumbers.add(add('<< /Type /Page /Parent @PAGES@ 0 R '
        '/MediaBox [0 0 612 792] /Contents $contents 0 R '
        '/Resources << $fonts >> $annots >>'));
  }
  final pages = add('<< /Type /Pages '
      '/Kids [${pageNumbers.map((n) => '$n 0 R').join(' ')}] '
      '/Count ${pageNumbers.length} >>');
  final catalog = add('<< /Type /Catalog /Pages $pages 0 R '
      '/AcroForm << /Fields [$clientField 0 R] /DA (/Helv 0 Tf 0 g) '
      '/DR << /Font << /Helv $f1 0 R >> >> >> >>');

  final buffer = StringBuffer('%PDF-1.7\n');
  final offsets = <int>[];
  for (var i = 0; i < objects.length; i++) {
    offsets.add(buffer.length);
    final body = objects[i]
        .replaceAll('@PAGES@', '$pages')
        .replaceAll('@PG1@', '${pageNumbers.first}');
    buffer.write('${i + 1} 0 obj\n$body\nendobj\n');
  }
  final xref = buffer.length;
  buffer
    ..write('xref\n0 ${objects.length + 1}\n0000000000 65535 f \n')
    ..writeAll([
      for (final o in offsets) '${o.toString().padLeft(10, '0')} 00000 n \n'
    ])
    ..write('trailer\n<< /Size ${objects.length + 1} /Root $catalog 0 R >>\n')
    ..write('startxref\n$xref\n%%EOF\n');
  return Uint8List.fromList(buffer.toString().codeUnits);
}
