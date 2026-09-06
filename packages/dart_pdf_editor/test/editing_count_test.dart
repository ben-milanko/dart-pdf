// Count tool (PdfEditTool.count): tap to drop check-marks Bluebeam-style.
// Each tap places a /Stamp check-mark annotation and bumps the running
// tally (PdfEditingController.checkMarkCount); the marks behave like any
// other annotation (select/move/delete) and the tally tracks undo/redo.
import 'dart:convert';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:dart_pdf_editor/src/editing/editing_overlay.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

String appearanceText(PdfEditingController editing) {
  final annotation = editing.document.page(0).annotations.single;
  return latin1.decode(
      editing.document.cos.decodeStreamData(annotation.normalAppearance!));
}

/// The editing overlay's preview painter, read through a dynamic cast
/// (the painter class is private to the library).
dynamic overlayPainter(WidgetTester tester) => tester
    .widget<CustomPaint>(find
        .descendant(
            of: find.byType(EditingPageOverlay),
            matching: find.byType(CustomPaint))
        .first)
    .painter;

/// The overlay's hover-cursor layer - the pen dot, eraser ring, count/stamp
/// previews and rotate glyph, which read live state and repaint without a
/// rebuild. Read through a dynamic cast (the painter class is private).
dynamic cursorPainter(WidgetTester tester) => tester
    .widgetList<CustomPaint>(find.descendant(
      of: find.byType(EditingPageOverlay),
      matching: find.byType(CustomPaint),
    ))
    .map((paint) => paint.painter)
    .firstWhere(
        (painter) => painter.runtimeType.toString() == '_HoverCursorPainter');

void main() {
  group('PdfEditingController check-marks', () {
    test('placeCheckMark drops a /Stamp /Check centered on the tap', () {
      SharedPreferences.setMockInitialValues({});
      final editing = PdfEditingController(buildMultiPagePdf(1));
      addTearDown(editing.dispose);

      expect(editing.placeCheckMark(0, 300, 400), isTrue);
      final mark = editing.document.page(0).annotations.single;
      expect(mark.isCheckMark, isTrue);
      expect((mark.rect.left + mark.rect.right) / 2, closeTo(300, 1e-9));
      expect((mark.rect.bottom + mark.rect.top) / 2, closeTo(400, 1e-9));
      // a default-size square mark
      expect(
          mark.rect.width, closeTo(PdfEditingController.checkMarkSize, 1e-9));
      expect(mark.rect.width, closeTo(mark.rect.height, 1e-9));
    });

    test('the mark follows the selected colour', () {
      SharedPreferences.setMockInitialValues({});
      final editing = PdfEditingController(buildMultiPagePdf(1));
      addTearDown(editing.dispose);

      editing.color = const Color(0xFFC03030);
      editing.placeCheckMark(0, 100, 100);
      expect(editing.document.page(0).annotations.single.color, 0xC03030);
    });

    test('placeCheckMark centers on the tap, off the page edge included', () {
      SharedPreferences.setMockInitialValues({});
      final editing = PdfEditingController(buildMultiPagePdf(1));
      addTearDown(editing.dispose);

      // a tap 2pt in from the corner of the 612x792 crop box: the mark
      // centers there and hangs off the page instead of jumping inward
      expect(editing.placeCheckMark(0, 2, 2), isTrue);
      final rect = editing.document.page(0).annotations.single.rect;
      const half = PdfEditingController.checkMarkSize / 2;
      expect(rect.left, closeTo(2 - half, 1e-9));
      expect(rect.bottom, closeTo(2 - half, 1e-9));
      expect(rect.right, closeTo(2 + half, 1e-9));
      expect(rect.top, closeTo(2 + half, 1e-9));
    });

    test('checkMarkPlacement is the rect the tap commits', () {
      SharedPreferences.setMockInitialValues({});
      final editing = PdfEditingController(buildMultiPagePdf(1));
      addTearDown(editing.dispose);

      // the count tool's hover preview draws this rect; drift between it
      // and the commit would show as the mark jumping on release
      final preview = editing.checkMarkPlacement(0, 600, 780);
      expect(editing.placeCheckMark(0, 600, 780), isTrue);
      expect(editing.document.page(0).annotations.single.rect, preview);
    });

    test('checkMarkCount tallies marks across pages and tracks undo/redo', () {
      SharedPreferences.setMockInitialValues({});
      final editing = PdfEditingController(buildMultiPagePdf(2));
      addTearDown(editing.dispose);

      expect(editing.checkMarkCount, 0);
      editing.placeCheckMark(0, 100, 100);
      editing.placeCheckMark(0, 200, 200);
      editing.placeCheckMark(1, 100, 100);
      expect(editing.checkMarkCount, 3);

      editing.undo();
      expect(editing.checkMarkCount, 2);
      editing.redo();
      expect(editing.checkMarkCount, 3);
    });

    test('non-check stamps do not count towards the tally', () {
      SharedPreferences.setMockInitialValues({});
      final editing = PdfEditingController(buildMultiPagePdf(1));
      addTearDown(editing.dispose);

      editing.placeTextStamp(0, 200, 200, 'APPROVED');
      expect(editing.checkMarkCount, 0);
    });

    test('placeCheckMark counter-rotates on a rotated page', () {
      SharedPreferences.setMockInitialValues({});
      final editing = PdfEditingController(buildMultiPagePdf(1));
      addTearDown(editing.dispose);

      expect(editing.rotatePages([0], 90), isTrue);
      expect(editing.placeCheckMark(0, 300, 400), isTrue);

      final mark = editing.document.page(0).annotations.single;
      expect(mark.isCheckMark, isTrue);
      expect(editing.checkMarkCount, 1);
      expect(appearanceText(editing), contains('0 1 -1 0'));
    });
  });

  group('count tool in the viewer', () {
    const scale = 800 / 612;
    Offset view(double x, double y) => Offset(x * scale, (792 - y) * scale);

    Future<void> tap(WidgetTester tester, Offset position) async {
      await tester.tapAt(position);
      await tester.pump(const Duration(milliseconds: 400));
    }

    Future<PdfEditingController> pumpEditor(WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      final editing = PdfEditingController(buildMultiPagePdf(1));
      final viewer = PdfViewerController();
      addTearDown(editing.dispose);
      addTearDown(viewer.dispose);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: editing,
            builder: (context, _) => PdfViewer(
              initialFit: PdfViewerFit.width,
              document: editing.document,
              controller: viewer,
              editing: editing,
            ),
          ),
        ),
      ));
      await tester.pump();
      return editing;
    }

    testWidgets('each tap drops a check-mark and bumps the tally',
        (tester) async {
      final editing = await pumpEditor(tester);
      editing.tool = PdfEditTool.count;
      await tester.pump();

      await tap(tester, view(200, 400));
      await tester.pump();
      await tap(tester, view(300, 400));
      await tester.pump();

      final marks = editing.document.page(0).annotations;
      expect(marks.length, 2);
      expect(marks.every((a) => a.isCheckMark), isTrue);
      expect(editing.checkMarkCount, 2);
    });

    testWidgets('count taps paint an immediate afterimage before the raster',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final editing = PdfEditingController(buildMultiPagePdf(1))
        ..color = const Color(0xFF2E7D32)
        ..tool = PdfEditTool.count;
      addTearDown(editing.dispose);

      final page = editing.document.page(0);
      final geometry = PdfPageGeometry(
        cropBox: page.cropBox,
        rotation: 0,
        viewSize: const Size(306, 396),
      );
      Offset local(double x, double y) => Offset(x * 0.5, (792 - y) * 0.5);
      await tester.pumpWidget(MaterialApp(
        home: Material(
          child: Center(
            child: SizedBox(
              width: geometry.viewSize.width,
              height: geometry.viewSize.height,
              child: EditingPageOverlay(
                controller: editing,
                pageIndex: 0,
                geometry: geometry,
                textPrompt: showPdfTextPrompt,
                rasterCurrent: false,
              ),
            ),
          ),
        ),
      ));
      await tester.pump();

      final origin = tester.getTopLeft(find.byType(EditingPageOverlay));
      await tester.tapAt(origin + local(240, 420),
          kind: PointerDeviceKind.mouse);
      await tester.pump();

      final mark = editing.document.page(0).annotations.single;
      final after = overlayPainter(tester).afterStamp;
      expect(after, isNotNull);
      expect(after.check, isTrue);
      expect(after.text, isNull);
      expect(after.color, const Color(0xFF2E7D32));
      expect(after.rect,
          rectMoreOrLessEquals(geometry.toViewRect(mark.rect), epsilon: 0.01));
    });

    testWidgets('count tool previews the check mark under the mouse',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final editing = PdfEditingController(buildMultiPagePdf(1))
        ..color = const Color(0xFF2E7D32)
        ..tool = PdfEditTool.count;
      addTearDown(editing.dispose);

      final page = editing.document.page(0);
      final geometry = PdfPageGeometry(
        cropBox: page.cropBox,
        rotation: 0,
        viewSize: const Size(306, 396),
      );
      Offset local(double x, double y) => Offset(x * 0.5, (792 - y) * 0.5);
      await tester.pumpWidget(MaterialApp(
        home: Material(
          child: Center(
            child: SizedBox(
              width: geometry.viewSize.width,
              height: geometry.viewSize.height,
              child: EditingPageOverlay(
                controller: editing,
                pageIndex: 0,
                geometry: geometry,
                textPrompt: showPdfTextPrompt,
              ),
            ),
          ),
        ),
      ));
      await tester.pump();

      final origin = tester.getTopLeft(find.byType(EditingPageOverlay));
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: origin + local(200, 420));
      await tester.pump();
      await gesture.moveTo(origin + local(240, 420));
      await tester.pump();

      final preview = cursorPainter(tester).countPreview;
      expect(preview, isNotNull);
      expect(preview.check, isTrue);
      expect(preview.text, isNull);
      expect(preview.color, const Color(0xFF2E7D32));
      expect(preview.rect.center,
          offsetMoreOrLessEquals(local(240, 420), epsilon: 0.01));
      expect(editing.document.page(0).annotations, isEmpty);

      await gesture.removePointer();
      await tester.pump();
    });

    testWidgets('the toolbar shows the running tally while the tool is armed',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final editing = PdfEditingController(buildMultiPagePdf(1));
      final viewer = PdfViewerController();
      addTearDown(editing.dispose);
      addTearDown(viewer.dispose);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: editing,
            builder: (context, _) => const SizedBox.expand(),
          ),
          bottomNavigationBar: PdfEditingToolbar(
            controller: editing,
            viewerController: viewer,
          ),
        ),
      ));
      await tester.pump();

      const tally = ValueKey('pdf-count-tally');
      // the tally chip only shows with the count tool armed
      expect(find.byKey(tally), findsNothing);
      editing.tool = PdfEditTool.count;
      await tester.pump();
      expect(find.byKey(tally), findsOneWidget);
      expect(find.descendant(of: find.byKey(tally), matching: find.text('0')),
          findsOneWidget);

      editing.placeCheckMark(0, 100, 100);
      editing.placeCheckMark(0, 200, 200);
      await tester.pump();
      expect(find.descendant(of: find.byKey(tally), matching: find.text('2')),
          findsOneWidget);
    });
  });
}
