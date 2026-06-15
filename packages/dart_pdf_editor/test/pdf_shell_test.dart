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

    testWidgets('color controls are present by default', (tester) async {
      await pump(tester, PdfEditorView(bytes: buildMultiPagePdf(1)));
      // the colour controls live in a group's strip — open one
      await tester.tap(find.byKey(const ValueKey('pdf-group-shapes')));
      await tester.pump();
      expect(find.byIcon(Icons.palette), findsOneWidget);
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
      // save now lives in the shell header (near the host's Open), keyed
      await tester.tap(find.byKey(const ValueKey('pdf-shell-save')),
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
    });

    testWidgets('Export pages… hands the host the chosen range', (tester) async {
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
      await tester.tap(find.byKey(const ValueKey('pdf-thumbnail-export-pages')));
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
      // insert needs page editing — hidden; export stands alone
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
      late EdgeInsets withoutInset;
      late EdgeInsets withInset;
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
      // clears the floating editing toolbar dock…
      expect(withoutInset.bottom, greaterThanOrEqualTo(84));
      // …and adds the device's bottom safe-area inset on top
      expect(withInset.bottom, withoutInset.bottom + 34);
    });
  });

  // On a narrow screen the side panels and the thumbnail strip become
  // bottom sheets instead of docking and crowding the page out.
  group('bottom sheets on small screens', () {
    testWidgets('compact: a toggled panel floats up as a bottom sheet',
        (tester) async {
      compactScreen(tester);
      await pump(tester, PdfEditorView(bytes: buildMultiPagePdf(2)));
      expect(find.byType(PdfAnnotationSidebar), findsNothing);

      await tester.tap(
          find.byKey(const ValueKey('pdf-shell-annotations-toggle')),
          kind: PointerDeviceKind.mouse);
      await tester.pump();

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

      await tester.tap(
          find.byKey(const ValueKey('pdf-shell-properties-toggle')),
          kind: PointerDeviceKind.mouse);
      await tester.pump();
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
      await tester.tap(
          find.byKey(const ValueKey('pdf-shell-properties-toggle')),
          kind: PointerDeviceKind.mouse);
      await tester.pump();

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
      // a resize is not a dismiss — the panel is still open
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

    testWidgets('compact reader: the thumbnail strip is a bottom sheet',
        (tester) async {
      final prefs = PdfEditingPreferences();
      await prefs.ready;
      addTearDown(prefs.dispose);
      compactScreen(tester);
      await pump(
          tester, PdfReader(bytes: buildMultiPagePdf(3), preferences: prefs));

      // compact first run starts closed; toggle it on
      await tester.tap(
          find.byKey(const ValueKey('pdf-shell-thumbnails-toggle')),
          kind: PointerDeviceKind.mouse);
      await tester.pump();

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
      expect(tester.getRect(bar).right,
          closeTo(tester.getRect(sheet).right, 4.0));
    });

    testWidgets('compact: dragging the empty margin of the thumbnail sheet '
        'scrolls it', (tester) async {
      // Regression: the tile column was a narrow centered SizedBox, so the
      // scroll viewport only covered the tiles — a drag on the wide sheet's
      // empty side margins hit nothing and never scrolled. The list now
      // fills the sheet and centers the column via its own inset.
      final prefs = PdfEditingPreferences();
      await prefs.ready;
      addTearDown(prefs.dispose);
      compactScreen(tester); // 600x800
      await pump(
          tester, PdfReader(bytes: buildMultiPagePdf(12), preferences: prefs));
      await tester.tap(
          find.byKey(const ValueKey('pdf-shell-thumbnails-toggle')),
          kind: PointerDeviceKind.mouse);
      await tester.pump();

      final sheet = find.byType(PdfThumbnailSidebar);
      final position = tester
          .state<ScrollableState>(
              find.descendant(of: sheet, matching: find.byType(Scrollable)).first)
          .position;
      expect(position.pixels, 0);
      expect(position.maxScrollExtent, greaterThan(0),
          reason: 'the strip should overflow with 12 pages');

      // drag UP from near the sheet's left edge — the empty margin beside
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

    testWidgets('the editable thumbnail strip has no Tooltip OverlayPortal '
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
      expect(find.widgetWithIcon(IconButton, Icons.delete_outline),
          findsWidgets);
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
    });

    testWidgets('wide: the editing toolbar floats over the viewer',
        (tester) async {
      // Above the breakpoint the toolbar is transparent floating cards —
      // it sits over the bottom of the page (Acrobat/Bluebeam-style).
      await pump(tester, PdfEditorView(bytes: buildMultiPagePdf(2)));

      final toolbar = find.byType(PdfEditingToolbar);
      expect(toolbar, findsOneWidget);
      final viewerBottom = tester.getRect(find.byType(PdfViewer)).bottom;
      final toolbarTop = tester.getRect(toolbar).top;
      expect(toolbarTop, lessThan(viewerBottom),
          reason: 'the floating toolbar overlaps the viewer');
    });
  });

  group('shell header bar', () {
    Color? iconColorOf(WidgetTester tester, Finder button) {
      final icon = find.descendant(of: button, matching: find.byType(Icon));
      return tester.widget<Icon>(icon.first).color ??
          IconTheme.of(tester.element(icon.first)).color;
    }

    testWidgets('every header icon button shares one colour', (tester) async {
      await pump(tester,
          PdfEditorView(bytes: buildMultiPagePdf(2), onSave: (_) {}));
      // the view-options PopupMenuButton used to render black87 while the
      // IconButtons rendered onSurfaceVariant
      final expected = iconColorOf(
          tester, find.byKey(const ValueKey('pdf-shell-save')));
      for (final key in const [
        'pdf-shell-author',
        'pdf-shell-view-options',
        'pdf-shell-annotations-toggle',
      ]) {
        expect(iconColorOf(tester, find.byKey(ValueKey(key))), expected,
            reason: '$key icon colour should match the others');
      }
    });
  });
}
