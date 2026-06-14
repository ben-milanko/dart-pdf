// The on-device OCR action is wired into the More menu when a document is
// open and the platform supports it (flutter_test's default platform is
// android, so OnDeviceOcr.isSupported is true). Running the full flow needs a
// downloaded model + platform channels, so this only asserts the entry point.
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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

  Future<void> pumpWithDoc(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: EditorScreen(
        prefs: prefs,
        initialDocument: (bytes: buildClassicPdf(), title: 'Scan.pdf'),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('the More menu offers "Add OCR text layer…" with a document open',
      (tester) async {
    await pumpWithDoc(tester);

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('menu-ocr')), findsOneWidget);
    expect(find.text('Add OCR text layer…'), findsOneWidget);
  });

  testWidgets('no OCR entry without a document open', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: EditorScreen(prefs: prefs),
    ));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('menu-ocr')), findsNothing);
  });
}
