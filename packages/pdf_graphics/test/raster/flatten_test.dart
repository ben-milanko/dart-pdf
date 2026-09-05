// Parity tests for the flattening port: the golden numbers mirror the
// flutter_gpu experiment's gpu_geometry.dart semantics exactly (Wang's
// bound subdivision count, close handling, dash re-cutting).
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pdf_graphics/pdf_graphics.dart';
import 'package:pdf_graphics/raster.dart';
import 'package:test/test.dart';

void main() {
  group('FloatBuilder/DoubleBuilder', () {
    test('grow past initial capacity and keep contents', () {
      final b = FloatBuilder(4);
      for (var i = 0; i < 100; i++) {
        b.add2(i.toDouble(), (i * 2).toDouble());
      }
      expect(b.length, 200);
      expect(b[0], 0);
      expect(b[199], 198);
      expect(b.bytes.lengthInBytes, 800);
      b.clear();
      expect(b.isEmpty, isTrue);
    });

    test('DoubleBuilder view is a prefix view', () {
      final b = DoubleBuilder(2)..add2(1, 2);
      b.add6(3, 4, 5, 6, 7, 8);
      expect(b.view, [1, 2, 3, 4, 5, 6, 7, 8]);
      b[0] = 9;
      expect(b.view.first, 9);
    });

    test('FloatBuilder add9 grows once and keeps interleaved vertices', () {
      final b = FloatBuilder(2)
        ..add9(1, 2, 3, 4, 5, 6, 7, 8, 9)
        ..add9(10, 11, 12, 13, 14, 15, 16, 17, 18);
      expect(b.length, 18);
      expect(b.view, [
        1,
        2,
        3,
        4,
        5,
        6,
        7,
        8,
        9,
        10,
        11,
        12,
        13,
        14,
        15,
        16,
        17,
        18,
      ]);
      expect(b.bytes.lengthInBytes, 18 * Float32List.bytesPerElement);
    });
  });

  group('flattenPath', () {
    test('lines pass through transformed', () {
      final path = PdfPath([
        PdfMoveTo(0, 0),
        PdfLineTo(10, 0),
        PdfLineTo(10, 5),
      ]);
      final subs =
          flattenPath(path, PdfMatrix(2, 0, 0, 2, 1, 1));
      expect(subs, hasLength(1));
      expect(subs[0].closed, isFalse);
      expect(subs[0].points, [1, 1, 21, 1, 21, 11]);
    });

    test('cubic subdivides per Wang bound (golden: n = 6)', () {
      // Control points (0,0) (10,0) (20,10) (30,10):
      //   d1 = max(|0-20+20|, |0-0+10|)   = 10
      //   d2 = max(|10-40+30|, |0-20+10|) = 10
      //   n  = ceil(sqrt(3*10 / (4*0.25))) = ceil(sqrt(30)) = 6
      final path = PdfPath([
        PdfMoveTo(0, 0),
        PdfCubicTo(10, 0, 20, 10, 30, 10),
      ]);
      final subs = flattenPath(path, PdfMatrix.identity);
      expect(subs, hasLength(1));
      final p = subs[0].points;
      expect(p.length, (1 + 6) * 2);
      // golden points: exact cubic samples at t = i/6
      for (var i = 0; i <= 6; i++) {
        final t = i / 6;
        final mt = 1 - t;
        final bx = 3 * mt * mt * t * 10 + 3 * mt * t * t * 20 + t * t * t * 30;
        final by = 3 * mt * t * t * 10 + t * t * t * 10;
        expect(p[2 * i], closeTo(bx, 1e-12));
        expect(p[2 * i + 1], closeTo(by, 1e-12));
      }
    });

    test('flattened cubic stays within tolerance of the true curve', () {
      final path = PdfPath([
        PdfMoveTo(0, 0),
        PdfCubicTo(0, 55, 100, -55, 100, 0),
      ]);
      const tol = 0.25;
      final subs = flattenPath(path, PdfMatrix.identity, tolerance: tol);
      final p = subs[0].points;
      // sample the true curve densely; every sample must be within ~tol of
      // the polyline
      double distToPolyline(double x, double y) {
        var best = double.infinity;
        for (var i = 0; i + 3 < p.length; i += 2) {
          final ax = p[i], ay = p[i + 1], bx = p[i + 2], by = p[i + 3];
          final vx = bx - ax, vy = by - ay;
          final len2 = vx * vx + vy * vy;
          var t = len2 == 0 ? 0.0 : ((x - ax) * vx + (y - ay) * vy) / len2;
          t = t.clamp(0.0, 1.0);
          final dx = x - (ax + vx * t), dy = y - (ay + vy * t);
          final d = math.sqrt(dx * dx + dy * dy);
          if (d < best) best = d;
        }
        return best;
      }

      for (var i = 0; i <= 500; i++) {
        final t = i / 500;
        final mt = 1 - t;
        final bx = 3 * mt * mt * t * 0 +
            3 * mt * t * t * 100 +
            t * t * t * 100;
        final by = 3 * mt * mt * t * 55 + 3 * mt * t * t * -55;
        expect(distToPolyline(bx, by), lessThanOrEqualTo(tol * 1.05),
            reason: 't=$t');
      }
    });

    test('close appends the start point and marks the subpath closed', () {
      final path = PdfPath([
        PdfMoveTo(0, 0),
        PdfLineTo(4, 0),
        PdfLineTo(4, 4),
        PdfClosePath(),
      ]);
      final subs = flattenPath(path, PdfMatrix.identity);
      expect(subs, hasLength(1));
      expect(subs[0].closed, isTrue);
      expect(subs[0].points, [0, 0, 4, 0, 4, 4, 0, 0]);
    });

    test('m..h m.. produces two subpaths; drops empty ones', () {
      final path = PdfPath([
        PdfMoveTo(0, 0),
        PdfLineTo(1, 0),
        PdfClosePath(),
        PdfMoveTo(5, 5),
        PdfLineTo(6, 5),
        PdfMoveTo(9, 9), // lone move: dropped
      ]);
      final subs = flattenPath(path, PdfMatrix.identity);
      expect(subs, hasLength(2));
      expect(subs[0].closed, isTrue);
      expect(subs[1].closed, isFalse);
      expect(subs[1].points, [5, 5, 6, 5]);
    });

    test('FlatBounds covers all subpaths', () {
      final subs = flattenPath(
          PdfPath([
            PdfMoveTo(1, 2),
            PdfLineTo(5, -3),
            PdfMoveTo(-4, 0),
            PdfLineTo(0, 7),
          ]),
          PdfMatrix.identity);
      final b = FlatBounds.of(subs)!;
      expect([b.left, b.top, b.right, b.bottom], [-4, -3, 5, 7]);
    });
  });

  group('dashSubpaths', () {
    FlatSubpath line(double x0, double y0, double x1, double y1) =>
        FlatSubpath(Float64List.fromList([x0, y0, x1, y1]), closed: false);

    test('golden: [4,2] over a length-10 line', () {
      final out = dashSubpaths([line(0, 0, 10, 0)], [4, 2], 0);
      expect(out, hasLength(2));
      expect(out[0].points, [0, 0, 4, 0]);
      expect(out[1].points, [6, 0, 10, 0]);
    });

    test('golden: phase 5 starts inside the gap', () {
      final out = dashSubpaths([line(0, 0, 10, 0)], [4, 2], 5);
      expect(out, hasLength(2));
      expect(out[0].points, [1, 0, 5, 0]);
      expect(out[1].points, [7, 0, 10, 0]);
    });

    test('odd pattern doubles (§8.4.3.6)', () {
      final out = dashSubpaths([line(0, 0, 9, 0)], [3], 0);
      // effective [3,3]: on 0-3, off 3-6, on 6-9
      expect(out, hasLength(2));
      expect(out[0].points, [0, 0, 3, 0]);
      expect(out[1].points, [6, 0, 9, 0]);
    });

    test('empty/zero pattern passes through', () {
      final subs = [line(0, 0, 10, 0)];
      expect(dashSubpaths(subs, [], 0), same(subs));
      expect(dashSubpaths(subs, [0, 0], 0), same(subs));
    });

    test('dashes continue across polyline corners', () {
      final sub = FlatSubpath(
          Float64List.fromList([0, 0, 5, 0, 5, 5]), closed: false);
      final out = dashSubpaths([sub], [6, 2], 0);
      // first dash runs 6 units: 5 along x then 1 down the corner
      expect(out[0].points, [0, 0, 5, 0, 5, 1]);
      expect(out[1].points, [5, 3, 5, 5]);
    });
  });

  group('FlattenedOutline', () {
    test('caches per outline identity', () {
      final outline = PdfPath([
        PdfMoveTo(0, 0),
        PdfCubicTo(0.2, 0.6, 0.5, 0.7, 0.7, 0),
        PdfClosePath(),
      ]);
      final a = FlattenedOutline.of(outline);
      final b = FlattenedOutline.of(outline);
      expect(identical(a, b), isTrue);
      expect(a.subpaths, isNotEmpty);
      // a different instance with equal segments flattens separately
      final other = PdfPath(outline.segments);
      expect(identical(FlattenedOutline.of(other), a), isFalse);
    });

    test('em-space flattening is fine enough for a 64-px em', () {
      // half-circle-ish bowl in em units
      final outline = PdfPath([
        PdfMoveTo(0, 0),
        PdfCubicTo(0, 0.55, 1, 0.55, 1, 0),
        PdfClosePath(),
      ]);
      final flat = FlattenedOutline.of(outline);
      final p = flat.subpaths[0].points;
      // deviation from the true curve at 64 px/em must stay ~0.25 px
      expect(p.length ~/ 2, greaterThan(8));
    });
  });
}
