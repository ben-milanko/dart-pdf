// A document opens in Select mode: the edit session starts with the Select
// tool armed, not in Hand mode.
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:material_ui/material_ui.dart';
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

  test('a new document tab starts in Select mode', () {
    final tab = DocumentTab.document(
      title: 'reader.pdf',
      bytes: buildMultiPagePdf(1),
      preferences: preferences,
    );
    addTearDown(tab.dispose);

    expect(tab.session!.tool, PdfEditTool.select);
    expect(tab.session!.isHandMode, isFalse);
    expect(tab.session!.markupTool, isNull);
  });

  testWidgets('the opened document reaches the viewer in Select mode',
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
    expect(viewer.editing!.tool, PdfEditTool.select);
    expect(viewer.editing!.isHandMode, isFalse);
  });
}
