import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('keyboard resize leaves no blank band under a zoomed text editor',
      (tester) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(400, 850);
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final editing = PdfEditingController(buildMultiPagePdf(9))
      ..addFreeText(0, const PdfRect(240, 220, 360, 260), 'test')
      ..selectAnnotation(0, 0);
    final viewer = PdfViewerController();
    addTearDown(editing.dispose);
    addTearDown(viewer.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ListenableBuilder(
          listenable: editing,
          builder: (context, _) => PdfViewer(
            document: editing.document,
            editing: editing,
            controller: viewer,
            initialFit: PdfViewerFit.width,
          ),
        ),
      ),
    ));
    await tester.pump();
    viewer.setZoom(1.3);
    await tester.pumpAndSettle();
    expect(editing.requestEditSelectedTextInline(), isTrue);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    const editorKey = ValueKey('pdf-freetext-editor');
    expect(find.byKey(editorKey), findsOneWidget);
    final editorRect = tester.getRect(find.byKey(editorKey));

    void expectCovered() {
      final interactive = tester.widget<InteractiveViewer>(find.descendant(
          of: find.byType(PdfViewer),
          matching: find.byType(InteractiveViewer)));
      final matrix = interactive.transformationController!.value;
      final viewport = tester.getSize(find.byType(PdfViewer));
      final bottom =
          viewport.height * matrix.getMaxScaleOnAxis() + matrix.storage[13];
      expect(bottom, greaterThanOrEqualTo(viewport.height - 0.01),
          reason: 'The transformed list must cover the resized PDF viewport');
    }

    expectCovered();
    final zoom = viewer.zoom;
    tester.view.viewInsets = const FakeViewPadding(bottom: 500);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.getSize(find.byType(PdfViewer)).height, 350);
    expectCovered();
    expect(viewer.zoom, closeTo(zoom, 0.001));
    final field = tester.widget<TextField>(find.byKey(editorKey));
    expect(field.focusNode!.hasFocus, isTrue);
    expect(field.controller!.text, 'test');
    expect(tester.getRect(find.byKey(editorKey)).top,
        closeTo(editorRect.top, 0.01));
    await tester.enterText(find.byKey(editorKey), 'Typed with keyboard open');

    tester.view.viewInsets = const FakeViewPadding();
    await tester.pumpAndSettle();
    expectCovered();
    expect(viewer.zoom, closeTo(zoom, 0.001));
    expect(field.focusNode!.hasFocus, isTrue);
    expect(field.controller!.text, 'Typed with keyboard open');
    // Closing through the viewer's normal outside-tap path commits the text.
    await tester.tapAt(const Offset(20, 40));
    await tester.pumpAndSettle();
    expect(editing.isEditingText, isFalse);
    expect(editing.document.page(0).annotations.single.contents,
        'Typed with keyboard open');
    final saved = PdfDocument.open(editing.bytes);
    expect(
        saved.page(0).annotations.single.contents, 'Typed with keyboard open');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  for (final horizontal in [false, true]) {
    testWidgets('main-axis window resize keeps zoom covered ($horizontal)',
        (tester) async {
      tester.view
        ..devicePixelRatio = 1
        ..physicalSize = const Size(800, 800);
      addTearDown(tester.view.reset);
      final viewer = PdfViewerController();
      addTearDown(viewer.dispose);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: PdfViewer(
            document: PdfDocument.open(buildMultiPagePdf(9)),
            controller: viewer,
            initialFit: PdfViewerFit.width,
            pageLayout: horizontal
                ? const PdfPageLayout.horizontalContinuous()
                : const PdfPageLayout.verticalContinuous(),
          ),
        ),
      ));
      await tester.pump();
      // At fit there is no transform to repair, including on a resize.
      tester.view.physicalSize =
          horizontal ? const Size(300, 800) : const Size(800, 300);
      await tester.pumpAndSettle();
      final fitZoom = viewer.zoom;
      tester.view.physicalSize = const Size(800, 800);
      await tester.pumpAndSettle();
      expect(viewer.zoom, closeTo(fitZoom, 0.001));
      viewer.setZoom(fitZoom * 2);
      await tester.pumpAndSettle();
      final zoom = viewer.zoom;
      final anchor = viewer.captureViewport()!;
      tester.view.physicalSize =
          horizontal ? const Size(300, 800) : const Size(800, 300);
      await tester.pumpAndSettle();
      final interactive = tester.widget<InteractiveViewer>(find.descendant(
          of: find.byType(PdfViewer),
          matching: find.byType(InteractiveViewer)));
      final matrix = interactive.transformationController!.value;
      const main = 300.0;
      final end = main * matrix.getMaxScaleOnAxis() +
          matrix.storage[horizontal ? 12 : 13];
      expect(end, greaterThanOrEqualTo(main - 0.01));
      expect(viewer.zoom, closeTo(zoom, 0.001));
      final after = viewer.captureViewport()!;
      expect(after.page, anchor.page);
      expect(horizontal ? after.left : after.top,
          closeTo(horizontal ? anchor.left : anchor.top, 0.001));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  }
}
