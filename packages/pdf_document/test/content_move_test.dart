import 'dart:convert';
import 'dart:typed_data';

import 'package:pdf_cos/pdf_cos.dart';
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

Uint8List buildTwoPageMovePdf() {
  const source = 'BT /F1 12 Tf 72 700 Td (move me) Tj (stay put) Tj ET\n';
  const target = 'BT /F1 12 Tf 72 500 Td (target) Tj ET\n';
  final objects = <String>[
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R 5 0 R] /Count 2 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] '
        '/Contents 4 0 R /Resources << /Font << /F1 7 0 R >> >> >>',
    '<< /Length ${source.length} >>\nstream\n$source\nendstream',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] '
        '/Contents 6 0 R /Resources << /Font << /F1 8 0 R >> >> >>',
    '<< /Length ${target.length} >>\nstream\n$target\nendstream',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Courier >>',
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
  return ascii.encode(buffer.toString());
}

// The rewrite carries the shift through the drawing's own transform, so a
// scaled placement pays one rounding of [ContentWriter.fmt] on the way in.
void expectRect(PdfRect? actual, PdfRect expected,
    {double epsilon = 0.01, String? reason}) {
  expect(actual, isNotNull, reason: reason);
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

    test('moves operators and their resources onto another page', () {
      final doc = PdfDocument.open(buildTwoPageMovePdf());
      final source = PdfPageElements.of(doc, 0);
      final moving = source.elements.singleWhere((e) => e.text == 'move me');
      final staying = source.elements.singleWhere((e) => e.text == 'stay put');
      final movingBefore = moving.bounds!;
      final stayingBefore = staying.bounds!;
      final editor = PdfEditor(doc);

      expect(
        editor.moveElementsToPage(
          source,
          [moving.id],
          1,
          transform: const PdfMatrix.translation(100, -200),
        ),
        1,
      );
      expect(editor.impact.visualPages, {0, 1});
      expect(editor.impact.contentPages, {0, 1});

      final out = PdfDocument.open(editor.save());
      final sourceAfter = PdfPageElements.of(out, 0).elements;
      expect(sourceAfter.map((e) => e.text), ['stay put']);
      expectRect(sourceAfter.single.bounds, stayingBefore,
          reason: 'removing the earlier run must not slide its neighbour');

      final targetAfter = PdfPageElements.of(out, 1).elements;
      expect(targetAfter.map((e) => e.text), ['target', 'move me']);
      final moved = targetAfter.last;
      expect(moved.kind, PdfElementKind.text);
      expectRect(moved.bounds, shift(movingBefore, 100, -200));

      // Both pages called their font /F1, but they meant different fonts.
      // The appended Tf is remapped to the imported Helvetica resource.
      expect(moved.resourceName, isNot('F1'));
      final fonts =
          out.cos.resolve(out.page(1).resources['Font']) as CosDictionary;
      final font = out.cos.resolve(fonts[moved.resourceName!]) as CosDictionary;
      expect(font['BaseFont'], const CosName('Helvetica'));
    });

    test('operationsRetaining drops the others and keeps the geometry', () {
      final doc = PdfDocument.open(buildContentPdf(richContent));
      final elements = PdfPageElements.of(doc, 0);
      final before = boundsOf(doc);

      // "the page without element 1"
      final without = elements.operationsRetaining((e) => e.id != 1);
      // "element 1 by itself"
      final only = elements.operationsRetaining((e) => e.id == 1);

      expect(latin1.decode(ContentStreamSerializer.serialize(without)),
          isNot(contains('(first line)')));
      final onlyText = latin1.decode(ContentStreamSerializer.serialize(only));
      expect(onlyText, contains('(first line)'));
      expect(onlyText, isNot(contains('(second line)')));
      expect(onlyText, isNot(contains('/Im1 Do')));

      // the surviving runs must not have moved in either list: a dropped run
      // hands back the advance it owed the rest of its text object
      PdfRect? boundsIn(List<ContentOperation> ops, String text) {
        final reopened = PdfDocument.open(buildContentPdf(
            latin1.decode(ContentStreamSerializer.serialize(ops))));
        for (final e in PdfPageElements.of(reopened, 0).elements) {
          if (e.text == text) return e.bounds;
        }
        return null;
      }

      expectRect(boundsIn(without, 'second line'), before[2]!);
      expectRect(boundsIn(only, 'first line'), before[1]!);
    });

    test('a dropped mid-line run leaves its neighbours in place', () {
      const content =
          'BT /F1 12 Tf 72 700 Td (one ) Tj (two) Tj 0 -14 Td (three) Tj ET\n';
      final doc = PdfDocument.open(buildContentPdf(content));
      final elements = PdfPageElements.of(doc, 0);
      final before = boundsOf(doc);

      // drop "one ", the run the other two are positioned relative to
      final ops = elements.operationsRetaining((e) => e.id != 0);
      final after = PdfDocument.open(buildContentPdf(
          latin1.decode(ContentStreamSerializer.serialize(ops))));
      final runs = PdfPageElements.of(after, 0).elements;

      expect(runs.map((e) => e.text), ['two', 'three']);
      expectRect(runs[0].bounds, before[1]!,
          reason: 'the rest of the line must not slide left');
      expectRect(runs[1].bounds, before[2]!);
    });

    test('dropping a quote-operator run keeps the lines after it in place', () {
      // `"` carries word/char spacing that outlives the run, and both
      // operators move to the next line before showing - a dropped run owes
      // the text object all of it.
      const content = 'BT /F1 12 Tf 14 TL 72 700 Td (top) Tj '
          '1 2 (middle) " (last) \' ET\n';
      final doc = PdfDocument.open(buildContentPdf(content));
      final elements = PdfPageElements.of(doc, 0);
      final before = boundsOf(doc);
      expect(before, hasLength(3));

      for (final drop in [0, 1]) {
        final ops = elements.operationsRetaining((e) => e.id != drop);
        final after = PdfDocument.open(buildContentPdf(
            latin1.decode(ContentStreamSerializer.serialize(ops))));
        final runs = PdfPageElements.of(after, 0).elements;
        expect(runs.map((e) => e.text), [
          for (var i = 0; i < 3; i++)
            if (i != drop) ['top', 'middle', 'last'][i],
        ]);
        for (final run in runs) {
          final original = before[['top', 'middle', 'last'].indexOf(run.text!)];
          expectRect(run.bounds, original!,
              reason: 'dropping element $drop moved "\${run.text}"');
        }
      }
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
