// A document opens as a reader: the edit session starts in explicit Hand
// mode, so a mouse drag pans the page instead of starting a text selection.
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dart_pdf_editor_app/document_tab.dart';
import 'package:dart_pdf_editor_app/editor_screen.dart';

void main() {
  late PdfEditingPreferences preferences;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    preferences = PdfEditingPreferences();
  });

  tearDown(() => preferences.dispose());

  test('a new document tab starts in Hand mode', () {
    final tab = DocumentTab.document(
      title: 'reader.pdf',
      bytes: buildMultiPagePdf(1),
      preferences: preferences,
    );
    addTearDown(tab.dispose);

    expect(tab.session!.isHandMode, isTrue);
    expect(tab.session!.tool, isNull);
    expect(tab.session!.markupTool, isNull);
  });

  testWidgets('the opened document reaches the viewer in Hand mode',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: EditorScreen(
        prefs: preferences,
        initialDocument: (bytes: buildMultiPagePdf(1), title: 'reader.pdf'),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final viewer = tester.widget<PdfViewer>(find.byType(PdfViewer));
    expect(viewer.editing!.isHandMode, isTrue);
  });
}
