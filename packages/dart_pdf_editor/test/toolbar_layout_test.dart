import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:pdf_document/pdf_document.dart' show PdfLineEnding;
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dart_pdf_editor/src/editing/first_fit_wrap.dart';

// Toolbar layout: docked bars (solid bands along the window edges, the
// default), tool bars docked to edges of their own, the properties bar, the
// floating mode and its style bar, the bars' grips (drag + placement menu)
// and the layout dialog.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // most of these tests arrange the bars, so they start in the customize
  // mode that shows the grips; pass customizing: false for the stock look
  Future<PdfEditingPreferences> pumpEditor(WidgetTester tester,
      {void Function(PdfEditingPreferences prefs)? configure,
      bool customizing = true}) async {
    tester.view.physicalSize = const Size(1280, 860);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final prefs = PdfEditingPreferences()..toolbarCustomizing = customizing;
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
      expect(a.toolbarPackTightly, isFalse, reason: 'in order by default');
      a.toolbarPackTightly = true;
      expect(a.toolbarMainInHeader, isFalse, reason: 'below by default');
      a.toolbarMainInHeader = true;
      await pumpEventQueue();

      final b = PdfEditingPreferences();
      await b.ready;
      // the arrangement was made docked; b opens floating, which has its own
      expect(b.toolbarFloating, isTrue);
      expect(b.toolStripDocks, isEmpty);
      b.toolbarFloating = false;
      expect(b.toolStripDocks, {
        PdfEditToolGroup.shapes: PdfPanelDock.right,
        PdfEditToolGroup.markup: PdfPanelDock.top,
      });
      expect(b.toolStripDock(PdfEditToolGroup.draw), isNull);
      expect(b.styleBarDock, PdfPanelDock.left);
      expect(b.toolbarPackTightly, isTrue);
      expect(b.toolbarMainInHeader, isTrue);

      b.setToolStripDock(PdfEditToolGroup.markup, null);
      expect(b.toolStripDock(PdfEditToolGroup.markup), isNull);
      b.resetToolbarLayout();
      await pumpEventQueue();
      expect(b.toolStripDocks, isEmpty);
      expect(b.styleBarDock, isNull);
      expect(b.toolbarDock, PdfPanelDock.top);
      expect(b.toolbarFloating, isFalse);
      expect(b.toolbarPackTightly, isFalse);
      expect(b.toolbarMainInHeader, isFalse);

      final c = PdfEditingPreferences();
      await c.ready;
      expect(c.toolStripDocks, isEmpty);
      expect(c.toolbarFloating, isFalse);
      a.dispose();
      b.dispose();
      c.dispose();
    });
  });

  test('docked and floating keep their own tool bar arrangements', () async {
    final a = PdfEditingPreferences();
    await a.ready;
    a.setToolStripDock(PdfEditToolGroup.shapes, PdfPanelDock.right);
    a.styleBarDock = PdfPanelDock.left;
    // floating starts from its own (stock) arrangement: no stray palettes
    a.toolbarFloating = true;
    expect(a.toolStripDocks, isEmpty);
    expect(a.styleBarDock, isNull);
    a.setToolStripDock(PdfEditToolGroup.markup, PdfPanelDock.left);
    a.styleBarDock = PdfPanelDock.bottom;
    // and docked gets its own back
    a.toolbarFloating = false;
    expect(a.toolStripDocks, {PdfEditToolGroup.shapes: PdfPanelDock.right});
    expect(a.styleBarDock, PdfPanelDock.left);
    await pumpEventQueue();

    final b = PdfEditingPreferences();
    await b.ready;
    expect(b.toolStripDocks, {PdfEditToolGroup.shapes: PdfPanelDock.right});
    b.toolbarFloating = true;
    expect(b.toolStripDocks, {PdfEditToolGroup.markup: PdfPanelDock.left});
    expect(b.styleBarDock, PdfPanelDock.bottom);
    // reset clears both
    b.resetToolbarLayout();
    expect(b.toolStripDocks, isEmpty);
    b.toolbarFloating = true;
    expect(b.toolStripDocks, isEmpty);
    expect(b.styleBarDock, isNull);
    a.dispose();
    b.dispose();
  });

  testWidgets('switching to floating leaves no docked rails behind',
      (tester) async {
    final prefs = await pumpEditor(tester, configure: (p) {
      p.setToolStripDock(PdfEditToolGroup.shapes, PdfPanelDock.right);
      p.setToolStripDock(PdfEditToolGroup.measure, PdfPanelDock.right);
    });
    expect(find.byKey(const ValueKey('pdf-tool-bar-shapes')), findsOneWidget);
    prefs.toolbarFloating = true;
    await tester.pumpAndSettle();
    // the floating switcher, and no pinned Shapes/Measure palettes
    expect(find.byKey(const ValueKey('pdf-group-shapes')), findsOneWidget);
    expect(find.byKey(const ValueKey('pdf-tool-bar-shapes')), findsNothing);
    expect(find.byKey(const ValueKey('pdf-tool-bar-measure')), findsNothing);
    prefs.toolbarFloating = false;
    await tester.pumpAndSettle();
    final rail = rectOf(tester, const ValueKey('pdf-tool-bar-shapes'));
    expect(rail.right, closeTo(1280, 0.5), reason: 'docked rail restored');
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

    testWidgets('labelled tools go icon-only, so Edit is no row of its own',
        (tester) async {
      await pumpEditor(tester);
      // Edit's tools, Color, Flatten and Totals keep their names for the
      // tooltip only: outlined labels made Edit a row of its own
      for (final label in ['Content', 'Erase', 'Redact', 'Flatten']) {
        expect(inBar('pdf-tool-bar-edit', find.text(label)), findsNothing,
            reason: label);
      }
      for (final key in ['pdf-tool-content', 'pdf-flatten-all']) {
        expect(
            find.descendant(
                of: find.byKey(ValueKey(key)), matching: find.byType(Text)),
            findsNothing,
            reason: key);
        expect(
            find.descendant(
                of: find.byKey(ValueKey(key)),
                matching: find.byType(IconButton),
                matchRoot: true),
            findsOneWidget,
            reason: key);
      }
      expect(inBar('pdf-tool-bar-measure', find.text('Totals')), findsNothing);
      // labelled, Edit alone was ~800px - a toolbar row of its own, and
      // three rows at 1280 and 1440px
      expect(rectOf(tester, const ValueKey('pdf-tool-bar-edit')).width,
          lessThan(500));
    });

    testWidgets('the armed tool is a tinted tile', (tester) async {
      await pumpEditor(tester);
      final rectangle = find.byKey(const ValueKey('pdf-tool-rectangle'));
      final style = IconButtonTheme.of(tester.element(rectangle)).style!;
      final scheme = Theme.of(tester.element(rectangle)).colorScheme;
      expect(style.backgroundColor!.resolve({WidgetState.selected}),
          scheme.primary.withValues(alpha: 0.15));
      expect(style.backgroundColor!.resolve({}), isNull);
      await tapMouse(tester, rectangle);
      expect(tester.widget<IconButton>(rectangle).isSelected, isTrue);
    });

    testWidgets('the empty properties bar reads on one line', (tester) async {
      await pumpEditor(tester);
      final empty =
          inBar(properties, find.byKey(const ValueKey('pdf-properties-empty')));
      expect(empty, findsOneWidget);
      final title = tester.getRect(find.descendant(
          of: empty, matching: find.text('Properties'.toUpperCase())));
      final hint = find.descendant(
          of: empty,
          matching: find
              .text('Pick a tool or select a markup to see its properties'));
      expect(tester.getRect(hint).center.dy, closeTo(title.center.dy, 1));
      expect(
          tester.widget<Text>(hint).style!.fontSize, greaterThanOrEqualTo(12));
    });

    testWidgets('packing tightly lays the toolbars out first-fit',
        (tester) async {
      final prefs = await pumpEditor(tester);
      expect(find.byType(FirstFitWrap), findsNothing);
      prefs.toolbarPackTightly = true;
      await tester.pumpAndSettle();
      expect(find.byType(FirstFitWrap), findsOneWidget);
      expect(tester.takeException(), isNull);
      // every toolbar is still there, inside the window
      for (final bar in [
        'pdf-docked-main',
        'pdf-tool-bar-markup',
        'pdf-tool-bar-draw',
        'pdf-tool-bar-shapes',
        'pdf-tool-bar-insert',
        'pdf-tool-bar-measure',
        'pdf-tool-bar-edit',
      ]) {
        final rect = rectOf(tester, ValueKey(bar));
        expect(rect.right, lessThanOrEqualTo(1280.5), reason: bar);
        expect(
            rect.bottom,
            lessThanOrEqualTo(
                rectOf(tester, const ValueKey(properties)).top + 0.5),
            reason: bar);
      }
    });

    testWidgets('the properties bar carries the popup\'s most-used rows',
        (tester) async {
      final prefs = await pumpEditor(tester);
      Finder bar(String key) => inBar(properties, find.byKey(ValueKey(key)));

      // a rectangle: fill and line type, out of the tune popup
      await tapMouse(tester, find.byKey(const ValueKey('pdf-tool-rectangle')));
      expect(bar('pdf-inline-fill'), findsOneWidget);
      expect(bar('pdf-inline-line-type'), findsOneWidget);
      expect(bar('pdf-inline-line-start'), findsNothing);
      await tapMouse(tester, bar('pdf-inline-line-type'));
      await tapMouse(tester,
          find.byKey(const ValueKey('pdf-inline-line-type-dashed')).last);
      expect(prefs.lineStyle, PdfLineStyle.dashed);
      await tapMouse(tester, bar('pdf-inline-fill'));
      await tapMouse(tester, find.byKey(const ValueKey('pdf-inline-fill-0')));
      expect(prefs.shapeFillColor, isNotNull);

      // a polyline: both line endings
      await tapMouse(tester, find.byKey(const ValueKey('pdf-tool-polyline')));
      expect(bar('pdf-inline-fill'), findsNothing);
      await tapMouse(tester, bar('pdf-inline-line-end'));
      await tapMouse(tester,
          find.byKey(const ValueKey('pdf-inline-line-end-closedArrow')).last);
      expect(prefs.lineEndEnding, PdfLineEnding.closedArrow);
      expect(bar('pdf-inline-line-start'), findsOneWidget);

      // a text box: bold/italic and alignment after the font chip
      await tapMouse(tester, find.byKey(const ValueKey('pdf-tool-freeText')));
      expect(bar('pdf-inline-font-style'), findsOneWidget);
      expect(bar('pdf-inline-text-align'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('floating strips keep those rows in the popup', (tester) async {
      await pumpEditor(tester, configure: (p) => p.toolbarFloating = true);
      await tapMouse(tester, find.byKey(const ValueKey('pdf-group-shapes')));
      await tapMouse(tester, find.byKey(const ValueKey('pdf-tool-rectangle')));
      expect(find.byKey(const ValueKey('pdf-inline-fill')), findsNothing);
      expect(find.byKey(const ValueKey('pdf-inline-line-type')), findsNothing);
    });

    testWidgets('the main toolbar can move into the header', (tester) async {
      final prefs = await pumpEditor(tester);
      final header = find.byKey(const ValueKey('pdf-header-tools'));
      expect(header, findsNothing);
      expect(find.byKey(const ValueKey('pdf-docked-main')), findsOneWidget);

      prefs.toolbarMainInHeader = true;
      await tester.pumpAndSettle();
      expect(header, findsOneWidget);
      expect(find.byKey(const ValueKey('pdf-docked-main')), findsNothing);
      // undo/redo and Hand/Select once each, in the header beside search
      for (final key in ['pdf-undo', 'pdf-redo', 'pdf-mode-hand']) {
        expect(find.byKey(ValueKey(key)), findsOneWidget, reason: key);
        expect(find.descendant(of: header, matching: find.byKey(ValueKey(key))),
            findsOneWidget,
            reason: key);
      }
      // no group switcher came with it
      expect(find.byKey(const ValueKey('pdf-group-shapes')), findsNothing);
      final tools = tester.getRect(header);
      final markup = rectOf(tester, const ValueKey('pdf-tool-bar-markup'));
      expect(tools.bottom, lessThanOrEqualTo(markup.top + 0.5));
      // and it still works from there
      await tapMouse(tester, find.byKey(const ValueKey('pdf-group-select')));
      expect(find.byKey(const ValueKey('pdf-tool-bar-markup')), findsOneWidget);

      // docked elsewhere, it leaves the header
      prefs.toolbarDock = PdfPanelDock.left;
      await tester.pumpAndSettle();
      expect(header, findsNothing);
      expect(find.byKey(const ValueKey('pdf-docked-main')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a narrow window keeps the main toolbar out of the header',
        (tester) async {
      tester.view.physicalSize = const Size(1000, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final prefs = PdfEditingPreferences()..toolbarMainInHeader = true;
      addTearDown(prefs.dispose);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: PdfEditorView(bytes: buildMultiPagePdf(1), preferences: prefs),
        ),
      ));
      await tester.pump();
      expect(find.byKey(const ValueKey('pdf-header-tools')), findsNothing);
      expect(find.byKey(const ValueKey('pdf-docked-main')), findsOneWidget);
    });

    testWidgets('a host header that leaves the tools out keeps them below',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 860);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final prefs = PdfEditingPreferences()..toolbarMainInHeader = true;
      addTearDown(prefs.dispose);
      PdfHeaderParts? seen;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: PdfEditorView(
            bytes: buildMultiPagePdf(1),
            preferences: prefs,
            headerBuilder: (context, parts) {
              seen = parts;
              return parts.bar(leading: [if (parts.search case final s?) s]);
            },
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(seen!.tools, isNotNull, reason: 'offered to the host');
      expect(find.byKey(const ValueKey('pdf-header-tools')), findsNothing);
      expect(find.byKey(const ValueKey('pdf-docked-main')), findsOneWidget);
      expect(find.byKey(const ValueKey('pdf-undo')), findsOneWidget);
    });

    testWidgets('the stock bars are just their tools: no grips, no names',
        (tester) async {
      final prefs = await pumpEditor(tester, customizing: false);
      expect(
          find.byKey(const ValueKey('pdf-tool-bar-move-shapes')), findsNothing);
      expect(find.byKey(const ValueKey('pdf-toolbar-move')), findsNothing);
      expect(find.byKey(const ValueKey('pdf-style-bar-move')), findsNothing);
      expect(inBar('pdf-tool-bar-shapes', find.text('SHAPES')), findsNothing);
      expect(find.byKey(const ValueKey('pdf-toolbar-customize-done')),
          findsNothing);

      // View options -> Customize toolbars brings the grips and a Done button
      await tapMouse(
          tester, find.byKey(const ValueKey('pdf-shell-view-options')));
      await tapMouse(
          tester, find.byKey(const ValueKey('pdf-shell-customize-toolbars')));
      expect(prefs.toolbarCustomizing, isTrue);
      expect(find.byKey(const ValueKey('pdf-tool-bar-move-shapes')),
          findsOneWidget);
      await tapMouse(
          tester, find.byKey(const ValueKey('pdf-toolbar-customize-done')));
      expect(prefs.toolbarCustomizing, isFalse);
      expect(
          find.byKey(const ValueKey('pdf-tool-bar-move-shapes')), findsNothing);

      // names are a preference
      prefs.toolbarShowNames = true;
      await tester.pumpAndSettle();
      expect(inBar('pdf-tool-bar-shapes', find.text('SHAPES')), findsOneWidget);
    });

    testWidgets('dropping a toolbar on another reorders them', (tester) async {
      final prefs = await pumpEditor(tester);
      double leftOf(String bar) =>
          rectOf(tester, ValueKey('pdf-tool-bar-$bar')).left;
      expect(leftOf('markup'), lessThan(leftOf('draw')));

      // drag Draw's grip onto Markup's leading half: Draw goes first
      final grip = find.byKey(const ValueKey('pdf-tool-bar-move-draw'));
      final markup = rectOf(tester, const ValueKey('pdf-tool-bar-markup'));
      final gesture = await tester.startGesture(tester.getCenter(grip),
          kind: PointerDeviceKind.mouse);
      await gesture.moveBy(const Offset(-10, 0));
      await tester.pump();
      await gesture.moveTo(markup.centerLeft + const Offset(12, 0));
      await tester.pump();
      expect(find.byKey(const ValueKey('pdf-tool-bar-drop-marker')),
          findsOneWidget);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(prefs.toolStripOrder.take(2),
          [PdfEditToolGroup.draw, PdfEditToolGroup.markup]);
      expect(leftOf('draw'), lessThan(leftOf('markup')));

      // the grip menu moves one place at a time, for keyboard and touch
      await tapMouse(
          tester, find.byKey(const ValueKey('pdf-tool-bar-move-draw')));
      expect(find.text('Move earlier'), findsNothing, reason: 'already first');
      await tapMouse(tester, find.text('Move later'));
      expect(prefs.toolStripOrder.take(2),
          [PdfEditToolGroup.markup, PdfEditToolGroup.draw]);
    });

    testWidgets('dropping on a toolbar on another edge moves it there',
        (tester) async {
      final prefs = await pumpEditor(tester,
          configure: (p) =>
              p.setToolStripDock(PdfEditToolGroup.shapes, PdfPanelDock.right));
      final grip = find.byKey(const ValueKey('pdf-tool-bar-move-measure'));
      final shapes = rectOf(tester, const ValueKey('pdf-tool-bar-shapes'));
      final gesture = await tester.startGesture(tester.getCenter(grip),
          kind: PointerDeviceKind.mouse);
      await gesture.moveBy(const Offset(0, 10));
      await tester.pump();
      await gesture.moveTo(shapes.bottomCenter - const Offset(0, 12));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      expect(prefs.toolStripDock(PdfEditToolGroup.measure), PdfPanelDock.right);
      final measure = rectOf(tester, const ValueKey('pdf-tool-bar-measure'));
      expect(measure.right, closeTo(1280, 0.5));
      expect(
          measure.top,
          greaterThanOrEqualTo(
              rectOf(tester, const ValueKey('pdf-tool-bar-shapes')).bottom -
                  0.5),
          reason: 'after Shapes on the rail');
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

    final style = find.byKey(const ValueKey('pdf-layout-style'));
    await tester.ensureVisible(style);
    await tester.pumpAndSettle();
    await tapMouse(tester, style);
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

    final pack = find.byKey(const ValueKey('pdf-layout-pack'));
    await tester.ensureVisible(pack);
    await tester.pumpAndSettle();
    await tapMouse(tester, pack);
    expect(prefs.toolbarPackTightly, isTrue);
    final inHeader = find.byKey(const ValueKey('pdf-layout-main-in-header'));
    await tester.ensureVisible(inHeader);
    await tester.pumpAndSettle();
    await tapMouse(tester, inHeader);
    expect(prefs.toolbarMainInHeader, isTrue);

    final mode = find.byKey(const ValueKey('pdf-layout-mode'));
    await tester.ensureVisible(mode);
    await tester.pumpAndSettle();
    await tapMouse(tester, mode);
    await tapMouse(
        tester, find.byKey(const ValueKey('pdf-layout-mode-floating')).last);
    expect(prefs.toolbarFloating, isTrue);
    // floating shows one group at a time: no rows to pack
    expect(find.byKey(const ValueKey('pdf-layout-pack')), findsNothing);

    await tapMouse(tester, find.byKey(const ValueKey('pdf-layout-reset')));
    expect(prefs.toolbarFloating, isFalse);
    expect(prefs.toolbarPackTightly, isFalse);
    expect(prefs.toolbarMainInHeader, isFalse);
    expect(prefs.styleBarDock, isNull);
    expect(prefs.toolStripDocks, isEmpty);
    await tapMouse(tester, find.byKey(const ValueKey('pdf-layout-done')));
    expect(find.byKey(const ValueKey('pdf-layout-main')), findsNothing);
  });
}
