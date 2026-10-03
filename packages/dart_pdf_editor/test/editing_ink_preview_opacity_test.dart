// The freehand ink preview paints at the opacity the stroke commits with.
// Before, the live stroke (and the buffered strokes awaiting auto-commit)
// drew the tool colour fully opaque, so a highlighter line went down solid
// and only turned translucent once the annotation landed.

import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // Green channel at [at]: the stroke is pure red over white paper, so an
  // opaque line reads ~0 and a 40% one reads ~153.
  Future<int> greenAt(
      WidgetTester tester, GlobalKey boundary, Offset at) async {
    final image = await tester.runAsync(() async {
      final render =
          boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      return render.toImage();
    });
    final data = (await tester.runAsync(image!.toByteData))!;
    final green =
        data.getUint8((at.dy.round() * image.width + at.dx.round()) * 4 + 1);
    image.dispose();
    return green;
  }

  for (final tool in [PdfEditTool.highlight, PdfEditTool.ink]) {
    testWidgets('${tool.name} previews at its committed opacity',
        (tester) async {
      final boundary = GlobalKey();
      final editing = PdfEditingController(buildMultiPagePdf(1));
      addTearDown(editing.dispose);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: RepaintBoundary(
            key: boundary,
            child: PdfViewer(
              initialFit: PdfViewerFit.width,
              controller: PdfViewerController(),
              editing: editing,
              predictStrokes: false,
            ),
          ),
        ),
      ));
      await tester.pump();
      editing.tool = tool;
      // style after arming: each tool remembers its own
      editing
        ..color = const Color(0xFFFF0000)
        ..preferences.strokeWidth = 12
        ..preferences.opacity = 0.4;
      await tester.pump();

      const start = Offset(200, 300);
      const probe = Offset(280, 300);
      final g =
          await tester.startGesture(start, kind: PointerDeviceKind.stylus);
      for (var i = 1; i <= 4; i++) {
        await g.moveTo(start + Offset(40.0 * i, 0));
      }
      await tester.pump();

      // the live stroke
      var green = await greenAt(tester, boundary, probe);
      expect(green, inInclusiveRange(120, 190), reason: 'live stroke');

      // lifted, buffered until auto-commit
      await g.up();
      await tester.pump();
      green = await greenAt(tester, boundary, probe);
      expect(green, inInclusiveRange(120, 190), reason: 'buffered stroke');

      await tester.pump(const Duration(milliseconds: 900));
      await tester.pump(const Duration(milliseconds: 400));
    });
  }
}
