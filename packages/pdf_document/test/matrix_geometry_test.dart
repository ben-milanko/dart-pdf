import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:test/test.dart';

void main() {
  group('boundsOfPoints', () {
    test('is null for an empty list', () {
      expect(boundsOfPoints(const []), isNull);
    });

    test('is the axis-aligned hull of the points', () {
      final r = boundsOfPoints(const [(1, 2), (5, -1), (3, 9)])!;
      expect([r.left, r.bottom, r.right, r.top], [1, -1, 5, 9]);
    });
  });

  group('boundsUnderMatrix', () {
    test('identity gives the box back', () {
      const box = PdfRect(2, 3, 10, 20);
      final r = boundsUnderMatrix(PdfMatrix.identity, box);
      expect([r.left, r.bottom, r.right, r.top], [2, 3, 10, 20]);
    });

    test('a 90-degree rotation swaps and negates axes into a tight box', () {
      const box = PdfRect(0, 0, 4, 2);
      // rotate CCW 90 about the origin: (x,y) -> (-y, x)
      const rot = PdfMatrix(0, 1, -1, 0, 0, 0);
      final r = boundsUnderMatrix(rot, box);
      expect([r.left, r.bottom, r.right, r.top], [-2, 0, 0, 4]);
    });
  });

  group('fitFormToRect (§12.5.5)', () {
    test('maps a translated/scaled BBox exactly onto the target rect', () {
      const bbox = PdfRect(0, 0, 100, 50);
      const rect = PdfRect(10, 20, 30, 60); // width 20, height 40
      final fit = fitFormToRect(bbox, PdfMatrix.identity, rect);
      // the BBox corners, mapped by matrix (identity) then the fit, must
      // land on the rect corners.
      final combined = PdfMatrix.identity.concat(fit);
      expect(combined.apply(0, 0), (10.0, 20.0));
      expect(combined.apply(100, 50), (30.0, 60.0));
    });

    test('accounts for the form /Matrix when computing the fit', () {
      const bbox = PdfRect(0, 0, 10, 10);
      // the form scales its own artwork 2x before the fit
      const formMatrix = PdfMatrix(2, 0, 0, 2, 0, 0);
      const rect = PdfRect(0, 0, 40, 40);
      final fit = fitFormToRect(bbox, formMatrix, rect);
      final combined = formMatrix.concat(fit);
      // transformed bbox bounds are 0..20; fitting onto 0..40 doubles again
      expect(combined.apply(0, 0), (0.0, 0.0));
      expect(combined.apply(10, 10), (40.0, 40.0));
    });

    test('degenerate axis falls back to unit scale (no NaN/Inf)', () {
      const bbox = PdfRect(0, 0, 0, 10); // zero width
      const rect = PdfRect(5, 5, 25, 45);
      final fit = fitFormToRect(bbox, PdfMatrix.identity, rect);
      expect(fit.a, 1.0); // x axis kept at unit scale
      expect(fit.d, closeTo((45 - 5) / 10, 1e-12));
      expect(fit.e.isFinite, isTrue);
      expect(fit.f.isFinite, isTrue);
    });
  });
}
