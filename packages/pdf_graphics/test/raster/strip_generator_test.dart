// Coverage correctness of the sparse-strip fine raster vs a brute-force
// supersampling reference (tolerance +-2/255 mean per shape), plus the
// strip-emission structure invariants (solid runs, alpha layout, sentinel,
// packing, viewport clipping, buffer reuse).
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pdf_graphics/pdf_graphics.dart';
import 'package:pdf_graphics/raster.dart';
import 'package:test/test.dart';

import 'reference_raster.dart';

final int black = premulRgba8(PdfColor.black, 1);

PdfPath polyPath(List<double> pts, {bool close = true}) {
  final segs = <PdfPathSegment>[PdfMoveTo(pts[0], pts[1])];
  for (var i = 2; i < pts.length; i += 2) {
    segs.add(PdfLineTo(pts[i], pts[i + 1]));
  }
  if (close) segs.add(const PdfClosePath());
  return PdfPath(segs);
}

Float64List ring(List<double> pts) => Float64List.fromList(pts);

void expectCoverage(StripGenerator gen, List<Float64List> rings, bool evenOdd,
    int w, int h,
    {int ss = 16, double tol = 2.0}) {
  final got = decodeStripCoverage(gen.strips, w, h);
  final want = referenceCoverage(rings, evenOdd, w, h, ss: ss);
  expect(meanAbsDiff(got, want), lessThanOrEqualTo(tol));
}

void main() {
  group('coverage vs reference', () {
    test('convex polygon (fractional pentagon)', () {
      const pts = [4.3, 2.2, 19.7, 5.1, 21.4, 16.8, 11.0, 21.6, 2.6, 13.4];
      final gen = StripGenerator()..begin(24, 24);
      gen.fillPath(polyPath(pts), PdfMatrix.identity, PdfFillRule.nonzero,
          black);
      expectCoverage(gen, [ring(pts)], false, 24, 24);
    });

    test('self-intersecting star, nonzero', () {
      // classic 5-point star drawn edge-to-edge (self-intersecting)
      final pts = <double>[];
      for (var i = 0; i < 5; i++) {
        final a = -1.5707963267948966 + i * 4 * 3.141592653589793 / 5;
        pts.addAll([12 + 10 * _cos(a), 12 + 10 * _sin(a)]);
      }
      final gen = StripGenerator()..begin(24, 24);
      gen.fillPath(polyPath(pts), PdfMatrix.identity, PdfFillRule.nonzero,
          black);
      expectCoverage(gen, [ring(pts)], false, 24, 24);
    });

    test('self-intersecting star, even-odd (hollow core)', () {
      final pts = <double>[];
      for (var i = 0; i < 5; i++) {
        final a = -1.5707963267948966 + i * 4 * 3.141592653589793 / 5;
        pts.addAll([12 + 10 * _cos(a), 12 + 10 * _sin(a)]);
      }
      final gen = StripGenerator()..begin(24, 24);
      gen.fillPath(polyPath(pts), PdfMatrix.identity, PdfFillRule.evenOdd,
          black);
      expectCoverage(gen, [ring(pts)], true, 24, 24);
    });

    test('nonzero hole ring vs even-odd', () {
      // outer CW + inner CCW: nonzero keeps the hole
      const outer = <double>[2.0, 2, 22, 2, 22, 22, 2, 22];
      const innerRev = <double>[8.0, 16, 16, 16, 16, 8, 8, 8]; // reversed winding
      final path = PdfPath([
        PdfMoveTo(2, 2), PdfLineTo(22, 2), PdfLineTo(22, 22),
        PdfLineTo(2, 22), const PdfClosePath(), //
        PdfMoveTo(8, 16), PdfLineTo(16, 16), PdfLineTo(16, 8),
        PdfLineTo(8, 8), const PdfClosePath(),
      ]);
      final gen = StripGenerator()..begin(24, 24);
      gen.fillPath(path, PdfMatrix.identity, PdfFillRule.nonzero, black);
      expectCoverage(gen, [ring(outer), ring(innerRev)], false, 24, 24);
    });

    test('thin sliver', () {
      const pts = [1.0, 3.1, 23.0, 4.4, 1.0, 3.6];
      final gen = StripGenerator()..begin(24, 8);
      gen.fillPath(polyPath(pts), PdfMatrix.identity, PdfFillRule.nonzero,
          black);
      expectCoverage(gen, [ring(pts)], false, 24, 8, ss: 32, tol: 2.0);
    });

    test('subpixel rect', () {
      const pts = [5.3, 5.2, 5.9, 5.2, 5.9, 5.75, 5.3, 5.75];
      final gen = StripGenerator()..begin(12, 12);
      gen.fillPath(polyPath(pts), PdfMatrix.identity, PdfFillRule.nonzero,
          black);
      expectCoverage(gen, [ring(pts)], false, 12, 12, ss: 32, tol: 1.0);
    });

    test('cubic blob through a transform', () {
      final path = PdfPath([
        PdfMoveTo(2, 2),
        PdfCubicTo(10, 14, 14, 14, 22, 2),
        const PdfClosePath(),
      ]);
      final m = PdfMatrix(1, 0.2, -0.1, 1, 2, 1);
      final gen = StripGenerator()..begin(28, 24);
      gen.fillPath(path, m, PdfFillRule.nonzero, black);
      // reference: transform a dense flattening of the same curve
      final flat = flattenPath(path, m, tolerance: 0.02);
      expectCoverage(gen, [flat[0].points], false, 28, 24);
    });

    test('unclosed fill subpath closes implicitly', () {
      final gen = StripGenerator()..begin(16, 16);
      gen.fillPath(polyPath([2, 2, 14, 2, 14, 14], close: false),
          PdfMatrix.identity, PdfFillRule.nonzero, black);
      expectCoverage(gen, [
        ring([2, 2, 14, 2, 14, 14])
      ], false, 16, 16);
    });

    test('viewport clipping preserves winding (shape hangs off all edges)',
        () {
      const pts = <double>[-8, -6, 20, -9, 30, 18, 4, 30];
      final gen = StripGenerator()..begin(16, 16);
      gen.fillPath(polyPath(pts), PdfMatrix.identity, PdfFillRule.nonzero,
          black);
      expectCoverage(gen, [ring(pts)], false, 16, 16);
    });

    test('fillSubpaths raw entry matches fillPath', () {
      const pts = [3.2, 3.7, 20.4, 5.1, 12.6, 19.3];
      final a = StripGenerator()..begin(24, 24);
      a.fillPath(polyPath(pts), PdfMatrix.identity, PdfFillRule.nonzero,
          black);
      final b = StripGenerator()..begin(24, 24);
      b.fillSubpaths(
          [FlatSubpath(ring(pts), closed: true)], PdfFillRule.nonzero, black);
      expect(decodeStripCoverage(b.strips, 24, 24),
          decodeStripCoverage(a.strips, 24, 24));
    });

    test('fillOutline (cached em-space glyph) matches fillPath', () {
      // a glyph-ish outline in em units, drawn at a 20-px em
      final outline = PdfPath([
        PdfMoveTo(0.1, 0.0),
        PdfLineTo(0.35, 0.7),
        PdfCubicTo(0.42, 0.85, 0.58, 0.85, 0.65, 0.7),
        PdfLineTo(0.9, 0.0),
        PdfLineTo(0.72, 0.0),
        PdfLineTo(0.5, 0.55),
        PdfLineTo(0.28, 0.0),
        const PdfClosePath(),
      ]);
      // em -> device: 20-px em, y-flip, baseline at y=22
      const m = PdfMatrix(20, 0, 0, -20, 2, 22);
      final direct = StripGenerator()..begin(24, 24);
      direct.fillPath(outline, m, PdfFillRule.nonzero, black);
      final cached = StripGenerator()..begin(24, 24);
      cached.fillOutline(FlattenedOutline.of(outline), m, black);
      final got = decodeStripCoverage(cached.strips, 24, 24);
      final want = decodeStripCoverage(direct.strips, 24, 24);
      // tolerances differ (em-space vs device-space flattening) but both
      // are sub-pixel at a 20-px em
      expect(meanAbsDiff(got, want), lessThanOrEqualTo(1.0));
    });
  });

  group('strip emission structure', () {
    test('interior solid runs carry no alphas; sentinel + flags set', () {
      final gen = StripGenerator()..begin(32, 8);
      // rect with fractional vertical edges, row-aligned horizontals
      gen.fillPath(polyPath([1.5, 0, 30.5, 0, 30.5, 8, 1.5, 8]),
          PdfMatrix.identity, PdfFillRule.nonzero, black);
      final b = gen.strips;
      // per row: mixed(1) solid(2..29) mixed(30)
      expect(b.length, 6);
      var solids = 0, mixed = 0;
      for (var i = 0; i < b.length; i++) {
        final w = b.widthFlags[i] & 0xFFFF;
        if (b.widthFlags[i] & stripFlagSolid != 0) {
          solids++;
          expect(b.alphaOffset[i], stripSolidSentinel);
          expect(w, 28);
        } else {
          mixed++;
          expect(w, 1);
          expect(b.alphaOffset[i], isNot(stripSolidSentinel));
        }
      }
      expect(solids, 2);
      expect(mixed, 4);
      expect(b.alphaColumns, 4);
      // half-covered vertical edge columns
      for (final a in b.alphas) {
        expect(a, inInclusiveRange(126, 129));
      }
    });

    test('alpha bytes are column-major scanline coverage', () {
      final gen = StripGenerator()..begin(12, 4);
      // rect covering scanlines 0..1 fully, 2..3 not at all
      gen.fillPath(polyPath([2, 0, 10, 0, 10, 2, 2, 2]), PdfMatrix.identity,
          PdfFillRule.nonzero, black);
      final b = gen.strips;
      expect(b.length, 1);
      expect(b.widthFlags[0] & stripFlagSolid, 0);
      expect(b.widthFlags[0] & 0xFFFF, 8);
      expect(b.alphaColumns, 8);
      final alphas = b.alphas;
      for (var col = 0; col < 8; col++) {
        expect(alphas[col * 4 + 0], 255, reason: 'col $col scanline 0');
        expect(alphas[col * 4 + 1], 255);
        expect(alphas[col * 4 + 2], 0);
        expect(alphas[col * 4 + 3], 0);
      }
    });

    test('xy packing and strip row origin', () {
      final gen = StripGenerator()..begin(16, 16);
      gen.fillPath(polyPath([4, 9, 12, 9, 12, 11, 4, 11]), PdfMatrix.identity,
          PdfFillRule.nonzero, black);
      final b = gen.strips;
      expect(b.length, 1);
      expect(b.xy[0] & 0xFFFF, 4);
      expect(b.xy[0] >> 16, 8, reason: 'row top of the 4-px row holding y=9');
    });

    test('even-odd flag recorded on emitted strips', () {
      final gen = StripGenerator()..begin(8, 8);
      gen.fillPath(polyPath([1, 1, 7, 1, 7, 7, 1, 7]), PdfMatrix.identity,
          PdfFillRule.evenOdd, black);
      final b = gen.strips;
      expect(b.length, greaterThan(0));
      for (var i = 0; i < b.length; i++) {
        expect(b.widthFlags[i] & stripFlagEvenOdd, stripFlagEvenOdd);
      }
    });

    test('premul color rides along per strip', () {
      final gen = StripGenerator()..begin(8, 8);
      final c = premulRgba8(const PdfColor(1, 0.5, 0), 0.5);
      gen.fillPath(polyPath([0, 0, 8, 0, 8, 8, 0, 8]), PdfMatrix.identity,
          PdfFillRule.nonzero, c);
      final b = gen.strips;
      expect(b.length, greaterThan(0));
      expect(b.color[0], c);
      expect(c >> 24, 128); // alpha
      expect(c & 0xFF, 128); // r premultiplied
    });

    test('separate islands produce separate strips', () {
      final gen = StripGenerator()..begin(24, 4);
      final path = PdfPath([
        PdfMoveTo(2, 0), PdfLineTo(6, 0), PdfLineTo(6, 4), PdfLineTo(2, 4),
        const PdfClosePath(), //
        PdfMoveTo(14, 0), PdfLineTo(20, 0), PdfLineTo(20, 4),
        PdfLineTo(14, 4), const PdfClosePath(),
      ]);
      gen.fillPath(path, PdfMatrix.identity, PdfFillRule.nonzero, black);
      final b = gen.strips;
      expect(b.length, 2);
      expect(b.xy[0] & 0xFFFF, 2);
      expect(b.xy[1] & 0xFFFF, 14);
      for (var i = 0; i < 2; i++) {
        expect(b.widthFlags[i] & stripFlagSolid, stripFlagSolid);
      }
    });

    test('begin() resets the buffer and generator state is reusable', () {
      final gen = StripGenerator()..begin(16, 16);
      gen.fillPath(polyPath([2, 2, 14, 2, 14, 14, 2, 14]), PdfMatrix.identity,
          PdfFillRule.nonzero, black);
      final firstLen = gen.strips.length;
      expect(firstLen, greaterThan(0));
      final firstCoverage = decodeStripCoverage(gen.strips, 16, 16);
      gen.begin(16, 16);
      expect(gen.strips.length, 0);
      expect(gen.strips.alphaColumns, 0);
      gen.fillPath(polyPath([2, 2, 14, 2, 14, 14, 2, 14]), PdfMatrix.identity,
          PdfFillRule.nonzero, black);
      expect(gen.strips.length, firstLen);
      expect(decodeStripCoverage(gen.strips, 16, 16), firstCoverage);
    });

    test('multiple fills accumulate into one buffer', () {
      final gen = StripGenerator()..begin(16, 16);
      gen.fillPath(polyPath([1, 1, 7, 1, 7, 7, 1, 7]), PdfMatrix.identity,
          PdfFillRule.nonzero, black);
      final afterOne = gen.strips.length;
      gen.fillPath(polyPath([9, 9, 15, 9, 15, 15, 9, 15]), PdfMatrix.identity,
          PdfFillRule.nonzero, premulRgba8(const PdfColor(1, 0, 0), 1));
      expect(gen.strips.length, greaterThan(afterOne));
    });

    test('offscreen shapes are culled to zero strips', () {
      final gen = StripGenerator()..begin(16, 16);
      for (final pts in <List<double>>[
        [20.0, 2, 30, 2, 30, 12], // right of viewport
        [-30.0, 2, -20, 2, -20, 12], // left (closed: zero net winding)
        [2.0, -30, 12, -30, 12, -20], // above
        [2.0, 20, 12, 20, 12, 30], // below
      ]) {
        gen.fillPath(polyPath(pts), PdfMatrix.identity, PdfFillRule.nonzero,
            black);
      }
      expect(gen.strips.length, 0);
    });
  });
}

double _cos(double a) => math.cos(a);
double _sin(double a) => math.sin(a);
