// Item 3 of the pencil-latency work: the in-progress ink layer draws a
// forward-extrapolated lead so the line keeps up with the pen tip. These
// tests prove the lead reaches pixels (and that PdfViewer.predictStrokes
// turns it off). The pure geometry is covered by stroke_prediction_test.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // 800px viewport over a 612pt page (fit-width)
  Future<PdfEditingController> pumpViewer(WidgetTester tester, GlobalKey boundary,
      {required bool predict}) async {
    final editing = PdfEditingController(buildMultiPagePdf(1))
      ..color = const Color(0xFFFF0000)
      ..strokeWidth = 8;
    addTearDown(editing.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RepaintBoundary(
          key: boundary,
          child: ListenableBuilder(
            listenable: editing,
            builder: (context, _) => PdfViewer(
              initialFit: PdfViewerFit.width,
              document: editing.document,
              controller: PdfViewerController(),
              editing: editing,
              predictStrokes: predict,
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
    return editing;
  }

  // Draws a horizontal stylus stroke (5 samples, 40px steps) and holds it,
  // then reports whether a red pixel sits `beyond` px past the last sample
  // along the stroke's line.
  Future<bool> redBeyondLastSample(WidgetTester tester, GlobalKey boundary,
      {required double beyond}) async {
    const start = Offset(200, 300);
    final g = await tester.startGesture(start, kind: PointerDeviceKind.stylus);
    var last = start;
    for (var i = 0; i < 4; i++) {
      last += const Offset(40, 0);
      await g.moveTo(last);
    }
    await tester.pump();

    final image = await tester.runAsync(() async {
      final render =
          boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      return render.toImage();
    });
    final data = (await tester.runAsync(image!.toByteData))!;
    int px(int x, int y) {
      final i = (y * image.width + x) * 4;
      return data.getUint8(i); // red channel
    }

    var sawRed = false;
    final x = (last.dx + beyond).round();
    for (var dy = -4; dy <= 4 && !sawRed; dy++) {
      final r = px(x, last.dy.round() + dy);
      // the line is opaque red over white paper; predicted ink reads red,
      // bare paper reads white (r==255 but with g==b==255). The byte data is
      // premultiplied straight RGBA, so check the green channel too.
      final gi = (last.dy.round() + dy) * image.width * 4 + x * 4 + 1;
      sawRed = r > 180 && data.getUint8(gi) < 140;
    }
    await g.up();
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pump(const Duration(milliseconds: 400));
    image.dispose();
    return sawRed;
  }

  testWidgets('the predicted lead inks past the last real sample',
      (tester) async {
    final boundary = GlobalKey();
    final editing = await pumpViewer(tester, boundary, predict: true);
    editing.tool = PdfEditTool.ink;
    await tester.pump();

    // 20px beyond the last sample is within the ~0.9-segment lead (≈34px
    // here) but well past the unpredicted round cap (~4px)
    expect(await redBeyondLastSample(tester, boundary, beyond: 20), isTrue);
  });

  testWidgets('predictStrokes:false leaves the line at the last sample',
      (tester) async {
    final boundary = GlobalKey();
    final editing = await pumpViewer(tester, boundary, predict: false);
    editing.tool = PdfEditTool.ink;
    await tester.pump();

    expect(await redBeyondLastSample(tester, boundary, beyond: 20), isFalse);
  });
}
