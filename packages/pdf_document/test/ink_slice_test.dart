// The circle eraser: pdfSliceInkStrokes (capsule slicing of stroke
// centerlines) and PdfEditor.sliceInk (in-place /InkList, /Rect, and
// appearance rewrite, with pressure recovery from our own appearances).

import 'dart:convert';

import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:test/test.dart';

void main() {
  group('pdfSliceInkStrokes', () {
    test('a crossing eraser splits the stroke at the circle boundary', () {
      // distance from (x, 0) to the vertical spine x = 5 is |x − 5|,
      // so radius 2 cuts exactly [3, 7]
      final result = pdfSliceInkStrokes(
        [
          [(0, 0), (10, 0)],
        ],
        null,
        (5, 5),
        (5, -5),
        2,
      );
      expect(result, isNotNull);
      final strokes = result!.strokes;
      expect(strokes, hasLength(2));
      expect(strokes[0].first, (0, 0));
      expect(strokes[0].last.$1, closeTo(3, 1e-6));
      expect(strokes[0].last.$2, closeTo(0, 1e-6));
      expect(strokes[1].first.$1, closeTo(7, 1e-6));
      expect(strokes[1].last, (10, 0));
      expect(result.pressures, isNull);
    });

    test('an eraser that touches nothing returns null', () {
      final result = pdfSliceInkStrokes(
        [
          [(0, 0), (10, 0)],
        ],
        null,
        (5, 10),
        (5, 4),
        2,
      );
      expect(result, isNull);
    });

    test('a stationary tap erases a circle (degenerate capsule)', () {
      final result = pdfSliceInkStrokes(
        [
          [(0, 0), (10, 0)],
        ],
        null,
        (5, 0),
        (5, 0),
        1.5,
      );
      final strokes = result!.strokes;
      expect(strokes, hasLength(2));
      expect(strokes[0].last.$1, closeTo(3.5, 1e-6));
      expect(strokes[1].first.$1, closeTo(6.5, 1e-6));
    });

    test('dots inside the eraser disappear, dots outside survive', () {
      final result = pdfSliceInkStrokes(
        [
          [(5, 1)],
          [(5, 1), (5, 1)],
          [(20, 0)],
        ],
        null,
        (5, 0),
        (5, 0),
        2,
      );
      final strokes = result!.strokes;
      expect(strokes, hasLength(1));
      expect(strokes.single, [(20, 0)]);
    });

    test('pressures interpolate at the cut boundaries', () {
      final result = pdfSliceInkStrokes(
        [
          [(0, 0), (10, 0)],
        ],
        [
          [0.0, 1.0],
        ],
        (5, 5),
        (5, -5),
        2,
      );
      final pressures = result!.pressures!;
      expect(pressures, hasLength(2));
      expect(pressures[0]!.first, 0);
      expect(pressures[0]!.last, closeTo(0.3, 1e-6));
      expect(pressures[1]!.first, closeTo(0.7, 1e-6));
      expect(pressures[1]!.last, 1);
    });

    test('a cut leaving an invisible crumb drops it', () {
      // the circle reaches x = 9.99; the right-hand remnant is 0.01
      // long - below the visibility floor, so only the left piece stays
      final result = pdfSliceInkStrokes(
        [
          [(0, 0), (10, 0)],
        ],
        null,
        (7.99, 0),
        (7.99, 0),
        2,
      );
      final strokes = result!.strokes;
      expect(strokes, hasLength(1));
      expect(strokes.single.first, (0, 0));
      expect(strokes.single.last.$1, closeTo(5.99, 1e-6));
    });

    test('an eraser engulfing the whole stroke leaves nothing', () {
      final result = pdfSliceInkStrokes(
        [
          [(0, 0), (4, 0), (8, 0)],
        ],
        null,
        (4, 0),
        (4, 0),
        20,
      );
      expect(result!.strokes, isEmpty);
    });

    test('untouched strokes pass through unchanged beside a cut one', () {
      final result = pdfSliceInkStrokes(
        [
          [(0, 50), (10, 50)],
          [(0, 0), (10, 0)],
        ],
        null,
        (5, 0),
        (5, 0),
        2,
      );
      expect(result!.strokes, hasLength(3));
      expect(result.strokes.first, [(0, 50), (10, 50)]);
    });
  });

  group('PdfEditor.sliceInk', () {
    PdfDocument addInk(
      void Function(PdfEditor) edit,
    ) {
      final editor = PdfEditor(PdfDocument.open(buildClassicPdf()));
      edit(editor);
      return PdfDocument.open(editor.save());
    }

    String appearanceText(PdfDocument doc, PdfAnnotation annot) {
      final stream = annot.normalAppearance;
      expect(stream, isNotNull);
      return latin1.decode(doc.cos.decodeStreamData(stream!));
    }

    test('slicing splits the InkList, tightens the rect, and keeps the '
        'annotation dictionary', () {
      final doc = addInk((e) => e.addInk(
            0,
            [
              [(100, 100), (200, 100)],
            ],
            strokeWidth: 4,
            author: 'Ben',
            contents: 'a line',
          ));
      final editor = PdfEditor(doc);
      final changed = editor.sliceInk(
          0, doc.page(0).annotations.single, [(150, 100)], 10);
      expect(changed, isTrue);
      final out = PdfDocument.open(editor.save());

      final ink = out.page(0).annotations.single;
      expect(ink.subtype, 'Ink');
      final strokes = ink.inkList!;
      expect(strokes, hasLength(2));
      expect(strokes[0].last.$1, closeTo(140, 1e-6));
      expect(strokes[1].first.$1, closeTo(160, 1e-6));
      // identity, author, and contents survive the in-place rewrite
      expect((out.cos.resolve(ink.dict['T']) as CosString).text, 'Ben');
      expect(
          (out.cos.resolve(ink.dict['Contents']) as CosString).text, 'a line');
      // the rect still hugs the strokes (pad = width/2 + 1 = 3)
      expect(ink.rect.left, closeTo(97, 1e-6));
      expect(ink.rect.right, closeTo(203, 1e-6));
      // and the regenerated appearance strokes both pieces
      final content = appearanceText(out, ink);
      expect('S\n'.allMatches('$content\n').length, greaterThanOrEqualTo(2));
    });

    test('a path that misses changes nothing', () {
      final doc = addInk((e) => e.addInk(0, [
            [(100, 100), (200, 100)],
          ]));
      final editor = PdfEditor(doc);
      final changed = editor.sliceInk(
          0, doc.page(0).annotations.single, [(150, 300), (160, 300)], 10);
      expect(changed, isFalse);
      expect(editor.hasChanges, isFalse);
    });

    test('erasing every stroke removes the annotation', () {
      final doc = addInk((e) => e.addInk(0, [
            [(100, 100), (110, 100)],
          ]));
      final editor = PdfEditor(doc);
      final changed = editor.sliceInk(
          0, doc.page(0).annotations.single, [(105, 100)], 50);
      expect(changed, isTrue);
      final out = PdfDocument.open(editor.save());
      expect(out.page(0).annotations, isEmpty);
    });

    test('pressure-variable widths survive the cut', () {
      final doc = addInk((e) => e.addInk(
            0,
            [
              [(0, 100), (50, 100), (100, 100)],
            ],
            strokeWidth: 4,
            pressures: [
              [0.0, 0.5, 1.0],
            ],
          ));
      final editor = PdfEditor(doc);
      // a circle at the middle cuts [40, 60]
      final changed = editor.sliceInk(
          0, doc.page(0).annotations.single, [(50, 100)], 10);
      expect(changed, isTrue);
      final out = PdfDocument.open(editor.save());

      final ink = out.page(0).annotations.single;
      expect(ink.inkList, hasLength(2));
      // recovered segment pressures 0.25/0.75, interpolated to the cut:
      // left avg 0.35 → 4×0.82 = 3.28, right avg 0.65 → 4×1.18 = 4.72
      final content = appearanceText(out, ink);
      expect(content, contains('3.28 w'));
      expect(content, contains('4.72 w'));
    });

    test('uniform ink stays uniform after the cut', () {
      final doc = addInk((e) => e.addInk(
            0,
            [
              [(0, 100), (50, 100), (100, 100)],
            ],
            strokeWidth: 4,
          ));
      final editor = PdfEditor(doc);
      editor.sliceInk(0, doc.page(0).annotations.single, [(50, 100)], 10);
      final out = PdfDocument.open(editor.save());
      final content = appearanceText(out, out.page(0).annotations.single);
      // one global width, no per-segment overrides
      expect(RegExp(r'[\d.]+ w').allMatches(content), hasLength(1));
      expect(content, contains('4 w'));
    });

    test('non-ink annotations and inkless ink refuse to slice', () {
      final doc = addInk((e) {
        e.addSquare(0, const PdfRect(100, 100, 200, 200));
      });
      final editor = PdfEditor(doc);
      expect(
          editor.sliceInk(0, doc.page(0).annotations.single, [(150, 150)], 50),
          isFalse);
    });
  });
}
