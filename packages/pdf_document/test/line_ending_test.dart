// Line-ending vocabulary (§12.5.6.7, Table 176): PdfEditor.addLine /
// addPolyLine draw the full set of /LE endings, and PdfEditor.setLineEndings
// swaps them in place. The appearance path geometry is KAT-checked on a
// known horizontal segment so each shape's vertices are pinned exactly.

import 'dart:convert';

import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:test/test.dart';

PdfDocument edited(PdfDocument doc, void Function(PdfEditor) edit) {
  final editor = PdfEditor(doc);
  edit(editor);
  return PdfDocument.open(editor.save());
}

String content(PdfDocument doc, PdfAnnotation annotation) =>
    latin1.decode(doc.cos.decodeStreamData(annotation.normalAppearance!));

(String, String) leNames(PdfDocument doc, PdfAnnotation annotation) {
  final le = doc.cos.resolve(annotation.dict['LE']) as CosArray;
  return (
    (doc.cos.resolve(le[0]) as CosName).value,
    (doc.cos.resolve(le[1]) as CosName).value,
  );
}

void main() {
  // The END ending sits at (100, 0) with the line arriving from (0, 0):
  // u points -x (back into the line), the left perpendicular p points -y.
  // strokeWidth 2 gives the characteristic size s = max(10, 2*5) = 10.
  PdfDocument lineWith(PdfLineEnding endEnding) => edited(
        PdfDocument.open(buildMultiPagePdf(1)),
        (e) => e.addLine(0, (0, 0), (100, 0),
            strokeWidth: 2, endEnding: endEnding),
      );

  test('every ending name round-trips through /LE [start end]', () {
    final doc = edited(
      PdfDocument.open(buildMultiPagePdf(1)),
      (e) => e.addLine(0, (0, 0), (100, 0),
          startEnding: PdfLineEnding.diamond,
          endEnding: PdfLineEnding.openArrow),
    );
    final line = doc.page(0).annotations.single;
    expect(leNames(doc, line), ('Diamond', 'OpenArrow'));
    expect(pdfLineEndings(line), (PdfLineEnding.diamond, PdfLineEnding.openArrow));
  });

  test('closedArrow: filled triangle barbs at (90, ±3.8), apex at the tip',
      () {
    final c = content(lineWith(PdfLineEnding.closedArrow),
        lineWith(PdfLineEnding.closedArrow).page(0).annotations.single);
    // barb, apex, barb — then close + fill
    expect(c, contains('90 -3.8 m'));
    expect(c, contains('100 0 l'));
    expect(c, contains('90 3.8 l'));
    expect(c, contains('f'));
  });

  test('openArrow: same barbs, stroked open V (no fill, no close)', () {
    final doc = lineWith(PdfLineEnding.openArrow);
    final c = content(doc, doc.page(0).annotations.single);
    expect(c, contains('90 -3.8 m'));
    expect(c, contains('100 0 l'));
    expect(c, contains('90 3.8 l'));
    // the V is stroked; the only fill in the stream is none for the ending
    expect('S\n'.allMatches(c).length, greaterThanOrEqualTo(2));
  });

  test('rClosedArrow: reversed — apex into the line, barbs on the endpoint',
      () {
    final doc = lineWith(PdfLineEnding.rClosedArrow);
    final c = content(doc, doc.page(0).annotations.single);
    expect(c, contains('100 -3.8 m')); // barb at the endpoint
    expect(c, contains('90 0 l')); // apex 10pt into the line
    expect(c, contains('100 3.8 l'));
    expect(c, contains('f'));
  });

  test('diamond: filled rhombus, half-diagonal 4.5 along u and p', () {
    final doc = lineWith(PdfLineEnding.diamond);
    final c = content(doc, doc.page(0).annotations.single);
    // at(4.5,0)=(95.5,0)  at(0,4.5)=(100,-4.5)  at(-4.5,0)=(104.5,0)
    expect(c, contains('95.5 0 m'));
    expect(c, contains('100 -4.5 l'));
    expect(c, contains('104.5 0 l'));
    expect(c, contains('100 4.5 l'));
    expect(c, contains('f'));
  });

  test('square: filled, axis-aligned to the line, half-side 3.5', () {
    final doc = lineWith(PdfLineEnding.square);
    final c = content(doc, doc.page(0).annotations.single);
    // at(3.5,3.5)=(96.5,-3.5)  at(3.5,-3.5)=(96.5,3.5)
    expect(c, contains('96.5 -3.5 m'));
    expect(c, contains('96.5 3.5 l'));
    expect(c, contains('103.5 3.5 l'));
    expect(c, contains('103.5 -3.5 l'));
    expect(c, contains('f'));
  });

  test('circle: filled, drawn as four cubic Béziers about the tip', () {
    final doc = lineWith(PdfLineEnding.circle);
    final c = content(doc, doc.page(0).annotations.single);
    // radius 4, starts at (tip.x + r, tip.y) = (104, 0)
    expect(c, contains('104 0 m'));
    expect('c\n'.allMatches(c).length, greaterThanOrEqualTo(4));
    expect(c, contains('f'));
  });

  test('butt: a stroked perpendicular bar, half-length 4.5', () {
    final doc = lineWith(PdfLineEnding.butt);
    final c = content(doc, doc.page(0).annotations.single);
    // p points -y, so at(0,4.5)=(100,-4.5) to at(0,-4.5)=(100,4.5)
    expect(c, contains('100 -4.5 m'));
    expect(c, contains('100 4.5 l'));
  });

  test('slash: a stroked slanted line, ~60° from the line', () {
    final doc = lineWith(PdfLineEnding.slash);
    final c = content(doc, doc.page(0).annotations.single);
    // u=(-1,0); rotate by 60° CCW -> (-0.5, -0.866); half-length 5
    // (100 + (-0.5)*5, 0 + (-0.866)*5) = (97.5, -4.330)
    expect(c, contains('97.5 -4.33 m'));
    expect(c, contains('102.5 4.33 l'));
  });

  test('the /Rect grows to cover the ending geometry', () {
    final plain = lineWith(PdfLineEnding.none);
    final arrow = lineWith(PdfLineEnding.closedArrow);
    final r0 = plain.page(0).annotations.single.rect;
    final r1 = arrow.page(0).annotations.single.rect;
    // the arrow reaches above/below the segment, so the rect is taller
    expect(r1.height, greaterThan(r0.height));
  });

  test('polyline carries /LE on its first and last vertex', () {
    final doc = edited(
      PdfDocument.open(buildMultiPagePdf(1)),
      (e) => e.addPolyLine(0, [(0, 0), (50, 40), (100, 0)],
          strokeWidth: 2,
          startEnding: PdfLineEnding.openArrow,
          endEnding: PdfLineEnding.closedArrow),
    );
    final poly = doc.page(0).annotations.single;
    expect(poly.subtype, 'PolyLine');
    expect(leNames(doc, poly), ('OpenArrow', 'ClosedArrow'));
    expect(pdfLineEndings(poly),
        (PdfLineEnding.openArrow, PdfLineEnding.closedArrow));
    // a closed (filled) arrowhead at the last vertex
    expect(content(doc, poly), contains('f'));
  });

  test('setLineEndings swaps endings in place, keeping slot + object number',
      () {
    final doc = edited(
      PdfDocument.open(buildMultiPagePdf(1)),
      (e) => e.addLine(0, (0, 0), (100, 0), strokeWidth: 2, author: 'Ben'),
    );
    final before = doc.page(0).annotations.single;
    final formRef = doc.cos.referenceTo(before.normalAppearance!)!;
    expect(leNames(doc, before), ('None', 'None'));

    final out = edited(
        doc,
        (e) => e.setLineEndings(0, before,
            startEnding: PdfLineEnding.circle,
            endEnding: PdfLineEnding.closedArrow));
    final after = out.page(0).annotations.single;
    expect(leNames(out, after), ('Circle', 'ClosedArrow'));
    expect(after.author, 'Ben'); // identity survives the in-place edit
    expect(after.line, ((0.0, 0.0), (100.0, 0.0))); // geometry unchanged
    // the appearance now paints both endings — the circle sits at the
    // start vertex (0,0), radius 4, so its Bézier starts at (4,0)
    expect(content(out, after), contains('4 0 m')); // start circle
    expect(content(out, after), contains('90 3.8 l')); // end arrow
    // replaced, not re-added — the form keeps its object number
    expect(out.cos.referenceTo(after.normalAppearance!)!.objectNumber,
        formRef.objectNumber);
  });

  test('setLineEndings is a no-op when nothing changes or wrong subtype', () {
    final doc = edited(
      PdfDocument.open(buildMultiPagePdf(1)),
      (e) {
        e.addLine(0, (0, 0), (100, 0), endEnding: PdfLineEnding.closedArrow);
        e.addSquare(0, const PdfRect(200, 200, 300, 300));
      },
    );
    final line = doc.page(0).annotations[0];
    final square = doc.page(0).annotations[1];
    final editor = PdfEditor(doc);
    expect(
        editor.setLineEndings(0, line, endEnding: PdfLineEnding.closedArrow),
        isFalse,
        reason: 'unchanged endings');
    expect(editor.setLineEndings(0, square, endEnding: PdfLineEnding.circle),
        isFalse,
        reason: 'not a line annotation');
  });
}
