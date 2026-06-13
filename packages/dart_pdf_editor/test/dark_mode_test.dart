import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<void> pumpViewer(WidgetTester tester,
      {ThemeData? theme, Color? backgroundColor}) async {
    await tester.pumpWidget(MaterialApp(
      theme: theme,
      home: Scaffold(
        body: PdfViewer(
          document: PdfDocument.open(buildMultiPagePdf(1)),
          backgroundColor: backgroundColor,
        ),
      ),
    ));
    await tester.pump();
  }

  Iterable<Color> canvasColors(WidgetTester tester) => tester
      .widgetList<ColoredBox>(find.descendant(
          of: find.byType(PdfViewer), matching: find.byType(ColoredBox)))
      .map((box) => box.color);

  testWidgets('a light theme keeps the desktop-viewer slate canvas',
      (tester) async {
    await pumpViewer(tester);
    expect(canvasColors(tester), contains(const Color(0xFF404347)));
  });

  testWidgets('a dark theme deepens the canvas', (tester) async {
    await pumpViewer(tester, theme: ThemeData(brightness: Brightness.dark));
    expect(canvasColors(tester), contains(const Color(0xFF202124)));
    expect(canvasColors(tester), isNot(contains(const Color(0xFF404347))));
  });

  testWidgets('backgroundColor overrides the theme default', (tester) async {
    await pumpViewer(tester, backgroundColor: const Color(0xFF123456));
    expect(canvasColors(tester), contains(const Color(0xFF123456)));
    expect(canvasColors(tester), isNot(contains(const Color(0xFF404347))));
  });

  testWidgets('toolbar palette swatches keep a visible border in dark mode',
      (tester) async {
    final editing = PdfEditingController(buildMultiPagePdf(1));
    final viewer = PdfViewerController();
    addTearDown(editing.dispose);
    addTearDown(viewer.dispose);
    final theme =
        ThemeData(colorSchemeSeed: Colors.indigo, brightness: Brightness.dark);
    await tester.pumpWidget(MaterialApp(
      theme: theme,
      home: Scaffold(
        bottomNavigationBar: PdfEditingToolbar(
          controller: editing,
          viewerController: viewer,
        ),
      ),
    ));
    await tester.pump();
    // the palette swatches live in a group's contextual strip — open one
    await tester.tap(find.byKey(const ValueKey('pdf-group-shapes')));
    await tester.pump();

    // the unselected swatches outline with the scheme's outline color —
    // the old hardcoded black26 was invisible on a dark toolbar
    final borders = tester
        .widgetList<Container>(find.byType(Container))
        .map((c) => c.decoration)
        .whereType<BoxDecoration>()
        .where((d) => d.shape == BoxShape.circle && d.border != null)
        .map((d) => (d.border! as Border).top.color)
        .toSet();
    expect(borders, contains(theme.colorScheme.outline));
    expect(borders, isNot(contains(Colors.black26)));
  });

  test('the theme mode persists as a preference', () async {
    SharedPreferences.setMockInitialValues({});
    final a = PdfEditingPreferences();
    await a.ready;
    expect(a.themeMode, ThemeMode.system);
    a.themeMode = ThemeMode.dark;
    await pumpEventQueue();

    final b = PdfEditingPreferences();
    await b.ready;
    expect(b.themeMode, ThemeMode.dark);
  });
}
