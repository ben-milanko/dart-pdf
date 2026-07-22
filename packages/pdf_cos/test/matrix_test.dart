import 'dart:math' as math;

import 'package:pdf_cos/pdf_cos.dart';
import 'package:test/test.dart';

void main() {
  group('PdfMatrix', () {
    test('identity leaves points and matrices unchanged', () {
      expect(PdfMatrix.identity.apply(3, 7), (3.0, 7.0));
      const m = PdfMatrix(2, 0, 0, 3, 4, 5);
      final r = m.concat(PdfMatrix.identity);
      expect([r.a, r.b, r.c, r.d, r.e, r.f], [2, 0, 0, 3, 4, 5]);
    });

    test('apply matches the row-vector formula', () {
      const m = PdfMatrix(2, 0, 0, 3, 10, 20);
      expect(m.apply(4, 5), (2 * 4 + 10.0, 3 * 5 + 20.0));
      expect(m.transformX(4, 5), 2 * 4 + 10.0);
      expect(m.transformY(4, 5), 3 * 5 + 20.0);
    });

    test('concat applies this first, then after (row-vector product)', () {
      // scale-by-2 then translate-by-(1,1): a point (x,y) -> (2x+1, 2y+1)
      final m = PdfMatrix.scaled(2, 2).concat(PdfMatrix.translation(1, 1));
      expect(m.apply(3, 4), (7.0, 9.0));
      // order matters: translate first then scale -> (2(x+1), 2(y+1))
      final n = PdfMatrix.translation(1, 1).concat(PdfMatrix.scaled(2, 2));
      expect(n.apply(3, 4), (8.0, 10.0));
    });

    test('translation.concat matches the old six-locals translate', () {
      // The content extractor / reflow updated a running (a..f) with
      // e += tx*a + ty*c; f += tx*b + ty*d. That is exactly
      // translation(tx,ty).concat(current).
      const current = PdfMatrix(1.5, 0.2, -0.1, 2.0, 30, 40);
      const tx = 5.0, ty = -3.0;
      final viaConcat = PdfMatrix.translation(tx, ty).concat(current);
      final e = tx * current.a + ty * current.c + current.e;
      final f = tx * current.b + ty * current.d + current.f;
      expect(viaConcat.e, closeTo(e, 1e-12));
      expect(viaConcat.f, closeTo(f, 1e-12));
      // the linear part is untouched by a pure translation
      expect([viaConcat.a, viaConcat.b, viaConcat.c, viaConcat.d],
          [current.a, current.b, current.c, current.d]);
    });

    test('concat is associative', () {
      const a = PdfMatrix(1, 2, 3, 4, 5, 6);
      const b = PdfMatrix(0.5, 0, 0, 0.5, 1, 1);
      const c = PdfMatrix(2, 0, -1, 3, -2, 4);
      final left = a.concat(b).concat(c);
      final right = a.concat(b.concat(c));
      expect(left, right);
    });

    test('inverted round-trips a point', () {
      final m = PdfMatrix.translation(10, -4)
          .concat(PdfMatrix(math.cos(0.7), math.sin(0.7), -math.sin(0.7),
              math.cos(0.7), 0, 0))
          .concat(PdfMatrix.scaled(2, 3));
      final inv = m.inverted()!;
      final (x, y) = m.apply(6, -8);
      final (bx, by) = inv.apply(x, y);
      expect(bx, closeTo(6, 1e-9));
      expect(by, closeTo(-8, 1e-9));
    });

    test('inverted returns null on a degenerate matrix', () {
      expect(const PdfMatrix(0, 0, 0, 0, 5, 5).inverted(), isNull);
    });

    test('row reads an [a b c d e f] array; short/null falls back', () {
      expect(PdfMatrix.row([2, 0, 0, 3, 4, 5]), const PdfMatrix(2, 0, 0, 3, 4, 5));
      expect(PdfMatrix.row(null), PdfMatrix.identity);
      expect(PdfMatrix.row([1, 2]), PdfMatrix.identity);
    });

    test('toList round-trips through row', () {
      const m = PdfMatrix(1.25, -0.5, 0.75, 2, -3, 8);
      expect(PdfMatrix.row(m.toList()), m);
    });

    test('scaleFactor is the sqrt of the absolute determinant', () {
      expect(PdfMatrix.scaled(2, 8).scaleFactor, closeTo(4, 1e-12));
    });

    test('equality and hashCode are structural', () {
      const a = PdfMatrix(1, 2, 3, 4, 5, 6);
      const same = PdfMatrix(1, 2, 3, 4, 5, 6);
      const differs = PdfMatrix(1, 2, 3, 4, 5, 7); // only f differs
      expect(a, same);
      expect(a.hashCode, same.hashCode);
      expect(a == differs, isFalse);
      expect(a == Object(), isFalse); // not a PdfMatrix
    });

    test('toString lists the six components', () {
      expect(const PdfMatrix(1, 2, 3, 4, 5, 6).toString(),
          'PdfMatrix(1.0, 2.0, 3.0, 4.0, 5.0, 6.0)');
    });
  });
}
