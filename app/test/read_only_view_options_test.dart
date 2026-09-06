// The app's read-only ("view") mode swaps PdfEditorView for PdfReader. Paper
// colour is an authoring choice, so the View options menu drops "Page color…"
// while reading and keeps it while editing.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:dart_pdf_editor_app/editor_screen.dart';

void main() {
  late PdfEditingPreferences prefs;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    prefs = PdfEditingPreferences();
  });
  tearDown(() => prefs.dispose());

  Future<void> pumpWithDoc(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: EditorScreen(
        prefs: prefs,
        initialDocument: (bytes: buildClassicPdf(), title: 'Report.pdf'),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  Future<void> switchToReadOnly(WidgetTester tester) async {
    await tester.tap(find.byTooltip('DartPDF menu'));
    await tester.pumpAndSettle();
    // Read-only is a switch row now, not a "Switch to read-only" verb.
    final item = find.byKey(const ValueKey('menu-read-only'));
    await tester.ensureVisible(item);
    await tester.pumpAndSettle();
    await tester.tap(item);
    await tester.pumpAndSettle();
  }

  Future<void> openViewOptions(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('pdf-shell-view-options')));
    await tester.pumpAndSettle();
  }

  testWidgets('view mode hides the page-color item', (tester) async {
    await pumpWithDoc(tester);
    await switchToReadOnly(tester);

    expect(find.byType(PdfReader), findsOneWidget);
    await openViewOptions(tester);
    // the menu is open (annotations item shows) but page color is gone
    expect(find.byKey(const ValueKey('pdf-shell-show-annotations')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('pdf-shell-page-color')), findsNothing);
  });

  testWidgets('edit mode still offers the page-color item', (tester) async {
    await pumpWithDoc(tester);

    expect(find.byType(PdfEditorView), findsOneWidget);
    await openViewOptions(tester);
    expect(find.byKey(const ValueKey('pdf-shell-page-color')), findsOneWidget);
  });
}
