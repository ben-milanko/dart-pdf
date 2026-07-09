// Stroke-expansion tests: contour structure (caps/joins/miter limit/dash)
// plus coverage checks - the expanded contours, filled nonzero, must match
// a brute-force rasterization of the geometrically expected shape.
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pdf_graphics/pdf_graphics.dart';
import 'package:pdf_graphics/raster.dart';
import 'package:test/test.dart';

import 'reference_raster.dart';

FlatSubpath poly(List<double> pts, {bool closed = false}) =>
    FlatSubpath(Float64List.fromList(pts), closed: closed);

double ringArea(Float64List r) {
  final n = r.length ~/ 2;
  var area = 0.0;
  for (var i = 0, j = n - 1; i < n; j = i++) {
    area += r[2 * j] * r[2 * i + 1] - r[2 * i] * r[2 * j + 1];
  }
  return area / 2;
}

bool ringHasPoint(Float64List r, double x, double y, {double tol = 1e-9}) {
  for (var i = 0; i < r.length; i += 2) {
    if ((r[i] - x).abs() < tol && (r[i + 1] - y).abs() < tol) return true;
  }
  return false;
}

void main() {
  StrokeContours expand(List<FlatSubpath> subs,
      {double width = 2,
      int cap = 0,
      int join = 0,
      double miterLimit = 10}) {
    final out = StrokeContours();
    strokeToContours(subs,
        width: width, cap: cap, join: join, miterLimit: miterLimit, out: out);
    return out;
  }

  test('single segment, butt caps: one quad covering the exact rectangle',
      () {
    final c = expand([
      poly([2, 6, 22, 6])
    ], width: 4);
    expect(c.ringCount, 1);
    final ring = contourRing(c, 0);
    expect(ringArea(ring).abs(), closeTo(20 * 4, 1e-9));

    // coverage parity vs the exact rectangle
    final gen = StripGenerator()..begin(24, 12);
    gen.fillContours(c, premulRgba8(PdfColor.black, 1));
    final got = decodeStripCoverage(gen.strips, 24, 12);
    final want = referenceCoverage([
      Float64List.fromList([2, 4, 22, 4, 22, 8, 2, 8])
    ], false, 24, 12);
    expect(meanAbsDiff(got, want), lessThanOrEqualTo(2.0));
  });

  test('all rings share one winding orientation', () {
    final c = expand(
        [
          poly([2, 2, 20, 2, 20, 20, 2, 20, 2, 2], closed: true),
          poly([4, 30, 28, 34, 6, 40]),
        ],
        width: 3,
        cap: 1,
        join: 1);
    expect(c.ringCount, greaterThan(4));
    for (var i = 0; i < c.ringCount; i++) {
      expect(ringArea(contourRing(c, i)), greaterThan(0),
          reason: 'ring $i must be shoelace-positive');
    }
  });

  test('right-angle miter join places the miter point', () {
    // L from (2,10) to (10,10) to (10,2), width 2 (hw 1): the outer corner
    // miter point sits at (11,11).
    final c = expand([
      poly([2, 10, 10, 10, 10, 2])
    ], width: 2, join: 0);
    // 2 segment quads + 1 miter wedge (4 points)
    expect(c.ringCount, 3);
    var found = false;
    for (var i = 0; i < c.ringCount; i++) {
      if (ringHasPoint(contourRing(c, i), 11, 11)) found = true;
    }
    expect(found, isTrue, reason: 'miter point (11,11) missing');
  });

  test('bevel join has no miter point', () {
    final c = expand([
      poly([2, 10, 10, 10, 10, 2])
    ], width: 2, join: 2);
    expect(c.ringCount, 3);
    for (var i = 0; i < c.ringCount; i++) {
      expect(ringHasPoint(contourRing(c, i), 11, 11), isFalse);
      // bevel wedge is a triangle
      expect(contourRing(c, i).length ~/ 2, lessThanOrEqualTo(4));
    }
  });

  test('miter limit falls back to bevel', () {
    // right angle: miter ratio sqrt(2) ~ 1.414 > limit 1.2 -> bevel
    final c = expand([
      poly([2, 10, 10, 10, 10, 2])
    ], width: 2, join: 0, miterLimit: 1.2);
    for (var i = 0; i < c.ringCount; i++) {
      expect(ringHasPoint(contourRing(c, i), 11, 11), isFalse);
    }
  });

  test('round join emits an arc fan', () {
    final c = expand([
      poly([2, 10, 10, 10, 10, 2])
    ], width: 2, join: 1);
    expect(c.ringCount, 3);
    var maxPts = 0;
    for (var i = 0; i < c.ringCount; i++) {
      final n = contourRing(c, i).length ~/ 2;
      if (n > maxPts) maxPts = n;
    }
    expect(maxPts, greaterThan(4), reason: 'arc fan must have arc points');
  });

  test('square caps extend by half width; coverage matches', () {
    final c = expand([
      poly([4, 6, 20, 6])
    ], width: 4, cap: 2);
    // quad + two cap quads
    expect(c.ringCount, 3);
    final gen = StripGenerator()..begin(26, 12);
    gen.fillContours(c, premulRgba8(PdfColor.black, 1));
    final got = decodeStripCoverage(gen.strips, 26, 12);
    final want = referenceCoverage([
      Float64List.fromList([2, 4, 22, 4, 22, 8, 2, 8])
    ], false, 26, 12);
    expect(meanAbsDiff(got, want), lessThanOrEqualTo(2.0));
  });

  test('round caps cover the end circles', () {
    final c = expand([
      poly([8, 8, 20, 8])
    ], width: 6, cap: 1);
    final gen = StripGenerator()..begin(28, 16);
    gen.fillContours(c, premulRgba8(PdfColor.black, 1));
    final got = decodeStripCoverage(gen.strips, 28, 16);
    // reference: rectangle + polygonal end circles (matching fan density is
    // not required at +-2/255 mean with 3-px radius circles)
    final circleL = <double>[];
    final circleR = <double>[];
    for (var i = 0; i < 32; i++) {
      final a = 2 * math.pi * i / 32;
      circleL.addAll([8 + 3 * math.cos(a), 8 + 3 * math.sin(a)]);
      circleR.addAll([20 + 3 * math.cos(a), 8 + 3 * math.sin(a)]);
    }
    final want = referenceCoverage([
      Float64List.fromList([8, 5, 20, 5, 20, 11, 8, 11]),
      Float64List.fromList(circleL),
      Float64List.fromList(circleR),
    ], false, 28, 16);
    expect(meanAbsDiff(got, want), lessThanOrEqualTo(2.0));
  });

  test('closed subpath strokes all four corners (wrap join)', () {
    final c = expand([
      poly([4, 4, 20, 4, 20, 20, 4, 20, 4, 4], closed: true)
    ], width: 2, join: 0);
    // 4 quads + 4 miter wedges
    expect(c.ringCount, 8);
    final gen = StripGenerator()..begin(26, 26);
    gen.fillContours(c, premulRgba8(PdfColor.black, 1));
    final got = decodeStripCoverage(gen.strips, 26, 26);
    // reference: outer rect minus inner rect (evenodd two-ring polygon)
    final want = referenceCoverage([
      Float64List.fromList([3, 3, 21, 3, 21, 21, 3, 21]),
      Float64List.fromList([5, 5, 19, 5, 19, 19, 5, 19]),
    ], true, 26, 26);
    expect(meanAbsDiff(got, want), lessThanOrEqualTo(2.0));
  });

  test('isolated point paints a dot for round/square caps, nothing for butt',
      () {
    for (final (cap, expectRings) in [(0, 0), (1, 2), (2, 1)]) {
      final c = expand([
        poly([5, 5, 5, 5])
      ], width: 4, cap: cap);
      expect(c.ringCount, expectRings, reason: 'cap $cap');
    }
  });

  test('hairline width is clamped to 1 device px', () {
    final c = expand([
      poly([2, 6, 22, 6])
    ], width: 0.01);
    final ring = contourRing(c, 0);
    expect(ringArea(ring).abs(), closeTo(20 * 1, 1e-6));
  });

  test('dashed stroke through StripGenerator matches two rectangles', () {
    final gen = StripGenerator()..begin(24, 12);
    final path = PdfPath([PdfMoveTo(2, 6), PdfLineTo(22, 6)]);
    gen.strokePath(
        path,
        PdfMatrix.identity,
        PdfStroke(width: 4, dashArray: [8, 4]),
        premulRgba8(PdfColor.black, 1));
    final got = decodeStripCoverage(gen.strips, 24, 12);
    final want = referenceCoverage([
      Float64List.fromList([2, 4, 10, 4, 10, 8, 2, 8]),
      Float64List.fromList([14, 4, 22, 4, 22, 8, 14, 8]),
    ], false, 24, 12);
    expect(meanAbsDiff(got, want), lessThanOrEqualTo(2.0));
  });

  test('diagonal stroke coverage matches the rotated rectangle', () {
    final c = expand([
      poly([4, 4, 20, 12])
    ], width: 2);
    expect(c.ringCount, 1);
    final gen = StripGenerator()..begin(24, 16);
    gen.fillContours(c, premulRgba8(PdfColor.black, 1));
    final got = decodeStripCoverage(gen.strips, 24, 16);
    // expected quad: offsets +-hw along the unit normal of (16,8)/17.889
    const len = 17.88854381999832; // sqrt(16^2+8^2)
    const nx = -8 / len, ny = 16 / len; // unit normal * hw(=1)
    final want = referenceCoverage([
      Float64List.fromList([
        4 + nx, 4 + ny, 20 + nx, 12 + ny, //
        20 - nx, 12 - ny, 4 - nx, 4 - ny,
      ]),
    ], false, 24, 16);
    expect(meanAbsDiff(got, want), lessThanOrEqualTo(2.0));
  });
}
