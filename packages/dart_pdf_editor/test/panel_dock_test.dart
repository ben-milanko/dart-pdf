import 'package:dart_pdf_editor/dart_pdf_editor.dart';
// PdfShellPanelLayout / PdfPanelTabGroup are shell-internal (not exported);
// reach them directly for these composition tests.
import 'package:dart_pdf_editor/src/shell_chrome.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Draggable/dockable panels: each panel remembers which edge it is docked
// on (left/right/top/bottom), the choice persists, and a panel's move handle
// can be dragged onto another edge to redock it live.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pump(WidgetTester tester, Widget body) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: body)));
    await tester.pump();
  }

  group('dock preferences', () {
    test('default docks reproduce the built-in layout', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = PdfEditingPreferences();
      addTearDown(prefs.dispose);
      await prefs.ready;
      expect(prefs.thumbnailSidebarDock, PdfPanelDock.left);
      expect(prefs.searchPanelDock, PdfPanelDock.left);
      expect(prefs.bookmarkSidebarDock, PdfPanelDock.left);
      expect(prefs.annotationSidebarDock, PdfPanelDock.right);
      expect(prefs.propertiesPanelDock, PdfPanelDock.right);
    });

    test('a redocked layout persists and a fresh instance restores it',
        () async {
      SharedPreferences.setMockInitialValues({});
      final a = PdfEditingPreferences();
      addTearDown(a.dispose);
      await a.ready;
      a.thumbnailSidebarDock = PdfPanelDock.top;
      a.searchPanelDock = PdfPanelDock.bottom;
      a.annotationSidebarDock = PdfPanelDock.left;
      a.propertiesPanelDock = PdfPanelDock.top;
      await pumpEventQueue(); // let the unawaited writes land

      final b = PdfEditingPreferences();
      addTearDown(b.dispose);
      await b.ready;
      expect(b.thumbnailSidebarDock, PdfPanelDock.top);
      expect(b.searchPanelDock, PdfPanelDock.bottom);
      expect(b.annotationSidebarDock, PdfPanelDock.left);
      expect(b.propertiesPanelDock, PdfPanelDock.top);
      // untouched panels keep their defaults
      expect(b.bookmarkSidebarDock, PdfPanelDock.left);
    });

    test('setting a dock to its current value writes nothing new', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = PdfEditingPreferences();
      addTearDown(prefs.dispose);
      await prefs.ready;
      var notifications = 0;
      prefs.addListener(() => notifications++);
      prefs.annotationSidebarDock = PdfPanelDock.right; // already the default
      expect(notifications, 0);
      prefs.annotationSidebarDock = PdfPanelDock.top;
      expect(notifications, 1);
    });
  });

  group('PdfPanelDock', () {
    test('left/right are horizontal, top/bottom are not', () {
      expect(PdfPanelDock.left.isHorizontal, isTrue);
      expect(PdfPanelDock.right.isHorizontal, isTrue);
      expect(PdfPanelDock.top.isHorizontal, isFalse);
      expect(PdfPanelDock.bottom.isHorizontal, isFalse);
    });
  });

  group('vertical dock frame', () {
    testWidgets('a top dock lays out as a fixed-height strip', (tester) async {
      await pump(
        tester,
        SizedBox(
          width: 500,
          height: 400,
          child: Column(children: [
            PdfSidebarPanelFrame(
              width: 180,
              minWidth: 120,
              maxWidth: 260,
              dock: PdfPanelDock.top,
              resizable: true,
              bottomSheet: false,
              gripKey: const ValueKey('v-grip'),
              builder: (context, geometry) => const ColoredBox(
                key: ValueKey('v-content'),
                color: Colors.white,
              ),
            ),
            const Expanded(child: SizedBox()),
          ]),
        ),
      );
      // the strip spans the full width and is bounded to its extent in height
      final size = tester.getSize(find.byType(PdfSidebarPanelFrame));
      expect(size.height, 180);
      expect(size.width, 500);
      // its grip is the horizontal (row-resize) variant, not the column one
      expect(find.byKey(const ValueKey('v-grip')), findsOneWidget);
    });
  });

  group('drag to redock', () {
    testWidgets('dragging a panel handle onto the top zone redocks it',
        (tester) async {
      final prefs = PdfEditingPreferences()..showAnnotationSidebar = true;
      addTearDown(prefs.dispose);
      await prefs.ready;
      await pump(
        tester,
        PdfEditorView(bytes: buildMultiPagePdf(2), preferences: prefs),
      );
      await tester.pump();

      // the annotation panel starts docked on the right (the default)
      expect(prefs.annotationSidebarDock, PdfPanelDock.right);
      final handle = find.byKey(const ValueKey('pdf-annotation-panel-move'));
      expect(handle, findsOneWidget);
      // no drop zones until a drag is underway
      expect(
          find.byKey(const ValueKey('pdf-shell-dropzone-top')), findsNothing);

      final gesture = await tester.startGesture(tester.getCenter(handle));
      // move past the touch slop to start the Draggable's drag
      await gesture.moveBy(const Offset(0, -24));
      await tester.pump(const Duration(milliseconds: 40));

      // the four edge drop zones appear while dragging
      final topZone = find.byKey(const ValueKey('pdf-shell-dropzone-top'));
      expect(topZone, findsOneWidget);
      expect(find.byKey(const ValueKey('pdf-shell-dropzone-left')),
          findsOneWidget);

      await gesture.moveTo(tester.getCenter(topZone));
      await tester.pump();
      await gesture.up();
      await tester.pump();

      // the panel is now docked on the top edge, and the choice is persisted
      expect(prefs.annotationSidebarDock, PdfPanelDock.top);
      // dropping ends the drag, so the zones are gone again
      expect(
          find.byKey(const ValueKey('pdf-shell-dropzone-top')), findsNothing);
      // the panel is still present (its search field survives the move)
      expect(
          find.byKey(const ValueKey('pdf-annotation-search')), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('a panel outside a drag scope shows no move handle',
        (tester) async {
      final editing = PdfEditingController(buildMultiPagePdf(1));
      final viewer = PdfViewerController();
      addTearDown(editing.dispose);
      addTearDown(viewer.dispose);
      await pump(
        tester,
        Row(children: [
          PdfAnnotationSidebar(
            controller: editing,
            viewerController: viewer,
            onClose: () {},
          ),
          const Expanded(child: SizedBox()),
        ]),
      );
      await tester.pump();
      // the close button renders, but the move handle stays inert with no
      // shell drag scope around it
      expect(find.byKey(const ValueKey('pdf-annotation-panel-close')),
          findsOneWidget);
      final handle = find.byKey(const ValueKey('pdf-annotation-panel-move'));
      expect(handle, findsOneWidget);
      expect(find.descendant(of: handle, matching: find.byType(Draggable)),
          findsNothing);
    });
  });

  group('tab groups', () {
    test('group ids default to standalone and persist', () async {
      SharedPreferences.setMockInitialValues({});
      final a = PdfEditingPreferences();
      addTearDown(a.dispose);
      await a.ready;
      // every panel starts in its own group (all side-by-side)
      final groups = {
        for (final p in PdfDockablePanel.values) a.panelGroup(p),
      };
      expect(groups.length, PdfDockablePanel.values.length);

      // tab properties into annotations' group
      a.setPanelGroup(PdfDockablePanel.properties,
          a.panelGroup(PdfDockablePanel.annotations));
      await pumpEventQueue();

      final b = PdfEditingPreferences();
      addTearDown(b.dispose);
      await b.ready;
      expect(b.panelGroup(PdfDockablePanel.properties),
          b.panelGroup(PdfDockablePanel.annotations));
    });

    testWidgets(
        'dropping a panel onto another tabs them, dragging a tab out '
        'to an edge splits it back', (tester) async {
      final prefs = PdfEditingPreferences()
        ..showAnnotationSidebar = true
        ..showPropertiesPanel = true;
      addTearDown(prefs.dispose);
      await prefs.ready;
      await pump(
        tester,
        PdfEditorView(bytes: buildMultiPagePdf(2), preferences: prefs),
      );
      await tester.pump();

      // annotations + properties start side-by-side on the right (two frames,
      // no tab group yet)
      expect(find.byType(PdfPanelTabGroup), findsNothing);
      final propsHandle =
          find.byKey(const ValueKey('pdf-properties-panel-move'));
      final annotationsPanel =
          find.byKey(const ValueKey('pdf-shell-annotations-docked'));
      expect(propsHandle, findsOneWidget);
      expect(annotationsPanel, findsOneWidget);

      // drag the properties handle onto the annotations panel body -> tab them
      var gesture = await tester.startGesture(tester.getCenter(propsHandle));
      await gesture.moveBy(const Offset(-24, 0));
      await tester.pump(const Duration(milliseconds: 40));
      await gesture.moveTo(tester.getCenter(annotationsPanel));
      await tester.pump();
      await gesture.up();
      await tester.pump();

      // they now share a group and render as one tabbed panel
      expect(prefs.panelGroup(PdfDockablePanel.properties),
          prefs.panelGroup(PdfDockablePanel.annotations));
      expect(prefs.propertiesPanelDock, PdfPanelDock.right);
      expect(find.byType(PdfPanelTabGroup), findsOneWidget);
      expect(find.byKey(const ValueKey('pdf-panel-tab-annotations')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('pdf-panel-tab-properties')),
          findsOneWidget);

      // now drag the properties tab onto the left edge zone -> split it out
      final tab = find.byKey(const ValueKey('pdf-panel-tab-properties'));
      await tester.ensureVisible(tab); // the tab strip scrolls; reveal it
      await tester.pump();
      gesture = await tester.startGesture(tester.getCenter(tab));
      await gesture.moveBy(const Offset(-24, 0));
      await tester.pump(const Duration(milliseconds: 40));
      final leftZone = find.byKey(const ValueKey('pdf-shell-dropzone-left'));
      expect(leftZone, findsOneWidget);
      await gesture.moveTo(tester.getCenter(leftZone));
      await tester.pump();
      await gesture.up();
      await tester.pump();

      // properties moved to the left, standalone (its own group again), so the
      // tab group is gone
      expect(prefs.propertiesPanelDock, PdfPanelDock.left);
      expect(prefs.panelGroup(PdfDockablePanel.properties),
          prefs.standalonePanelGroup(PdfDockablePanel.properties));
      expect(find.byType(PdfPanelTabGroup), findsNothing);
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('tapping a tab switches the visible panel', (tester) async {
      final prefs = PdfEditingPreferences()
        ..showAnnotationSidebar = true
        ..showPropertiesPanel = true;
      addTearDown(prefs.dispose);
      await prefs.ready;
      // pre-tab annotations + properties into one group on the right
      prefs.setPanelGroup(PdfDockablePanel.properties,
          prefs.panelGroup(PdfDockablePanel.annotations));
      await pump(
        tester,
        PdfEditorView(bytes: buildMultiPagePdf(2), preferences: prefs),
      );
      await tester.pump();

      expect(find.byType(PdfPanelTabGroup), findsOneWidget);
      // the first tab (annotations) is selected: its search field shows
      expect(
          find.byKey(const ValueKey('pdf-annotation-search')), findsOneWidget);

      final propsTab = find.byKey(const ValueKey('pdf-panel-tab-properties'));
      await tester.ensureVisible(propsTab); // the tab strip scrolls; reveal it
      await tester.pump();
      await tester.tap(propsTab);
      await tester.pump();
      // properties tab body is now shown (its "select an annotation" empty
      // state), and the tabs are still both present
      expect(find.byKey(const ValueKey('pdf-panel-tab-annotations')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('pdf-panel-tab-properties')),
          findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
    });
  });

  group('viewer is invariant to the panels', () {
    // Panels overlay the viewer rather than squeezing it, so opening, closing,
    // or resizing a panel must not change the viewer's size - the document view
    // can't zoom or shift under the reader when a panel toggles.
    Widget shell({List<Widget> leading = const [], double panelWidth = 260}) =>
        PdfShellPanelLayout(
          viewer: const SizedBox.expand(
            key: ValueKey('test-viewer'),
            child: ColoredBox(color: Color(0xFF000000)),
          ),
          leadingPanels: [
            for (final _ in leading)
              SizedBox(
                key: const ValueKey('test-panel'),
                width: panelWidth,
                height: double.infinity,
                child: const ColoredBox(color: Color(0xFF888888)),
              ),
          ],
        );

    testWidgets('the viewer fills the whole area with no panels open',
        (tester) async {
      await pump(tester, shell());
      final full = tester.getSize(find.byKey(const ValueKey('test-viewer')));
      expect(full.width, greaterThan(0));
      expect(full.height, greaterThan(0));
    });

    testWidgets('opening a panel does not resize the viewer', (tester) async {
      await pump(tester, shell());
      final before = tester.getSize(find.byKey(const ValueKey('test-viewer')));

      // open a leading panel
      await pump(tester, shell(leading: const [SizedBox()]));
      expect(find.byKey(const ValueKey('test-panel')), findsOneWidget);
      final after = tester.getSize(find.byKey(const ValueKey('test-viewer')));

      expect(after, before,
          reason: 'the viewer keeps the full content area - the panel '
              'overlays it rather than pushing it');
    });

    testWidgets('resizing a panel does not resize the viewer', (tester) async {
      await pump(tester, shell(leading: const [SizedBox()], panelWidth: 200));
      final before = tester.getSize(find.byKey(const ValueKey('test-viewer')));

      await pump(tester, shell(leading: const [SizedBox()], panelWidth: 360));
      final after = tester.getSize(find.byKey(const ValueKey('test-viewer')));

      expect(after, before,
          reason: 'a wider panel still overlays the viewer, size unchanged');
    });
  });
}
