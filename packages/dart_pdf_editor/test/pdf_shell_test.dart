import 'dart:typed_data';

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

// The drop-in shells: PdfReader (view-only) and PdfEditorView (the full
// workbench). The pieces they compose have their own suites - these
// tests cover the wiring: features toggling chrome, panel toggles,
// session ownership, and the save/changed callbacks.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pump(WidgetTester tester, Widget body) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: body)));
    await tester.pump();
  }

  void compactScreen(WidgetTester tester) {
    tester.view.physicalSize = const Size(600, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Uint8List buildBookmarkedPdf() {
    final editor = PdfEditor(PdfDocument.open(buildMultiPagePdf(3)));
    editor.addOutlineItem('Intro', pageIndex: 0);
    editor.addOutlineItem('Details', pageIndex: 1);
    return editor.save();
  }

  Future<void> openShellControls(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('pdf-shell-controls')),
        kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
  }

  Visibility actionVisibility(WidgetTester tester, Finder action) =>
      tester.widget<Visibility>(
        find.ancestor(of: action, matching: find.byType(Visibility)).first,
      );

  Future<TestGesture> hoverAt(WidgetTester tester, Offset target) async {
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(799, 599));
    addTearDown(mouse.removePointer);
    await tester.pump();
    await mouse.moveTo(target);
    await tester.pump();
    return mouse;
  }

  group('PdfReader', () {
    testWidgets('stock chrome: search, page number, view options, thumbnails',
        (tester) async {
      await pump(tester, PdfReader(bytes: buildMultiPagePdf(3)));
      expect(find.byKey(const ValueKey('pdf-search-field')), findsOneWidget);
      expect(
          find.byKey(const ValueKey('pdf-page-number-field')), findsOneWidget);
      expect(
          find.byKey(const ValueKey('pdf-shell-view-options')), findsOneWidget);
      expect(find.byKey(const ValueKey('pdf-shell-zoom-menu')), findsOneWidget);
      expect(
          find.byKey(const ValueKey('pdf-shell-zoom-reset')), findsOneWidget);
      expect(find.byKey(const ValueKey('pdf-shell-thumbnails-toggle')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('pdf-shell-bookmarks-toggle')),
          findsOneWidget);
      // view-only: no editing toolbar anywhere
      expect(find.byType(PdfEditingToolbar), findsNothing);
      expect(find.byType(PdfViewer), findsOneWidget);
    });

    testWidgets('forwards page preview and raster cache policies',
        (tester) async {
      final viewer = PdfViewerController();
      addTearDown(viewer.dispose);
      const policy = PdfPageRasterCachePolicy(
        maxBytes: 2 * 1024 * 1024 * 1024,
        maxEntryBytes: 64 * 1024 * 1024,
      );
      const lodPolicy = PdfPagePreviewLodPolicy(
        intermediateLongestSides: [360, 720],
      );
      await pump(
        tester,
        PdfReader(
          bytes: buildMultiPagePdf(2),
          controller: viewer,
          pagePreviewLodPolicy: lodPolicy,
          pageRasterCachePolicy: policy,
        ),
      );
      expect(viewer.pagePreviewCache!.maxFullRasterBytes, policy.maxBytes);
      expect(viewer.pagePreviewCache!.intermediateLongestSides,
          lodPolicy.intermediateLongestSides);
    });

    testWidgets('zoom menu changes and resets viewer zoom', (tester) async {
      final viewer = PdfViewerController();
      addTearDown(viewer.dispose);
      await pump(
          tester, PdfReader(bytes: buildMultiPagePdf(2), controller: viewer));

      expect(
          find.byKey(const ValueKey('pdf-shell-zoom-label')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('pdf-shell-zoom-menu')),
          kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('pdf-shell-zoom-150')),
          kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      expect(viewer.zoom, closeTo(1.5, 0.01));
      expect(find.text('150%'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('pdf-shell-zoom-reset')),
          kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      expect(viewer.zoom, closeTo(1, 0.01));
      expect(find.text('100%'), findsOneWidget);
    });

    testWidgets('PdfReaderFeatures.none leaves just the pages', (tester) async {
      await pump(
        tester,
        PdfReader(
          bytes: buildMultiPagePdf(2),
          features: const PdfReaderFeatures.none(),
        ),
      );
      expect(find.byType(PdfViewer), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(find.byType(PdfThumbnailSidebar), findsNothing);
      expect(find.byType(IconButton), findsNothing);
    });

    testWidgets('thumbnails are read-only: no delete button, no reorder drag',
        (tester) async {
      // showThumbnailSidebar defaults true, so the strip is open
      await pump(tester, PdfReader(bytes: buildMultiPagePdf(3)));
      expect(find.byType(PdfThumbnailSidebar), findsOneWidget);
      // the editing strip shows a per-tile delete; the reader must not
      expect(
        find.descendant(
          of: find.byType(PdfThumbnailSidebar),
          matching: find.byIcon(Icons.delete_outline),
        ),
        findsNothing,
      );
    });

    testWidgets('bookmarks panel navigates in reader mode', (tester) async {
      final viewer = PdfViewerController();
      final prefs = PdfEditingPreferences();
      addTearDown(viewer.dispose);
      addTearDown(prefs.dispose);
      prefs.showBookmarkSidebar = true;

      await pump(
          tester,
          PdfReader(
              bytes: buildBookmarkedPdf(),
              controller: viewer,
              preferences: prefs));

      expect(find.byType(PdfBookmarkSidebar), findsOneWidget);
      expect(find.text('Details'), findsOneWidget);
      expect(find.byKey(const ValueKey('pdf-bookmark-add')), findsNothing);

      await tester.tap(find.text('Details'));
      await tester.pumpAndSettle();
      expect(viewer.currentPage, 1);
    });

    testWidgets('compact first run starts with thumbnails closed',
        (tester) async {
      compactScreen(tester);
      final prefs = PdfEditingPreferences();
      await prefs.ready;
      addTearDown(prefs.dispose);

      await pump(
          tester, PdfReader(bytes: buildMultiPagePdf(2), preferences: prefs));
      expect(prefs.showThumbnailSidebar, isTrue);
      expect(prefs.hasShowThumbnailSidebarPreference, isFalse);
      expect(find.byType(PdfThumbnailSidebar), findsNothing);
      expect(find.byKey(const ValueKey('pdf-shell-thumbnails-toggle')),
          findsNothing);
      await openShellControls(tester);
      final toggle = tester.widget(
          find.byKey(const ValueKey('pdf-shell-thumbnails-toggle'))) as dynamic;
      expect(toggle.active, isFalse);

      await tester.tap(
          find.byKey(const ValueKey('pdf-shell-thumbnails-toggle')),
          kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      expect(find.byType(PdfThumbnailSidebar), findsOneWidget);
      expect(prefs.hasShowThumbnailSidebarPreference, isTrue);
      expect(prefs.showThumbnailSidebar, isTrue);
    });

    testWidgets('header toggle hides and shows the thumbnail strip',
        (tester) async {
      final prefs = PdfEditingPreferences();
      addTearDown(prefs.dispose);
      await pump(
          tester, PdfReader(bytes: buildMultiPagePdf(2), preferences: prefs));
      expect(find.byType(PdfThumbnailSidebar), findsOneWidget);
      await tester.tap(
          find.byKey(const ValueKey('pdf-shell-thumbnails-toggle')),
          kind: PointerDeviceKind.mouse);
      await tester.pump();
      expect(find.byType(PdfThumbnailSidebar), findsNothing);
      expect(prefs.showThumbnailSidebar, isFalse);
    });

    testWidgets('swapping bytes opens the new document', (tester) async {
      final viewer = PdfViewerController();
      addTearDown(viewer.dispose);
      final one = buildMultiPagePdf(1);
      final three = buildMultiPagePdf(3);
      await pump(tester, PdfReader(bytes: one, controller: viewer));
      expect(viewer.pageCount, 1);
      await pump(tester, PdfReader(bytes: three, controller: viewer));
      expect(viewer.pageCount, 3);
    });

    testWidgets('view options menu toggles persisted display settings',
        (tester) async {
      final prefs = PdfEditingPreferences();
      addTearDown(prefs.dispose);
      await pump(
          tester, PdfReader(bytes: buildMultiPagePdf(1), preferences: prefs));
      expect(prefs.showAnnotations, isTrue);
      await tester.tap(find.byKey(const ValueKey('pdf-shell-view-options')),
          kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('pdf-shell-show-annotations')),
          kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      expect(prefs.showAnnotations, isFalse);

      expect(prefs.showScrollbarChapters, isFalse);
      await tester.tap(find.byKey(const ValueKey('pdf-shell-view-options')),
          kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      await tester.tap(
          find.byKey(const ValueKey('pdf-shell-show-scrollbar-chapters')),
          kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      expect(prefs.showScrollbarChapters, isTrue);
      expect(
          tester
              .widget<PdfViewer>(find.byType(PdfViewer))
              .showScrollbarChapters,
          isTrue);
    });

    testWidgets('view options can switch to reflow text', (tester) async {
      final prefs = PdfEditingPreferences();
      addTearDown(prefs.dispose);
      await pump(
          tester, PdfReader(bytes: buildClassicPdf(), preferences: prefs));
      expect(find.byType(PdfViewer), findsOneWidget);
      expect(find.byType(PdfReflowView), findsNothing);

      await tester.tap(find.byKey(const ValueKey('pdf-shell-view-options')),
          kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('pdf-shell-reflow-view')),
          kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();

      expect(prefs.showReflowView, isTrue);
      expect(find.byType(PdfViewer), findsNothing);
      // The Pages strip stays available in reflow - it drives the reading view
      // (page taps scroll it) - while the canvas-bound search and page-number
      // controls, which have no page to act on, drop away.
      expect(find.byType(PdfThumbnailSidebar), findsOneWidget);
      expect(find.byKey(const ValueKey('pdf-search-field')), findsNothing);
      expect(find.byKey(const ValueKey('pdf-page-number-field')), findsNothing);
      expect(find.byType(PdfReflowView), findsOneWidget);
      expect(find.text('Hello, world!'), findsOneWidget);
    });

    testWidgets('pageColorEditable: false hides the page-color item',
        (tester) async {
      final prefs = PdfEditingPreferences();
      addTearDown(prefs.dispose);
      await pump(
          tester,
          PdfReader(
              bytes: buildMultiPagePdf(1),
              preferences: prefs,
              features: const PdfReaderFeatures(pageColorEditable: false)));
      await tester.tap(find.byKey(const ValueKey('pdf-shell-view-options')),
          kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      // the menu is open (annotations item shows) but page color is gone
      expect(find.byKey(const ValueKey('pdf-shell-show-annotations')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('pdf-shell-page-color')), findsNothing);
    });
  });

  group('PdfEditorView', () {
    testWidgets('stock chrome: header, toolbar, panel toggles', (tester) async {
      await pump(tester, PdfEditorView(bytes: buildMultiPagePdf(2)));
      expect(find.byType(PdfEditingToolbar), findsOneWidget);
      expect(find.byKey(const ValueKey('pdf-search-field')), findsOneWidget);
      expect(
          find.byKey(const ValueKey('pdf-page-number-field')), findsOneWidget);
      for (final key in const [
        'pdf-shell-search-results-toggle',
        'pdf-shell-view-options',
        'pdf-shell-thumbnails-toggle',
        'pdf-shell-bookmarks-toggle',
        'pdf-shell-annotations-toggle',
        'pdf-shell-properties-toggle',
      ]) {
        expect(find.byKey(ValueKey(key)), findsOneWidget, reason: key);
      }
      expect(
          find.descendant(
              of: find.byKey(const ValueKey('pdf-shell-panels')),
              matching: find
                  .byKey(const ValueKey('pdf-shell-search-results-toggle'))),
          findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('pdf-shell-view-options')),
          kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('pdf-shell-author')), findsOneWidget);
      expect(
          find.byKey(const ValueKey('pdf-shell-reflow-view')), findsOneWidget);
    });

    testWidgets('forwards page preview and raster cache policies',
        (tester) async {
      final viewer = PdfViewerController();
      addTearDown(viewer.dispose);
      const policy = PdfPageRasterCachePolicy(
        maxBytes: 2 * 1024 * 1024 * 1024,
        maxEntryBytes: 64 * 1024 * 1024,
      );
      const lodPolicy = PdfPagePreviewLodPolicy(
        intermediateLongestSides: [360, 720],
      );
      await pump(
        tester,
        PdfEditorView(
          bytes: buildMultiPagePdf(2),
          viewerController: viewer,
          pagePreviewLodPolicy: lodPolicy,
          pageRasterCachePolicy: policy,
        ),
      );
      expect(viewer.pagePreviewCache!.maxFullRasterBytes, policy.maxBytes);
      expect(viewer.pagePreviewCache!.intermediateLongestSides,
          lodPolicy.intermediateLongestSides);
    });

    testWidgets('customStamps are supplied to the owned editor session',
        (tester) async {
      List<PdfCustomStamp>? seen;
      const audit = PdfCustomStamp(
        text: 'AUDIT',
        color: 0x1A3E8C,
        type: 'Audit',
        tags: ['external'],
      );
      await pump(
        tester,
        PdfEditorView(
          bytes: buildMultiPagePdf(1),
          customStamps: const [audit],
          toolbarBuilder: (context, controller, viewer) {
            seen = controller.customStamps;
            return const SizedBox.shrink();
          },
        ),
      );

      expect(seen, [audit]);
    });

    testWidgets('settings opens keyboard shortcuts submenu', (tester) async {
      await pump(tester, PdfEditorView(bytes: buildMultiPagePdf(2)));

      await tester.tap(find.byKey(const ValueKey('pdf-shell-view-options')),
          kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('pdf-shell-shortcuts')));
      await tester.pumpAndSettle();

      expect(find.text('Keyboard shortcuts'), findsOneWidget);
      expect(find.byKey(const ValueKey('pdf-shell-shortcut-rectangle')),
          findsOneWidget);
      expect(find.text('R'), findsOneWidget);
      expect(find.byKey(const ValueKey('pdf-shell-shortcuts-reset')),
          findsOneWidget);
    });

    // Opens the keyboard-shortcuts sheet from the settings menu.
    Future<void> openShortcutsSheet(WidgetTester tester) async {
      await tester.tap(find.byKey(const ValueKey('pdf-shell-view-options')),
          kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('pdf-shell-shortcuts')));
      await tester.pumpAndSettle();
    }

    // Filters the (now full) tool list down to a single tool so its tile is
    // on-screen and tappable regardless of list length.
    Future<void> filterShortcuts(WidgetTester tester, String query) async {
      await tester.enterText(
          find.byKey(const ValueKey('pdf-shell-shortcuts-search')), query);
      await tester.pumpAndSettle();
    }

    testWidgets('rebinding a shortcut updates the label and persists on Done',
        (tester) async {
      await pump(tester, PdfEditorView(bytes: buildMultiPagePdf(2)));
      await openShortcutsSheet(tester);
      await filterShortcuts(tester, 'Rectangle');

      // Capture a new key for the rectangle tool.
      await tester
          .tap(find.byKey(const ValueKey('pdf-shell-shortcut-rectangle')));
      await tester.pumpAndSettle();
      expect(find.text('Press a key'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
      await tester.pumpAndSettle();

      // The capture dialog closed and the new binding is shown.
      expect(find.text('Press a key'), findsNothing);
      expect(find.text('B'), findsOneWidget);
      expect(find.text('R'), findsNothing);

      // Done commits the draft; reopening shows the persisted binding.
      await tester.tap(find.byKey(const ValueKey('pdf-shell-shortcuts-done')));
      await tester.pumpAndSettle();
      await openShortcutsSheet(tester);
      await filterShortcuts(tester, 'Rectangle');
      expect(find.text('B'), findsOneWidget);
    });

    testWidgets('Delete clears a binding and Reset restores the defaults',
        (tester) async {
      await pump(tester, PdfEditorView(bytes: buildMultiPagePdf(2)));
      await openShortcutsSheet(tester);
      await filterShortcuts(tester, 'Rectangle');

      await tester
          .tap(find.byKey(const ValueKey('pdf-shell-shortcut-rectangle')));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pumpAndSettle();
      expect(find.text('R'), findsNothing);
      expect(find.text('Unbound'), findsWidgets);

      await tester.tap(find.byKey(const ValueKey('pdf-shell-shortcuts-reset')));
      await tester.pumpAndSettle();
      expect(find.text('R'), findsOneWidget);
    });

    testWidgets('Escape cancels key capture and leaves the binding intact',
        (tester) async {
      await pump(tester, PdfEditorView(bytes: buildMultiPagePdf(2)));
      await openShortcutsSheet(tester);
      await filterShortcuts(tester, 'Rectangle');

      await tester
          .tap(find.byKey(const ValueKey('pdf-shell-shortcut-rectangle')));
      await tester.pumpAndSettle();
      expect(find.text('Press a key'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(find.text('Press a key'), findsNothing);
      expect(find.text('R'), findsOneWidget);
    });

    testWidgets('shortcuts are grouped under tool-category headers',
        (tester) async {
      await pump(tester, PdfEditorView(bytes: buildMultiPagePdf(2)));
      await openShortcutsSheet(tester);

      // The Shapes header sits above the rectangle tool it groups.
      expect(find.byKey(const ValueKey('pdf-shell-shortcut-group-shapes')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('pdf-shell-shortcut-rectangle')),
          findsOneWidget);
      expect(find.text('R'), findsOneWidget);
      final headerY = tester
          .getTopLeft(
              find.byKey(const ValueKey('pdf-shell-shortcut-group-shapes')))
          .dy;
      final rectY = tester
          .getTopLeft(
              find.byKey(const ValueKey('pdf-shell-shortcut-rectangle')))
          .dy;
      expect(headerY, lessThan(rectY));

      // A group lower down builds once scrolled into view.
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('pdf-shell-shortcut-group-insert')),
        200,
        scrollable: find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(find.byKey(const ValueKey('pdf-shell-shortcut-group-insert')),
          findsOneWidget);
    });

    testWidgets('searching filters the shortcut list and its group headers',
        (tester) async {
      await pump(tester, PdfEditorView(bytes: buildMultiPagePdf(2)));
      await openShortcutsSheet(tester);

      await tester.enterText(
          find.byKey(const ValueKey('pdf-shell-shortcuts-search')), 'rect');
      await tester.pumpAndSettle();

      // Only the rectangle tool (and its Shapes header) survives the filter.
      expect(find.byKey(const ValueKey('pdf-shell-shortcut-rectangle')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('pdf-shell-shortcut-ellipse')),
          findsNothing);
      expect(find.byKey(const ValueKey('pdf-shell-shortcut-group-shapes')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('pdf-shell-shortcut-group-insert')),
          findsNothing);
    });

    testWidgets('searching by key label matches, and a miss shows a message',
        (tester) async {
      await pump(tester, PdfEditorView(bytes: buildMultiPagePdf(2)));
      await openShortcutsSheet(tester);

      // The rectangle tool is bound to "R" - searching the key finds it.
      await tester.enterText(
          find.byKey(const ValueKey('pdf-shell-shortcuts-search')), 'r');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('pdf-shell-shortcut-rectangle')),
          findsOneWidget);

      // A query no tool matches shows the empty-state message instead.
      await tester.enterText(
          find.byKey(const ValueKey('pdf-shell-shortcuts-search')), 'zzzz');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('pdf-shell-shortcuts-no-matches')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('pdf-shell-shortcut-rectangle')),
          findsNothing);
    });

    testWidgets('view options can switch the editor to reflow text',
        (tester) async {
      final prefs = PdfEditingPreferences();
      addTearDown(prefs.dispose);
      await pump(
          tester, PdfEditorView(bytes: buildClassicPdf(), preferences: prefs));
      expect(find.byType(PdfViewer), findsOneWidget);
      expect(find.byType(PdfReflowView), findsNothing);
      expect(find.byType(PdfEditingToolbar), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('pdf-shell-view-options')),
          kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('pdf-shell-reflow-view')),
          kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();

      expect(prefs.showReflowView, isTrue);
      expect(find.byType(PdfViewer), findsNothing);
      expect(find.byType(PdfReflowView), findsOneWidget);
      expect(find.byType(PdfEditingToolbar), findsNothing);
      expect(find.byKey(const ValueKey('pdf-search-field')), findsNothing);
      expect(find.byKey(const ValueKey('pdf-page-number-field')), findsNothing);
      expect(find.text('Hello, world!'), findsOneWidget);
    });

    testWidgets('View options can swap in the full-area page grid',
        (tester) async {
      final prefs = PdfEditingPreferences();
      addTearDown(prefs.dispose);
      await pump(tester,
          PdfEditorView(bytes: buildMultiPagePdf(3), preferences: prefs));
      expect(find.byType(PdfThumbnailView), findsNothing);
      expect(find.byType(PdfViewer), findsOneWidget);
      expect(find.byType(PdfEditingToolbar), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('pdf-shell-view-options')),
          kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('pdf-shell-page-grid')),
          kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();

      expect(prefs.showThumbnailView, isTrue);
      expect(find.byType(PdfThumbnailView), findsOneWidget);
      // the viewer stays mounted under the opaque grid (so a tap can scroll
      // it), but the editing toolbar and the viewer-only header controls go
      expect(find.byType(PdfViewer), findsOneWidget);
      expect(find.byType(PdfEditingToolbar), findsNothing);
      expect(find.byKey(const ValueKey('pdf-search-field')), findsNothing);
      expect(find.byKey(const ValueKey('pdf-shell-zoom-menu')), findsNothing);

      // single click selects; the second click opens the page and returns to
      // the page view
      await tester.tap(find.text('Page 2'));
      await tester.pump();
      expect(prefs.showThumbnailView, isTrue);
      await tester.tap(find.text('Page 2'));
      await tester.pump();
      expect(prefs.showThumbnailView, isFalse);
      expect(find.byType(PdfThumbnailView), findsNothing);
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('opening the page grid clears reflow', (tester) async {
      final prefs = PdfEditingPreferences();
      addTearDown(prefs.dispose);
      prefs.showReflowView = true;
      await pump(
          tester, PdfEditorView(bytes: buildClassicPdf(), preferences: prefs));
      expect(find.byType(PdfReflowView), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('pdf-shell-view-options')),
          kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('pdf-shell-page-grid')),
          kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();

      expect(prefs.showReflowView, isFalse);
      expect(prefs.showThumbnailView, isTrue);
      expect(find.byType(PdfReflowView), findsNothing);
      expect(find.byType(PdfThumbnailView), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('thumbnails: false hides the page-grid view option',
        (tester) async {
      await pump(
          tester,
          PdfEditorView(
              bytes: buildMultiPagePdf(2),
              features: const PdfEditorFeatures(thumbnails: false)));
      await tester.tap(find.byKey(const ValueKey('pdf-shell-view-options')),
          kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('pdf-shell-page-grid')), findsNothing);
    });

    testWidgets('reflowView: false hides editor reflow option', (tester) async {
      final prefs = PdfEditingPreferences();
      addTearDown(prefs.dispose);
      await pump(
          tester,
          PdfEditorView(
              bytes: buildClassicPdf(),
              preferences: prefs,
              features: const PdfEditorFeatures(reflowView: false)));
      await tester.tap(find.byKey(const ValueKey('pdf-shell-view-options')),
          kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('pdf-shell-show-annotations')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('pdf-shell-reflow-view')), findsNothing);
    });

    testWidgets('compact layout honors an explicit thumbnail preference',
        (tester) async {
      compactScreen(tester);
      SharedPreferences.setMockInitialValues(
          {'dart_pdf_editor.editing.showThumbnailSidebar': true});
      final prefs = PdfEditingPreferences();
      await prefs.ready;
      addTearDown(prefs.dispose);

      await pump(tester,
          PdfEditorView(bytes: buildMultiPagePdf(2), preferences: prefs));
      expect(prefs.hasShowThumbnailSidebarPreference, isTrue);
      expect(find.byType(PdfThumbnailSidebar), findsOneWidget);
      await openShellControls(tester);
      final toggle = tester.widget(
          find.byKey(const ValueKey('pdf-shell-thumbnails-toggle'))) as dynamic;
      expect(toggle.active, isTrue);
    });

    testWidgets('panel toggles open the annotation and properties panels',
        (tester) async {
      await pump(tester, PdfEditorView(bytes: buildMultiPagePdf(1)));
      expect(find.byType(PdfAnnotationSidebar), findsNothing);
      await tester.tap(
          find.byKey(const ValueKey('pdf-shell-annotations-toggle')),
          kind: PointerDeviceKind.mouse);
      await tester.pump();
      expect(find.byType(PdfAnnotationSidebar), findsOneWidget);
      await tester.tap(
          find.byKey(const ValueKey('pdf-shell-properties-toggle')),
          kind: PointerDeviceKind.mouse);
      await tester.pump();
      expect(find.byType(PdfAnnotationSidebar), findsOneWidget);
      expect(find.byType(PdfAnnotationPropertiesPanel), findsOneWidget);
    });

    testWidgets('bookmarks panel creates edits and deletes outline items',
        (tester) async {
      final editing = PdfEditingController(buildMultiPagePdf(3));
      final viewer = PdfViewerController();
      addTearDown(editing.dispose);
      addTearDown(viewer.dispose);
      editing.preferences.showBookmarkSidebar = true;

      await pump(
          tester, PdfEditorView(controller: editing, viewerController: viewer));

      expect(find.byType(PdfBookmarkSidebar), findsOneWidget);
      expect(
          find.byKey(const ValueKey('pdf-bookmark-empty-add')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('pdf-bookmark-empty-add')),
          kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const ValueKey('pdf-bookmark-title')), 'Chapter 1');
      await tester.enterText(
          find.byKey(const ValueKey('pdf-bookmark-page')), '2');
      await tester.tap(find.byKey(const ValueKey('pdf-bookmark-save')),
          kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();

      expect(editing.outline.items.single.title, 'Chapter 1');
      expect(editing.outline.items.single.destination?.pageIndex, 1);

      await tester.tap(find.byKey(const ValueKey('pdf-bookmark-edit-0')),
          kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const ValueKey('pdf-bookmark-title')), 'Renamed');
      await tester.tap(find.byKey(const ValueKey('pdf-bookmark-save')),
          kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();

      expect(editing.outline.items.single.title, 'Renamed');

      await tester.tap(find.byKey(const ValueKey('pdf-bookmark-delete-0')),
          kind: PointerDeviceKind.mouse);
      await tester.pump();
      expect(editing.outline.items, isEmpty);
    });

    testWidgets(
        'desktop bookmark controls reveal on hover without reserved space',
        (tester) async {
      final editing = PdfEditingController(buildMultiPagePdf(2));
      final viewer = PdfViewerController();
      addTearDown(editing.dispose);
      addTearDown(viewer.dispose);
      editing
        ..addBookmark('Chapter 1', pageIndex: 0)
        ..preferences.showBookmarkSidebar = true;

      await pump(
          tester, PdfEditorView(controller: editing, viewerController: viewer));

      final edit = find.byKey(const ValueKey('pdf-bookmark-edit-0'));
      expect(edit, findsNothing);

      await hoverAt(tester,
          tester.getCenter(find.byKey(const ValueKey('pdf-bookmark-tile-0'))));

      expect(edit, findsOneWidget);
    }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

    testWidgets(
        'desktop thumbnail controls reveal on hover without reserved space',
        (tester) async {
      await pump(tester, PdfEditorView(bytes: buildMultiPagePdf(2)));

      final rotate = find.byKey(const ValueKey('pdf-thumbnail-rotate-0'));
      expect(rotate, findsNothing);

      await hoverAt(
          tester,
          tester.getCenter(
              find.byKey(const ValueKey('pdf-thumbnail-tile-chip-0'))));

      expect(rotate, findsOneWidget);
    }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

    testWidgets('desktop annotation controls reveal on hover without shifting',
        (tester) async {
      final editing = PdfEditingController(buildMultiPagePdf(1))
        ..addRectangle(0, const PdfRect(100, 550, 180, 610));
      final viewer = PdfViewerController();
      addTearDown(editing.dispose);
      addTearDown(viewer.dispose);

      await pump(
        tester,
        Row(children: [
          PdfAnnotationSidebar(controller: editing, viewerController: viewer),
          const Expanded(child: SizedBox()),
        ]),
      );

      final delete = find.byKey(const ValueKey('pdf-annotation-delete-0-0'));
      expect(actionVisibility(tester, delete).visible, isFalse);
      final before = tester.getRect(delete);

      await hoverAt(tester, tester.getCenter(find.text('Square')));

      expect(actionVisibility(tester, delete).visible, isTrue);
      expect(tester.getRect(delete), before);
    }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

    testWidgets('features can strip the chrome down to the viewer',
        (tester) async {
      await pump(
        tester,
        PdfEditorView(
          bytes: buildMultiPagePdf(1),
          features: const PdfEditorFeatures(
            headerBar: false,
            toolbar: false,
            thumbnails: false,
          ),
        ),
      );
      expect(find.byType(PdfViewer), findsOneWidget);
      expect(find.byType(PdfEditingToolbar), findsNothing);
      expect(find.byType(TextField), findsNothing);
      expect(find.byType(PdfThumbnailSidebar), findsNothing);
    });

    testWidgets('a tool subset hides the other tool buttons', (tester) async {
      await pump(
        tester,
        PdfEditorView(
          bytes: buildMultiPagePdf(1),
          features: const PdfEditorFeatures(
            tools: {PdfEditTool.ink, PdfEditTool.select},
            markup: false,
            flatten: false,
            colorControls: false,
            styleControls: false,
            undoRedo: false,
          ),
        ),
      );
      expect(find.byIcon(Icons.draw), findsOneWidget);
      expect(find.byIcon(Icons.near_me), findsOneWidget);
      expect(find.byIcon(Icons.rectangle_outlined), findsNothing);
      expect(find.byIcon(Icons.approval), findsNothing);
      expect(find.byIcon(Icons.history_edu), findsNothing);
      expect(find.byIcon(Icons.ballot_outlined), findsNothing);
      expect(find.byIcon(Icons.border_color), findsNothing);
      expect(find.byIcon(Icons.undo), findsNothing);
      expect(find.byIcon(Icons.layers), findsNothing);
      expect(find.byIcon(Icons.palette), findsNothing);
    });

    testWidgets('toolGroups hides whole tool types', (tester) async {
      await pump(
        tester,
        PdfEditorView(
          bytes: buildMultiPagePdf(1),
          features: const PdfEditorFeatures(
            toolGroups: {PdfEditToolGroup.select, PdfEditToolGroup.draw},
          ),
        ),
      );
      // the two kept groups show their dock chips...
      expect(find.byKey(const ValueKey('pdf-group-select')), findsOneWidget);
      expect(find.byKey(const ValueKey('pdf-group-draw')), findsOneWidget);
      // ...and every other group is gone
      expect(find.byKey(const ValueKey('pdf-group-markup')), findsNothing);
      expect(find.byKey(const ValueKey('pdf-group-shapes')), findsNothing);
      expect(find.byKey(const ValueKey('pdf-group-insert')), findsNothing);
      expect(find.byKey(const ValueKey('pdf-group-measure')), findsNothing);
      expect(find.byKey(const ValueKey('pdf-group-edit')), findsNothing);
    });

    testWidgets('colorControls hides the color changer, keeps the style popup',
        (tester) async {
      await pump(
        tester,
        PdfEditorView(
          bytes: buildMultiPagePdf(1),
          features: const PdfEditorFeatures(
            colorControls: false,
            // styleControls stays true: stroke/opacity/font remain
          ),
        ),
      );
      // open the Shapes group; its strip is where colour + style controls
      // now live (the toolbar's first scrollable once the strip is up)
      await tester.tap(find.byKey(const ValueKey('pdf-group-shapes')));
      await tester.pump();
      // color changer gone: "More colors…" picker and eyedropper
      expect(find.byIcon(Icons.palette), findsNothing);
      expect(find.byIcon(Icons.colorize), findsNothing);
      // the style popup (stroke/opacity/font) still shows
      expect(find.byTooltip('Stroke, opacity, font'), findsOneWidget);
      // its text-box color rows are gone with color controls off
      await tester.scrollUntilVisible(
          find.byTooltip('Stroke, opacity, font'), 100,
          scrollable: find
              .descendant(
                  of: find.byType(PdfEditingToolbar),
                  matching: find.byType(Scrollable))
              .first);
      await tester.tap(find.byTooltip('Stroke, opacity, font'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('pdf-text-fill-none')), findsNothing);
      expect(find.byKey(const ValueKey('pdf-text-border-none')), findsNothing);
      // but the sliders survive
      expect(find.byType(Slider), findsWidgets);
    });

    testWidgets('colorControls locks the freehand highlight color',
        (tester) async {
      final editing = PdfEditingController(buildMultiPagePdf(1));
      addTearDown(editing.dispose);
      editing.color = const Color(0xFF123456);

      await pump(
        tester,
        PdfEditorView(
          controller: editing,
          features: const PdfEditorFeatures(colorControls: false),
        ),
      );

      await tester.tap(find.byKey(const ValueKey('pdf-group-draw')));
      await tester.pump();
      expect(editing.tool, PdfEditTool.ink);
      expect(editing.color, const Color(0xFF123456));

      await tester.tap(find.byTooltip('Highlight - draw freehand (⇧H)'));
      await tester.pump();
      expect(editing.tool, PdfEditTool.highlight);
      expect(editing.color, const Color(0xFF123456));
      expect(editing.preferences.strokeWidth, 12);
      expect(editing.preferences.opacity, 0.45);
    });

    testWidgets('color controls are present by default', (tester) async {
      await pump(tester, PdfEditorView(bytes: buildMultiPagePdf(1)));
      // the colour controls live in a group's strip - open one
      await tester.tap(find.byKey(const ValueKey('pdf-group-shapes')));
      await tester.pump();
      final moreColors = find.byKey(const ValueKey('pdf-more-colors'));
      expect(moreColors, findsOneWidget);
      final material = tester.widget<Material>(moreColors);
      expect(material.shape, isA<CircleBorder>());
      expect(find.byIcon(Icons.colorize), findsOneWidget);
      await tester.scrollUntilVisible(
          find.byTooltip('Stroke, opacity, font'), 100,
          scrollable: find
              .descendant(
                  of: find.byType(PdfEditingToolbar),
                  matching: find.byType(Scrollable))
              .first);
      await tester.tap(find.byTooltip('Stroke, opacity, font'));
      await tester.pumpAndSettle();
      // the Shapes popup carries the shape interior-fill colour row
      expect(find.byKey(const ValueKey('pdf-shape-fill-none')), findsOneWidget);
    });

    testWidgets('compact markup tools explain the arm-first workflow',
        (tester) async {
      tester.view.physicalSize = const Size(560, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await pump(tester, PdfEditorView(bytes: buildClassicPdf()));

      await tester.tap(find.byKey(const ValueKey('pdf-tools-handle')),
          kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('pdf-group-tab-markup')),
          kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();

      expect(find.text('Choose a markup, then select text'), findsOneWidget);
    });

    testWidgets('desktop markup tools explain the arm-first workflow',
        (tester) async {
      final editing = PdfEditingController(buildClassicPdf());
      addTearDown(editing.dispose);
      await pump(tester, PdfEditorView(controller: editing));

      await tester.tap(find.byKey(const ValueKey('pdf-group-markup')),
          kind: PointerDeviceKind.mouse);
      await tester.pump();

      expect(find.text('Choose a markup, then select text'), findsOneWidget);
      final highlight = find.byKey(const ValueKey('pdf-markup-highlight'));
      expect(tester.widget<IconButton>(highlight).onPressed, isNotNull);

      await tester.tap(highlight, kind: PointerDeviceKind.mouse);
      await tester.pump();
      expect(editing.markupTool, PdfMarkupKind.highlight);
      expect(find.text('Choose a markup, then select text'), findsNothing,
          reason: 'the selected button now communicates the armed state');
    });

    testWidgets('toolbar buttons drive the owned session', (tester) async {
      await pump(tester, PdfEditorView(bytes: buildMultiPagePdf(1)));
      await tester.tap(find.byIcon(Icons.draw), kind: PointerDeviceKind.mouse);
      await tester.pump();
      // the draw button reads back as armed from the internal session
      final button = tester.widget<IconButton>(find.ancestor(
        of: find.byIcon(Icons.draw),
        matching: find.byType(IconButton),
      ));
      expect(button.isSelected, isTrue);
    });

    testWidgets('custom toolbar widgets can drive the owned session',
        (tester) async {
      var changed = 0;
      await pump(
        tester,
        PdfEditorView(
          bytes: buildMultiPagePdf(1),
          features: const PdfEditorFeatures(
            tools: {PdfEditTool.select},
            markup: false,
            undoRedo: false,
            styleControls: false,
            flatten: false,
          ),
          toolbarTrailing: [
            (context, editing, viewer) => IconButton(
                  key: const ValueKey('custom-toolbar-rectangle'),
                  icon: const Icon(Icons.crop_square),
                  tooltip: 'Add host rectangle',
                  onPressed: () => editing.addRectangle(
                    0,
                    const PdfRect(100, 550, 180, 610),
                  ),
                ),
          ],
          onDocumentChanged: (_) => changed++,
        ),
      );

      await tester.tap(find.byKey(const ValueKey('custom-toolbar-rectangle')),
          kind: PointerDeviceKind.mouse);
      await tester.pump();

      expect(changed, 1);
    });

    testWidgets('custom toolbar builder can replace the stock toolbar',
        (tester) async {
      var changed = 0;
      await pump(
        tester,
        PdfEditorView(
          bytes: buildMultiPagePdf(1),
          toolbarBuilder: (context, editing, viewer) => Material(
            child: IconButton(
              key: const ValueKey('custom-toolbar-builder-rectangle'),
              icon: const Icon(Icons.crop_square),
              tooltip: 'Add host rectangle',
              onPressed: () => editing.addRectangle(
                0,
                const PdfRect(100, 550, 180, 610),
              ),
            ),
          ),
          onDocumentChanged: (_) => changed++,
        ),
      );

      expect(find.byType(PdfEditingToolbar), findsNothing);

      await tester.tap(
        find.byKey(const ValueKey('custom-toolbar-builder-rectangle')),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();

      expect(changed, 1);
    });

    testWidgets('external controller: edits flow through onDocumentChanged',
        (tester) async {
      final editing = PdfEditingController(buildMultiPagePdf(1));
      addTearDown(editing.dispose);
      final reported = <int>[];
      await pump(
        tester,
        PdfEditorView(
          controller: editing,
          onDocumentChanged: (bytes) => reported.add(bytes.length),
        ),
      );
      editing.addRectangle(0, const PdfRect(100, 550, 300, 650));
      await tester.pump();
      expect(editing.isModified, isTrue);
      expect(reported, [editing.bytes.length]);
      editing.undo();
      await tester.pump();
      expect(reported, hasLength(2));
      expect(reported.last, editing.bytes.length);
    });

    testWidgets('save button hands the host the current bytes', (tester) async {
      final editing = PdfEditingController(buildMultiPagePdf(1));
      addTearDown(editing.dispose);
      List<int>? saved;
      await pump(
        tester,
        PdfEditorView(
          controller: editing,
          onSave: (bytes) => saved = bytes,
        ),
      );
      editing.addRectangle(0, const PdfRect(100, 550, 300, 650));
      await tester.pump();
      // save now lives in the shell header (near the host's Open), keyed
      final save = find.byKey(const ValueKey('pdf-shell-save'));
      await tester.scrollUntilVisible(
        save,
        80,
        scrollable: find.ancestor(
          of: save,
          matching: find.byType(Scrollable),
        ),
      );
      await tester.tap(save, kind: PointerDeviceKind.mouse);
      expect(saved, isNotNull);
      expect(saved!.length, editing.bytes.length);
    });

    testWidgets('no onSave, no save button', (tester) async {
      await pump(tester, PdfEditorView(bytes: buildMultiPagePdf(1)));
      expect(find.byIcon(Icons.save_alt), findsNothing);
    });

    testWidgets('save button is disabled until there are changes',
        (tester) async {
      final editing = PdfEditingController(buildMultiPagePdf(1));
      addTearDown(editing.dispose);
      await pump(
        tester,
        PdfEditorView(controller: editing, onSave: (_) {}),
      );
      FilledButton saveButton() => tester
          .widget<FilledButton>(find.byKey(const ValueKey('pdf-shell-save')));

      // freshly opened: nothing to save, so the button is disabled
      expect(saveButton().onPressed, isNull);

      // an edit enables it
      editing.addRectangle(0, const PdfRect(100, 550, 300, 650));
      await tester.pump();
      expect(saveButton().onPressed, isNotNull);

      // undoing back to the original disables it again
      editing.undo();
      await tester.pump();
      expect(saveButton().onPressed, isNull);
    });

    testWidgets('showSaveButton hides only the stock save control',
        (tester) async {
      final editing = PdfEditingController(buildMultiPagePdf(1));
      addTearDown(editing.dispose);
      List<int>? saved;
      await pump(
        tester,
        PdfEditorView(
          controller: editing,
          onSave: (bytes) => saved = bytes,
          showSaveButton: false,
        ),
      );
      expect(find.byKey(const ValueKey('pdf-shell-save')), findsNothing);

      // an edit so there's something to save (⌘S is a no-op otherwise)
      editing.addRectangle(0, const PdfRect(100, 550, 300, 650));
      await tester.tap(find.byType(PdfViewer), kind: PointerDeviceKind.mouse);
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);

      expect(saved, editing.bytes);
    });

    testWidgets('Ctrl+S saves through onSave', (tester) async {
      final editing = PdfEditingController(buildMultiPagePdf(1));
      addTearDown(editing.dispose);
      List<int>? saved;
      await pump(
        tester,
        PdfEditorView(
          controller: editing,
          onSave: (bytes) => saved = bytes,
        ),
      );
      // an edit so there's something to save (⌘S is a no-op otherwise)
      editing.addRectangle(0, const PdfRect(100, 550, 300, 650));
      // focus the viewer the way a user would: click it, so the
      // shell's CallbackShortcuts has a focused descendant
      await tester.tap(find.byType(PdfViewer), kind: PointerDeviceKind.mouse);
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(saved, isNotNull);
      expect(saved!.length, editing.bytes.length);
    });

    testWidgets('Ctrl+Shift+S saves through onSaveAs', (tester) async {
      final editing = PdfEditingController(buildMultiPagePdf(1));
      addTearDown(editing.dispose);
      List<int>? saved;
      List<int>? savedAs;
      await pump(
        tester,
        PdfEditorView(
          controller: editing,
          onSave: (bytes) => saved = bytes,
          onSaveAs: (bytes) => savedAs = bytes,
        ),
      );
      // focus the viewer the way a user would: click it, so the
      // shell's CallbackShortcuts has a focused descendant
      await tester.tap(find.byType(PdfViewer), kind: PointerDeviceKind.mouse);
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(saved, isNull);
      expect(savedAs, isNotNull);
      expect(savedAs!.length, editing.bytes.length);
    });

    testWidgets('Meta+Shift+S saves through onSaveAs', (tester) async {
      final editing = PdfEditingController(buildMultiPagePdf(1));
      addTearDown(editing.dispose);
      List<int>? saved;
      List<int>? savedAs;
      await pump(
        tester,
        PdfEditorView(
          controller: editing,
          onSave: (bytes) => saved = bytes,
          onSaveAs: (bytes) => savedAs = bytes,
        ),
      );
      await tester.tap(find.byType(PdfViewer), kind: PointerDeviceKind.mouse);
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pump();
      expect(saved, isNull);
      expect(savedAs, isNotNull);
      expect(savedAs!.length, editing.bytes.length);
    });

    testWidgets('swapping bytes opens a fresh session', (tester) async {
      final viewer = PdfViewerController();
      addTearDown(viewer.dispose);
      await pump(tester,
          PdfEditorView(bytes: buildMultiPagePdf(1), viewerController: viewer));
      expect(viewer.pageCount, 1);
      await pump(tester,
          PdfEditorView(bytes: buildMultiPagePdf(3), viewerController: viewer));
      expect(viewer.pageCount, 3);
    });

    testWidgets('pageColor pins the paper color over the preference',
        (tester) async {
      await pump(
        tester,
        PdfEditorView(
          bytes: buildMultiPagePdf(1),
          pageColor: const Color(0xFFEEF7EE),
        ),
      );
      final viewer = tester.widget<PdfViewer>(find.byType(PdfViewer));
      expect(viewer.pageColor, const Color(0xFFEEF7EE));
    });

    testWidgets('floating toolbar can be dragged to another edge',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final prefs = PdfEditingPreferences();
      addTearDown(prefs.dispose);
      await pump(
        tester,
        PdfEditorView(
          bytes: buildMultiPagePdf(1),
          preferences: prefs,
        ),
      );

      expect(prefs.toolbarDock, PdfPanelDock.bottom);
      final handle = find.byKey(const ValueKey('pdf-toolbar-move'));
      expect(handle, findsOneWidget);
      final gesture = await tester.startGesture(
        tester.getCenter(handle),
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveBy(const Offset(12, 0));
      await tester.pump();

      final top = find.byKey(const ValueKey('pdf-shell-dropzone-top'));
      expect(top, findsOneWidget);
      final viewerRect = tester.getRect(
        find.byKey(const ValueKey('pdf-shell-viewer')),
      );
      final leftTarget = tester.getRect(
        find.byKey(const ValueKey('pdf-shell-dropzone-left')),
      );
      final rightTarget = tester.getRect(
        find.byKey(const ValueKey('pdf-shell-dropzone-right')),
      );
      expect(viewerRect.left, greaterThan(100));
      expect(leftTarget.left, greaterThanOrEqualTo(viewerRect.left));
      expect(rightTarget.right, lessThanOrEqualTo(viewerRect.right));
      expect(tester.getRect(top).top, greaterThanOrEqualTo(viewerRect.top));
      await gesture.moveTo(tester.getCenter(top));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(prefs.toolbarDock, PdfPanelDock.top);
      final card = find.byKey(const ValueKey('pdf-editing-toolbar-card'));
      expect(tester.getTopLeft(card).dy, lessThan(140));
    });

    testWidgets('left toolbar is a vertical rail inside docked panels',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final prefs = PdfEditingPreferences();
      addTearDown(prefs.dispose);
      prefs.toolbarDock = PdfPanelDock.left;

      await pump(
        tester,
        PdfEditorView(
          bytes: buildMultiPagePdf(1),
          preferences: prefs,
        ),
      );

      final card = find.byKey(const ValueKey('pdf-editing-toolbar-card'));
      final pages = find.byType(PdfThumbnailSidebar);
      expect(card, findsOneWidget);
      expect(pages, findsOneWidget);
      expect(
        tester.getRect(card).left,
        greaterThanOrEqualTo(tester.getRect(pages).right - 0.5),
      );

      final markup =
          tester.getCenter(find.byKey(const ValueKey('pdf-group-markup')));
      final draw =
          tester.getCenter(find.byKey(const ValueKey('pdf-group-draw')));
      expect((markup.dx - draw.dx).abs(), lessThan(0.5));
      expect(draw.dy, greaterThan(markup.dy));
      final markupIcon = tester.getCenter(find.descendant(
        of: find.byKey(const ValueKey('pdf-group-markup')),
        matching: find.byIcon(Icons.edit_note),
      ));
      expect(markupIcon.dx, closeTo(markup.dx, 0.1));

      await tester.tap(find.byKey(const ValueKey('pdf-group-markup')),
          kind: PointerDeviceKind.mouse);
      await tester.pump();
      final openCards = find.byKey(const ValueKey('pdf-editing-toolbar-card'));
      expect(openCards, findsNWidgets(2));
      final openRects = [
        for (final element in openCards.evaluate())
          tester.getRect(find.byElementPredicate((e) => identical(e, element))),
      ]..sort((a, b) => a.left.compareTo(b.left));
      expect(openRects.last.left, greaterThan(openRects.first.right));
      expect(openRects.first.width, lessThan(openRects.last.width));
    });

    testWidgets('right toolbar is a vertical rail inside docked panels',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final prefs = PdfEditingPreferences();
      addTearDown(prefs.dispose);
      prefs.showThumbnailSidebar = false;
      prefs.showAnnotationSidebar = true;
      prefs.toolbarDock = PdfPanelDock.right;

      await pump(
        tester,
        PdfEditorView(
          bytes: buildMultiPagePdf(1),
          preferences: prefs,
        ),
      );

      final card = find.byKey(const ValueKey('pdf-editing-toolbar-card'));
      final annotations = find.byType(PdfAnnotationSidebar);
      expect(card, findsOneWidget);
      expect(annotations, findsOneWidget);
      expect(
        tester.getRect(card).right,
        lessThanOrEqualTo(tester.getRect(annotations).left + 0.5),
      );

      final markup =
          tester.getCenter(find.byKey(const ValueKey('pdf-group-markup')));
      final draw =
          tester.getCenter(find.byKey(const ValueKey('pdf-group-draw')));
      expect((markup.dx - draw.dx).abs(), lessThan(0.5));
      expect(draw.dy, greaterThan(markup.dy));

      await tester.tap(find.byKey(const ValueKey('pdf-group-markup')),
          kind: PointerDeviceKind.mouse);
      await tester.pump();
      final openCards = find.byKey(const ValueKey('pdf-editing-toolbar-card'));
      expect(openCards, findsNWidgets(2));
      final openRects = [
        for (final element in openCards.evaluate())
          tester.getRect(find.byElementPredicate((e) => identical(e, element))),
      ]..sort((a, b) => a.left.compareTo(b.left));
      expect(openRects.first.right, lessThan(openRects.last.left));
      expect(openRects.last.width, lessThan(openRects.first.width));
    });

    testWidgets('view options show page color hex and current author',
        (tester) async {
      final prefs = PdfEditingPreferences();
      addTearDown(prefs.dispose);
      prefs.pageColor = const Color(0xFFEEF7EE);
      final editing =
          PdfEditingController(buildMultiPagePdf(1), preferences: prefs);
      addTearDown(editing.dispose);
      editing.preferences.author = 'A. Reviewer';

      await pump(
        tester,
        PdfEditorView(controller: editing),
      );

      await tester.tap(find.byKey(const ValueKey('pdf-shell-view-options')),
          kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();

      expect(find.text('#EEF7EE'), findsOneWidget);
      expect(find.text('A. Reviewer'), findsOneWidget);
    });

    testWidgets('the page-actions menu is hidden without insert/export',
        (tester) async {
      await pump(tester, PdfEditorView(bytes: buildMultiPagePdf(1)));
      expect(find.byKey(const ValueKey('pdf-thumbnail-page-actions')),
          findsNothing);
    });

    testWidgets('Insert PDF… merges the picked file after the current page',
        (tester) async {
      final editing = PdfEditingController(buildMultiPagePdf(2));
      final viewer = PdfViewerController();
      addTearDown(editing.dispose);
      addTearDown(viewer.dispose);
      await pump(
        tester,
        PdfEditorView(
          controller: editing,
          viewerController: viewer,
          onPickPdfToInsert: () async => buildMultiPagePdf(3),
        ),
      );

      await tester.tap(find.byKey(const ValueKey('pdf-thumbnail-page-actions')),
          kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('pdf-thumbnail-insert-pdf')));
      await tester.pumpAndSettle();
      // current page is 0, so the 3 pages land at index 1
      expect(editing.document.pageCount, 5);
      expect(viewer.currentPage, 1,
          reason: 'the view follows the first inserted page');
    });

    testWidgets('Export pages… hands the host the chosen range',
        (tester) async {
      final editing = PdfEditingController(buildMultiPagePdf(4));
      addTearDown(editing.dispose);
      Uint8List? exported;
      await pump(
        tester,
        PdfEditorView(
          controller: editing,
          onExportPages: (bytes) => exported = bytes,
        ),
      );

      await tester.tap(find.byKey(const ValueKey('pdf-thumbnail-page-actions')),
          kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      await tester
          .tap(find.byKey(const ValueKey('pdf-thumbnail-export-pages')));
      await tester.pumpAndSettle();
      // default range covers the whole document; narrow it to pages 2–3
      await tester.enterText(
          find.byKey(const ValueKey('pdf-page-range-from')), '2');
      await tester.enterText(
          find.byKey(const ValueKey('pdf-page-range-to')), '3');
      await tester.tap(find.byKey(const ValueKey('pdf-page-range-confirm')));
      await tester.pumpAndSettle();

      expect(exported, isNotNull);
      final out = PdfDocument.open(exported!);
      expect(out.pageCount, 2);
      // the source document is untouched
      expect(editing.document.pageCount, 4);
    });

    testWidgets('export is offered even when page editing is off',
        (tester) async {
      await pump(
        tester,
        PdfEditorView(
          bytes: buildMultiPagePdf(2),
          features: const PdfEditorFeatures(pageEditing: false),
          onPickPdfToInsert: () async => buildMultiPagePdf(1),
          onExportPages: (_) {},
        ),
      );
      await tester.tap(find.byKey(const ValueKey('pdf-thumbnail-page-actions')),
          kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      // insert needs page editing - hidden; export stands alone
      expect(
          find.byKey(const ValueKey('pdf-thumbnail-insert-pdf')), findsNothing);
      expect(find.byKey(const ValueKey('pdf-thumbnail-export-pages')),
          findsOneWidget);
    });

    testWidgets('the page-actions menu lives inside the thumbnail strip',
        (tester) async {
      await pump(
        tester,
        PdfEditorView(
          bytes: buildMultiPagePdf(2),
          onPickPdfToInsert: () async => buildMultiPagePdf(1),
          onExportPages: (_) {},
        ),
      );
      // it moved out of the header and into the strip's header row
      expect(
        find.descendant(
          of: find.byType(PdfThumbnailSidebar),
          matching: find.byKey(const ValueKey('pdf-thumbnail-page-actions')),
        ),
        findsOneWidget,
      );
    });
  });

  group('floating toast margin', () {
    testWidgets('lifts the toast above the dock and the safe-area inset',
        (tester) async {
      late EdgeInsetsGeometry withoutInset;
      late EdgeInsetsGeometry withInset;
      await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(size: Size(800, 600)),
          child: Builder(builder: (context) {
            withoutInset = pdfFloatingToastMargin(context);
            return const SizedBox();
          }),
        ),
      ));
      await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(800, 600),
            padding: EdgeInsets.only(bottom: 34),
          ),
          child: Builder(builder: (context) {
            withInset = pdfFloatingToastMargin(context);
            return const SizedBox();
          }),
        ),
      ));
      final withoutInsetLtr = withoutInset.resolve(TextDirection.ltr);
      final withInsetLtr = withInset.resolve(TextDirection.ltr);
      // clears the floating editing toolbar dock…
      expect(withoutInsetLtr.bottom, greaterThanOrEqualTo(84));
      // …and adds the device's bottom safe-area inset on top
      expect(withInsetLtr.bottom, withoutInsetLtr.bottom + 34);
    });
  });

  // On a narrow screen the side panels and the thumbnail strip become
  // bottom sheets instead of docking and crowding the page out.
  group('bottom sheets on small screens', () {
    testWidgets('compact: shell right controls move into a controls sheet',
        (tester) async {
      compactScreen(tester);
      await pump(tester, PdfEditorView(bytes: buildMultiPagePdf(2)));

      expect(find.byKey(const ValueKey('pdf-shell-controls')), findsOneWidget);
      expect(
          find.byKey(const ValueKey('pdf-shell-view-options')), findsNothing);
      expect(find.byKey(const ValueKey('pdf-shell-annotations-toggle')),
          findsNothing);
      expect(find.byKey(const ValueKey('pdf-shell-zoom-menu')), findsNothing);

      await openShellControls(tester);

      expect(find.text('Controls'), findsOneWidget);
      expect(find.byKey(const ValueKey('pdf-shell-zoom-menu')), findsOneWidget);
      expect(
          find.byKey(const ValueKey('pdf-shell-view-options')), findsOneWidget);
      expect(find.byKey(const ValueKey('pdf-shell-annotations-toggle')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('pdf-shell-properties-toggle')),
          findsOneWidget);
    });

    testWidgets('compact: a toggled panel floats up as a bottom sheet',
        (tester) async {
      compactScreen(tester);
      await pump(tester, PdfEditorView(bytes: buildMultiPagePdf(2)));
      expect(find.byType(PdfAnnotationSidebar), findsNothing);

      await openShellControls(tester);
      await tester.tap(
          find.byKey(const ValueKey('pdf-shell-annotations-toggle')),
          kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();

      // the panel is present, wrapped in a bottom sheet (its close button)
      expect(find.byType(PdfAnnotationSidebar), findsOneWidget);
      expect(find.byKey(const ValueKey('pdf-shell-annotations-sheet-close')),
          findsOneWidget);
      // and it does not dock a side resize grip
      expect(find.byKey(const ValueKey('pdf-annotation-resize-grip')),
          findsNothing);
    });

    testWidgets('compact: the sheet close button hides the panel',
        (tester) async {
      final prefs = PdfEditingPreferences();
      addTearDown(prefs.dispose);
      compactScreen(tester);
      await pump(tester,
          PdfEditorView(bytes: buildMultiPagePdf(2), preferences: prefs));

      await openShellControls(tester);
      await tester.tap(
          find.byKey(const ValueKey('pdf-shell-properties-toggle')),
          kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      expect(find.byType(PdfAnnotationPropertiesPanel), findsOneWidget);

      await tester.tap(
          find.byKey(const ValueKey('pdf-shell-properties-sheet-close')),
          kind: PointerDeviceKind.mouse);
      await tester.pump();
      expect(find.byType(PdfAnnotationPropertiesPanel), findsNothing);
      expect(prefs.showPropertiesPanel, isFalse);
    });

    testWidgets('compact: dragging the sheet handle up resizes it (to 90%)',
        (tester) async {
      final prefs = PdfEditingPreferences();
      addTearDown(prefs.dispose);
      compactScreen(tester); // 600x800
      await pump(tester,
          PdfEditorView(bytes: buildMultiPagePdf(2), preferences: prefs));
      await openShellControls(tester);
      await tester.tap(
          find.byKey(const ValueKey('pdf-shell-properties-toggle')),
          kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();

      // the panel fills the sheet below its header, so its height tracks the
      // sheet's
      final panel = find.byType(PdfAnnotationPropertiesPanel);
      final before = tester.getSize(panel).height;

      // drag the handle (just above the panel) up by a lot; the sheet grows,
      // capped at 90% of the content area
      final panelTop = tester.getRect(panel).top;
      final g = await tester
          .startGesture(Offset(tester.getCenter(panel).dx, panelTop - 20));
      await g.moveBy(const Offset(0, -1000));
      await tester.pump();
      await g.up();
      await tester.pump();

      final after = tester.getSize(panel).height;
      // grew past the old 0.55 cap, toward the 0.9 cap (800px content area,
      // no app bar in this harness)
      expect(before, lessThan(800 * 0.55));
      expect(after, greaterThan(800 * 0.6));
      expect(after, lessThanOrEqualTo(800 * 0.9 + 1));
      // a resize is not a dismiss - the panel is still open
      expect(panel, findsOneWidget);
    });

    testWidgets('wide: panels dock to the side, not a bottom sheet',
        (tester) async {
      // the default 800x600 test surface is above the compact width
      await pump(tester, PdfEditorView(bytes: buildMultiPagePdf(2)));
      await tester.tap(
          find.byKey(const ValueKey('pdf-shell-annotations-toggle')),
          kind: PointerDeviceKind.mouse);
      await tester.pump();
      expect(find.byType(PdfAnnotationSidebar), findsOneWidget);
      // docked: a side resize grip, no bottom-sheet chrome
      expect(find.byKey(const ValueKey('pdf-annotation-resize-grip')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('pdf-shell-annotations-sheet-close')),
          findsNothing);
    });

    testWidgets('wide: every docked panel\'s close button hides it',
        (tester) async {
      final prefs = PdfEditingPreferences();
      addTearDown(prefs.dispose);
      // the default 800x600 test surface is above the compact width, so
      // panels dock to the side and carry their own little × (the sheet
      // variants - and their close buttons - are not mounted here)
      await pump(tester,
          PdfEditorView(bytes: buildMultiPagePdf(2), preferences: prefs));

      // each panel: (toggle key, close key, panel type, "now closed" check).
      // The thumbnails strip is shown by default; the rest start hidden, so
      // their toggles open them first.
      final cases = <({
        String? toggle,
        String close,
        Type type,
        bool Function() closed,
      })>[
        (
          toggle: null,
          close: 'pdf-thumbnail-panel-close',
          type: PdfThumbnailSidebar,
          closed: () => !prefs.showThumbnailSidebar,
        ),
        (
          toggle: 'pdf-shell-search-results-toggle',
          close: 'pdf-search-panel-close',
          type: PdfSearchResultsPanel,
          closed: () => !prefs.showSearchResultsPanel,
        ),
        (
          toggle: 'pdf-shell-annotations-toggle',
          close: 'pdf-annotation-panel-close',
          type: PdfAnnotationSidebar,
          closed: () => !prefs.showAnnotationSidebar,
        ),
        (
          toggle: 'pdf-shell-properties-toggle',
          close: 'pdf-properties-panel-close',
          type: PdfAnnotationPropertiesPanel,
          closed: () => !prefs.showPropertiesPanel,
        ),
      ];

      for (final c in cases) {
        if (c.toggle != null) {
          await tester.tap(find.byKey(ValueKey(c.toggle!)),
              kind: PointerDeviceKind.mouse);
          await tester.pump();
        }
        expect(find.byType(c.type), findsOneWidget,
            reason: 'panel ${c.type} should be docked open');
        final close = find.byKey(ValueKey(c.close));
        expect(close, findsOneWidget,
            reason: '${c.type} should carry a docked close button');
        await tester.tap(close, kind: PointerDeviceKind.mouse);
        await tester.pump();
        expect(find.byType(c.type), findsNothing,
            reason: 'closing should hide ${c.type}');
        expect(c.closed(), isTrue,
            reason: 'closing should turn ${c.type}\'s preference off');
      }
    });

    testWidgets('wide reader: the docked thumbnail strip has a close button',
        (tester) async {
      final prefs = PdfEditingPreferences();
      await prefs.ready;
      addTearDown(prefs.dispose);
      // wide surface: the strip docks (shown by default) rather than
      // floating up as a sheet
      await pump(
          tester, PdfReader(bytes: buildMultiPagePdf(3), preferences: prefs));
      expect(find.byType(PdfThumbnailSidebar), findsOneWidget);

      final close = find.byKey(const ValueKey('pdf-thumbnail-panel-close'));
      expect(close, findsOneWidget);
      await tester.tap(close, kind: PointerDeviceKind.mouse);
      await tester.pump();
      expect(find.byType(PdfThumbnailSidebar), findsNothing);
      expect(prefs.showThumbnailSidebar, isFalse);
    });

    testWidgets('compact reader: the thumbnail strip is a bottom sheet',
        (tester) async {
      final prefs = PdfEditingPreferences();
      await prefs.ready;
      addTearDown(prefs.dispose);
      compactScreen(tester);
      await pump(
          tester, PdfReader(bytes: buildMultiPagePdf(3), preferences: prefs));

      // compact first run starts closed; toggle it on
      await openShellControls(tester);
      await tester.tap(
          find.byKey(const ValueKey('pdf-shell-thumbnails-toggle')),
          kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();

      expect(find.byType(PdfThumbnailSidebar), findsOneWidget);
      expect(find.byKey(const ValueKey('pdf-shell-thumbnails-sheet-close')),
          findsOneWidget);
      // the strip's side resize grip is gone in sheet form
      expect(find.byKey(const ValueKey('pdf-thumbnail-resize-grip')),
          findsNothing);

      // the scrollbar sits at the sheet's right edge, not the centered
      // tile column's right edge
      final sheet = find.byType(PdfThumbnailSidebar);
      final bar = find.byKey(const ValueKey('pdf-thumbnail-scrollbar-thumb'));
      expect(bar, findsOneWidget);
      expect(
          tester.getRect(bar).right, closeTo(tester.getRect(sheet).right, 4.0));
    });

    testWidgets(
        'compact: dragging the empty margin of the thumbnail sheet '
        'scrolls it', (tester) async {
      // Regression: the tile column was a narrow centered SizedBox, so the
      // scroll viewport only covered the tiles - a drag on the wide sheet's
      // empty side margins hit nothing and never scrolled. The list now
      // fills the sheet and centers the column via its own inset.
      final prefs = PdfEditingPreferences();
      await prefs.ready;
      addTearDown(prefs.dispose);
      compactScreen(tester); // 600x800
      await pump(
          tester, PdfReader(bytes: buildMultiPagePdf(12), preferences: prefs));
      await openShellControls(tester);
      await tester.tap(
          find.byKey(const ValueKey('pdf-shell-thumbnails-toggle')),
          kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();

      final sheet = find.byType(PdfThumbnailSidebar);
      final position = tester
          .state<ScrollableState>(find
              .descendant(of: sheet, matching: find.byType(Scrollable))
              .first)
          .position;
      expect(position.pixels, 0);
      expect(position.maxScrollExtent, greaterThan(0),
          reason: 'the strip should overflow with 12 pages');

      // drag UP from near the sheet's left edge - the empty margin beside
      // the centered tile column, not on a tile; check the offset while the
      // gesture is held (the raster loop never settles, so no pumpAndSettle)
      final sheetRect = tester.getRect(sheet);
      final g = await tester
          .startGesture(Offset(sheetRect.left + 6, sheetRect.center.dy));
      await g.moveBy(const Offset(0, -200));
      await tester.pump();
      expect(position.pixels, greaterThan(0));
      await g.up();
      await tester.pump();
    });

    testWidgets(
        'the editable thumbnail strip has no Tooltip OverlayPortal '
        'in its reorderable tiles', (tester) async {
      // Regression: the delete-button Tooltip was an OverlayPortal inside a
      // ReorderableListView item; reactivating the item during a layout
      // pass (the strip's bottom-sheet LayoutBuilder, or a reorder) mutated
      // the overlay's RenderObject mid-layout and tripped "A RenderObject
      // was mutated ... performLayout". The button is now Semantics-labelled
      // instead. Guard the tile against any Tooltip reappearing.
      final prefs = PdfEditingPreferences();
      await prefs.ready;
      addTearDown(prefs.dispose);
      prefs.showThumbnailSidebar = true;

      // compact, so the strip is a bottom sheet (its LayoutBuilder is the
      // layout-phase context that made the OverlayPortal mutation fatal)
      // the explicit pref keeps the strip shown on compact (as a sheet)
      compactScreen(tester);
      await pump(tester,
          PdfEditorView(bytes: buildMultiPagePdf(3), preferences: prefs));

      expect(find.byType(PdfThumbnailSidebar), findsOneWidget);
      expect(find.byKey(const ValueKey('pdf-shell-thumbnails-sheet-close')),
          findsOneWidget);
      // the editable delete buttons are present...
      expect(
          find.widgetWithIcon(IconButton, Icons.delete_outline), findsWidgets);
      // ...but carry no Tooltip (no OverlayPortal in the reorderable items)
      expect(
          find.descendant(
            of: find.byType(ReorderableListView),
            matching: find.byType(Tooltip),
          ),
          findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('phone: the editing toolbar docks below the viewer',
        (tester) async {
      // Below PdfEditingToolbar.mobileBreakpoint the toolbar is a solid
      // bar; floating it over the page would hide the bottom of the
      // content, so it docks below the viewer and takes its own space.
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await pump(tester, PdfEditorView(bytes: buildMultiPagePdf(2)));

      final toolbar = find.byType(PdfEditingToolbar);
      expect(toolbar, findsOneWidget);
      // docked = no vertical overlap with the viewer (the toolbar's top is
      // at or below the viewer's bottom)
      final viewerBottom = tester.getRect(find.byType(PdfViewer)).bottom;
      final toolbarTop = tester.getRect(toolbar).top;
      expect(toolbarTop, greaterThanOrEqualTo(viewerBottom - 0.5));
      expect(
          tester.widget<PdfViewer>(find.byType(PdfViewer)).trailingPadding, 0);
    });

    testWidgets('wide: the editing toolbar floats over the viewer',
        (tester) async {
      // Above the breakpoint the toolbar is transparent floating cards -
      // it sits over the bottom of the page (Acrobat/Bluebeam-style).
      await pump(tester, PdfEditorView(bytes: buildMultiPagePdf(2)));

      final toolbar = find.byType(PdfEditingToolbar);
      expect(toolbar, findsOneWidget);
      final viewerBottom = tester.getRect(find.byType(PdfViewer)).bottom;
      final toolbarTop = tester.getRect(toolbar).top;
      expect(toolbarTop, lessThan(viewerBottom),
          reason: 'the floating toolbar overlaps the viewer');
      expect(
          tester.widget<PdfViewer>(find.byType(PdfViewer)).trailingPadding, 144,
          reason: 'the document must scroll clear of the floating toolbar');
    });
  });

  group('shell header bar', () {
    Color? iconColorOf(WidgetTester tester, Finder button) {
      final icon = find.descendant(of: button, matching: find.byType(Icon));
      return tester.widget<Icon>(icon.first).color ??
          IconTheme.of(tester.element(icon.first)).color;
    }

    testWidgets('neutral header icon buttons share one colour', (tester) async {
      await pump(
          tester, PdfEditorView(bytes: buildMultiPagePdf(2), onSave: (_) {}));
      // the view-options PopupMenuButton used to render black87 while the
      // IconButtons rendered onSurfaceVariant
      final expected = iconColorOf(
          tester, find.byKey(const ValueKey('pdf-shell-view-options')));
      for (final key in const [
        'pdf-shell-annotations-toggle',
        'pdf-shell-properties-toggle',
      ]) {
        expect(iconColorOf(tester, find.byKey(ValueKey(key))), expected,
            reason: '$key icon colour should match the others');
      }
    });

    testWidgets(
        'the overflow scroller never drag-scrolls, so its controls '
        'stay tappable (macOS trackpad)', (tester) async {
      await pump(
          tester, PdfEditorView(bytes: buildMultiPagePdf(2), onSave: (_) {}));

      // The header wraps its controls in a horizontal scroll view for narrow
      // windows. If that scroller accepts pointer *drags* (Flutter's default
      // dragDevices include the trackpad), a trackpad click - which carries a
      // little motion - is claimed by the drag recognizer and the tap on the
      // control underneath is swallowed, leaving the whole bar hover-only on
      // macOS while every other bar works. It must scroll only on the wheel /
      // trackpad scroll signal, i.e. with no drag devices at all.
      final scroller = find
          .ancestor(
            of: find.byKey(const ValueKey('pdf-shell-panels')),
            matching: find.byType(SingleChildScrollView),
          )
          .first;
      final config = tester.widget<ScrollConfiguration>(
        find
            .ancestor(of: scroller, matching: find.byType(ScrollConfiguration))
            .first,
      );
      expect(config.behavior.dragDevices, isEmpty);
    });
  });
}
