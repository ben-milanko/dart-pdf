import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';

void main() {
  group('PdfEditingController.nudgeSelected', () {
    PdfEditingController oneRect() => PdfEditingController(buildMultiPagePdf(2))
      ..addRectangle(0, const PdfRect(100, 650, 180, 700));

    test('nothing selected is a no-op (no revision)', () {
      final editing = oneRect();
      addTearDown(editing.dispose);
      final revisions = editing.bytes.length;
      editing.nudgeSelected(0, -1);
      expect(editing.bytes.length, revisions);
    });

    test('arrow directions map to page space with y up (rotation 0)', () {
      final editing = oneRect();
      addTearDown(editing.dispose);
      editing.selectAnnotationAt(0, 140, 675);

      // up on screen raises the annotation in page space
      editing.nudgeSelected(0, -1);
      var rect = editing.document.page(0).annotations.single.rect;
      expect(rect.top, closeTo(701, 0.01));
      expect(rect.left, closeTo(100, 0.01));

      // right on screen increases x
      editing.nudgeSelected(1, 0);
      rect = editing.document.page(0).annotations.single.rect;
      expect(rect.left, closeTo(101, 0.01));
      expect(rect.top, closeTo(701, 0.01));

      // down and left walk it back
      editing.nudgeSelected(0, 1);
      editing.nudgeSelected(-1, 0);
      rect = editing.document.page(0).annotations.single.rect;
      expect(rect.left, closeTo(100, 0.01));
      expect(rect.top, closeTo(700, 0.01));

      // the selection survives the nudges
      expect(editing.selectedAnnotationSlots, [(0, 0)]);

      // each nudge is its own revision - a single undo reverts just the last
      editing.undo();
      rect = editing.document.page(0).annotations.single.rect;
      expect(rect.left, closeTo(101, 0.01));
      expect(rect.top, closeTo(700, 0.01));
    });

    test('the delta is translated through the page /Rotate (90°)', () {
      // page 0 of the nested tree inherits /Rotate 90
      final editing = PdfEditingController(buildNestedPageTreePdf())
        ..addRectangle(0, const PdfRect(100, 150, 180, 200));
      addTearDown(editing.dispose);
      expect(editing.document.page(0).rotation, 90);
      editing.selectAnnotationAt(0, 140, 175);

      // on a page turned 90° clockwise, pressing right on screen slides the
      // annotation along +y in page space (and up slides it along -x)
      editing.nudgeSelected(1, 0);
      var rect = editing.document.page(0).annotations.single.rect;
      expect(rect.left, closeTo(100, 0.01));
      expect(rect.bottom, closeTo(151, 0.01));

      editing.nudgeSelected(0, -1);
      rect = editing.document.page(0).annotations.single.rect;
      expect(rect.left, closeTo(99, 0.01));
      expect(rect.bottom, closeTo(151, 0.01));
    });
  });

  group('arrow keys in the viewer', () {
    const scale = 800 / 612;
    // an empty patch mid-page to focus the viewer without selecting anything
    final empty = const Offset(450 * scale, (792 - 400) * scale);

    Future<PdfEditingController> pumpEditor(WidgetTester tester) async {
      final editing = PdfEditingController(buildMultiPagePdf(2))
        ..addRectangle(0, const PdfRect(100, 650, 180, 700));
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

    Future<void> focusViewer(WidgetTester tester) async {
      await tester.tapAt(empty, kind: PointerDeviceKind.mouse);
      await tester.pump();
    }

    Future<void> arrow(WidgetTester tester, LogicalKeyboardKey key,
        {bool shift = false}) async {
      if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(key);
      if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
    }

    testWidgets('each arrow nudges the selection by a point', (tester) async {
      final editing = await pumpEditor(tester);
      await focusViewer(tester);
      editing.selectAnnotationAt(0, 140, 675);
      await tester.pump();
      PdfRect rect() => editing.document.page(0).annotations.single.rect;

      await arrow(tester, LogicalKeyboardKey.arrowUp);
      expect(rect().top, closeTo(701, 0.01));
      await arrow(tester, LogicalKeyboardKey.arrowDown);
      expect(rect().top, closeTo(700, 0.01));
      await arrow(tester, LogicalKeyboardKey.arrowRight);
      expect(rect().left, closeTo(101, 0.01));
      await arrow(tester, LogicalKeyboardKey.arrowLeft);
      expect(rect().left, closeTo(100, 0.01));
    });

    testWidgets('each Shift+arrow nudges by the coarse step', (tester) async {
      final editing = await pumpEditor(tester);
      await focusViewer(tester);
      editing.selectAnnotationAt(0, 140, 675);
      await tester.pump();
      PdfRect rect() => editing.document.page(0).annotations.single.rect;

      await arrow(tester, LogicalKeyboardKey.arrowRight, shift: true);
      expect(rect().left, closeTo(110, 0.01));
      await arrow(tester, LogicalKeyboardKey.arrowLeft, shift: true);
      expect(rect().left, closeTo(100, 0.01));
      await arrow(tester, LogicalKeyboardKey.arrowUp, shift: true);
      expect(rect().top, closeTo(710, 0.01));
      await arrow(tester, LogicalKeyboardKey.arrowDown, shift: true);
      expect(rect().top, closeTo(700, 0.01));
    });

    testWidgets('with nothing selected the arrow keys leave annotations alone',
        (tester) async {
      final editing = await pumpEditor(tester);
      await focusViewer(tester);
      final revisions = editing.bytes.length;

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(editing.bytes.length, revisions);
      expect(editing.document.page(0).annotations.single.rect.top,
          closeTo(700, 0.01));
    });
  });
}
