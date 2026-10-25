import 'package:pdf_graphics/pdf_graphics.dart';
import 'package:test/test.dart';

PdfPath _path(List<PdfPathSegment> segments) => PdfPath(segments);

void main() {
  group('pdfPathAxisAlignedRects', () {
    test('reads an `re` subpath as left, bottom, right, top', () {
      final rects = pdfPathAxisAlignedRects(_path(const [
        PdfMoveTo(10, 20),
        PdfLineTo(110, 20),
        PdfLineTo(110, 20.5),
        PdfLineTo(10, 20.5),
        PdfClosePath(),
      ]));
      expect(rects, [10, 20, 110, 20.5]);
    });

    test('takes either winding, a repeated start point and no close', () {
      final rects = pdfPathAxisAlignedRects(_path(const [
        PdfMoveTo(5, 5),
        PdfLineTo(5, 1),
        PdfLineTo(1, 1),
        PdfLineTo(1, 5),
        PdfLineTo(5, 5),
        PdfMoveTo(0, 0),
        PdfLineTo(0, 2),
        PdfLineTo(3, 2),
        PdfLineTo(3, 0),
      ]));
      expect(rects, [1, 1, 5, 5, 0, 0, 3, 2]);
    });

    test('a zero-thickness rectangle still counts', () {
      expect(
          pdfPathAxisAlignedRects(_path(const [
            PdfMoveTo(0, 0),
            PdfLineTo(10, 0),
            PdfLineTo(10, 0),
            PdfLineTo(0, 0),
            PdfClosePath(),
          ])),
          [0, 0, 10, 0]);
    });

    test('rejects curves, slanted edges and other corner counts', () {
      expect(
          pdfPathAxisAlignedRects(_path(const [
            PdfMoveTo(0, 0),
            PdfLineTo(10, 0),
            PdfCubicTo(10, 1, 10, 2, 10, 3),
            PdfLineTo(0, 3),
            PdfClosePath(),
          ])),
          isNull);
      expect(
          pdfPathAxisAlignedRects(_path(const [
            PdfMoveTo(0, 0),
            PdfLineTo(10, 1),
            PdfLineTo(10, 3),
            PdfLineTo(0, 3),
            PdfClosePath(),
          ])),
          isNull);
      expect(
          pdfPathAxisAlignedRects(_path(const [
            PdfMoveTo(0, 0),
            PdfLineTo(10, 0),
            PdfLineTo(10, 3),
            PdfClosePath(),
          ])),
          isNull);
      // one rectangle and one triangle: the whole path is not rectangles
      expect(
          pdfPathAxisAlignedRects(_path(const [
            PdfMoveTo(0, 0),
            PdfLineTo(10, 0),
            PdfLineTo(10, 3),
            PdfLineTo(0, 3),
            PdfClosePath(),
            PdfMoveTo(20, 0),
            PdfLineTo(30, 0),
            PdfLineTo(30, 3),
            PdfClosePath(),
          ])),
          isNull);
      expect(pdfPathAxisAlignedRects(_path(const [])), isNull);
    });
  });

  group('pdfThinRectFill', () {
    PdfPath rects(List<List<double>> boxes) => PdfPath([
          for (final [l, b, r, t] in boxes) ...[
            PdfMoveTo(l, b),
            PdfLineTo(r, b),
            PdfLineTo(r, t),
            PdfLineTo(l, t),
            const PdfClosePath(),
          ],
        ]);

    test('a table corner - rules meeting at right angles - is rules', () {
      expect(
          pdfThinRectFill(
              rects([
                [0, 0, 100, 0.5],
                [0, 0, 0.5, 100],
                [0, 99.5, 100, 100],
              ]),
              2),
          isNotNull);
    });

    test('parallel rows stacked edge to edge are an area, not rules', () {
      // a traced bitmap: 0.66 pt rows, as in Ghent GWG080's checkmarks
      expect(
          pdfThinRectFill(
              rects([
                [10, 0, 20, 0.66],
                [12, 0.66, 22, 1.32],
              ]),
              2),
          isNull);
      // parallel rules with a gap between them are still rules
      expect(
          pdfThinRectFill(
              rects([
                [10, 0, 20, 0.5],
                [10, 1.5, 20, 2],
              ]),
              2),
          isNotNull);
    });

    test('one thick rectangle keeps the whole path exact', () {
      expect(
          pdfThinRectFill(
              rects([
                [0, 0, 100, 20],
                [0, 10, 100, 10.5],
              ]),
              2),
          isNull);
    });
  });
}
