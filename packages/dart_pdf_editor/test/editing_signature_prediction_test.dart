// The signature pad draws the same forward-extrapolated lead the ink tool
// uses (stroke_prediction.dart), so the drawn line keeps up with the pen
// tip. These tests prove the lead reaches pixels on the pad and that
// predictStrokes:false turns it off. The pure geometry is covered by
// stroke_prediction_test; the ink-tool wiring by editing_prediction_test.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';

void main() {
  Future<void> pumpPad(WidgetTester tester, GlobalKey boundary,
      {required bool predict}) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RepaintBoundary(
          key: boundary,
          child: PdfSignatureDialog(predictStrokes: predict),
        ),
      ),
    ));
    await tester.pump();
  }

  // Draws a short horizontal stylus stroke on the pad, holds it, and reports
  // whether a dark (ink over white paper) pixel sits `beyond` px past the
  // last sample along the stroke's line.
  Future<bool> inkedBeyondLastSample(WidgetTester tester, GlobalKey boundary,
      {required double beyond}) async {
    final pad = find.byKey(const ValueKey('pdf-signature-pad'));
    final topLeft = tester.getTopLeft(pad);
    final start = topLeft + const Offset(60, 90);
    final g = await tester.startGesture(start, kind: PointerDeviceKind.stylus);
    var last = start;
    for (var i = 0; i < 4; i++) {
      last += const Offset(30, 0);
      await g.moveTo(last);
    }
    await tester.pump();

    final image = await tester.runAsync(() async {
      final render =
          boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      return render.toImage();
    });
    final data = (await tester.runAsync(image!.toByteData))!;
    // pad-local -> repaint-boundary pixels (boundary is at 0,0 here)
    final x = (last.dx + beyond).round();
    var sawInk = false;
    for (var dy = -4; dy <= 4 && !sawInk; dy++) {
      final y = last.dy.round() + dy;
      final i = (y * image.width + x) * 4;
      // black ink over white paper: all channels drop; paper stays ~255.
      sawInk = data.getUint8(i) < 140 && data.getUint8(i + 1) < 140;
    }
    await g.up();
    await tester.pump();
    image.dispose();
    return sawInk;
  }

  testWidgets('the predicted lead inks past the last real sample on the pad',
      (tester) async {
    final boundary = GlobalKey();
    await pumpPad(tester, boundary, predict: true);
    // 12px beyond the last sample is within the lead (~0.9 of a 30px
    // segment) but well past the unpredicted round cap (~1.5px).
    expect(await inkedBeyondLastSample(tester, boundary, beyond: 12), isTrue);
  });

  testWidgets('predictStrokes:false leaves the pad line at the last sample',
      (tester) async {
    final boundary = GlobalKey();
    await pumpPad(tester, boundary, predict: false);
    expect(await inkedBeyondLastSample(tester, boundary, beyond: 12), isFalse);
  });
}
