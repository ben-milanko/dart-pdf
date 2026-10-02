import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Toolbar layout: tool bars docked to edges of their own, the separate style
// bar, the bars' grips (drag + placement menu) and the layout dialog.
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

  group('preferences', () {
    test('tool bar docks and the style bar persist, and reset clears them',
        () async {
      final a = PdfEditingPreferences();
      await a.ready;
      expect(a.toolStripDocks, isEmpty);
      expect(a.styleBarDock, isNull);
      a.setToolStripDock(PdfEditToolGroup.shapes, PdfPanelDock.right);
      a.setToolStripDock(PdfEditToolGroup.markup, PdfPanelDock.top);
      a.styleBarDock = PdfPanelDock.left;
      a.toolbarDock = PdfPanelDock.top;
      await pumpEventQueue();

      final b = PdfEditingPreferences();
      await b.ready;
      expect(b.toolStripDocks, {
        PdfEditToolGroup.shapes: PdfPanelDock.right,
        PdfEditToolGroup.markup: PdfPanelDock.top,
      });
      expect(b.toolStripDock(PdfEditToolGroup.draw), isNull);
      expect(b.styleBarDock, PdfPanelDock.left);

      b.setToolStripDock(PdfEditToolGroup.markup, null);
      expect(b.toolStripDock(PdfEditToolGroup.markup), isNull);
      b.resetToolbarLayout();
      await pumpEventQueue();
      expect(b.toolStripDocks, isEmpty);
      expect(b.styleBarDock, isNull);
      expect(b.toolbarDock, PdfPanelDock.bottom);

      final c = PdfEditingPreferences();
      await c.ready;
      expect(c.toolStripDocks, isEmpty);
      expect(c.styleBarDock, isNull);
      a.dispose();
      b.dispose();
      c.dispose();
    });
  });

  group('docked tool bars', () {
    testWidgets('a tool bar docked right stays there as a vertical palette',
        (tester) async {
      await pumpEditor(tester,
          configure: (p) =>
              p.setToolStripDock(PdfEditToolGroup.shapes, PdfPanelDock.right));

      // shown with its group closed - the main toolbar still rests on Select
      const bar = 'pdf-tool-bar-shapes';
      expect(find.byKey(const ValueKey(bar)), findsOneWidget);
      final rect = inBar(bar, find.byKey(const ValueKey('pdf-tool-rectangle')));
      final ellipse =
          inBar(bar, find.byKey(const ValueKey('pdf-tool-ellipse')));
      expect(rect, findsOneWidget);
      expect(tester.getCenter(rect).dx,
          closeTo(tester.getCenter(ellipse).dx, 0.5));
      expect(
          tester.getCenter(ellipse).dy, greaterThan(tester.getCenter(rect).dy));
      final barRect = rectOf(tester, const ValueKey(bar));
      expect(viewer(tester).right - barRect.right, lessThan(40));
      // the main toolbar keeps the bottom edge, and the right rail stays in
      // the band above it
      final main = rectOf(tester, const ValueKey('pdf-group-markup'));
      expect(main.top, greaterThan(viewer(tester).bottom - 100));
      expect(barRect.bottom, lessThanOrEqualTo(main.top));
      // closed, it offers tools but no settings
      expect(inBar(bar, find.byKey(const ValueKey('pdf-more-colors'))),
          findsNothing);

      // arming a tool from the docked bar opens its settings in place and
      // leaves no second shapes strip beside the main toolbar
      await tapMouse(tester, rect);
      expect(inBar(bar, find.byKey(const ValueKey('pdf-more-colors'))),
          findsOneWidget);
      expect(find.byKey(const ValueKey('pdf-tool-rectangle')), findsOneWidget);
    });

    testWidgets('dragging a tool bar grip to an edge docks it there',
        (tester) async {
      final prefs = await pumpEditor(tester);
      await tapMouse(tester, find.byKey(const ValueKey('pdf-group-shapes')));
      final grip = find.byKey(const ValueKey('pdf-tool-bar-move-shapes'));
      expect(grip, findsOneWidget);

      final gesture = await tester.startGesture(tester.getCenter(grip),
          kind: PointerDeviceKind.mouse);
      await gesture.moveBy(const Offset(12, -12));
      await tester.pump();
      final right = find.byKey(const ValueKey('pdf-shell-dropzone-right'));
      expect(right, findsOneWidget);
      await gesture.moveTo(tester.getCenter(right));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(prefs.toolStripDock(PdfEditToolGroup.shapes), PdfPanelDock.right);
      // the main toolbar did not move
      expect(prefs.toolbarDock, PdfPanelDock.bottom);
      expect(find.byKey(const ValueKey('pdf-tool-bar-shapes')), findsOneWidget);
    });

    testWidgets('a grip click opens a placement menu', (tester) async {
      final prefs = await pumpEditor(tester,
          configure: (p) =>
              p.setToolStripDock(PdfEditToolGroup.draw, PdfPanelDock.left));
      await tapMouse(
          tester, find.byKey(const ValueKey('pdf-tool-bar-move-draw')));
      expect(
          find.byKey(const ValueKey('pdf-bar-place-attached')), findsOneWidget);
      await tapMouse(
          tester, find.byKey(const ValueKey('pdf-bar-place-attached')));
      expect(prefs.toolStripDock(PdfEditToolGroup.draw), isNull);
      expect(find.byKey(const ValueKey('pdf-tool-bar-draw')), findsNothing);

      // the main toolbar's grip offers the four edges
      await tapMouse(tester, find.byKey(const ValueKey('pdf-toolbar-move')));
      expect(
          find.byKey(const ValueKey('pdf-bar-place-attached')), findsNothing);
      await tapMouse(tester, find.byKey(const ValueKey('pdf-bar-place-top')));
      expect(prefs.toolbarDock, PdfPanelDock.top);
      final markup = rectOf(tester, const ValueKey('pdf-group-markup'));
      expect(markup.top - viewer(tester).top, lessThan(40));
    });
  });

  group('style bar', () {
    testWidgets('holds the style controls for the armed tool and selection',
        (tester) async {
      await pumpEditor(tester,
          configure: (p) => p.styleBarDock = PdfPanelDock.top);
      const styleBar = 'pdf-style-bar';
      // resting: nothing restyles, so no bar
      expect(find.byKey(const ValueKey(styleBar)), findsNothing);

      await tapMouse(tester, find.byKey(const ValueKey('pdf-group-shapes')));
      expect(find.byKey(const ValueKey(styleBar)), findsOneWidget);
      expect(inBar(styleBar, find.byKey(const ValueKey('pdf-more-colors'))),
          findsOneWidget);
      // the colour lives in one place only
      expect(find.byKey(const ValueKey('pdf-more-colors')), findsOneWidget);
      final bar = rectOf(tester, const ValueKey(styleBar));
      expect(bar.top - viewer(tester).top, lessThan(40));

      // a different tool keeps the bar where it was
      await tapMouse(tester, find.byKey(const ValueKey('pdf-group-draw')));
      expect(
          rectOf(tester, const ValueKey(styleBar)).top, closeTo(bar.top, 0.5));
      expect(find.byKey(const ValueKey('pdf-more-colors')), findsOneWidget);
    });

    testWidgets('a tool bar menu switches the style bar on and off',
        (tester) async {
      final prefs = await pumpEditor(tester);
      await tapMouse(tester, find.byKey(const ValueKey('pdf-group-shapes')));
      // inline by default: style sits at the trailing end of the strip
      final scale = find.byKey(const ValueKey('pdf-tool-ellipse'));
      expect(tester.getCenter(find.byKey(const ValueKey('pdf-more-colors'))).dx,
          greaterThan(tester.getCenter(scale).dx));

      await tapMouse(
          tester, find.byKey(const ValueKey('pdf-tool-bar-move-shapes')));
      await tapMouse(tester, find.byKey(const ValueKey('pdf-bar-extra-0')));
      // the main toolbar is at the bottom, so the style bar goes across
      expect(prefs.styleBarDock, PdfPanelDock.top);
      expect(
          inBar('pdf-style-bar', find.byKey(const ValueKey('pdf-more-colors'))),
          findsOneWidget);

      await tapMouse(tester, find.byKey(const ValueKey('pdf-style-bar-move')));
      await tapMouse(
          tester, find.byKey(const ValueKey('pdf-bar-place-attached')));
      expect(prefs.styleBarDock, isNull);
      expect(find.byKey(const ValueKey('pdf-style-bar')), findsNothing);
      expect(find.byKey(const ValueKey('pdf-more-colors')), findsOneWidget);
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

    await tapMouse(tester, find.byKey(const ValueKey('pdf-layout-reset')));
    expect(prefs.styleBarDock, isNull);
    expect(prefs.toolStripDocks, isEmpty);
    await tapMouse(tester, find.byKey(const ValueKey('pdf-layout-done')));
    expect(find.byKey(const ValueKey('pdf-layout-main')), findsNothing);
  });
}
