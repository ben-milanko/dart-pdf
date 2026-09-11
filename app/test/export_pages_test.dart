// Exporting pages out of a document (the thumbnail panels' Export actions)
// saves them and then opens what was written, so the extracted pages land in
// front of the user instead of only on disk (editor_screen.dart `_exportPages`).
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_graphics/pdf_graphics.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dart_pdf_editor_app/editor_screen.dart';
import 'package:dart_pdf_editor_app/file_io.dart';

import 'test_finders.dart';

void main() {
  late PdfEditingPreferences prefs;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    prefs = PdfEditingPreferences();
  });

  tearDown(() {
    prefs.dispose();
  });

  Finder tabTitle(String name) => find.descendant(
        of: find.byKey(const ValueKey('tab-strip')),
        matching: findMiddleEllipsisText(name),
      );

  /// The editor view of whichever tab is active.
  PdfEditorView activeView(WidgetTester tester) =>
      tester.widget<PdfEditorView>(find.byType(PdfEditorView));

  /// Pumps the screen over a 4-page document and returns the saves the export
  /// backend was handed, newest last.
  Future<List<({Uint8List bytes, String name})>> pumpEditor(
    WidgetTester tester, {
    required SaveResult Function(String name) onSave,
  }) async {
    final saves = <({Uint8List bytes, String name})>[];
    await tester.pumpWidget(MaterialApp(
      home: EditorScreen(
        prefs: prefs,
        initialDocument: (bytes: buildMultiPagePdf(4), title: 'Report.pdf'),
        saveDocumentAs: (context, bytes, suggestedName) async {
          saves.add((bytes: bytes, name: suggestedName));
          return onSave(suggestedName);
        },
      ),
    ));
    await tester.pumpAndSettle();
    return saves;
  }

  /// Exports pages [pages] (0-based) of the active document through the host
  /// callback the thumbnail panels' Export actions use.
  Future<void> exportPages(WidgetTester tester, List<int> pages) async {
    final view = activeView(tester);
    await tester.runAsync(
      () async => view.onExportPages!(view.controller!.exportPages(pages)),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('exported pages open as a new tab pointed at the saved file',
      (tester) async {
    final saves = await pumpEditor(tester,
        onSave: (_) => SaveResult.saved('/docs/Report-pages.pdf'));
    final source = activeView(tester).controller!;
    final sourceBytes = Uint8List.fromList(source.bytes);

    await exportPages(tester, [1, 3]);

    // The save was offered the extracted pages under the document's name.
    expect(saves, hasLength(1));
    expect(saves.single.name, 'Report.pdf');

    // The saved file is open, named after where it landed, and it is the
    // export rather than the whole document.
    expect(tabTitle('Report-pages.pdf'), findsOneWidget);
    expect(tabTitle('Report.pdf'), findsOneWidget);
    final exported = activeView(tester).controller!;
    expect(exported.document.pageCount, 2);
    expect(PdfTextExtractor.extract(exported.document, 0).text, 'Page 2');
    expect(PdfTextExtractor.extract(exported.document, 1).text, 'Page 4');
    expect(exported.bytes, saves.single.bytes);

    // An export reads the document; it must not edit it.
    expect(source.bytes, sourceBytes);
    await tester.pump();
    expect(find.text('Saved to /docs/Report-pages.pdf'), findsOneWidget);
  }, timeout: const Timeout(Duration(seconds: 60)));

  testWidgets('a cancelled export opens nothing and says nothing',
      (tester) async {
    final saves = await pumpEditor(tester, onSave: (_) => SaveResult.cancelled);

    await exportPages(tester, [0]);

    expect(saves, hasLength(1));
    // Still the one document, and no toast for a save the user called off.
    expect(find.byType(PdfEditorView), findsOneWidget);
    expect(activeView(tester).controller!.document.pageCount, 4);
    expect(tabTitle('Report.pdf'), findsOneWidget);
    expect(find.textContaining('Saved to'), findsNothing);
  }, timeout: const Timeout(Duration(seconds: 60)));

  testWidgets('a download with no path still opens the exported pages',
      (tester) async {
    await pumpEditor(tester, onSave: (name) => SaveResult.downloaded(name));

    await exportPages(tester, [2]);

    final exported = activeView(tester).controller!;
    expect(exported.document.pageCount, 1);
    expect(PdfTextExtractor.extract(exported.document, 0).text, 'Page 3');
    expect(find.text('Downloaded Report.pdf'), findsOneWidget);
  }, timeout: const Timeout(Duration(seconds: 60)));

  testWidgets('a failed export reports the failure and opens nothing',
      (tester) async {
    await pumpEditor(tester, onSave: (_) => SaveResult.failed('disk full'));

    await exportPages(tester, [0]);

    expect(find.byType(PdfEditorView), findsOneWidget);
    expect(activeView(tester).controller!.document.pageCount, 4);
    expect(find.textContaining('disk full'), findsOneWidget);
  }, timeout: const Timeout(Duration(seconds: 60)));
}
