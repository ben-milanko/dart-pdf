// Copy/cut/paste of whole pages: the shared [PdfPageClipboard], the
// controller operations that fill and consume it, cross-document-tab
// pasting, and the thumbnail-view UI (selection-bar buttons, the context
// menu, the ⌘/Ctrl+C/X/V shortcuts, and the header paste entry).

import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/gestures.dart' show PointerDeviceKind, kSecondaryButton;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The "Page N" label a page draws, or '' for a blank page.
String labelOf(PdfDocument doc, int index) {
  final content = String.fromCharCodes(doc.page(index).contentBytes());
  return RegExp(r'\((Page \d+)\)').firstMatch(content)?.group(1) ?? '';
}

List<String> labelsOf(PdfDocument doc) =>
    [for (var i = 0; i < doc.pageCount; i++) labelOf(doc, i)];

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('PdfPageClipboard', () {
    test('starts empty and fills / clears with notification', () {
      final clip = PdfPageClipboard();
      var notified = 0;
      clip.addListener(() => notified++);
      expect(clip.isEmpty, isTrue);
      expect(clip.isNotEmpty, isFalse);
      expect(clip.pageCount, 0);
      expect(clip.bytes, isNull);

      clip.setPages(buildMultiPagePdf(2), 2);
      expect(clip.isNotEmpty, isTrue);
      expect(clip.pageCount, 2);
      expect(clip.bytes, isNotNull);
      expect(notified, 1);

      clip.clear();
      expect(clip.isEmpty, isTrue);
      expect(notified, 2);
      // clearing an already-empty clipboard doesn't notify again
      clip.clear();
      expect(notified, 2);
    });

    test('a controller defaults to the shared process-wide instance', () {
      addTearDown(PdfPageClipboard.instance.clear);
      final editing = PdfEditingController(buildMultiPagePdf(1));
      addTearDown(editing.dispose);
      expect(
          identical(editing.pageClipboard, PdfPageClipboard.instance), isTrue);
    });
  });

  group('controller copy / paste', () {
    test('copy fills the clipboard without touching the document', () {
      final clip = PdfPageClipboard();
      final editing =
          PdfEditingController(buildMultiPagePdf(3), pageClipboard: clip);
      addTearDown(editing.dispose);
      final before = editing.document;

      expect(editing.hasPageClipboard, isFalse);
      expect(editing.copyPages([0, 2]), isTrue);
      expect(editing.hasPageClipboard, isTrue);
      expect(clip.pageCount, 2);
      // copying is not an edit: no new revision, the document is unchanged
      expect(identical(editing.document, before), isTrue);
      expect(editing.document.pageCount, 3);
    });

    test('copy of nothing valid is a no-op', () {
      final editing = PdfEditingController(buildMultiPagePdf(2),
          pageClipboard: PdfPageClipboard());
      addTearDown(editing.dispose);
      expect(editing.copyPages(const []), isFalse);
      expect(editing.copyPages([5, 9]), isFalse);
      expect(editing.hasPageClipboard, isFalse);
    });

    test('paste drops the copied pages and selects them; one undo', () {
      final editing = PdfEditingController(buildMultiPagePdf(3),
          pageClipboard: PdfPageClipboard());
      addTearDown(editing.dispose);
      editing.copyPages([0]); // "Page 1"

      expect(editing.pastePages(at: 2), isTrue);
      expect(
          labelsOf(editing.document), ['Page 1', 'Page 2', 'Page 1', 'Page 3']);
      // the pasted run is selected so the strip highlights what landed
      expect(editing.selectedPages, [2]);

      // one revision: a single undo removes the paste
      editing.undo();
      expect(labelsOf(editing.document), ['Page 1', 'Page 2', 'Page 3']);
    });

    test('paste with no target appends at the end', () {
      final editing = PdfEditingController(buildMultiPagePdf(2),
          pageClipboard: PdfPageClipboard());
      addTearDown(editing.dispose);
      editing.copyPages([1]); // "Page 2"
      expect(editing.pastePages(), isTrue);
      expect(labelsOf(editing.document), ['Page 1', 'Page 2', 'Page 2']);
      expect(editing.selectedPages, [2]);
    });

    test('paste with an empty clipboard is a no-op', () {
      final editing = PdfEditingController(buildMultiPagePdf(2),
          pageClipboard: PdfPageClipboard());
      addTearDown(editing.dispose);
      expect(editing.pastePages(), isFalse);
      expect(editing.document.pageCount, 2);
    });

    test('copySelectedPages copies the strip selection', () {
      final clip = PdfPageClipboard();
      final editing =
          PdfEditingController(buildMultiPagePdf(4), pageClipboard: clip);
      addTearDown(editing.dispose);
      editing.selectPage(1);
      editing.selectPageRange(2); // pages 1..2
      expect(editing.copySelectedPages(), isTrue);
      expect(clip.pageCount, 2);
    });
  });

  group('controller cut', () {
    test('cut copies then removes, one undo restores both', () {
      final clip = PdfPageClipboard();
      final editing =
          PdfEditingController(buildMultiPagePdf(3), pageClipboard: clip);
      addTearDown(editing.dispose);

      expect(editing.cutPages([1]), isTrue);
      expect(clip.pageCount, 1);
      expect(labelsOf(editing.document), ['Page 1', 'Page 3']);
      expect(editing.hasPageSelection, isFalse);

      editing.undo();
      expect(labelsOf(editing.document), ['Page 1', 'Page 2', 'Page 3']);
    });

    test('cut that would empty the document is refused, clipboard untouched',
        () {
      final clip = PdfPageClipboard();
      final editing =
          PdfEditingController(buildMultiPagePdf(2), pageClipboard: clip);
      addTearDown(editing.dispose);
      expect(editing.cutPages([0, 1]), isFalse);
      expect(clip.isEmpty, isTrue);
      expect(editing.document.pageCount, 2);
    });

    test('cut then paste moves a page', () {
      final editing = PdfEditingController(buildMultiPagePdf(3),
          pageClipboard: PdfPageClipboard());
      addTearDown(editing.dispose);
      editing.cutPages([0]); // remove "Page 1"
      expect(labelsOf(editing.document), ['Page 2', 'Page 3']);
      editing.pastePages(); // append it at the end
      expect(labelsOf(editing.document), ['Page 2', 'Page 3', 'Page 1']);
    });
  });

  group('cross-document-tab paste', () {
    test('pages copied in one controller paste into another sharing the clip',
        () {
      final clip = PdfPageClipboard();
      final tabA =
          PdfEditingController(buildMultiPagePdf(3), pageClipboard: clip)
            ..addBlankPage(); // keep this session distinct
      addTearDown(tabA.dispose);
      final tabB =
          PdfEditingController(buildMultiPagePdf(2), pageClipboard: clip);
      addTearDown(tabB.dispose);

      expect(tabA.copyPages([0, 2]), isTrue); // "Page 1", "Page 3"
      // the other tab sees the shared clipboard right away
      expect(tabB.hasPageClipboard, isTrue);

      expect(tabB.pastePages(at: 1), isTrue);
      expect(labelsOf(tabB.document), ['Page 1', 'Page 1', 'Page 3', 'Page 2']);
      // pasting into B left A untouched
      expect(tabA.document.pageCount, 4);
    });

    test('the shared clipboard notifies every controller bound to it', () {
      final clip = PdfPageClipboard();
      final tabA =
          PdfEditingController(buildMultiPagePdf(1), pageClipboard: clip);
      addTearDown(tabA.dispose);
      final tabB =
          PdfEditingController(buildMultiPagePdf(1), pageClipboard: clip);
      addTearDown(tabB.dispose);
      var notifiedB = 0;
      tabB.addListener(() => notifiedB++);

      tabA.copyPages([0]);
      // B rebuilds so its paste affordances can enable
      expect(notifiedB, greaterThan(0));
      expect(tabB.hasPageClipboard, isTrue);
    });
  });

  group('PdfThumbnailView UI', () {
    void wideScreen(WidgetTester tester) {
      tester.view.physicalSize = const Size(1000, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
    }

    Future<({PdfEditingController editing, PdfViewerController viewer})>
        pumpGrid(
      WidgetTester tester, {
      int pages = 4,
      PdfEditingController? controller,
    }) async {
      final editing = controller ??
          PdfEditingController(buildMultiPagePdf(pages),
              pageClipboard: PdfPageClipboard());
      final viewer = PdfViewerController();
      if (controller == null) addTearDown(editing.dispose);
      addTearDown(viewer.dispose);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: PdfThumbnailView(
            controller: editing,
            viewerController: viewer,
          ),
        ),
      ));
      await tester.pump();
      return (editing: editing, viewer: viewer);
    }

    Future<void> drain(WidgetTester tester) =>
        tester.pump(const Duration(seconds: 2));

    testWidgets('the selection bar copies pages', (tester) async {
      wideScreen(tester);
      final refs = await pumpGrid(tester, pages: 4);
      await tester.tap(find.text('Page 1'));
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
      await tester.tap(find.text('Page 2'));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
      await tester.pump();
      expect(refs.editing.selectedPages, [0, 1]);

      await tester
          .tap(find.byKey(const ValueKey('pdf-thumbnail-copy-selected')));
      await tester.pump();
      expect(refs.editing.pageClipboard.pageCount, 2);
      expect(refs.editing.document.pageCount, 4); // copy is not an edit
      await drain(tester);
    });

    testWidgets('the selection bar cuts pages', (tester) async {
      wideScreen(tester);
      final refs = await pumpGrid(tester, pages: 4);
      // the bar only appears for a multi-selection
      await tester.tap(find.text('Page 1'));
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
      await tester.tap(find.text('Page 2'));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
      await tester.pump();
      expect(refs.editing.selectedPages, [0, 1]);

      await tester
          .tap(find.byKey(const ValueKey('pdf-thumbnail-cut-selected')));
      await tester.pump();
      expect(labelsOf(refs.editing.document), ['Page 3', 'Page 4']);
      expect(refs.editing.pageClipboard.pageCount, 2);
      expect(refs.editing.hasPageSelection, isFalse);
      await drain(tester);
    });

    testWidgets('⌘C copies the selection and ⌘V pastes it', (tester) async {
      wideScreen(tester);
      final refs = await pumpGrid(tester, pages: 3);
      await tester.tap(find.text('Page 1'));
      await tester.pump();
      expect(refs.editing.selectedPages, [0]);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(refs.editing.pageClipboard.pageCount, 1);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      // pasted right after the selected page 1
      expect(labelsOf(refs.editing.document),
          ['Page 1', 'Page 1', 'Page 2', 'Page 3']);
      await drain(tester);
    });

    testWidgets('⌘X cuts the selection', (tester) async {
      wideScreen(tester);
      final refs = await pumpGrid(tester, pages: 3);
      await tester.tap(find.text('Page 2'));
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyX);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(labelsOf(refs.editing.document), ['Page 1', 'Page 3']);
      expect(refs.editing.pageClipboard.pageCount, 1);
      await drain(tester);
    });

    testWidgets('Delete removes the grid selection', (tester) async {
      wideScreen(tester);
      final refs = await pumpGrid(tester, pages: 4);
      await tester.tap(find.text('Page 2'));
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
      await tester.tap(find.text('Page 3'));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
      await tester.pump();
      expect(refs.editing.selectedPages, [1, 2]);

      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pump();
      expect(labelsOf(refs.editing.document), ['Page 1', 'Page 4']);
      expect(refs.editing.hasPageSelection, isFalse);
      await drain(tester);
    });

    testWidgets('the header page-actions menu pastes', (tester) async {
      wideScreen(tester);
      final refs = await pumpGrid(tester, pages: 2);
      // nothing copied yet - no page actions button (no insert/export wired)
      expect(find.byKey(const ValueKey('pdf-thumbnail-page-actions')),
          findsNothing);

      refs.editing.copyPages([0]);
      await tester.pump();
      // the button appears once there's something to paste
      await tester
          .tap(find.byKey(const ValueKey('pdf-thumbnail-page-actions')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('pdf-thumbnail-paste-pages')));
      await tester.pumpAndSettle();
      // the header paste lands after the current page (index 0)
      expect(labelsOf(refs.editing.document), ['Page 1', 'Page 1', 'Page 2']);
      await drain(tester);
    });

    testWidgets('right-clicking a tile copies then pastes via the menu',
        (tester) async {
      wideScreen(tester);
      final refs = await pumpGrid(tester, pages: 3);

      // right-click page 1 -> Copy page
      await tester.tapAt(tester.getCenter(find.text('Page 1')),
          buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('pdf-thumbnail-menu-copy')));
      await tester.pumpAndSettle();
      expect(refs.editing.pageClipboard.pageCount, 1);

      // right-click page 3 -> Paste page (lands after it)
      await tester.tapAt(tester.getCenter(find.text('Page 3')),
          buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('pdf-thumbnail-menu-paste')));
      await tester.pumpAndSettle();
      expect(labelsOf(refs.editing.document),
          ['Page 1', 'Page 2', 'Page 3', 'Page 1']);
      await drain(tester);
    });
  });

  group('PdfThumbnailSidebar paste indicator', () {
    Future<({PdfEditingController editing, PdfViewerController viewer})>
        pumpStrip(
      WidgetTester tester, {
      int pages = 4,
    }) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final editing = PdfEditingController(buildMultiPagePdf(pages),
          pageClipboard: PdfPageClipboard());
      final viewer = PdfViewerController();
      addTearDown(editing.dispose);
      addTearDown(viewer.dispose);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Row(children: [
            PdfThumbnailSidebar(controller: editing, viewerController: viewer),
            const Expanded(child: SizedBox()),
          ]),
        ),
      ));
      await tester.pump();
      return (editing: editing, viewer: viewer);
    }

    Finder marker(int i) =>
        find.byKey(ValueKey('pdf-thumbnail-paste-indicator-$i'));

    testWidgets('hovering the strip marks where a copied page would paste',
        (tester) async {
      // the insertion mark is a desktop-hover affordance - pin a desktop
      // platform so hover is treated as reliable (touch has no hover). The
      // override must clear before the test body ends, so reset in finally.
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        final refs = await pumpStrip(tester, pages: 4);

        // hover Page 2 (index 1) with a mouse before anything is copied
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: Offset.zero);
        addTearDown(mouse.removePointer);
        await mouse.moveTo(tester.getCenter(find.text('Page 2')));
        await tester.pump();
        // nothing on the clipboard yet - no insertion mark
        expect(marker(1), findsNothing);

        // copy a page: the hovered tile now shows the insertion bar, alone
        refs.editing.copyPages([0]);
        await tester.pump();
        expect(marker(1), findsOneWidget);
        expect(marker(0), findsNothing);
        expect(marker(2), findsNothing);

        // the mark follows the cursor to another tile
        await mouse.moveTo(tester.getCenter(find.text('Page 3')));
        await tester.pump();
        expect(marker(1), findsNothing);
        expect(marker(2), findsOneWidget);

        // leaving the strip clears it
        await mouse.moveTo(const Offset(700, 700));
        await tester.pump();
        expect(marker(2), findsNothing);
        await tester.pump(const Duration(seconds: 2)); // drain tile renders
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('⌘/Ctrl+V lands after the hovered tile, not the selection',
        (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        final refs = await pumpStrip(tester, pages: 3);

        // select page 1 (the non-hover paste anchor) and copy it
        await tester.tap(find.text('Page 1'));
        await tester.pump();
        expect(refs.editing.selectedPages, [0]);
        refs.editing.copyPages([0]);
        await tester.pump();

        // hover Page 3 (index 2): the mark, and the paste, follow the cursor
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: Offset.zero);
        addTearDown(mouse.removePointer);
        await mouse.moveTo(tester.getCenter(find.text('Page 3')));
        await tester.pump();
        expect(marker(2), findsOneWidget);

        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pump();

        // pasted after the hovered Page 3, not after the selected Page 1
        expect(labelsOf(refs.editing.document),
            ['Page 1', 'Page 2', 'Page 3', 'Page 1']);
        await tester.pump(const Duration(seconds: 2)); // drain tile renders
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });
}
