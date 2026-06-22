import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:test/test.dart';

/// One-page PDF around [content], with /F1 Helvetica available.
Uint8List buildReflowPdf(String content) {
  final objects = <String>[
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R '
        '/Resources << /Font << /F1 5 0 R /F2 6 0 R >> >> >>',
    '<< /Length ${content.length} >>\nstream\n$content\nendstream',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Times-Roman >>',
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

/// Builds a one-page PDF that draws [lines] (one per visual line) with an
/// embedded composite (/Type0) font, separated by `T*` at [leading].
Uint8List buildType0ReflowPdf(
    List<String> lines, Uint8List fontBytes, double size, double leading) {
  final font = PdfEmbeddedFont.parse(fontBytes);
  final hexes = [for (final line in lines) font.encodeHex(line)];
  final builder = CosDocumentBuilder();

  final body = StringBuffer('BT /F0 $size Tf $leading TL 72 700 Td ');
  for (var i = 0; i < hexes.length; i++) {
    if (i > 0) body.write('T* ');
    body.write('<${hexes[i]}> Tj ');
  }
  body.write('ET');
  final content = latin1.encode(body.toString());
  final contentRef = builder.add(CosStream(
      CosDictionary({'Length': CosInteger(content.length)}),
      Uint8List.fromList(content)));

  final type0Dict = font.buildResource(builder.add)['F0']!;
  final fontRef = builder.add(type0Dict);

  final pageDict = CosDictionary({
    'Type': const CosName('Page'),
    'MediaBox': CosArray(const [
      CosInteger(0),
      CosInteger(0),
      CosInteger(612),
      CosInteger(792),
    ]),
    'Contents': contentRef,
    'Resources': CosDictionary({
      'Font': CosDictionary({'F0': fontRef})
    }),
  });
  final pageRef = builder.add(pageDict);
  final pagesRef = builder.add(CosDictionary({
    'Type': const CosName('Pages'),
    'Kids': CosArray([pageRef]),
    'Count': const CosInteger(1),
  }));
  pageDict['Parent'] = pagesRef;
  final catalogRef = builder
      .add(CosDictionary({'Type': const CosName('Catalog'), 'Pages': pagesRef}));
  return builder.build(root: catalogRef);
}

/// Ordered (paint order) text elements of page 0 as (text, baseline-ish
/// bottom, left).
List<({String text, double bottom, double left})> textRuns(PdfDocument doc) => [
      for (final e in PdfPageElements.of(doc, 0).elements)
        if (e.kind == PdfElementKind.text && e.bounds != null)
          (text: e.text!, bottom: e.bounds!.bottom, left: e.bounds!.left),
    ];

String pageContent(PdfDocument doc) => latin1.decode(doc.page(0).contentBytes());

void main() {
  group('paragraph reflow — simple fonts', () {
    // Two lines of body text (group A), a paragraph gap, then a two-line
    // footer (group B) reached relatively so it cascades.
    const fixture = 'BT /F1 12 Tf 14 TL 72 700 Td '
        '(Alpha beta gamma delta) Tj '
        'T* (epsilon zeta eta theta) Tj '
        '0 -28 Td (Footer one) Tj '
        'T* (Footer two) Tj ET';

    test('growing a paragraph adds a line and cascades the following lines',
        () {
      final doc = PdfDocument.open(buildReflowPdf(fixture));
      final before = textRuns(doc);
      expect(before.map((r) => r.text).toList(), [
        'Alpha beta gamma delta',
        'epsilon zeta eta theta',
        'Footer one',
        'Footer two',
      ]);
      final footerOneBefore =
          before.firstWhere((r) => r.text == 'Footer one').bottom;

      final editor = PdfEditor(doc);
      final ran = editor.reflowText(0, 'delta',
          'delta alongerwordhere plus several more trailing words to wrap');
      expect(ran, isTrue);
      final out = PdfDocument.open(editor.save());

      final after = textRuns(out);
      // group B is untouched, still two footer lines
      final footers =
          after.where((r) => r.text.startsWith('Footer')).toList();
      expect(footers.map((r) => r.text), ['Footer one', 'Footer two']);

      // group A re-wrapped to more than its original two lines
      final body = after.where((r) => !r.text.startsWith('Footer')).toList();
      expect(body.length, greaterThan(2));

      // the paragraph reads as the edited text with line breaks removed
      final joined =
          body.map((r) => r.text).join(' ').replaceAll(RegExp(r'\s+'), ' ');
      expect(
          joined,
          'Alpha beta gamma delta alongerwordhere plus several more '
          'trailing words to wrap epsilon zeta eta theta');

      // 'Footer one' cascaded down by exactly the lines A grew, times leading
      final grew = body.length - 2;
      final footerOneAfter =
          after.firstWhere((r) => r.text == 'Footer one').bottom;
      expect(footerOneAfter, closeTo(footerOneBefore - grew * 14, 0.01));

      // no overlap: the last body line sits above the first footer line
      final lastBodyBottom = body.last.bottom;
      final footerOneTop = footerOneAfter + 12; // ~one line box up
      expect(lastBodyBottom, greaterThan(footerOneTop - 14));
    });

    test('shrinking a paragraph removes a line and pulls following lines up',
        () {
      // a three-line paragraph that collapses to one line after the edit
      const wide = 'BT /F1 12 Tf 14 TL 72 700 Td '
          '(one two three) Tj '
          'T* (four five six) Tj '
          'T* (seven eight nine) Tj '
          '0 -28 Td (Footer one) Tj ET';
      final doc = PdfDocument.open(buildReflowPdf(wide));
      final footerBefore =
          textRuns(doc).firstWhere((r) => r.text == 'Footer one').bottom;

      final editor = PdfEditor(doc);
      final ran = editor.reflowText(
          0, 'one two three four five six seven eight nine', 'tiny');
      expect(ran, isTrue);
      final out = PdfDocument.open(editor.save());

      final after = textRuns(out);
      final body = after.where((r) => r.text != 'Footer one').toList();
      expect(body.length, 1);
      expect(body.single.text, 'tiny');

      // two lines removed → footer pulled up by 2 * leading
      final footerAfter =
          after.firstWhere((r) => r.text == 'Footer one').bottom;
      expect(footerAfter, closeTo(footerBefore + 2 * 14, 0.01));
    });

    test('a same-line-count edit reflows without moving following lines', () {
      // a two-line paragraph whose edit (a shorter word) re-wraps to two
      // lines again, so the following footer must not move.
      const twoLine = 'BT /F1 12 Tf 14 TL 72 700 Td '
          '(short one here) Tj '
          'T* (short two here) Tj '
          '0 -28 Td (Footer one) Tj '
          'T* (Footer two) Tj ET';
      final doc = PdfDocument.open(buildReflowPdf(twoLine));
      final footerBefore =
          textRuns(doc).firstWhere((r) => r.text == 'Footer one').bottom;
      final editor = PdfEditor(doc);
      expect(editor.reflowText(0, 'one here', '1'), isTrue);
      final out = PdfDocument.open(editor.save());
      final after = textRuns(out);
      final body = after.where((r) => !r.text.startsWith('Footer')).toList();
      expect(body.length, 2, reason: 'still a two-line paragraph');
      expect(body.map((r) => r.text).join(' '), contains('short 1'));
      // line count unchanged → the footer stays exactly where it was
      expect(after.firstWhere((r) => r.text == 'Footer one').bottom,
          closeTo(footerBefore, 0.01));
    });

    test('a Td-broken paragraph reflows through Td breaks', () {
      const tdFixture = 'BT /F1 12 Tf 72 700 Td '
          '(red green blue) Tj '
          '0 -15 Td (cyan magenta) Tj '
          '0 -30 Td (Footer) Tj ET';
      final doc = PdfDocument.open(buildReflowPdf(tdFixture));
      final footerBefore =
          textRuns(doc).firstWhere((r) => r.text == 'Footer').bottom;
      final editor = PdfEditor(doc);
      expect(
          editor.reflowText(0, 'blue',
              'blue plus a good many extra words to force another line break'),
          isTrue);
      final out = PdfDocument.open(editor.save());
      // reflow emitted Td breaks (the paragraph's own style), not T*
      expect(pageContent(out), contains('0 -15 Td'));
      final after = textRuns(out);
      final body = after.where((r) => r.text != 'Footer').toList();
      expect(body.length, greaterThan(2));
      final grew = body.length - 2;
      expect(after.firstWhere((r) => r.text == 'Footer').bottom,
          closeTo(footerBefore - grew * 15, 0.01));
    });

    test('a miss returns false and queues nothing', () {
      final editor = PdfEditor(PdfDocument.open(buildReflowPdf(fixture)));
      expect(editor.reflowText(0, 'not present', 'x'), isFalse);
      expect(editor.hasChanges, isFalse);
    });

    test('rotated text is left untouched', () {
      const rotated = 'BT /F1 12 Tf 0.707 0.707 -0.707 0.707 72 700 Tm '
          '(rotated heading text) Tj ET';
      final editor = PdfEditor(PdfDocument.open(buildReflowPdf(rotated)));
      expect(editor.reflowText(0, 'heading', 'header'), isFalse);
      expect(editor.hasChanges, isFalse);
    });

    test('a mid-paragraph font change splits the block and is left untouched',
        () {
      const mixed = 'BT /F1 12 Tf 14 TL 72 700 Td '
          '(first line here) Tj '
          'T* /F2 12 Tf (second line here) Tj ET';
      final editor = PdfEditor(PdfDocument.open(buildReflowPdf(mixed)));
      // 'here second' spans the font boundary, so no single block holds it
      expect(editor.reflowText(0, 'here second', 'X'), isFalse);
      expect(editor.hasChanges, isFalse);
    });

    test('the page round-trips and re-parses after a reflow', () {
      final doc = PdfDocument.open(buildReflowPdf(fixture));
      final editor = PdfEditor(doc);
      expect(editor.reflowText(0, 'delta', 'delta and more words to wrap over'),
          isTrue);
      final out = PdfDocument.open(editor.save());
      // a second independent edit still works on the saved file
      final editor2 = PdfEditor(out);
      expect(editor2.reflowText(0, 'Footer one', 'Footer uno'), isTrue);
      final out2 = PdfDocument.open(editor2.save());
      final footers = textRuns(out2)
          .where((r) => r.text.startsWith('Footer'))
          .map((r) => r.text)
          .join(' ');
      expect(footers, contains('Footer uno'));
    });
  });

  group('paragraph reflow — composite /Type0 fonts', () {
    final fontBytes = File('test/fonts/DejaVuSans.ttf').readAsBytesSync();

    test('grows a composite paragraph and cascades nothing when last', () {
      final pdf = buildType0ReflowPdf(
          ['Hello there world', 'second short line'], fontBytes, 18, 22);
      final editor = PdfEditor(PdfDocument.open(pdf));
      final ran = editor.reflowText(0, 'world',
          'world and quite a few additional words here to force wrapping');
      expect(ran, isTrue);
      final out = PdfDocument.open(editor.save());
      final body = textRuns(out);
      expect(body.length, greaterThan(2));
      final joined =
          body.map((r) => r.text).join(' ').replaceAll(RegExp(r'\s+'), ' ');
      expect(
          joined,
          'Hello there world and quite a few additional words here to '
          'force wrapping second short line');
    });

    test('can type a character not originally on the page (font carries it)',
        () {
      final pdf = buildType0ReflowPdf(
          ['Hello there world', 'second short line'], fontBytes, 18, 22);
      final editor = PdfEditor(PdfDocument.open(pdf));
      // 'ö' is absent from the page but DejaVuSans (embedded whole) has it
      expect(editor.reflowText(0, 'world', 'wörld'), isTrue);
      final out = PdfDocument.open(editor.save());
      expect(textRuns(out).any((r) => r.text.contains('wörld')), isTrue);
    });

    test('a composite miss returns false', () {
      final pdf = buildType0ReflowPdf(['Hello world'], fontBytes, 18, 22);
      final editor = PdfEditor(PdfDocument.open(pdf));
      expect(editor.reflowText(0, 'absent', 'x'), isFalse);
      expect(editor.hasChanges, isFalse);
    });
  });
}
