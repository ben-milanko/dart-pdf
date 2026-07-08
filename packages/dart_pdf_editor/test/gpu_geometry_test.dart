// Pure-Dart unit tests for the GPU tessellation helpers (no GPU needed).
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dart_pdf_editor/gpu.dart';
import 'package:flutter_test/flutter_test.dart';

Float64List _ring(List<double> pts) => Float64List.fromList(pts);

double _triArea(Float64List t) {
  var area = 0.0;
  for (var i = 0; i + 5 < t.length; i += 6) {
    area += ((t[i + 2] - t[i]) * (t[i + 5] - t[i + 1]) -
            (t[i + 3] - t[i + 1]) * (t[i + 4] - t[i]))
        .abs() /
        2;
  }
  return area;
}

bool _covers(Float64List tris, double px, double py) {
  for (var i = 0; i + 5 < tris.length; i += 6) {
    final ax = tris[i], ay = tris[i + 1];
    final bx = tris[i + 2], by = tris[i + 3];
    final cx = tris[i + 4], cy = tris[i + 5];
    final d1 = (px - bx) * (ay - by) - (ax - bx) * (py - by);
    final d2 = (px - cx) * (by - cy) - (bx - cx) * (py - cy);
    final d3 = (px - ax) * (cy - ay) - (cx - ax) * (py - ay);
    final neg = d1 < 0 || d2 < 0 || d3 < 0;
    final pos = d1 > 0 || d2 > 0 || d3 > 0;
    if (!(neg && pos)) return true;
  }
  return false;
}

void main() {
  test('earClipPolygon triangulates a concave polygon', () {
    final out = DoubleBuilder();
    // L-shape, area 3
    expect(
        earClipPolygon(
            _ring([0, 0, 2, 0, 2, 1, 1, 1, 1, 2, 0, 2]), out),
        isTrue);
    expect(_triArea(out.view), closeTo(3.0, 1e-9));
  });

  test('earClipWithHoles handles an axis-aligned square ring', () {
    final out = DoubleBuilder();
    final ok = earClipWithHoles(
        _ring([0, 0, 10, 0, 10, 10, 0, 10]),
        [_ring([2, 2, 2, 8, 8, 8, 8, 2])],
        out);
    expect(ok, isTrue, reason: 'square ring should clip');
    expect(_triArea(out.view), closeTo(100 - 36, 1e-6));
    expect(_covers(out.view, 1, 1), isTrue);
    expect(_covers(out.view, 5, 5), isFalse, reason: 'hole must stay open');
  });

  test('earClipWithHoles handles a thin rotated ring', () {
    // rectangle ring rotated 30 degrees, wall thickness 1
    final c = math.cos(math.pi / 6), s = math.sin(math.pi / 6);
    Float64List rot(List<double> pts) {
      final out = Float64List(pts.length);
      for (var i = 0; i < pts.length; i += 2) {
        out[i] = pts[i] * c - pts[i + 1] * s;
        out[i + 1] = pts[i] * s + pts[i + 1] * c;
      }
      return out;
    }

    final out = DoubleBuilder();
    final ok = earClipWithHoles(
        rot([0, 0, 40, 0, 40, 6, 0, 6]),
        [Float64List.fromList(rot([1, 1, 1, 5, 39, 5, 39, 1]))],
        out);
    expect(ok, isTrue, reason: 'rotated thin ring should clip');
    expect(_triArea(out.view), closeTo(40 * 6 - 38 * 4, 1e-6));
  });

  test('earClipWithHoles handles clockwise outer with ccw hole', () {
    final out = DoubleBuilder();
    final ok = earClipWithHoles(
        _ring([0, 0, 0, 10, 10, 10, 10, 0]), // CW
        [_ring([2, 2, 2, 8, 8, 8, 8, 2])],
        out);
    expect(ok, isTrue);
    expect(_triArea(out.view), closeTo(64, 1e-6));
  });

  test('earClipWithHoles rejects a hole crossing the outer boundary', () {
    final out = DoubleBuilder();
    final ok = earClipWithHoles(
        _ring([0, 0, 10, 0, 10, 10, 0, 10]),
        [_ring([5, 5, 15, 5, 15, 8, 5, 8])],
        out);
    expect(ok, isFalse);
    expect(out.length, 0);
  });
}
