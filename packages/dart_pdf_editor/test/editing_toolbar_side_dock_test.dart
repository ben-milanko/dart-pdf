import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A side-docked toolbar's contextual strip is a column beside the rail, so
/// its width comes straight off the page (#1161): it carries no text, and
/// the desktop cards use compact density on every dock.
void main() {
  final card = find.byKey(const ValueKey('pdf-editing-toolbar-card'));

  Future<PdfEditingController> pump(WidgetTester tester,
      {PdfPanelDock dock = PdfPanelDock.left}) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1280, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final editing = PdfEditingController(buildMultiPagePdf(2));
    final viewer = PdfViewerController();
    addTearDown(editing.dispose);
    addTearDown(viewer.dispose);
    final toolbar = PdfEditingToolbar(
      controller: editing,
      viewerController: viewer,
      dock: dock,
      compact: false,
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Stack(fit: StackFit.expand, children: [
          if (dock == PdfPanelDock.bottom)
            Positioned(left: 0, right: 0, bottom: 0, child: toolbar)
          else
            Positioned.fill(
              child: Align(alignment: Alignment.centerLeft, child: toolbar),
            ),
        ]),
      ),
    ));
    await tester.pump();
    return editing;
  }

  Future<void> openGroup(WidgetTester tester, String id) async {
    await tester.tap(find.byKey(ValueKey('pdf-group-$id')));
    await tester.pump();
  }

  /// The contextual strip's card beside a side rail (the rail is the first).
  Finder strip() => card.last;

  double stripWidth(WidgetTester tester) => tester.getSize(strip()).width;

  testWidgets('desktop cards use compact 40px icon buttons', (tester) async {
    await pump(tester, dock: PdfPanelDock.bottom);
    expect(tester.getSize(find.byKey(const ValueKey('pdf-undo'))),
        const Size(40, 40));
  });

  testWidgets('the Edit strip goes icon-only beside a side rail',
      (tester) async {
    await pump(tester);
    await openGroup(tester, 'edit');
    expect(card, findsNWidgets(2));
    expect(stripWidth(tester), lessThanOrEqualTo(64));
    // the labels move into tooltips, and the group name is dropped
    expect(find.descendant(of: strip(), matching: find.text('Flatten')),
        findsNothing);
    expect(find.descendant(of: strip(), matching: find.text('EDIT')),
        findsNothing);
    final flatten = find.byKey(const ValueKey('pdf-flatten-all'));
    expect(find.descendant(of: flatten, matching: find.byType(IconButton)),
        findsOneWidget);
    expect(find.descendant(of: flatten, matching: find.byType(Tooltip)),
        findsOneWidget);
  });

  testWidgets('a bottom dock keeps the labelled Edit tools', (tester) async {
    await pump(tester, dock: PdfPanelDock.bottom);
    await openGroup(tester, 'edit');
    expect(find.text('Flatten'), findsOneWidget);
    expect(find.text('EDIT'), findsOneWidget);
  });

  testWidgets('a side Draw strip stacks presets and stands the slider up',
      (tester) async {
    await pump(tester);
    await openGroup(tester, 'draw');
    expect(stripWidth(tester), lessThanOrEqualTo(64));
    final slider = find.byKey(const ValueKey('pdf-strip-opacity-slider'));
    expect(find.ancestor(of: slider, matching: find.byType(RotatedBox)),
        findsOneWidget);
    // still adjustable: a drag along the standing slider lowers opacity
    final editing =
        (tester.widget<PdfEditingToolbar>(find.byType(PdfEditingToolbar)))
            .controller;
    final before = editing.preferences.opacity;
    await tester.drag(slider, const Offset(0, 60));
    await tester.pump();
    expect(editing.preferences.opacity, lessThan(before));
  });

  testWidgets('a side Measure strip shows the scale as an icon',
      (tester) async {
    await pump(tester);
    await openGroup(tester, 'measure');
    expect(stripWidth(tester), lessThanOrEqualTo(64));
    final scale = find.byKey(const ValueKey('pdf-measure-scale'));
    expect(tester.widget(scale), isA<IconButton>());
    expect((tester.widget<IconButton>(scale)).tooltip, startsWith('Scale'));
    expect(find.descendant(of: strip(), matching: find.text('Totals')),
        findsNothing);
  });

  testWidgets('a side Insert strip uses the tune icon, not the font chip',
      (tester) async {
    await pump(tester);
    await openGroup(tester, 'insert');
    expect(stripWidth(tester), lessThanOrEqualTo(64));
    expect(find.descendant(of: strip(), matching: find.byIcon(Icons.tune)),
        findsOneWidget);
  });

  testWidgets('a side Markup strip keeps its hint as an info tooltip',
      (tester) async {
    await pump(tester);
    await openGroup(tester, 'markup');
    expect(stripWidth(tester), lessThanOrEqualTo(64));
    final info =
        find.descendant(of: strip(), matching: find.byIcon(Icons.info_outline));
    expect(info, findsOneWidget);
    final tip = tester.widget<Tooltip>(
        find.ancestor(of: info, matching: find.byType(Tooltip)).first);
    expect(tip.message, contains('Choose a markup, then select text'));
  });
}
