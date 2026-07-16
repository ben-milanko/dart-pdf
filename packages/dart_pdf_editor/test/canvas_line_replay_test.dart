import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dart_pdf_editor/src/canvas_device.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_graphics/pdf_graphics.dart';

void main() {
  testWidgets('direct simple-line replay is pixel-identical to drawPath',
      (tester) async {
    await tester.runAsync(() async {
      final optimized = await _render(optimized: true);
      final reference = await _render(optimized: false);
      expect(optimized, orderedEquals(reference));
    });
  });

  testWidgets('reused fill Paints are pixel-identical to fresh Paints',
      (tester) async {
    await tester.runAsync(() async {
      final optimized = await _renderFills(optimized: true);
      final reference = await _renderFills(optimized: false);
      expect(optimized, orderedEquals(reference));
    });
  });
}

Future<Uint8List> _renderFills({required bool optimized}) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder)
    ..translate(7.5, 5.25)
    ..rotate(-0.08)
    ..scale(1.2, 1.4);
  final device = CanvasPdfDevice(canvas);
  final draws = <(PdfPath, PdfColor, PdfFillRule, double)>[
    (
      const PdfPath([
        PdfMoveTo(3, 4),
        PdfLineTo(31, 5),
        PdfLineTo(28, 29),
        PdfClosePath(),
      ]),
      const PdfColor(0.8, 0.15, 0.25),
      PdfFillRule.nonzero,
      1,
    ),
    (
      const PdfPath([
        PdfMoveTo(22, 13),
        PdfLineTo(58, 8),
        PdfLineTo(63, 37),
        PdfLineTo(29, 41),
        PdfClosePath(),
      ]),
      const PdfColor(0.8, 0.15, 0.25),
      PdfFillRule.evenOdd,
      1,
    ),
    (
      const PdfPath([
        PdfMoveTo(7, 34),
        PdfLineTo(42, 48),
        PdfLineTo(15, 61),
        PdfClosePath(),
      ]),
      const PdfColor(0.1, 0.45, 0.85),
      PdfFillRule.nonzero,
      0.55,
    ),
    // Returning to the first style proves later cache entries do not mutate
    // paint snapshots already recorded in the picture.
    (
      const PdfPath([
        PdfMoveTo(48, 43),
        PdfLineTo(72, 52),
        PdfLineTo(51, 65),
        PdfClosePath(),
      ]),
      const PdfColor(0.8, 0.15, 0.25),
      PdfFillRule.nonzero,
      1,
    ),
  ];

  for (final (path, color, rule, alpha) in draws) {
    if (optimized) {
      device.fillPath(path, color, rule, alpha);
      continue;
    }
    final uiPath = ui.Path()
      ..fillType = rule == PdfFillRule.evenOdd
          ? ui.PathFillType.evenOdd
          : ui.PathFillType.nonZero;
    for (final segment in path.segments) {
      switch (segment) {
        case PdfMoveTo(:final x, :final y):
          uiPath.moveTo(x, y);
        case PdfLineTo(:final x, :final y):
          uiPath.lineTo(x, y);
        case PdfCubicTo():
          uiPath.cubicTo(segment.x1, segment.y1, segment.x2, segment.y2,
              segment.x3, segment.y3);
        case PdfClosePath():
          uiPath.close();
      }
    }
    canvas.drawPath(
      uiPath,
      Paint()
        ..style = PaintingStyle.fill
        ..color = Color.from(
          alpha: alpha,
          red: color.red,
          green: color.green,
          blue: color.blue,
        ),
    );
  }

  final picture = recorder.endRecording();
  final image = await picture.toImage(128, 96);
  picture.dispose();
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  return data!.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
}

Future<Uint8List> _render({required bool optimized}) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder)
    ..translate(11.25, 9.5)
    ..rotate(0.17)
    ..scale(1.35, 1.15);
  final device = CanvasPdfDevice(canvas);
  final draws = <(PdfPath, PdfColor, PdfStroke, double)>[
    (
      const PdfPath([PdfMoveTo(2, 3), PdfLineTo(55, 7)]),
      const PdfColor(0.85, 0.1, 0.2),
      const PdfStroke(width: 0, cap: 0),
      1,
    ),
    (
      const PdfPath([PdfMoveTo(8, 18), PdfLineTo(62, 31)]),
      const PdfColor(0.1, 0.35, 0.9),
      const PdfStroke(width: 0.5, cap: 1),
      0.65,
    ),
    (
      const PdfPath([PdfMoveTo(4, 43), PdfLineTo(71, 17)]),
      const PdfColor(0.15, 0.7, 0.3),
      const PdfStroke(width: 3, cap: 2, join: 2, miterLimit: 4),
      1,
    ),
    // A zero-length round-cap stroke exercises the PDF dot case.
    (
      const PdfPath([PdfMoveTo(46, 42), PdfLineTo(46, 42)]),
      const PdfColor(0.85, 0.1, 0.2),
      const PdfStroke(width: 5, cap: 1),
      1,
    ),
    // Return to an earlier style: cached Paint objects must not mutate draws
    // that have already been recorded by the canvas.
    (
      const PdfPath([PdfMoveTo(14, 51), PdfLineTo(68, 54)]),
      const PdfColor(0.85, 0.1, 0.2),
      const PdfStroke(width: 0, cap: 0),
      1,
    ),
  ];

  for (final (path, color, stroke, alpha) in draws) {
    if (optimized) {
      device.strokePath(path, color, stroke, alpha);
    } else {
      final move = path.segments[0] as PdfMoveTo;
      final line = path.segments[1] as PdfLineTo;
      final uiPath = ui.Path()
        ..moveTo(move.x, move.y)
        ..lineTo(line.x, line.y);
      canvas.drawPath(
        uiPath,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = Color.from(
            alpha: alpha,
            red: color.red,
            green: color.green,
            blue: color.blue,
          )
          ..strokeWidth = stroke.width
          ..strokeCap = switch (stroke.cap) {
            1 => StrokeCap.round,
            2 => StrokeCap.square,
            _ => StrokeCap.butt,
          }
          ..strokeJoin = switch (stroke.join) {
            1 => StrokeJoin.round,
            2 => StrokeJoin.bevel,
            _ => StrokeJoin.miter,
          }
          ..strokeMiterLimit = stroke.miterLimit,
      );
    }
  }

  final picture = recorder.endRecording();
  final image = await picture.toImage(128, 96);
  picture.dispose();
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  return data!.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
}
