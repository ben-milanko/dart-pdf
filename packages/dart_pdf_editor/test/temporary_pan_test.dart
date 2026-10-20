import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets(
      'search typing never arms Space; focus loss and cancel release hand',
      (tester) async {
    final editing = PdfEditingController(buildMultiPagePdf(3))
      ..tool = PdfEditTool.rectangle;
    final viewer = PdfViewerController();
    final search = TextEditingController();
    final searchFocus = FocusNode();
    await tester.pumpWidget(MaterialApp(
        home: Material(
            child: Column(children: [
      TextField(controller: search, focusNode: searchFocus),
      Expanded(
          child: ListenableBuilder(
              listenable: editing,
              builder: (_, __) => PdfViewer(
                  document: editing.document,
                  editing: editing,
                  controller: viewer,
                  initialFit: PdfViewerFit.width))),
    ]))));
    await tester.pumpAndSettle();
    searchFocus.requestFocus();
    await tester.pump();
    expect(await tester.sendKeyDownEvent(LogicalKeyboardKey.space), isFalse);
    await tester.enterText(find.byType(TextField), 'two words');
    expect(search.text, 'two words');
    await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
    viewer.requestKeyboardFocus();
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
    final original = editing.document;
    final drag = await tester.startGesture(const Offset(400, 350),
        kind: PointerDeviceKind.mouse);
    await drag.moveBy(const Offset(0, -50));
    await tester.pump();
    final region = viewer.visiblePageRegion(0);
    searchFocus.requestFocus();
    await tester.pump();
    await drag.moveBy(const Offset(0, -50));
    await tester.pump();
    expect(viewer.visiblePageRegion(0), region);
    await drag.cancel();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
    expect(editing.document, same(original));
    viewer.requestKeyboardFocus();
    await tester.pump();
    final next = await tester.startGesture(const Offset(300, 250),
        kind: PointerDeviceKind.mouse);
    await next.moveBy(const Offset(100, 100));
    await next.up();
    await tester.pumpAndSettle();
    expect(editing.document, isNot(same(original)),
        reason: 'the original drawing tool works again');
    await tester.pumpWidget(const SizedBox());
    editing.dispose();
    viewer.dispose();
    search.dispose();
    searchFocus.dispose();
  });
  for (final form in [false, true]) {
    testWidgets('Space belongs to the ${form ? "form" : "inline"} editor',
        (tester) async {
      final editing = PdfEditingController(
          form ? buildAcroFormPdf() : buildMultiPagePdf(1));
      if (!form) {
        editing.addFreeText(0, const PdfRect(100, 600, 300, 650), 'Original');
        editing.selectAnnotation(0, 0);
      }
      final viewer = PdfViewerController();
      await tester.pumpWidget(MaterialApp(
          home: Material(
              child: PdfViewer(
                  editing: editing,
                  controller: viewer,
                  initialFit: PdfViewerFit.width))));
      await tester.pumpAndSettle();
      final position = form ? const Offset(243, 105) : const Offset(260, 215);
      await tester.tapAt(position, kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      final field = find.byType(EditableText);
      expect(field, findsOneWidget);
      final before = viewer.visiblePageRegion(0);
      expect(await tester.sendKeyDownEvent(LogicalKeyboardKey.space), isFalse);
      await tester.enterText(field, 'two words');
      await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
      expect(tester.widget<EditableText>(field).controller.text, 'two words');
      expect(viewer.visiblePageRegion(0), before);
      await tester.pumpWidget(const SizedBox());
      editing.dispose();
      viewer.dispose();
    });
  }
  for (final middle in [false, true]) {
    for (final tool in [
      PdfEditTool.ink,
      PdfEditTool.select,
      PdfEditTool.rectangle
    ]) {
      testWidgets('${middle ? "middle" : "Space"} pans without changing $tool',
          (tester) async {
        final editing = PdfEditingController(buildMultiPagePdf(3))
          ..addRectangle(0, const PdfRect(100, 500, 200, 600))
          ..selectAnnotation(0, 0)
          ..tool = tool;
        final viewer = PdfViewerController();
        await tester.pumpWidget(MaterialApp(
            home: ListenableBuilder(
          listenable: editing,
          builder: (_, __) => PdfViewer(
              document: editing.document,
              editing: editing,
              controller: viewer,
              initialFit: PdfViewerFit.width),
        )));
        await tester.pumpAndSettle();
        viewer.setZoom(3);
        viewer.requestKeyboardFocus();
        await tester.pumpAndSettle();
        final document = editing.document;
        final selected = editing.selectedAnnotationSlots.toList();
        final transform = tester
            .widget<InteractiveViewer>(find.byType(InteractiveViewer))
            .transformationController!;
        final before = transform.value.clone();
        final scroll = tester
            .state<ScrollableState>(find
                .descendant(
                    of: find.byType(PdfViewer),
                    matching: find.byType(Scrollable))
                .first)
            .position;
        final beforeY =
            scroll.pixels - before.storage[13] / before.getMaxScaleOnAxis();
        if (!middle) await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
        final drag = await tester.startGesture(const Offset(400, 300),
            kind: PointerDeviceKind.mouse,
            buttons: middle ? kMiddleMouseButton : kPrimaryMouseButton);
        await drag.moveBy(const Offset(-60, -80));
        await tester.pump();
        final after = transform.value;
        expect(after.storage[12] - before.storage[12], closeTo(-60, 0.01));
        final afterY =
            scroll.pixels - after.storage[13] / after.getMaxScaleOnAxis();
        expect(afterY - beforeY, closeTo(80 / after.getMaxScaleOnAxis(), 0.01));
        expect(editing.document, same(document));
        expect(editing.tool, tool);
        expect(editing.selectedAnnotationSlots, selected);
        if (tool == PdfEditTool.select) expect(selected, [(0, 0)]);
        if (!middle) {
          await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
          final held = transform.value.clone();
          final heldScroll = scroll.pixels;
          await drag.moveBy(const Offset(-40, -40));
          await tester.pump();
          expect(transform.value, held);
          expect(scroll.pixels, heldScroll);
        }
        await drag.up();
        await tester.pumpAndSettle();
        expect(editing.document, same(document));
        await tester.pumpWidget(const SizedBox());
        editing.dispose();
        viewer.dispose();
      });
    }
  }
}
