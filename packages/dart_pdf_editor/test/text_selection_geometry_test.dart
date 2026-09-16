import 'package:dart_pdf_editor/src/text_selection_geometry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';

void main() {
  test('live selection unions every selected fragment on one line', () {
    final quads = normalizeTextSelectionQuads(const [
      PdfTextQuad([(10, 10), (40, 10), (40, 22), (10, 22)]),
      PdfTextQuad([(50, 10), (120, 10), (120, 22), (50, 22)]),
    ]);
    expect(quads, hasLength(1));
    expect(quads.single.bounds, const PdfRect(10, 10, 120, 22));
  });

  test('live selection keeps separate lines separate', () {
    final quads = normalizeTextSelectionQuads(const [
      PdfTextQuad([(10, 30), (40, 30), (40, 42), (10, 42)]),
      PdfTextQuad([(50, 30), (120, 30), (120, 42), (50, 42)]),
      PdfTextQuad([(10, 10), (40, 10), (40, 22), (10, 22)]),
      PdfTextQuad([(50, 10), (120, 10), (120, 22), (50, 22)]),
    ]);
    expect(quads.map((quad) => quad.bounds), const [
      PdfRect(10, 30, 120, 42),
      PdfRect(10, 10, 120, 22),
    ]);
  });

  test('fragments a column gutter apart stay separate on one line', () {
    const left = PdfTextQuad([(72, 10), (290, 10), (290, 20), (72, 20)]);
    const right = PdfTextQuad([(322, 10), (540, 10), (540, 20), (322, 20)]);
    final quads = normalizeTextSelectionQuads(const [left, right]);
    expect(quads, hasLength(2));
    expect(identical(quads.first, left), isTrue);
    expect(identical(quads.last, right), isTrue);
  });

  test('a rotated singleton keeps its exact corners and direction', () {
    const rotated = PdfTextQuad(
      [(10, 10), (30, 20), (25, 30), (5, 20)],
      isRightToLeft: true,
    );
    final result = normalizeTextSelectionQuads(const [rotated]);
    expect(identical(result.single, rotated), isTrue);
    expect(result.single.corners, rotated.corners);
    expect(result.single.isRightToLeft, isTrue);
  });

  test('rectangle and live-quad normalization use identical line unions', () {
    const rects = [
      PdfRect(10, 30, 40, 42),
      PdfRect(50, 30, 120, 42),
      PdfRect(10, 10, 40, 22),
      PdfRect(50, 10, 120, 22),
    ];
    final quads = [
      for (final rect in rects)
        PdfTextQuad([
          (rect.left, rect.bottom),
          (rect.right, rect.bottom),
          (rect.right, rect.top),
          (rect.left, rect.top),
        ]),
    ];
    expect(
      normalizeTextSelectionQuads(quads).map((quad) => quad.bounds),
      normalizeTextSelectionRects(rects),
    );
  });
}
