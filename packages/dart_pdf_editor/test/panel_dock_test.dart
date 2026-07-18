import 'package:dart_pdf_editor/dart_pdf_editor.dart';
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
}
