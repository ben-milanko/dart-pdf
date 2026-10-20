import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:dart_pdf_editor/src/editing/editing_overlay.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pdf_cos/perf.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';

void main() {
  Future<PdfEditingController> mount(WidgetTester tester) async {
    final editor = PdfEditor(PdfDocument.open(
        buildSyntheticCadStrip(ops: 20000, pageW: 612, pageH: 792)))
      ..addFreeText(0, const PdfRect(100, 600, 300, 650), 'Resize me');
    final editing = PdfEditingController(editor.save())
      ..tool = PdfEditTool.select
      ..selectAnnotation(0, 0);
    addTearDown(editing.dispose);
    addTearDown(() => PdfPerf.enabled = false);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
          width: 612,
          height: 792,
          child: EditingPageOverlay(
            controller: editing,
            pageIndex: 0,
            geometry: const PdfPageGeometry(
                cropBox: PdfRect(0, 0, 612, 792),
                rotation: 0,
                viewSize: Size(612, 792)),
            textPrompt: (context,
                    {required title, initial = '', multiline = false}) async =>
                null,
          )),
    ))));
    await tester.pump();
    PdfPerf.enabled = true;
    PdfPerf.reset();
    return editing;
  }

  testWidgets('a dense-page resize starts without a synchronous page parse',
      (tester) async {
    await mount(tester);
    final gesture = await tester.startGesture(const Offset(300, 192),
        kind: PointerDeviceKind.mouse);
    await gesture.moveTo(const Offset(250, 212));
    final beforeFrame =
        PdfPerf.snapshot().counts[PdfPerfCount.contentOps.index];
    expect(beforeFrame, lessThan(100),
        reason: 'only annotation-sized work may precede the preview frame');
    await tester.pump();
    expect(
        find.byKey(const ValueKey('pdf-text-resize-preview')), findsOneWidget);
    expect(PdfPerf.snapshot().counts[PdfPerfCount.contentOps.index],
        greaterThan(10000),
        reason: 'the clean page is still rendered after the preview frame');
    await gesture.cancel();
    await tester.pump();
  });

  testWidgets('ending before the frame skips the pending clean-page render',
      (tester) async {
    final editing = await mount(tester);
    final revision = editing.revisionId;
    final gesture = await tester.startGesture(const Offset(300, 192),
        kind: PointerDeviceKind.mouse);
    await gesture.moveTo(const Offset(250, 212));
    await gesture.up();
    await tester.pump();
    expect(editing.revisionId, revision + 1);
    expect(PdfPerf.snapshot().counts[PdfPerfCount.contentOps.index],
        lessThan(100));
    expect(find.byKey(const ValueKey('pdf-text-resize-preview')), findsNothing);
  });
}
