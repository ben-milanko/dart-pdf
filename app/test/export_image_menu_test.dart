// "Export page as image…" is wired into the DartPDF app menu when a document
// is open, and opens a format/resolution dialog. The actual rasterize + save
// needs the engine and platform channels, so these tests assert the wiring and
// the dialog, stopping short of the save.
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

  testWidgets('the menu offers Export page as image with a document open',
      (tester) async {
    await pumpWithDoc(tester);

    await tester.tap(find.byTooltip('DartPDF menu'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('menu-export-image')), findsOneWidget);
    expect(find.text('Export page as image…'), findsOneWidget);
  });

  testWidgets('no Export entry without a document open', (tester) async {
    await tester.pumpWidget(MaterialApp(home: EditorScreen(prefs: prefs)));
    await tester.pump();

    await tester.tap(find.byTooltip('DartPDF menu'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('menu-export-image')), findsNothing);
  });

  testWidgets('selecting it opens the format/resolution dialog',
      (tester) async {
    await pumpWithDoc(tester);

    await tester.tap(find.byTooltip('DartPDF menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('menu-export-image')));
    await tester.pumpAndSettle();

    expect(find.text('Export page as image'), findsOneWidget);
    expect(find.text('PNG'), findsOneWidget);
    expect(find.text('JPEG'), findsOneWidget);
    expect(find.byKey(const ValueKey('export-image-dpi')), findsOneWidget);
    expect(find.byKey(const ValueKey('export-image-confirm')), findsOneWidget);

    // Cancel - the rasterize + save path needs platform channels.
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Export page as image'), findsNothing);
  });
}
