import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:test/test.dart';

PdfDocument reopened(PdfEditor editor) => PdfDocument.open(editor.save());

/// The page's content streams concatenated, as text.
String contentOf(PdfDocument doc, int index) =>
    String.fromCharCodes(doc.page(index).contentBytes());

List<double> numbers(PdfDocument doc, CosObject? value) {
  final array = doc.cos.resolve(value) as CosArray;
  return [
    for (final item in array.items)
      switch (doc.cos.resolve(item)) {
        CosInteger(:final value) => value.toDouble(),
        CosReal(:final value) => value,
        _ => double.nan,
      },
  ];
}

void main() {
  group('resizePages', () {
    test('scales a Letter page to fit A4, centred, content untouched', () {
      final doc = PdfDocument.open(buildMultiPagePdf(2));
      final before = contentOf(doc, 0);
      final editor = PdfEditor(doc)
        ..resizePages([0], PdfPageSize.a4.width, PdfPageSize.a4.height);
      final out = reopened(editor);
      final page = out.page(0);
      expect(page.mediaBox, PdfRect(0, 0, 595.28, 841.89));
      expect(page.cropBox, page.mediaBox);
      // Letter → A4 is width-bound: s = 595.28 / 612, centred vertically
      const s = 595.28 / 612;
      final dy = (841.89 - 792 * s) / 2;
      final content = contentOf(out, 0);
      expect(content, contains(before));
      final cm = RegExp(r'q ([\d.]+) 0 0 ([\d.]+) ([-\d.]+) ([-\d.]+) cm')
          .firstMatch(content)!;
      expect(double.parse(cm.group(1)!), closeTo(s, 1e-4));
      expect(double.parse(cm.group(3)!), closeTo(0, 1e-3));
      expect(double.parse(cm.group(4)!), closeTo(dy, 1e-3));
      // the old crop box is the clip, so nothing cropped out reappears
      expect(content, contains('0 0 612 792 re W n'));
      expect(content.trimRight(), endsWith('Q'));
      // the other page keeps its size
      expect(out.page(1).mediaBox, const PdfRect(0, 0, 612, 792));
    });

    test('keepContentSize centres the content without scaling it', () {
      final doc = PdfDocument.open(buildMultiPagePdf(1));
      final editor = PdfEditor(doc)
        ..resizePages([0], 712, 892, mode: PdfPageResizeMode.keepContentSize);
      final content = contentOf(reopened(editor), 0);
      expect(content, contains('q 1 0 0 1 50 50 cm'));
    });

    test('a rotated page takes the size as displayed', () {
      final doc = PdfDocument.open(buildMultiPagePdf(1, rotation: 90));
      // landscape A4 as displayed = portrait A4 in the page's own space
      final editor = PdfEditor(doc)
        ..resizePages([0], PdfPageSize.a4.height, PdfPageSize.a4.width);
      final page = reopened(editor).page(0);
      expect(page.rotation, 90);
      expect(page.mediaBox, PdfRect(0, 0, 595.28, 841.89));
    });

    test('a page already at the size is left untouched', () {
      final editor = PdfEditor(PdfDocument.open(buildMultiPagePdf(2)))
        ..resizePages([0, 1], 612, 792);
      expect(editor.hasChanges, isFalse);
    });

    test('an off-origin crop box maps onto the new paper', () {
      final doc = PdfDocument.open(buildMultiPagePdf(1));
      // set up in memory: the resize marks the page dict changed, so the
      // boxes reach the saved revision with it
      doc.page(0).dict
        ..['CropBox'] = CosArray([
          CosInteger(100),
          CosInteger(100),
          CosInteger(400),
          CosInteger(500)
        ])
        ..['TrimBox'] = CosArray([
          CosInteger(110),
          CosInteger(110),
          CosInteger(390),
          CosInteger(490)
        ]);
      final cropped = doc;
      // the visible 300 × 400 area doubles onto 600 × 800
      final editor = PdfEditor(cropped)..resizePages([0], 600, 800);
      final out = reopened(editor);
      final page = out.page(0);
      expect(page.mediaBox, const PdfRect(0, 0, 600, 800));
      expect(page.cropBox, const PdfRect(0, 0, 600, 800));
      expect(numbers(out, page.dict['TrimBox']), [20, 20, 580, 780]);
      expect(contentOf(out, 0), contains('q 2 0 0 2 -200 -200 cm'));
      expect(contentOf(out, 0), contains('100 100 300 400 re W n'));
    });

    test('annotations follow the content', () {
      final doc = PdfDocument.open(buildMultiPagePdf(1));
      final setup = PdfEditor(doc)
        ..addSquare(0, const PdfRect(100, 100, 200, 300))
        ..addInk(0, [
          [(10, 20), (30, 40)],
        ]);
      final annotated = reopened(setup);
      // double the page: every coordinate doubles
      final editor = PdfEditor(annotated)..resizePages([0], 1224, 1584);
      final out = reopened(editor);
      final annots = out.page(0).annotations;
      final square = annots.firstWhere((a) => a.subtype == 'Square');
      expect(square.rect, const PdfRect(200, 200, 400, 600));
      final ink = annots.firstWhere((a) => a.subtype == 'Ink');
      final strokes = out.cos.resolve(ink.dict['InkList']) as CosArray;
      expect(numbers(out, strokes.items.first), [20, 40, 60, 80]);
    });

    test('bad sizes and indices are rejected', () {
      final editor = PdfEditor(PdfDocument.open(buildMultiPagePdf(2)));
      expect(() => editor.resizePages([0], 0, 100), throwsArgumentError);
      expect(() => editor.resizePages([0], 100, -1), throwsArgumentError);
      expect(
          () => editor.resizePages([0], double.nan, 100), throwsArgumentError);
      expect(() => editor.resizePages([4], 100, 100), throwsRangeError);
      expect(editor.hasChanges, isFalse);
    });

    test('saves are incremental: the original bytes survive verbatim', () {
      final original = buildMultiPagePdf(2);
      final editor = PdfEditor(PdfDocument.open(original))
        ..resizePages([0, 1], 300, 300);
      final saved = editor.save();
      expect(saved.sublist(0, original.length), original);
      expect(PdfDocument.open(saved).page(1).mediaBox,
          const PdfRect(0, 0, 300, 300));
    });
  });
}
