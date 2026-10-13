import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The tune popup trigger must be reachable from the collapsed mobile dock,
/// not just the wide desktop strip. It appears once a tool with tune-able
/// controls is armed and opens the same stroke/opacity sliders.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<(PdfEditingController, PdfViewerController)> pumpMobileToolbar(
      WidgetTester tester) async {
    final editing = PdfEditingController(buildMultiPagePdf(1));
    final viewer = PdfViewerController();
    addTearDown(editing.dispose);
    addTearDown(viewer.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: SizedBox(
            // below PdfEditingToolbar.mobileBreakpoint (600) -> collapsed dock
            width: 380,
            child: PdfEditingToolbar(
              controller: editing,
              viewerController: viewer,
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
    return (editing, viewer);
  }

  testWidgets('the mobile dock shows the tune button for an armed draw tool',
      (tester) async {
    final (editing, _) = await pumpMobileToolbar(tester);

    // no tool armed: nothing to tune, no gear icon
    expect(find.byIcon(Icons.tune), findsNothing);

    // arm a stroke-using tool (freehand ink) - the tune trigger appears
    editing.tool = PdfEditTool.ink;
    await tester.pump();
    expect(find.byIcon(Icons.tune), findsOneWidget);

    // and it opens the style popup's stroke/opacity sliders
    await tester.tap(find.byIcon(Icons.tune));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('pdf-tune-stroke-width-slider')),
        findsOneWidget);
    expect(
        find.byKey(const ValueKey('pdf-tune-opacity-slider')), findsOneWidget);
  });

  testWidgets('the mobile tune popup offers the full palette for a pen',
      (tester) async {
    // The dock fits only two swatches beside the tune button, so the popup
    // must reach the rest of the palette - a pen's style fields carry no
    // colour row of their own (Ben: "I only see 2 colours and have to go
    // into tools to see more").
    final (editing, _) = await pumpMobileToolbar(tester);
    editing.tool = PdfEditTool.ink;
    await tester.pump();
    expect(find.byKey(const ValueKey('pdf-mobile-swatch-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('pdf-mobile-swatch-2')), findsNothing);

    await tester.tap(find.byIcon(Icons.tune));
    await tester.pumpAndSettle();
    final palette = PdfEditingToolbar.defaultPalette;
    for (var i = 0; i < palette.length; i++) {
      expect(find.byKey(ValueKey('pdf-tool-color-$i')), findsOneWidget);
    }
    expect(find.byKey(const ValueKey('pdf-tool-color-none')), findsNothing);

    await tester
        .tap(find.byKey(ValueKey('pdf-tool-color-${palette.length - 1}')));
    await tester.pump();
    expect(editing.color, palette.last);
  });

  testWidgets('a shape keeps its outline row, without a duplicate colour row',
      (tester) async {
    final (editing, _) = await pumpMobileToolbar(tester);
    editing.tool = PdfEditTool.rectangle;
    await tester.pump();
    await tester.tap(find.byIcon(Icons.tune));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('pdf-shape-outline-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('pdf-tool-color-0')), findsNothing);
  });

  testWidgets('the mobile dock shows the tune button for a selected annotation',
      (tester) async {
    final (editing, _) = await pumpMobileToolbar(tester);

    // draw a shape and select it - the dock now carries delete + tune
    editing.addEllipse(0, const PdfRect(100, 600, 300, 700));
    await tester.pump();
    expect(editing.selectAnnotation(0, 0), isTrue);
    await tester.pump();

    expect(find.byIcon(Icons.delete_outline), findsOneWidget);
    expect(find.byIcon(Icons.tune), findsOneWidget,
        reason: 'a selected annotation can be restyled from the dock');
    expect(tester.takeException(), isNull,
        reason: 'the selection actions + tune fit the narrow dock');

    // the popup restyles the selection
    await tester.tap(find.byIcon(Icons.tune));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('pdf-tune-stroke-width-slider')),
        findsOneWidget);
  });
}
