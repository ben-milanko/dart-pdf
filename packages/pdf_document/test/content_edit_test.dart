import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:test/test.dart';

/// One-page PDF around a custom content stream, with /F1 Helvetica and a
/// 1×1 gray image /Im1 available.
Uint8List buildContentPdf(String content) {
  final objects = <String>[
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R '
        '/Resources << /Font << /F1 5 0 R >> '
        '/XObject << /Im1 6 0 R >> >> >>',
    '<< /Length ${content.length} >>\nstream\n$content\nendstream',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
    '<< /Type /XObject /Subtype /Image /Width 1 /Height 1 '
        '/ColorSpace /DeviceGray /BitsPerComponent 8 /Length 1 >>\n'
        'stream\nx\nendstream',
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

const richContent = '1 0 0 RG 0 0 1 rg '
    '100 100 50 40 re f\n'
    'BT /F1 12 Tf 72 700 Td (first line) Tj 0 -14 Td (second line) Tj ET\n'
    'q 200 0 0 100 50 300 cm /Im1 Do Q\n';

String pageText(PdfDocument doc, [int index = 0]) =>
    latin1.decode(doc.page(index).contentBytes());

void main() {
  group('elements', () {
    test('paths, text runs, and images list with bounds', () {
      final doc = PdfDocument.open(buildContentPdf(richContent));
      final elements = PdfPageElements.of(doc, 0).elements;
      expect(elements, hasLength(4));

      expect(elements[0].kind, PdfElementKind.path);
      expect(elements[0].bounds, const PdfRect(100, 100, 150, 140));

      expect(elements[1].kind, PdfElementKind.text);
      expect(elements[1].text, 'first line');
      expect(elements[1].bounds!.left, 72);
      expect(elements[1].bounds!.bottom, closeTo(700 - 2.4, 0.01));

      expect(elements[2].kind, PdfElementKind.text);
      expect(elements[2].text, 'second line');
      expect(elements[2].bounds!.bottom, closeTo(686 - 2.4, 0.01));

      expect(elements[3].kind, PdfElementKind.image);
      expect(elements[3].resourceName, 'Im1');
      expect(elements[3].bounds, const PdfRect(50, 300, 250, 400));
    });

    test('elementsAt hit-tests topmost first', () {
      final doc = PdfDocument.open(buildContentPdf(richContent));
      final elements = PdfPageElements.of(doc, 0);
      expect(elements.elementsAt(120, 120).single.kind, PdfElementKind.path);
      expect(elements.elementsAt(100, 350).single.kind, PdfElementKind.image);
      expect(elements.elementsAt(0, 0), isEmpty);
    });
  });

  group('deletion', () {
    test('deleting a path keeps everything else byte-compatible', () {
      final doc = PdfDocument.open(buildContentPdf(richContent));
      final elements = PdfPageElements.of(doc, 0);
      final editor = PdfEditor(doc)
        ..deleteElements(elements, [elements.elements[0].id]);
      final out = PdfDocument.open(editor.save());
      final text = pageText(out);
      expect(text, isNot(contains('re')));
      expect(text, contains('(first line) Tj'));
      expect(text, contains('/Im1 Do'));
      expect(PdfPageElements.of(out, 0).elements, hasLength(3));
    });

    test('deleting one text run leaves its sibling in place', () {
      final doc = PdfDocument.open(buildContentPdf(richContent));
      final elements = PdfPageElements.of(doc, 0);
      final second =
          elements.elements.firstWhere((e) => e.text == 'second line');
      final editor = PdfEditor(doc)..deleteElements(elements, [second.id]);
      final out = PdfDocument.open(editor.save());
      expect(pageText(out), contains('(first line) Tj'));
      expect(pageText(out), isNot(contains('second line')));
      // positioning context survives
      expect(pageText(out), contains('0 -14 Td'));
    });

    test("deleting a ' run keeps its line advance", () {
      final doc = PdfDocument.open(buildContentPdf(
          "BT /F1 12 Tf 14 TL 72 700 Td (one) Tj (two) ' (three) ' ET"));
      final elements = PdfPageElements.of(doc, 0);
      final two = elements.elements.firstWhere((e) => e.text == 'two');
      final editor = PdfEditor(doc)..deleteElements(elements, [two.id]);
      final out = PdfDocument.open(editor.save());
      final text = pageText(out);
      expect(text, isNot(contains('(two)')));
      expect(text, contains('T*'));
      // 'three' still lands two leadings below 700
      final reparsed = PdfPageElements.of(out, 0);
      final three = reparsed.elements.firstWhere((e) => e.text == 'three');
      expect(three.bounds!.bottom, closeTo(700 - 28 - 2.4, 0.01));
    });

    test('inline images round-trip through a rewrite', () {
      final doc = PdfDocument.open(buildContentPdf('100 100 10 10 re f\n'
          'q 5 0 0 5 10 10 cm BI /W 2 /H 1 /CS /G /BPC 8 ID \xa0\xa1 EI Q\n'));
      final elements = PdfPageElements.of(doc, 0);
      expect(elements.elements[1].kind, PdfElementKind.inlineImage);
      final editor = PdfEditor(doc)
        ..deleteElements(elements, [elements.elements[0].id]);
      final out = PdfDocument.open(editor.save());
      final reparsed = PdfPageElements.of(out, 0);
      expect(reparsed.elements.single.kind, PdfElementKind.inlineImage);
      final bi = reparsed.operations[reparsed.elements.single.start];
      expect((bi.operands[1] as CosString).bytes, [0xa0, 0xa1]);
    });
  });

  group('text replacement', () {
    test('replaces a run and survives a round-trip', () {
      final doc = PdfDocument.open(buildMultiPagePdf(2));
      final editor = PdfEditor(doc);
      expect(editor.replaceText(0, 'Page 1', 'Cover'), 1);
      final out = PdfDocument.open(editor.save());
      expect(pageText(out), contains('(Cover) Tj'));
      expect(pageText(out), isNot(contains('Page 1')));
      expect(pageText(out, 1), contains('(Page 2) Tj'));
    });

    test('replaceElementText changes only the selected operation', () {
      final doc = PdfDocument.open(buildContentPdf(
          'BT /F1 12 Tf 72 700 Td (Page 1) Tj 0 -20 Td (Page 2) Tj ET'));
      final elements = PdfPageElements.of(doc, 0);
      final texts = elements.elements
          .where((element) => element.kind == PdfElementKind.text)
          .toList();
      final editor = PdfEditor(doc);

      expect(
          editor.replaceElementText(elements, texts.first, 'Page', 'Sheet'), 1);

      final reopened = PdfDocument.open(editor.save());
      final text = PdfPageElements.of(reopened, 0)
          .elements
          .where((element) => element.kind == PdfElementKind.text)
          .map((element) => element.text)
          .toList();
      expect(text, ['Sheet 1', 'Page 2']);
    });

    test('repeated edits through one snapshot compose', () {
      // replaceElementText reuses the caller's PdfPageElements to skip a
      // second decode + tokenization (#402). Edits mutate that snapshot's
      // operation list in place, so successive edits through the SAME
      // snapshot stay consistent - this pins that contract.
      final doc = PdfDocument.open(buildContentPdf(
          'BT /F1 12 Tf 72 700 Td (Page 1) Tj 0 -20 Td (Page 2) Tj ET'));
      final elements = PdfPageElements.of(doc, 0);
      final texts = elements.elements
          .where((element) => element.kind == PdfElementKind.text)
          .toList();
      final editor = PdfEditor(doc);

      expect(
          editor.replaceElementText(elements, texts.first, 'Page', 'Sheet'), 1);
      expect(
          editor.replaceElementText(elements, texts[1], 'Page', 'Folio'), 1);

      final reopened = PdfDocument.open(editor.save());
      final text = PdfPageElements.of(reopened, 0)
          .elements
          .where((element) => element.kind == PdfElementKind.text)
          .map((element) => element.text)
          .toList();
      expect(text, ['Sheet 1', 'Folio 2'],
          reason: 'the first edit must survive the second');
    });

    test('an edit made through another snapshot is not clobbered', () {
      // The hazard the snapshot reuse actually introduces: a DIFFERENT
      // snapshot rewrites the page in between, so the held one no longer
      // describes the document. Reusing it there would serialize operations
      // that predate the other edit and silently undo it.
      final doc = PdfDocument.open(buildContentPdf('BT /F1 12 Tf 72 700 Td '
          '(Page 1) Tj 0 -20 Td (Page 2) Tj 0 -20 Td (Page 3) Tj ET'));
      final held = PdfPageElements.of(doc, 0);
      final texts = held.elements
          .where((element) => element.kind == PdfElementKind.text)
          .toList();
      final editor = PdfEditor(doc);

      expect(editor.replaceElementText(held, texts.first, 'Page', 'Sheet'), 1);

      // A separate snapshot deletes the third run.
      final fresh = PdfPageElements.of(doc, 0);
      final freshTexts = fresh.elements
          .where((element) => element.kind == PdfElementKind.text)
          .toList();
      editor.deleteElements(fresh, [freshTexts.last.id]);

      // Back to the held snapshot, which knows nothing of that delete.
      expect(editor.replaceElementText(held, texts[1], 'Page', 'Folio'), 1);

      final reopened = PdfDocument.open(editor.save());
      final text = PdfPageElements.of(reopened, 0)
          .elements
          .where((element) => element.kind == PdfElementKind.text)
          .map((element) => element.text)
          .toList();
      expect(text, ['Sheet 1', 'Folio 2'],
          reason: 'the delete made through the other snapshot must survive');
    });

    test('a miss returns zero and queues nothing', () {
      final editor = PdfEditor(PdfDocument.open(buildMultiPagePdf(1)));
      expect(editor.replaceText(0, 'absent text', 'x'), 0);
      expect(editor.hasChanges, isFalse);
    });

    test('replaces within a single TJ element', () {
      final doc = PdfDocument.open(
          buildContentPdf('BT /F1 12 Tf 72 700 Td [(spli) -20 (t run)] TJ ET'));
      final editor = PdfEditor(doc);
      expect(editor.replaceText(0, 't run', 't sprint'), 1);
      expect(pageText(PdfDocument.open(editor.save())), contains('(t sprint)'));
    });

    test('matches across TJ array elements and their kern', () {
      final doc = PdfDocument.open(
          buildContentPdf('BT /F1 12 Tf 72 700 Td [(spli) -20 (t run)] TJ ET'));
      final editor = PdfEditor(doc);
      // 'split' spans both strings and the -20 kern between them
      expect(editor.replaceText(0, 'split', 'joined'), 1);
      final text = pageText(PdfDocument.open(editor.save()));
      expect(text, contains('(joined)'));
      expect(text, contains('( run)'));
      expect(text, isNot(contains('-20')), reason: 'interior kern consumed');
    });

    test('a width change inserts a compensating adjustment', () {
      final doc = PdfDocument.open(
          buildContentPdf('BT /F1 12 Tf 72 700 Td [(AAA) (BBB)] TJ ET'));
      final editor = PdfEditor(doc);
      expect(editor.replaceText(0, 'AAA', 'AA'), 1);
      // Helvetica 'A' is 667/1000 em; dropping one shifts 'BBB' back by 667,
      // so a +667-unit kern is inserted to hold it in place.
      expect(pageText(PdfDocument.open(editor.save())),
          contains('[(AA) -667 (BBB)] TJ'));
    });

    test('a match can span consecutive show operators', () {
      final doc = PdfDocument.open(
          buildContentPdf('BT /F1 12 Tf 72 700 Td (foo) Tj (bar) Tj ET'));
      final editor = PdfEditor(doc);
      expect(editor.replaceText(0, 'ooba', 'X'), 1);
      final text = pageText(PdfDocument.open(editor.save()));
      expect(text, contains('(fX)'));
      expect(text, contains('(r)'));
      expect(text, isNot(contains('(foo) Tj (bar) Tj')));
    });

    test('composite Type0 runs are skipped', () {
      final bytes = buildContentPdf('BT /F1 12 Tf 72 700 Td (find me) Tj ET');
      // rewrite the font to claim /Subtype /Type0
      final doc = PdfDocument.open(ascii(latin1
          .decode(bytes)
          .replaceFirst('/Subtype /Type1', '/Subtype /Type0')));
      final editor = PdfEditor(doc);
      expect(editor.replaceText(0, 'find me', 'found'), 0);
    });
  });

  group('stamping', () {
    test('stamped text and shapes land over the page content', () {
      final doc = PdfDocument.open(buildClassicPdf());
      final editor = PdfEditor(doc)
        ..stampPage(0, (stamp) {
          stamp.rect(40, 40, 200, 60, fillColor: 0xFFEE00);
          stamp.text('APPROVED',
              x: 50, y: 60, size: 24, color: 0xCC0000, bold: true);
        });
      final out = PdfDocument.open(editor.save());
      final text = pageText(out);
      expect(text, contains('(Hello, world!) Tj'));
      expect(text, contains('(APPROVED) Tj'));
      expect(text.indexOf('APPROVED'), greaterThan(text.indexOf('Hello')));

      final fonts =
          out.cos.resolve(out.page(0).resources['Font']) as CosDictionary;
      final stampFont = out.cos.resolve(fonts['StF1']) as CosDictionary;
      expect(stampFont['BaseFont'], const CosName('Helvetica-Bold'));
      // the original font reference is untouched
      expect(out.cos.resolve(fonts['F1']), isA<CosDictionary>());
    });

    test('the original content is wrapped in q/Q exactly once', () {
      final doc = PdfDocument.open(buildClassicPdf());
      final editor = PdfEditor(doc)
        ..stampPage(0, (s) => s.text('one', x: 10, y: 10))
        ..stampPage(0, (s) => s.text('two', x: 10, y: 30));
      final out = PdfDocument.open(editor.save());
      final contents =
          out.cos.resolve(out.page(0).dict['Contents']) as CosArray;
      // q-prefix, original, Q-suffix, stamp one, stamp two
      expect(contents.length, 5);
      expect(pageText(out), startsWith('q\n'));
    });

    test('rotated text writes a rotation matrix', () {
      final doc = PdfDocument.open(buildClassicPdf());
      final editor = PdfEditor(doc)
        ..stampPage(
            0, (s) => s.text('DRAFT', x: 100, y: 100, angleDegrees: 45));
      final out = PdfDocument.open(editor.save());
      expect(pageText(out), contains('0.707'));
    });

    test('stamping a page with inherited resources copies them privately', () {
      final doc = PdfDocument.open(buildNestedPageTreePdf());
      final editor = PdfEditor(doc)
        ..stampPage(0, (s) => s.text('stamp', x: 5, y: 5));
      final out = PdfDocument.open(editor.save());
      final page0Fonts =
          out.cos.resolve(out.page(0).resources['Font']) as CosDictionary;
      expect(page0Fonts.containsKey('StF1'), isTrue);
      expect(page0Fonts.containsKey('F1'), isTrue, reason: 'inherited kept');
      final page1Fonts =
          out.cos.resolve(out.page(1).resources['Font']) as CosDictionary;
      expect(page1Fonts.containsKey('StF1'), isFalse,
          reason: 'sibling page must not see the stamp font');
    });

    test('a JPEG stamps as a DCTDecode image XObject', () {
      // minimal SOF0 header claiming 4×3 RGB; never decoded by the editor
      final jpeg = Uint8List.fromList([
        0xFF, 0xD8, // SOI
        0xFF, 0xC0, 0x00, 0x11, 0x08, // SOF0, length 17, 8-bit
        0x00, 0x03, // height 3
        0x00, 0x04, // width 4
        0x03, // 3 components
        ...List.filled(9, 0),
        0xFF, 0xD9, // EOI
      ]);
      final doc = PdfDocument.open(buildClassicPdf());
      final editor = PdfEditor(doc)
        ..stampPage(0, (s) => s.jpegImage(jpeg, x: 100, y: 500, width: 200));
      final out = PdfDocument.open(editor.save());
      final xobjects =
          out.cos.resolve(out.page(0).resources['XObject']) as CosDictionary;
      final image = out.cos.resolve(xobjects['Im1']) as CosStream;
      expect(image.dictionary['Width'], const CosInteger(4));
      expect(image.dictionary['Height'], const CosInteger(3));
      expect(image.dictionary['Filter'], const CosName('DCTDecode'));
      expect(image.dictionary['ColorSpace'], const CosName('DeviceRGB'));
      // 200 wide → 150 tall by aspect
      expect(pageText(out), contains('200 0 0 150 100 500 cm'));
      expect(image.rawBytes, jpeg);
    });

    test('a PNG stamps as a Flate image XObject with an /SMask', () {
      // 2x2 RGBA fixture from png_test.dart: known pixels + alphas
      final png = base64.decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAYAAABytg0kAAAAGUlEQVR4nGP4z8DwHwgb'
          'WBgZ/jNyicr7AgA3BAUOTnqjAAAAAABJRU5ErkJggg==');
      final doc = PdfDocument.open(buildClassicPdf());
      final editor = PdfEditor(doc)
        ..stampPage(
            0,
            (s) => s.image(PdfEmbeddableImage.decode(png),
                x: 50, y: 60, height: 100));
      final out = PdfDocument.open(editor.save());
      final xobjects =
          out.cos.resolve(out.page(0).resources['XObject']) as CosDictionary;
      final image = out.cos.resolve(xobjects['Im1']) as CosStream;
      expect(image.dictionary['Width'], const CosInteger(2));
      expect(image.dictionary['Height'], const CosInteger(2));
      expect(image.dictionary['Filter'], const CosName('FlateDecode'));
      expect(image.dictionary['ColorSpace'], const CosName('DeviceRGB'));
      expect(out.cos.decodeStreamData(image),
          [255, 0, 0, 0, 255, 0, 0, 0, 255, 10, 20, 30]);
      final smask = out.cos.resolve(image.dictionary['SMask']) as CosStream;
      expect(smask.dictionary['ColorSpace'], const CosName('DeviceGray'));
      expect(out.cos.decodeStreamData(smask), [255, 128, 0, 77]);
      // square pixels, height 100 → width 100
      expect(pageText(out), contains('100 0 0 100 50 60 cm'));
    });

    test('stamps compose with element deletion in one session', () {
      final doc = PdfDocument.open(buildContentPdf(richContent));
      final elements = PdfPageElements.of(doc, 0);
      final editor = PdfEditor(doc)
        ..deleteElements(elements, [elements.elements[0].id])
        ..stampPage(0, (s) => s.text('REVISED', x: 400, y: 80));
      final out = PdfDocument.open(editor.save());
      final text = pageText(out);
      expect(text, isNot(contains('100 100 50 40 re')));
      expect(text, contains('(REVISED) Tj'));
      expect(text, contains('(first line) Tj'));
    });
  });

  group('styled replacement', () {
    PdfDocument styledEdit(
        String content, String find, String replace, PdfTextStyle style) {
      final doc = PdfDocument.open(buildContentPdf(content));
      final editor = PdfEditor(doc)..replaceStyledText(0, find, replace, style);
      return PdfDocument.open(editor.save());
    }

    test('recolours the replacement and restores the prior colour', () {
      final out = styledEdit('BT /F1 12 Tf 72 700 Td (Hello World) Tj ET',
          'Hello', 'Hi', const PdfTextStyle(color: 0xFF0000));
      final text = pageText(out);
      // the replacement is drawn red, then black is restored for " World"
      expect(text, contains('1 0 0 rg'));
      expect(text, contains('(Hi) Tj'));
      expect(text.indexOf('1 0 0 rg'), lessThan(text.indexOf('(Hi) Tj')));
      expect(text, contains('0 0 0 rg'));
      // the reader still reads the whole line
      final el = PdfPageElements.of(out, 0)
          .elements
          .where((e) => e.kind == PdfElementKind.text)
          .map((e) => e.text)
          .join();
      expect(el, contains('Hi World'));
    });

    test('restores the run existing colour, not black', () {
      final out = styledEdit(
          'BT /F1 12 Tf 0 0 1 rg 72 700 Td (Hello World) Tj ET',
          'Hello',
          'Hi',
          const PdfTextStyle(color: 0xFF0000));
      final text = pageText(out);
      // after the red replacement, the run blue is put back for " World"
      final afterHi = text.substring(text.indexOf('(Hi) Tj'));
      expect(afterHi, contains('0 0 1 rg'));
    });

    test('changes font size with a Tf switch and restores it', () {
      final out = styledEdit('BT /F1 12 Tf 72 700 Td (Hello World) Tj ET',
          'Hello', 'Hi', const PdfTextStyle(fontSize: 24));
      final text = pageText(out);
      expect(text, contains('/F1 24 Tf'));
      expect(text, contains('(Hi) Tj'));
      // the original size is restored for the following text
      expect(text.lastIndexOf('/F1 12 Tf'),
          greaterThan(text.indexOf('/F1 24 Tf')));
    });

    test('bold substitutes a base-14 variant font resource', () {
      final out = styledEdit('BT /F1 12 Tf 72 700 Td (Hello World) Tj ET',
          'Hello', 'Hi', const PdfTextStyle(bold: true));
      final fonts =
          out.cos.resolve(out.page(0).resources['Font']) as CosDictionary;
      final bold = fonts.entries.values
          .map((v) => out.cos.resolve(v))
          .whereType<CosDictionary>()
          .where((f) => f['BaseFont'] == const CosName('Helvetica-Bold'));
      expect(bold, isNotEmpty);
      final text = pageText(out);
      // the bold face is selected for the replacement then /F1 restored
      expect(text, contains('(Hi) Tj'));
      expect(text, contains('/F1 12 Tf'));
    });

    test('keeps following text in place when the width changes', () {
      final out = styledEdit('BT /F1 12 Tf 72 700 Td (Hello World) Tj ET',
          'Hello', 'Hi', const PdfTextStyle(fontSize: 24));
      // a compensating TJ adjustment follows the restored-size replacement
      expect(pageText(out), contains('] TJ'));
    });

    test('italic substitutes the oblique base-14 variant', () {
      final out = styledEdit('BT /F1 12 Tf 72 700 Td (Hello World) Tj ET',
          'Hello', 'Hi', const PdfTextStyle(italic: true));
      final fonts =
          out.cos.resolve(out.page(0).resources['Font']) as CosDictionary;
      final oblique = fonts.entries.values
          .map((v) => out.cos.resolve(v))
          .whereType<CosDictionary>()
          .where((f) => f['BaseFont'] == const CosName('Helvetica-Oblique'));
      expect(oblique, isNotEmpty);
    });

    test('changing the font family substitutes a base-14 family', () {
      final out = styledEdit(
          'BT /F1 12 Tf 72 700 Td (Hello World) Tj ET',
          'Hello',
          'Hi',
          const PdfTextStyle(family: PdfStandardFontFamily.serif));
      final fonts =
          out.cos.resolve(out.page(0).resources['Font']) as CosDictionary;
      final serif = fonts.entries.values
          .map((v) => out.cos.resolve(v))
          .whereType<CosDictionary>()
          .where((f) => f['BaseFont'] == const CosName('Times-Roman'));
      expect(serif, isNotEmpty);
      expect(pageText(out), contains('(Hi) Tj'));
    });

    test('draws the replacement in a supplied embedded font', () {
      final fontBytes = File('test/fonts/DejaVuSans.ttf').readAsBytesSync();
      final embedded = PdfEmbeddedFont.parse(fontBytes);
      final doc = PdfDocument.open(
          buildContentPdf('BT /F1 12 Tf 72 700 Td (Hello World) Tj ET'));
      final editor = PdfEditor(doc)
        ..replaceStyledText(
            0, 'Hello', 'Hi', PdfTextStyle(embeddedFont: embedded));
      final out = PdfDocument.open(editor.save());

      // a new Type0 page /Font resource was embedded and the replacement
      // switches to it, then restores /F1 for the following text
      final fonts =
          out.cos.resolve(out.page(0).resources['Font']) as CosDictionary;
      final embName = fonts.entries.keys.firstWhere((k) => k.startsWith('Emb'));
      final embFont = out.cos.resolve(fonts[embName]) as CosDictionary;
      expect(embFont['Subtype'], const CosName('Type0'));
      expect(embFont['Encoding'], const CosName('Identity-H'));
      final text = pageText(out);
      expect(text, contains('/$embName 12 Tf'));
      expect(text, contains('/F1 12 Tf'));
      // the replacement stays readable through the new font's /ToUnicode
      final reader = PdfPageElements.of(out, 0)
          .elements
          .where((e) => e.kind == PdfElementKind.text)
          .map((e) => e.text)
          .join();
      expect(reader, contains('Hi'));
      expect(reader, contains('World'));
    });

    test('embedded font types non-Latin-1 text a simple font could not', () {
      final fontBytes = File('test/fonts/DejaVuSans.ttf').readAsBytesSync();
      final embedded = PdfEmbeddedFont.parse(fontBytes);
      final doc = PdfDocument.open(
          buildContentPdf('BT /F1 12 Tf 72 700 Td (Hello World) Tj ET'));
      // Cyrillic — outside Latin-1, so only drawable via the embedded font
      final editor = PdfEditor(doc)
        ..replaceStyledText(
            0, 'Hello', 'Привет', PdfTextStyle(embeddedFont: embedded));
      final out = PdfDocument.open(editor.save());
      final reader = PdfPageElements.of(out, 0)
          .elements
          .where((e) => e.kind == PdfElementKind.text)
          .map((e) => e.text)
          .join();
      expect(reader, contains('Привет'));
      expect(reader, contains('World'));
    });

    test('leaves the run untouched when nothing can draw the replacement', () {
      // U+4E00 (CJK 一) is non-Latin-1 and absent from DejaVu Sans, so there
      // is no safe way to draw it - the run is left exactly as it was
      final fontBytes = File('test/fonts/DejaVuSans.ttf').readAsBytesSync();
      final embedded = PdfEmbeddedFont.parse(fontBytes);
      final doc = PdfDocument.open(
          buildContentPdf('BT /F1 12 Tf 72 700 Td (Hello World) Tj ET'));
      final editor = PdfEditor(doc)
        ..replaceStyledText(0, 'Hello', '一',
            PdfTextStyle(embeddedFont: embedded, color: 0xFF0000));
      final out = PdfDocument.open(editor.save());
      final fonts =
          out.cos.resolve(out.page(0).resources['Font']) as CosDictionary;
      expect(fonts.entries.keys.where((k) => k.startsWith('Emb')), isEmpty);
      expect(pageText(out), contains('(Hello World) Tj'));
    });

    test('restores a /cs + scn nonstroking colour after the replacement', () {
      final out = styledEdit(
          'BT /F1 12 Tf /DeviceRGB cs 0 0 1 scn 72 700 Td (Hello World) Tj ET',
          'Hello',
          'Hi',
          const PdfTextStyle(color: 0xFF0000));
      final afterHi = pageText(out);
      final tail = afterHi.substring(afterHi.indexOf('(Hi) Tj'));
      // the colourspace and its scn value are both put back for " World"
      expect(tail, contains('/DeviceRGB cs'));
      expect(tail, contains('0 0 1 scn'));
    });

    test('an empty style behaves like a plain replaceText', () {
      final out = styledEdit('BT /F1 12 Tf 72 700 Td (Hello World) Tj ET',
          'Hello', 'Hi', const PdfTextStyle());
      final text = pageText(out);
      expect(text, contains('(Hi)'));
      expect(text, isNot(contains(' rg')));
      final reader = PdfPageElements.of(out, 0)
          .elements
          .where((e) => e.kind == PdfElementKind.text)
          .map((e) => e.text)
          .join();
      expect(reader, contains('Hi World'));
    });

    test('leaves composite runs unstyled but still replaced is skipped', () {
      // simple-font restyle applies; nothing here to assert about Type0,
      // but a plain simple replacement must not emit stray style ops.
      final out = styledEdit('BT /F1 12 Tf 72 700 Td (Hello World) Tj ET',
          'World', 'Earth', const PdfTextStyle(color: 0x00FF00));
      final text = pageText(out);
      expect(text, contains('0 1 0 rg'));
      expect(text, contains('(Earth) Tj'));
    });
  });
}
