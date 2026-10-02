import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Toolbar layout: docked bars (solid bands along the window edges, the
// default), tool bars docked to edges of their own, the properties bar, the
// floating mode and its style bar, the bars' grips (drag + placement menu)
// and the layout dialog.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<PdfEditingPreferences> pumpEditor(WidgetTester tester,
      {void Function(PdfEditingPreferences prefs)? configure}) async {
    tester.view.physicalSize = const Size(1280, 860);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final prefs = PdfEditingPreferences();
    addTearDown(prefs.dispose);
    configure?.call(prefs);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PdfEditorView(bytes: buildMultiPagePdf(1), preferences: prefs),
      ),
    ));
    await tester.pump();
    return prefs;
  }

  Rect rectOf(WidgetTester tester, Key key) => tester.getRect(find.byKey(key));

  Rect viewer(WidgetTester tester) =>
      rectOf(tester, const ValueKey('pdf-shell-viewer'));

  Finder inBar(String bar, Finder matching) => find.descendant(
        of: find.byKey(ValueKey(bar)),
        matching: matching,
      );

  Future<void> tapMouse(WidgetTester tester, Finder finder) async {
    await tester.tap(finder, kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
  }

  const properties = 'pdf-style-bar';

  group('preferences', () {
    test('the toolbar layout persists, and reset docks everything on top',
        () async {
      final a = PdfEditingPreferences();
      await a.ready;
      expect(a.toolbarFloating, isFalse);
      expect(a.toolbarDock, PdfPanelDock.top);
      expect(a.toolStripDocks, isEmpty);
      expect(a.styleBarDock, isNull);
      a.setToolStripDock(PdfEditToolGroup.shapes, PdfPanelDock.right);
      a.setToolStripDock(PdfEditToolGroup.markup, PdfPanelDock.top);
      a.styleBarDock = PdfPanelDock.left;
      a.toolbarDock = PdfPanelDock.bottom;
      a.toolbarFloating = true;
      await pumpEventQueue();

      final b = PdfEditingPreferences();
      await b.ready;
      expect(b.toolStripDocks, {
        PdfEditToolGroup.shapes: PdfPanelDock.right,
        PdfEditToolGroup.markup: PdfPanelDock.top,
      });
      expect(b.toolStripDock(PdfEditToolGroup.draw), isNull);
      expect(b.styleBarDock, PdfPanelDock.left);
      expect(b.toolbarFloating, isTrue);

      b.setToolStripDock(PdfEditToolGroup.markup, null);
      expect(b.toolStripDock(PdfEditToolGroup.markup), isNull);
      b.resetToolbarLayout();
      await pumpEventQueue();
      expect(b.toolStripDocks, isEmpty);
      expect(b.styleBarDock, isNull);
      expect(b.toolbarDock, PdfPanelDock.top);
      expect(b.toolbarFloating, isFalse);

      final c = PdfEditingPreferences();
      await c.ready;
      expect(c.toolStripDocks, isEmpty);
      expect(c.toolbarFloating, isFalse);
      a.dispose();
      b.dispose();
      c.dispose();
    });
  });

  group('docked', () {
    testWidgets('every group is its own toolbar, with no group switcher',
        (tester) async {
      await pumpEditor(tester);
      // docked, Bluebeam-style: each group's toolbar is on show...
      for (final group in [
        'markup',
        'draw',
        'shapes',
        'insert',
        'measure',
        'edit'
      ]) {
        expect(find.byKey(ValueKey('pdf-tool-bar-$group')), findsOneWidget,
            reason: group);
        expect(
            find.byKey(ValueKey('pdf-tool-bar-move-$group')), findsOneWidget);
        // ...and there is no switcher chip to open it
        expect(find.byKey(ValueKey('pdf-group-$group')), findsNothing);
      }
      expect(find.byKey(const ValueKey('pdf-docked-main')), findsOneWidget);
      // the toolbars sit above the properties bar, which sits above the
      // content, all spanning the window above the side panels
      final shapes = rectOf(tester, const ValueKey('pdf-tool-bar-shapes'));
      final bar = rectOf(tester, const ValueKey(properties));
      final pageTop = viewer(tester).top;
      expect(shapes.bottom, lessThanOrEqualTo(bar.top + 0.5));
      expect(bar.bottom, lessThanOrEqualTo(pageTop + 0.5));
      expect(bar.width, closeTo(1280, 0.5));
      final pages = find.byType(PdfThumbnailSidebar);
      expect(tester.getRect(pages).top, greaterThanOrEqualTo(bar.bottom - 0.5));
      expect(inBar(properties, find.text('Properties'.toUpperCase())),
          findsOneWidget);
    });

    testWidgets('one click arms a tool; its properties never move the page',
        (tester) async {
      final prefs = await pumpEditor(tester);
      final pageTop = viewer(tester).top;
      final barHeight = rectOf(tester, const ValueKey(properties)).height;

      await tapMouse(tester, find.byKey(const ValueKey('pdf-tool-rectangle')));
      expect(inBar(properties, find.byKey(const ValueKey('pdf-more-colors'))),
          findsOneWidget);
      expect(inBar(properties, find.text('RECTANGLE')), findsOneWidget);
      // the tools are not repeated in the properties bar
      expect(find.byKey(const ValueKey('pdf-tool-rectangle')), findsOneWidget);
      expect(viewer(tester).top, closeTo(pageTop, 0.5));
      expect(rectOf(tester, const ValueKey(properties)).height,
          closeTo(barHeight, 0.5));

      // straight to a tool in another group, no switcher in between
      await tapMouse(tester, find.byKey(const ValueKey('pdf-tool-ink')));
      expect(inBar(properties, find.text('PEN')), findsNothing);
      expect(viewer(tester).top, closeTo(pageTop, 0.5));
      expect(prefs.toolbarFloating, isFalse);
    });

    testWidgets('a narrow window wraps the toolbars and never overflows',
        (tester) async {
      tester.view.physicalSize = const Size(800, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final prefs = PdfEditingPreferences();
      addTearDown(prefs.dispose);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: PdfEditorView(bytes: buildMultiPagePdf(1), preferences: prefs),
        ),
      ));
      await tester.pump();
      expect(tester.takeException(), isNull);
      final markup = rectOf(tester, const ValueKey('pdf-tool-bar-markup'));
      final edit = rectOf(tester, const ValueKey('pdf-tool-bar-edit'));
      expect(edit.top, greaterThan(markup.top), reason: 'wrapped to a new row');
      expect(edit.right, lessThanOrEqualTo(800.5));
    });

    testWidgets('a tool bar docked right is a rail beside the content',
        (tester) async {
      await pumpEditor(tester,
          configure: (p) =>
              p.setToolStripDock(PdfEditToolGroup.shapes, PdfPanelDock.right));

      const bar = 'pdf-tool-bar-shapes';
      final rail = rectOf(tester, const ValueKey(bar));
      expect(rail.right, closeTo(1280, 0.5));
      expect(rail.left, greaterThanOrEqualTo(viewer(tester).right - 0.5));
      final rect = inBar(bar, find.byKey(const ValueKey('pdf-tool-rectangle')));
      final ellipse =
          inBar(bar, find.byKey(const ValueKey('pdf-tool-ellipse')));
      expect(tester.getCenter(rect).dx,
          closeTo(tester.getCenter(ellipse).dx, 0.5));
      expect(
          tester.getCenter(ellipse).dy, greaterThan(tester.getCenter(rect).dy));

      // arming from the rail shows its properties in the properties bar, and
      // the tools are not repeated there
      await tapMouse(tester, ellipse);
      expect(inBar(properties, find.byKey(const ValueKey('pdf-more-colors'))),
          findsOneWidget);
      expect(find.byKey(const ValueKey('pdf-tool-ellipse')), findsOneWidget);
      expect(inBar(bar, find.byKey(const ValueKey('pdf-more-colors'))),
          findsNothing);
    });

    testWidgets('dragging a group\'s tools to an edge docks them there',
        (tester) async {
      final prefs = await pumpEditor(tester);
      final grip = find.byKey(const ValueKey('pdf-tool-bar-move-shapes'));
      expect(inBar('pdf-tool-bar-shapes', grip), findsOneWidget);

      final gesture = await tester.startGesture(tester.getCenter(grip),
          kind: PointerDeviceKind.mouse);
      await gesture.moveBy(const Offset(12, 12));
      await tester.pump();
      final right = find.byKey(const ValueKey('pdf-shell-dropzone-right'));
      expect(right, findsOneWidget);
      await gesture.moveTo(tester.getCenter(right));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(prefs.toolStripDock(PdfEditToolGroup.shapes), PdfPanelDock.right);
      expect(prefs.toolbarDock, PdfPanelDock.top);
      expect(find.byKey(const ValueKey('pdf-tool-bar-shapes')), findsOneWidget);
    });

    testWidgets('the main toolbar docks left as a rail, properties on top',
        (tester) async {
      final prefs = await pumpEditor(tester);
      await tapMouse(tester, find.byKey(const ValueKey('pdf-toolbar-move')));
      await tapMouse(tester, find.byKey(const ValueKey('pdf-bar-place-left')));
      expect(prefs.toolbarDock, PdfPanelDock.left);

      // the main toolbar and the groups that ride with it form rails down
      // the left edge, outside the side panels
      final main = rectOf(tester, const ValueKey('pdf-docked-main'));
      final rectangle = rectOf(tester, const ValueKey('pdf-tool-rectangle'));
      final ellipse = rectOf(tester, const ValueKey('pdf-tool-ellipse'));
      expect(main.left, lessThan(20));
      expect(ellipse.center.dx, closeTo(rectangle.center.dx, 0.5));
      expect(ellipse.top, greaterThan(rectangle.top));
      final pages = tester.getRect(find.byType(PdfThumbnailSidebar));
      expect(rectangle.right, lessThanOrEqualTo(pages.left + 0.5));
      final bar = rectOf(tester, const ValueKey(properties));
      expect(bar.width, closeTo(1280, 0.5));
      expect(bar.bottom, lessThanOrEqualTo(main.top));
    });

    testWidgets('the main grip menu switches to floating and back',
        (tester) async {
      final prefs = await pumpEditor(tester);
      expect(
          find.byKey(const ValueKey('pdf-editing-toolbar-card')), findsNothing);
      await tapMouse(tester, find.byKey(const ValueKey('pdf-toolbar-move')));
      await tapMouse(tester, find.byKey(const ValueKey('pdf-bar-extra-0')));
      expect(prefs.toolbarFloating, isTrue);
      expect(
          find.byKey(const ValueKey('pdf-editing-toolbar-band')), findsNothing);
      expect(find.byKey(const ValueKey('pdf-editing-toolbar-card')),
          findsOneWidget);

      await tapMouse(tester, find.byKey(const ValueKey('pdf-toolbar-move')));
      await tapMouse(tester, find.byKey(const ValueKey('pdf-bar-extra-0')));
      expect(prefs.toolbarFloating, isFalse);
      // the toolbar area and the properties bar
      expect(find.byKey(const ValueKey('pdf-editing-toolbar-band')),
          findsNWidgets(2));
    });

    testWidgets('View options toggles floating toolbars', (tester) async {
      final prefs = await pumpEditor(tester);
      await tapMouse(
          tester, find.byKey(const ValueKey('pdf-shell-view-options')));
      await tapMouse(
          tester, find.byKey(const ValueKey('pdf-shell-floating-toolbars')));
      expect(prefs.toolbarFloating, isTrue);
      // floating keeps the group switcher and its contextual strip
      expect(find.byKey(const ValueKey('pdf-group-shapes')), findsOneWidget);
      expect(find.byKey(const ValueKey('pdf-tool-bar-shapes')), findsNothing);
      await tapMouse(tester, find.byKey(const ValueKey('pdf-group-shapes')));
      expect(find.byKey(const ValueKey('pdf-tool-rectangle')), findsOneWidget);

      await tapMouse(
          tester, find.byKey(const ValueKey('pdf-shell-view-options')));
      await tapMouse(
          tester, find.byKey(const ValueKey('pdf-shell-floating-toolbars')));
      expect(prefs.toolbarFloating, isFalse);
      expect(find.byKey(const ValueKey('pdf-group-shapes')), findsNothing);
    });
  });

  group('floating', () {
    void floating(PdfEditingPreferences p) => p
      ..toolbarFloating = true
      ..toolbarDock = PdfPanelDock.bottom;

    testWidgets('a docked tool bar stays on its edge as a palette',
        (tester) async {
      await pumpEditor(tester, configure: (p) {
        floating(p);
        p.setToolStripDock(PdfEditToolGroup.shapes, PdfPanelDock.right);
      });
      const bar = 'pdf-tool-bar-shapes';
      final rect = inBar(bar, find.byKey(const ValueKey('pdf-tool-rectangle')));
      expect(rect, findsOneWidget);
      final barRect = rectOf(tester, const ValueKey(bar));
      expect(viewer(tester).right - barRect.right, lessThan(40));
      expect(inBar(bar, find.byKey(const ValueKey('pdf-more-colors'))),
          findsNothing);
      await tapMouse(tester, rect);
      expect(inBar(bar, find.byKey(const ValueKey('pdf-more-colors'))),
          findsOneWidget);
    });

    testWidgets('the style bar holds the style controls in one place',
        (tester) async {
      await pumpEditor(tester, configure: (p) {
        floating(p);
        p.styleBarDock = PdfPanelDock.top;
      });
      // resting: nothing restyles, so no bar
      expect(find.byKey(const ValueKey(properties)), findsNothing);

      await tapMouse(tester, find.byKey(const ValueKey('pdf-group-shapes')));
      expect(inBar(properties, find.byKey(const ValueKey('pdf-more-colors'))),
          findsOneWidget);
      expect(find.byKey(const ValueKey('pdf-more-colors')), findsOneWidget);
      final bar = rectOf(tester, const ValueKey(properties));
      expect(bar.top - viewer(tester).top, lessThan(40));

      await tapMouse(tester, find.byKey(const ValueKey('pdf-group-draw')));
      expect(rectOf(tester, const ValueKey(properties)).top,
          closeTo(bar.top, 0.5));
    });

    testWidgets('a tool bar menu switches the style bar on and off',
        (tester) async {
      final prefs = await pumpEditor(tester, configure: floating);
      await tapMouse(tester, find.byKey(const ValueKey('pdf-group-shapes')));
      // inline: style sits at the trailing end of the strip
      expect(
          tester.getCenter(find.byKey(const ValueKey('pdf-more-colors'))).dx,
          greaterThan(tester
              .getCenter(find.byKey(const ValueKey('pdf-tool-ellipse')))
              .dx));

      await tapMouse(
          tester, find.byKey(const ValueKey('pdf-tool-bar-move-shapes')));
      await tapMouse(tester, find.byKey(const ValueKey('pdf-bar-extra-0')));
      expect(prefs.styleBarDock, PdfPanelDock.top);
      expect(inBar(properties, find.byKey(const ValueKey('pdf-more-colors'))),
          findsOneWidget);

      await tapMouse(tester, find.byKey(const ValueKey('pdf-style-bar-move')));
      await tapMouse(
          tester, find.byKey(const ValueKey('pdf-bar-place-attached')));
      expect(prefs.styleBarDock, isNull);
      expect(find.byKey(const ValueKey(properties)), findsNothing);
    });
  });

  testWidgets('the view options open the toolbar layout dialog',
      (tester) async {
    final prefs = await pumpEditor(tester);
    await tapMouse(
        tester, find.byKey(const ValueKey('pdf-shell-view-options')));
    await tapMouse(
        tester, find.byKey(const ValueKey('pdf-shell-toolbar-layout')));
    expect(find.byKey(const ValueKey('pdf-layout-main')), findsOneWidget);
    expect(find.byKey(const ValueKey('pdf-layout-bar-select')), findsNothing);

    await tapMouse(tester, find.byKey(const ValueKey('pdf-layout-style')));
    await tapMouse(
        tester, find.byKey(const ValueKey('pdf-layout-style-left')).last);
    expect(prefs.styleBarDock, PdfPanelDock.left);

    final measure = find.byKey(const ValueKey('pdf-layout-bar-measure'));
    await tester.ensureVisible(measure);
    await tester.pumpAndSettle();
    await tapMouse(tester, measure);
    await tapMouse(tester,
        find.byKey(const ValueKey('pdf-layout-bar-measure-right')).last);
    expect(prefs.toolStripDock(PdfEditToolGroup.measure), PdfPanelDock.right);

    final mode = find.byKey(const ValueKey('pdf-layout-mode'));
    await tester.ensureVisible(mode);
    await tester.pumpAndSettle();
    await tapMouse(tester, mode);
    await tapMouse(
        tester, find.byKey(const ValueKey('pdf-layout-mode-floating')).last);
    expect(prefs.toolbarFloating, isTrue);

    await tapMouse(tester, find.byKey(const ValueKey('pdf-layout-reset')));
    expect(prefs.toolbarFloating, isFalse);
    expect(prefs.styleBarDock, isNull);
    expect(prefs.toolStripDocks, isEmpty);
    await tapMouse(tester, find.byKey(const ValueKey('pdf-layout-done')));
    expect(find.byKey(const ValueKey('pdf-layout-main')), findsNothing);
  });
}
