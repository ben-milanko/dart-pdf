import 'dart:convert';
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

    test('erasing a region clips partial hits instead of dropping them', () {
      final doc = PdfDocument.open(buildContentPdf(richContent));
      final elements = PdfPageElements.of(doc, 0);
      final editor = PdfEditor(doc);
      expect(
          editor.eraseElementsInRect(
              elements, const PdfRect(115, 110, 125, 120)),
          1);

      final out = PdfDocument.open(editor.save());
      final text = pageText(out);
      expect(text, contains('100 100 50 40 re'));
      expect(text, contains('W n'));
      expect(text, contains('Q'));
      expect(
          PdfPageElements.of(out, 0)
              .elements
              .where((e) => e.kind == PdfElementKind.path),
          hasLength(1));
    });

    test('erasing a region deletes fully-covered hits', () {
      final doc = PdfDocument.open(buildContentPdf(richContent));
      final elements = PdfPageElements.of(doc, 0);
      final editor = PdfEditor(doc);
      expect(
          editor.eraseElementsInRect(elements, const PdfRect(95, 95, 155, 145)),
          1);

      final out = PdfDocument.open(editor.save());
      expect(pageText(out), isNot(contains('100 100 50 40 re')));
      expect(
          PdfPageElements.of(out, 0)
              .elements
              .where((e) => e.kind == PdfElementKind.path),
          isEmpty);
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

    test('a miss returns zero and queues nothing', () {
      final editor = PdfEditor(PdfDocument.open(buildMultiPagePdf(1)));
      expect(editor.replaceText(0, 'absent text', 'x'), 0);
      expect(editor.hasChanges, isFalse);
    });

    test('TJ string elements replace individually', () {
      final doc = PdfDocument.open(
          buildContentPdf('BT /F1 12 Tf 72 700 Td [(spli) -20 (t run)] TJ ET'));
      final editor = PdfEditor(doc);
      // a match across the split is honestly out of reach
      expect(editor.replaceText(0, 'split', 'joined'), 0);
      expect(editor.replaceText(0, 't run', 't sprint'), 1);
      final out = PdfDocument.open(editor.save());
      expect(pageText(out), contains('(t sprint)'));
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
}
