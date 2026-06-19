// Touch text selection: drags scroll (never select), a long press
// selects the word under the finger and extends by word while dragged,
// and lifting shows drag handles plus a Copy/Select-All chip.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  // 800px viewport over a 612pt page (fit-width); fixture text 'Page N'
  // sits at 72,720 in 24pt Helvetica ('Page' spans x 72..120, 'N'
  // 132..144)
  const scale = 800 / 612;
  Offset view(double x, double y) => Offset(x * scale, (792 - y) * scale);

  Future<PdfViewerController> pumpViewer(WidgetTester tester,
      {int pages = 3}) async {
    final controller = PdfViewerController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PdfViewer(
          initialFit: PdfViewerFit.width,
          document: PdfDocument.open(buildMultiPagePdf(pages)),
          controller: controller,
        ),
      ),
    ));
    await tester.pump();
    return controller;
  }

  /// Long-presses the word at [at] and lifts, leaving handles + chip.
  Future<void> longPressSelect(WidgetTester tester, Offset at) async {
    final gesture = await tester.startGesture(at);
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.up();
    await tester.pump();
  }

  group('touch scrolling vs selection', () {
    testWidgets('a vertical touch drag over text scrolls, never selects',
        (tester) async {
      final controller = await pumpViewer(tester, pages: 5);
      await tester.dragFrom(view(100, 720), const Offset(0, -2500));
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      expect(controller.currentPage, greaterThan(0));
      expect(controller.hasSelection, isFalse);
      await tester.pump(const Duration(milliseconds: 400));
    });

    testWidgets('a horizontal touch drag across text does not select',
        (tester) async {
      // regression: the selection pan recognizer accepted touch, so any
      // swipe with a horizontal component crossed pan slop first and
      // turned into a text selection instead of a scroll
      final controller = await pumpViewer(tester);
      final gesture = await tester.startGesture(view(158, 720));
      await gesture.moveBy(const Offset(-40, -6));
      await tester.pump();
      await gesture.moveTo(view(50, 715));
      await tester.pump();
      await gesture.up();
      await tester.pump();
      expect(controller.hasSelection, isFalse);
      await tester.pump(const Duration(milliseconds: 400));
    });

    testWidgets('mouse drag selection still works and shows no touch chrome',
        (tester) async {
      final controller = await pumpViewer(tester);
      final gesture = await tester.startGesture(view(158, 720),
          kind: PointerDeviceKind.mouse);
      await gesture.moveBy(const Offset(-20, 0));
      await tester.pump();
      await gesture.moveTo(view(50, 720));
      await tester.pump();
      await gesture.up();
      await tester.pump();
      expect(controller.selectedText, 'Page 1');
      expect(find.byKey(const ValueKey('pdf-text-handle-start')), findsNothing);
      expect(find.byKey(const ValueKey('pdf-text-handle-end')), findsNothing);
      expect(
          find.byKey(const ValueKey('pdf-text-selection-chip')), findsNothing);
    });
  });

  group('long-press selection', () {
    testWidgets(
        'long press selects the word under the finger and shows '
        'handles and the chip', (tester) async {
      final controller = await pumpViewer(tester);
      await longPressSelect(tester, view(100, 720));

      expect(controller.selectedText, 'Page');
      expect(
          find.byKey(const ValueKey('pdf-text-handle-start')), findsOneWidget);
      expect(find.byKey(const ValueKey('pdf-text-handle-end')), findsOneWidget);
      expect(find.byKey(const ValueKey('pdf-text-selection-chip')),
          findsOneWidget);
      await tester.pump(const Duration(milliseconds: 400));
    });

    testWidgets('chrome stays hidden while the press is still down',
        (tester) async {
      final controller = await pumpViewer(tester);
      final gesture = await tester.startGesture(view(100, 720));
      await tester.pump(const Duration(milliseconds: 600));
      expect(controller.selectedText, 'Page');
      expect(find.byKey(const ValueKey('pdf-text-handle-end')), findsNothing);
      expect(
          find.byKey(const ValueKey('pdf-text-selection-chip')), findsNothing);
      await gesture.up();
      await tester.pump();
      expect(find.byKey(const ValueKey('pdf-text-handle-end')), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 400));
    });

    testWidgets('dragging during the long press extends by whole words',
        (tester) async {
      final controller = await pumpViewer(tester);
      final gesture = await tester.startGesture(view(100, 720));
      await tester.pump(const Duration(milliseconds: 600));
      expect(controller.selectedText, 'Page');
      await gesture.moveTo(view(140, 720));
      await tester.pump();
      expect(controller.selectedText, 'Page 1');
      await gesture.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    });

    testWidgets('long press on empty page area clears the selection',
        (tester) async {
      final controller = await pumpViewer(tester);
      await longPressSelect(tester, view(100, 720));
      expect(controller.hasSelection, isTrue);

      await longPressSelect(tester, view(300, 400));
      expect(controller.hasSelection, isFalse);
      expect(find.byKey(const ValueKey('pdf-text-handle-end')), findsNothing);
      await tester.pump(const Duration(milliseconds: 400));
    });

    testWidgets('a plain tap dismisses the selection and its chrome',
        (tester) async {
      final controller = await pumpViewer(tester);
      await longPressSelect(tester, view(100, 720));
      expect(controller.hasSelection, isTrue);

      await tester.tapAt(view(300, 400));
      await tester.pump(const Duration(milliseconds: 400));
      expect(controller.hasSelection, isFalse);
      expect(
          find.byKey(const ValueKey('pdf-text-selection-chip')), findsNothing);
    });

    testWidgets('long press does not select while an editing tool is armed',
        (tester) async {
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
      editing.tool = PdfEditTool.rectangle;
      await tester.pump();

      final gesture = await tester.startGesture(view(100, 720));
      await tester.pump(const Duration(milliseconds: 600));
      expect(viewer.hasSelection, isFalse);
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 400));
      expect(viewer.hasSelection, isFalse);
    });
  });

  group('selection handles', () {
    testWidgets('dragging the end handle extends the selection',
        (tester) async {
      final controller = await pumpViewer(tester);
      await longPressSelect(tester, view(100, 720));
      expect(controller.selectedText, 'Page');

      final endHandle = find.byKey(const ValueKey('pdf-text-handle-end'));
      final box = tester.getTopLeft(endHandle);
      final size = tester.getSize(endHandle);
      final handle = box + Offset(size.width / 2, size.height - 9);
      final gesture = await tester.startGesture(handle);
      await tester.pump();
      // the eager recognizer claims on contact: no slop to pay
      await gesture.moveBy(Offset((150 - 120) * scale, 0));
      await tester.pump();
      expect(controller.selectedText, 'Page 1');
      await gesture.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    });

    testWidgets('dragging the start handle re-anchors the other end',
        (tester) async {
      final controller = await pumpViewer(tester);
      await longPressSelect(tester, view(135, 720)); // the '1'
      expect(controller.selectedText, '1');

      // grab the ball above the line: on a one-word selection the two
      // handle boxes overlap across the stem zone (the end handle, on
      // top, wins there), but the ball regions stay unambiguous
      final box = tester
          .getTopLeft(find.byKey(const ValueKey('pdf-text-handle-start')));
      final size =
          tester.getSize(find.byKey(const ValueKey('pdf-text-handle-start')));
      final gesture =
          await tester.startGesture(box + Offset(size.width / 2, 6));
      await tester.pump();
      await gesture.moveTo(view(72, 720));
      await tester.pump();
      expect(controller.selectedText, 'Page 1');
      await gesture.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    });

    testWidgets('a handle drag scrolls nothing out from under itself',
        (tester) async {
      final controller = await pumpViewer(tester);
      await longPressSelect(tester, view(100, 720));
      final before = controller.currentPage;

      final handle =
          tester.getCenter(find.byKey(const ValueKey('pdf-text-handle-end')));
      final gesture = await tester.startGesture(handle);
      await tester.pump();
      await gesture.moveBy(const Offset(0, 120));
      await tester.pump();
      await gesture.up();
      await tester.pump();
      expect(controller.currentPage, before);
      await tester.pump(const Duration(milliseconds: 400));
    });
  });

  group('copy chip', () {
    testWidgets('Copy puts the selection on the clipboard and dismisses',
        (tester) async {
      final controller = await pumpViewer(tester);
      await longPressSelect(tester, view(100, 720));
      expect(controller.selectedText, 'Page');

      final copied = <String?>[];
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add((call.arguments as Map)['text'] as String?);
        }
        return null;
      });

      await tester
          .tap(find.byKey(const ValueKey('pdf-text-selection-chip-copy')));
      // touch taps on chrome resolve after the double-tap timeout
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();

      expect(copied, ['Page']);
      expect(controller.hasSelection, isFalse);
      expect(
          find.byKey(const ValueKey('pdf-text-selection-chip')), findsNothing);
    });

    testWidgets('Select all selects the whole page text', (tester) async {
      final controller = await pumpViewer(tester);
      await longPressSelect(tester, view(100, 720));
      expect(controller.selectedText, 'Page');

      await tester.tap(
          find.byKey(const ValueKey('pdf-text-selection-chip-select-all')));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();

      expect(controller.selectedText, 'Page 1');
      expect(find.byKey(const ValueKey('pdf-text-selection-chip')),
          findsOneWidget);
    });
  });
}
