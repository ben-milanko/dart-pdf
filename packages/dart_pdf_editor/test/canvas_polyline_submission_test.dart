// #1270 A/B switch: CanvasPdfDevice.debugStraightPolylines submits straight
// polylines as line segments. These pin its eligibility rules; the raster
// timing lives in the macOS Patrol A/B (patrol_test/polyline_ab_perf_test.dart).
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_graphics/pdf_graphics.dart';

const _size = 64;

Future<Uint8List> _render(
  PdfPolylineSubmission mode,
  void Function(CanvasPdfDevice device) draw,
) async {
  final previous = CanvasPdfDevice.debugStraightPolylines;
  CanvasPdfDevice.debugStraightPolylines = mode;
  try {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder)
      ..drawColor(const ui.Color(0xFFFFFFFF), ui.BlendMode.src);
    draw(CanvasPdfDevice(canvas, images: const {}));
    final picture = recorder.endRecording();
    final image = await picture.toImage(_size, _size);
    picture.dispose();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    return bytes!.buffer.asUint8List();
  } finally {
    CanvasPdfDevice.debugStraightPolylines = previous;
  }
}

double _meanDifference(Uint8List a, Uint8List b) {
  var total = 0;
  for (var i = 0; i < a.length; i++) {
    total += (a[i] - b[i]).abs();
  }
  return total / a.length;
}

int _inked(Uint8List rgba) {
  var count = 0;
  for (var i = 0; i < rgba.length; i += 4) {
    if (rgba[i] < 200) count++;
  }
  return count;
}

const _polyline = PdfPath([
  PdfMoveTo(8, 8),
  PdfLineTo(56, 8),
  PdfLineTo(56, 40),
  PdfLineTo(20, 40),
  PdfLineTo(20, 56),
]);

const _black = PdfColor(0, 0, 0);

void main() {
  void stroke(CanvasPdfDevice d, PdfPath path,
          {double width = 1, double alpha = 1, List<double> dash = const []}) =>
      d.strokePath(
          path, _black, PdfStroke(width: width, dashArray: dash), alpha);

  test('segments render a thin opaque polyline like its path', () async {
    final path =
        await _render(PdfPolylineSubmission.path, (d) => stroke(d, _polyline));
    for (final mode in [
      PdfPolylineSubmission.lines,
      PdfPolylineSubmission.rawPoints,
    ]) {
      final split = await _render(mode, (d) => stroke(d, _polyline));
      expect(_inked(split), greaterThan(0), reason: '$mode drew nothing');
      // Only the four 1-unit miter corners may differ.
      expect(_meanDifference(path, split), lessThan(2.0), reason: '$mode');
    }
  });

  test('ineligible strokes fall back to the exact path rendering', () async {
    const curve = PdfPath([
      PdfMoveTo(8, 8),
      PdfLineTo(30, 8),
      PdfCubicTo(40, 8, 56, 20, 56, 40),
    ]);
    final cases = <String, void Function(CanvasPdfDevice)>{
      'curve': (d) => stroke(d, curve),
      'translucent': (d) => stroke(d, _polyline, alpha: 0.5),
      'dashed': (d) => stroke(d, _polyline, dash: const [4, 2]),
      'too wide': (d) => stroke(d, _polyline, width: 4),
    };
    for (final entry in cases.entries) {
      final path = await _render(PdfPolylineSubmission.path, entry.value);
      final split = await _render(PdfPolylineSubmission.lines, entry.value);
      expect(split, path, reason: '${entry.key} must not be decomposed');
    }
  });

  test('closed subpaths draw their closing segment', () async {
    const square = PdfPath([
      PdfMoveTo(10, 10),
      PdfLineTo(50, 10),
      PdfLineTo(50, 50),
      PdfLineTo(10, 50),
      PdfClosePath(),
    ]);
    final path =
        await _render(PdfPolylineSubmission.path, (d) => stroke(d, square));
    final split =
        await _render(PdfPolylineSubmission.lines, (d) => stroke(d, square));
    expect(_meanDifference(path, split), lessThan(2.0));
    // The left edge (the closing segment) is inked.
    expect(split[(30 * _size + 10) * 4], lessThan(200));
  });

  test('the switch is off by default', () {
    expect(CanvasPdfDevice.debugStraightPolylines, PdfPolylineSubmission.path);
  });
}
