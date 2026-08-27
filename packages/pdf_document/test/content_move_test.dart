import 'package:pdf_document/pdf_document.dart';
import 'package:test/test.dart';

import 'content_edit_test.dart' show buildContentPdf, pageText, richContent;

/// The bounds of every element on page 0, in paint order.
List<PdfRect?> boundsOf(PdfDocument doc) =>
    [for (final e in PdfPageElements.of(doc, 0).elements) e.bounds];

/// Moves element [id] on page 0 by [dx], [dy] and returns the move count.
int move(PdfDocument doc, int id, double dx, double dy) => PdfEditor(doc)
    .moveElements(PdfPageElements.of(doc, 0), [id], dx: dx, dy: dy);

PdfRect shift(PdfRect rect, double dx, double dy) =>
    PdfRect(rect.left + dx, rect.bottom + dy, rect.right + dx, rect.top + dy);

// The rewrite carries the shift through the drawing's own transform, so a
// scaled placement pays one rounding of [ContentWriter.fmt] on the way in.
void expectRect(PdfRect? actual, PdfRect expected, {double epsilon = 0.01}) {
  expect(actual, isNotNull);
  expect(actual!.left, closeTo(expected.left, epsilon));
  expect(actual.bottom, closeTo(expected.bottom, epsilon));
  expect(actual.right, closeTo(expected.right, epsilon));
  expect(actual.top, closeTo(expected.top, epsilon));
}

void main() {
  group('moving page content', () {
    test('an image moves and nothing else does', () {
      final doc = PdfDocument.open(buildContentPdf(richContent));
      final before = boundsOf(doc);
      expect(move(doc, 3, 20, -30), 1);

      final after = boundsOf(doc);
      expect(after, hasLength(before.length));
      expectRect(after[3], const PdfRect(70, 270, 270, 370));
      for (final i in [0, 1, 2]) {
        expectRect(after[i], before[i]!);
      }
      expect(pageText(doc), contains('/Im1 Do'));
    });

    test('a filled path moves by the page-space delta', () {
      final doc = PdfDocument.open(buildContentPdf(richContent));
      expect(move(doc, 0, -40, 12), 1);
      expectRect(boundsOf(doc)[0], const PdfRect(60, 112, 110, 152));
    });

    test('a text run moves without disturbing the next line', () {
      final doc = PdfDocument.open(buildContentPdf(richContent));
      final before = boundsOf(doc);
      expect(move(doc, 1, 30, -100), 1);

      final elements = PdfPageElements.of(doc, 0).elements;
      // ids and paint order survive: the splices are Tm/TJ, not drawings
      expect(elements, hasLength(4));
      expect(elements[1].text, 'first line');
      expect(elements[2].text, 'second line');
      expectRect(elements[1].bounds, shift(before[1]!, 30, -100));
      // the second line is placed by a relative `Td` off the first line's
      // line matrix - restoring it is the whole point
      expectRect(elements[2].bounds, before[2]!);
    });

    test('a moved run replays its advance so the rest of the line holds', () {
      const content =
          'BT /F1 12 Tf 72 700 Td (one ) Tj (two) Tj 0 -14 Td (three) Tj ET\n';
      final doc = PdfDocument.open(buildContentPdf(content));
      final before = boundsOf(doc);
      expect(move(doc, 0, 0, 50), 1);

      final after = boundsOf(doc);
      expectRect(after[0], shift(before[0]!, 0, 50));
      expectRect(after[1], before[1]!); // same line, after the moved run
      expectRect(after[2], before[2]!); // the next line
    });

    test('a moved run that is not first on its line holds its neighbours', () {
      const content =
          'BT /F1 12 Tf 72 700 Td (one ) Tj (two) Tj 0 -14 Td (three) Tj ET\n';
      final doc = PdfDocument.open(buildContentPdf(content));
      final before = boundsOf(doc);
      expect(move(doc, 1, 0, 50), 1);

      final after = boundsOf(doc);
      expectRect(after[0], before[0]!);
      expectRect(after[1], shift(before[1]!, 0, 50));
      expectRect(after[2], before[2]!);
    });

    test("a `'` run keeps its own line move", () {
      const content = "BT /F1 12 Tf 14 TL 72 700 Td (top) Tj (next) ' "
          "(last) ' ET\n";
      final doc = PdfDocument.open(buildContentPdf(content));
      final before = boundsOf(doc);
      expect(before, hasLength(3));
      expect(move(doc, 1, 100, 0), 1);

      final after = boundsOf(doc);
      expectRect(after[0], before[0]!);
      expectRect(after[1], shift(before[1]!, 100, 0));
      expectRect(after[2], before[2]!);
    });

    test('a rotated placement shifts along the page, not its own axes', () {
      // 90 degree CTM: the drawing's +x runs up the page
      const content = 'q 0 1 -1 0 400 100 cm 0 0 50 20 re f Q\n';
      final doc = PdfDocument.open(buildContentPdf(content));
      expectRect(boundsOf(doc)[0], const PdfRect(380, 100, 400, 150));
      expect(move(doc, 0, 10, 5), 1);
      expectRect(boundsOf(doc)[0], const PdfRect(390, 105, 410, 155));
    });

    test('a scaled placement keeps its scale', () {
      const content = 'q 2 0 0 3 10 20 cm 0 0 10 10 re f Q\n';
      final doc = PdfDocument.open(buildContentPdf(content));
      expectRect(boundsOf(doc)[0], const PdfRect(10, 20, 30, 50));
      expect(move(doc, 0, 5, 5), 1);
      expectRect(boundsOf(doc)[0], const PdfRect(15, 25, 35, 55));
    });

    test('a path that also clips is left alone', () {
      const content = '0 0 100 100 re W f\n';
      final doc = PdfDocument.open(buildContentPdf(content));
      final before = pageText(doc);
      expect(move(doc, 0, 10, 10), 0);
      expect(pageText(doc), before); // untouched, not just unmoved
    });

    test('a zero delta changes nothing', () {
      final doc = PdfDocument.open(buildContentPdf(richContent));
      final before = pageText(doc);
      expect(move(doc, 3, 0, 0), 0);
      expect(pageText(doc), before);
    });

    test('several elements move in one rewrite', () {
      final doc = PdfDocument.open(buildContentPdf(richContent));
      final before = boundsOf(doc);
      expect(
        PdfEditor(doc)
            .moveElements(PdfPageElements.of(doc, 0), [0, 3], dx: 5, dy: 5),
        2,
      );
      final after = boundsOf(doc);
      expectRect(after[0], shift(before[0]!, 5, 5));
      expectRect(after[1], before[1]!);
      expectRect(after[3], shift(before[3]!, 5, 5));
    });

    test('an unknown id is a range error', () {
      final doc = PdfDocument.open(buildContentPdf(richContent));
      final elements = PdfPageElements.of(doc, 0);
      expect(
        () => PdfEditor(doc).moveElements(elements, [9], dx: 1, dy: 1),
        throwsRangeError,
      );
    });

    test('moving twice accumulates', () {
      final doc = PdfDocument.open(buildContentPdf(richContent));
      final before = boundsOf(doc);
      expect(move(doc, 3, 10, 0), 1);
      expect(move(doc, 3, 0, 10), 1);
      expectRect(boundsOf(doc)[3], shift(before[3]!, 10, 10));
    });

    test('a kern-only TJ is not an element', () {
      const content = 'BT /F1 12 Tf 72 700 Td [ -500 ] TJ (word) Tj ET\n';
      final doc = PdfDocument.open(buildContentPdf(content));
      final elements = PdfPageElements.of(doc, 0).elements;
      expect(elements, hasLength(1));
      expect(elements.single.text, 'word');
    });
  });
}
