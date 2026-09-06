// The app menu is sectioned: a command-palette row on top, then File, This
// document and App under quiet headers, with read-only as a switch rather
// than a verb that rewrites its own label.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dart_pdf_editor_app/editor_screen.dart';

void main() {
  late PdfEditingPreferences prefs;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    prefs = PdfEditingPreferences();
  });
  tearDown(() => prefs.dispose());

  Future<void> pump(WidgetTester tester, {bool withDoc = false}) async {
    await tester.pumpWidget(MaterialApp(
      home: EditorScreen(
        prefs: prefs,
        initialDocument:
            withDoc ? (bytes: buildClassicPdf(), title: 'Report.pdf') : null,
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  Future<void> openMenu(WidgetTester tester) async {
    await tester.tap(find.byTooltip('DartPDF menu'));
    await tester.pumpAndSettle();
  }

  testWidgets('a document open shows all three section headers',
      (tester) async {
    await pump(tester, withDoc: true);
    await openMenu(tester);

    expect(find.text('FILE'), findsOneWidget);
    expect(find.text('THIS DOCUMENT'), findsOneWidget);
    expect(find.text('APP'), findsOneWidget);
  });

  testWidgets(
      'with nothing open the document section goes, and a lone App '
      'row keeps a bare divider instead of a header', (tester) async {
    await pump(tester);
    await openMenu(tester);

    expect(find.text('FILE'), findsOneWidget);
    expect(find.text('THIS DOCUMENT'), findsNothing);
    // Settings is the only App row without a document, and a label over one
    // row says less than the divider above it.
    expect(find.text('APP'), findsNothing);
    expect(find.byKey(const ValueKey('menu-settings')), findsOneWidget);
  });

  testWidgets('read-only is a switch that reports its state', (tester) async {
    await pump(tester, withDoc: true);
    await openMenu(tester);

    final row = find.byKey(const ValueKey('menu-read-only'));
    expect(row, findsOneWidget);
    expect(
        tester
            .widget<Switch>(
                find.descendant(of: row, matching: find.byType(Switch)))
            .value,
        isFalse);

    await tester.ensureVisible(row);
    await tester.pumpAndSettle();
    await tester.tap(row);
    await tester.pumpAndSettle();

    // Read-only swaps the editor for the reader...
    expect(find.byType(PdfReader), findsOneWidget);
    // ...and the switch now reads back on.
    await openMenu(tester);
    expect(
        tester
            .widget<Switch>(
                find.descendant(of: row, matching: find.byType(Switch)))
            .value,
        isTrue);
  });

  testWidgets('the palette row leads the menu and carries its shortcut',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      await pump(tester, withDoc: true);
      await openMenu(tester);

      expect(
          find.byKey(const ValueKey('menu-command-palette')), findsOneWidget);
      expect(find.text('Search actions…'), findsOneWidget);
      expect(find.text('Ctrl+K'), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
