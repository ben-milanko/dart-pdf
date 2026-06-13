import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

// The drop-in shells: PdfReader (view-only) and PdfEditorView (the full
// workbench). The pieces they compose have their own suites — these
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

  group('PdfReader', () {
    testWidgets('stock chrome: search, page number, view options, thumbnails',
        (tester) async {
      await pump(tester, PdfReader(bytes: buildMultiPagePdf(3)));
      expect(find.byKey(const ValueKey('pdf-search-field')), findsOneWidget);
      expect(
          find.byKey(const ValueKey('pdf-page-number-field')), findsOneWidget);
      expect(
          find.byKey(const ValueKey('pdf-shell-view-options')), findsOneWidget);
      expect(find.byKey(const ValueKey('pdf-shell-thumbnails-toggle')),
          findsOneWidget);
      // view-only: no editing toolbar anywhere
      expect(find.byType(PdfEditingToolbar), findsNothing);
      expect(find.byType(PdfViewer), findsOneWidget);
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
      final toggle = tester.widget<IconButton>(find.ancestor(
        of: find.byIcon(Icons.grid_view),
        matching: find.byType(IconButton),
      ));
      expect(toggle.isSelected, isFalse);

      await tester.tap(
          find.byKey(const ValueKey('pdf-shell-thumbnails-toggle')),
          kind: PointerDeviceKind.mouse);
      await tester.pump();
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

    testWidgets('view options menu toggles annotation visibility',
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
      expect(find.byType(PdfThumbnailSidebar), findsNothing);
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
      expect(
          find.byKey(const ValueKey('pdf-shell-page-color')), findsNothing);
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
        'pdf-shell-author',
        'pdf-shell-view-options',
        'pdf-shell-thumbnails-toggle',
        'pdf-shell-annotations-toggle',
        'pdf-shell-properties-toggle',
      ]) {
        expect(find.byKey(ValueKey(key)), findsOneWidget, reason: key);
      }
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
      final toggle = tester.widget<IconButton>(find.ancestor(
        of: find.byIcon(Icons.grid_view),
        matching: find.byType(IconButton),
      ));
      expect(toggle.isSelected, isTrue);
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
      expect(find.byType(PdfAnnotationPropertiesPanel), findsOneWidget);
    });

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
      // color changer gone: "More colors…" picker and eyedropper
      expect(find.byIcon(Icons.palette), findsNothing);
      expect(find.byIcon(Icons.colorize), findsNothing);
      // the style popup (stroke/opacity/font) still shows
      expect(find.byTooltip('Stroke, opacity, font'), findsOneWidget);
      // its text-box color rows are gone with color controls off
      await tester.scrollUntilVisible(
          find.byTooltip('Stroke, opacity, font'), 100,
          scrollable: find.descendant(
              of: find.byType(PdfEditingToolbar),
              matching: find.byType(Scrollable)));
      await tester.tap(find.byTooltip('Stroke, opacity, font'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('pdf-text-fill-none')), findsNothing);
      expect(find.byKey(const ValueKey('pdf-text-border-none')), findsNothing);
      // but the sliders survive
      expect(find.byType(Slider), findsWidgets);
    });

    testWidgets('color controls are present by default', (tester) async {
      await pump(tester, PdfEditorView(bytes: buildMultiPagePdf(1)));
      expect(find.byIcon(Icons.palette), findsOneWidget);
      expect(find.byIcon(Icons.colorize), findsOneWidget);
      await tester.scrollUntilVisible(
          find.byTooltip('Stroke, opacity, font'), 100,
          scrollable: find.descendant(
              of: find.byType(PdfEditingToolbar),
              matching: find.byType(Scrollable)));
      await tester.tap(find.byTooltip('Stroke, opacity, font'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('pdf-text-fill-none')), findsOneWidget);
      expect(
          find.byKey(const ValueKey('pdf-text-border-none')), findsOneWidget);
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
      await tester.scrollUntilVisible(find.byIcon(Icons.save_alt), 80,
          scrollable: find.descendant(
            of: find.byType(PdfEditingToolbar),
            matching: find.byType(Scrollable),
          ));
      await tester.tap(find.byIcon(Icons.save_alt),
          kind: PointerDeviceKind.mouse);
      expect(saved, isNotNull);
      expect(saved!.length, editing.bytes.length);
    });

    testWidgets('no onSave, no save button', (tester) async {
      await pump(tester, PdfEditorView(bytes: buildMultiPagePdf(1)));
      expect(find.byIcon(Icons.save_alt), findsNothing);
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
  });
}
