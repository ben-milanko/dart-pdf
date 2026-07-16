import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dart_pdf_editor_app/editor_screen.dart';

void main() {
  late PdfEditingPreferences prefs;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    prefs = PdfEditingPreferences();
  });

  tearDown(() => prefs.dispose());

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(home: EditorScreen(prefs: prefs)));
    await tester.pump();
    await tester.pump();
  }

  Future<void> openNewDocumentDialog(WidgetTester tester) async {
    await tester.tap(find.byTooltip('DartPDF menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('menu-new-document')));
    await tester.pumpAndSettle();
  }

  testWidgets('the app menu opens the new-document dialog', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.byTooltip('DartPDF menu'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('menu-new-document')), findsOneWidget);
    expect(find.text('New document…'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('menu-new-document')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('new-document-dialog')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('new-document-page-size')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('new-document-orientation')),
      findsOneWidget,
    );
    expect(find.text('A4 (210 × 297 mm)'), findsOneWidget);
  });

  testWidgets('creates the selected page size and orientation', (tester) async {
    await pumpApp(tester);
    await openNewDocumentDialog(tester);

    await tester.tap(find.byKey(const ValueKey('new-document-page-size')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('US Letter (8.5 × 11 in)').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Landscape'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('new-document-create')));
    await tester.pumpAndSettle();

    expect(find.text('Untitled.pdf'), findsWidgets);
    final view = tester.widget<PdfEditorView>(find.byType(PdfEditorView));
    final page = view.controller!.document.page(0);
    expect(page.mediaBox.width, 792);
    expect(page.mediaBox.height, 612);
    expect(page.contentBytes(), isEmpty);
    // New files have no saved origin and must prompt before being discarded.
    expect(find.byIcon(Icons.circle), findsWidgets);
  });

  testWidgets('new documents receive unique tab names', (tester) async {
    await pumpApp(tester);

    await openNewDocumentDialog(tester);
    await tester.tap(find.byKey(const ValueKey('new-document-create')));
    await tester.pumpAndSettle();

    await openNewDocumentDialog(tester);
    await tester.tap(find.byKey(const ValueKey('new-document-create')));
    await tester.pumpAndSettle();

    expect(find.text('Untitled.pdf'), findsOneWidget);
    expect(find.text('Untitled 2.pdf'), findsOneWidget);
  });
}
