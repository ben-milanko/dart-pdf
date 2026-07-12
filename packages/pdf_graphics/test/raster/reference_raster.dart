// Shared helpers for the strip-raster tests: a brute-force supersampling
// reference rasterizer (winding-number point sampling, 16x16 or denser per
// pixel) and a StripBuffer decoder that reconstructs the full coverage
// image a strip consumer would composite.
import 'dart:typed_data';

import 'package:pdf_graphics/raster.dart';

/// Rasterizes closed [rings] (flat `[x,y,...]` polygons, device space) by
/// supersampling [ss] x [ss] points per pixel with the winding-number rule
/// ([evenOdd] selects the parity rule). Returns w*h coverage bytes.
Uint8List referenceCoverage(
    List<Float64List> rings, bool evenOdd, int w, int h,
    {int ss = 16}) {
  final out = Uint8List(w * h);
  final samples = ss * ss;
  for (var py = 0; py < h; py++) {
    for (var px = 0; px < w; px++) {
      var inside = 0;
      for (var sy = 0; sy < ss; sy++) {
        final y = py + (sy + 0.5) / ss;
        for (var sx = 0; sx < ss; sx++) {
          final x = px + (sx + 0.5) / ss;
          var winding = 0;
          for (final ring in rings) {
            final n = ring.length ~/ 2;
            for (var i = 0, j = n - 1; i < n; j = i++) {
              final y0 = ring[2 * j + 1], y1 = ring[2 * i + 1];
              if ((y0 > y) == (y1 > y)) continue;
              final x0 = ring[2 * j], x1 = ring[2 * i];
              final xCross = x0 + (y - y0) * (x1 - x0) / (y1 - y0);
              if (xCross > x) winding += y1 > y0 ? 1 : -1;
            }
          }
          final isIn = evenOdd ? winding.isOdd : winding != 0;
          if (isIn) inside++;
        }
      }
      out[py * w + px] = (inside * 255 + samples ~/ 2) ~/ samples;
    }
  }
  return out;
}

/// Reconstructs the w*h coverage image described by [b]. Overlapping strips
/// (possible across fills) keep the maximum coverage - the tests only ever
/// decode a single shape, where strips never overlap.
Uint8List decodeStripCoverage(StripBuffer b, int w, int h) {
  final out = Uint8List(w * h);
  final alphas = b.alphas;
  for (var i = 0; i < b.length; i++) {
    final x = b.xy[i] & 0xFFFF;
    final y = b.xy[i] >> 16;
    final width = b.widthFlags[i] & 0xFFFF;
    final solid = b.widthFlags[i] & stripFlagSolid != 0;
    final aOff = b.alphaOffset[i];
    for (var col = 0; col < width; col++) {
      for (var k = 0; k < 4; k++) {
        final py = y + k;
        final px = x + col;
        if (py >= h || px >= w) continue;
        final a = solid ? 255 : alphas[(aOff + col) * 4 + k];
        final at = py * w + px;
        if (a > out[at]) out[at] = a;
      }
    }
  }
  return out;
}

/// Mean absolute coverage difference in byte units (0..255).
double meanAbsDiff(Uint8List a, Uint8List b) {
  var sum = 0;
  for (var i = 0; i < a.length; i++) {
    sum += (a[i] - b[i]).abs();
  }
  return sum / a.length;
}

/// Extracts contour ring [i] as a flat Float64List (for the reference
/// rasterizer).
Float64List contourRing(StrokeContours c, int i) {
  final start = c.ringStart(i), end = c.ringEnd(i);
  final out = Float64List(end - start);
  for (var k = start; k < end; k++) {
    out[k - start] = c.points[k];
  }
  return out;
}

/// All rings of [c] as reference-rasterizer input.
List<Float64List> contourRings(StrokeContours c) =>
    [for (var i = 0; i < c.ringCount; i++) contourRing(c, i)];
