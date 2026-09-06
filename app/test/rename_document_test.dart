import 'dart:convert';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dart_pdf_editor_app/editor_screen.dart';
import 'package:dart_pdf_editor_app/file_io.dart';
import 'package:dart_pdf_editor_app/recents.dart';
import 'package:dart_pdf_editor_app/unsaved_changes.dart';

import 'test_finders.dart';

void main() {
  late PdfEditingPreferences prefs;
  late InMemoryUnsavedChangesStore recovery;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    prefs = PdfEditingPreferences();
    recovery = InMemoryUnsavedChangesStore();
  });
  tearDown(() => prefs.dispose());

  final title = find.byKey(const ValueKey('mobile-document-title'));
  final name = find.byKey(const ValueKey('rename-document-name'));
  final confirm = find.byKey(const ValueKey('rename-document-confirm'));

  Future<void> pump(
    WidgetTester tester, {
    String? initialTitle = 'Original.pdf',
    bool wide = false,
    Future<SaveResult> Function(BuildContext, Uint8List, String)? save,
  }) async {
    tester.view.physicalSize = Size(wide ? 1200 : 430, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      home: EditorScreen(
        prefs: prefs,
        unsavedChangesStore: recovery,
        initialDocument: initialTitle == null
            ? null
            : (bytes: buildClassicPdf(), title: initialTitle),
        saveDocumentAs: save,
      ),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> rename(WidgetTester tester, String value) async {
    await tester.tap(title);
    await tester.pumpAndSettle();
    await tester.enterText(name, value);
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 500));
  }

  testWidgets(
      'title rename keeps edits and uses the new PDF filename for Share',
      (tester) async {
    String? sharedName;
    Uint8List? sharedBytes;
    await pump(tester, save: (_, bytes, filename) async {
      sharedName = filename;
      sharedBytes = bytes;
      return SaveResult.cancelled;
    });
    final before =
        tester.widget<PdfEditorView>(find.byType(PdfEditorView)).controller!;
    before.addBookmark('Keep this edit');
    final editedBytes = before.bytes;
    await tester.pump();

    await tester.tap(title);
    await tester.pumpAndSettle();
    final field = tester.widget<TextField>(name);
    expect(field.controller!.text, 'Original.pdf');
    expect(field.controller!.selection,
        const TextSelection(baseOffset: 0, extentOffset: 8));
    await tester.enterText(name, '  Project notes  ');
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 500));

    final after =
        tester.widget<PdfEditorView>(find.byType(PdfEditorView)).controller!;
    expect(identical(before, after), isTrue);
    expect(after.bytes, editedBytes);
    expect(after.canUndo, isTrue);
    expect(findMiddleEllipsisText('Project notes.pdf'), findsOneWidget);
    expect((await recovery.list()).single.title, 'Project notes.pdf');

    await tester.tap(find.byKey(const ValueKey('mobile-app-save')));
    await tester.pumpAndSettle();
    expect(sharedName, 'Project notes.pdf');
    expect(sharedBytes, editedBytes);
  });

  testWidgets('iOS keyboard Done accepts Unicode and normalizes the extension',
      (tester) async {
    await pump(tester);
    await tester.tap(title);
    await tester.pumpAndSettle();
    await tester.enterText(name, '測量 – Café.PDF');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 500));
    expect(name, findsNothing);
    expect(findMiddleEllipsisText('測量 – Café.pdf'), findsOneWidget);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('empty names cannot submit and Cancel preserves the title',
      (tester) async {
    await pump(tester);
    await tester.tap(title);
    await tester.pumpAndSettle();
    for (final invalid in ['', '  ', '.pdf', '..']) {
      await tester.enterText(name, invalid);
      await tester.pump();
      expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(name, findsOneWidget);
    }
    await tester.enterText(name, 'Do not save this');
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(findMiddleEllipsisText('Original.pdf'), findsOneWidget);
    expect(await recovery.list(), isEmpty);
  });

  testWidgets('pasted paths cannot escape the shared filename', (tester) async {
    await pump(tester);
    await rename(tester, 'Reports/September\\notes.pdf.pdf');
    expect(findMiddleEllipsisText('ReportsSeptembernotes.pdf'), findsOneWidget);
  });

  testWidgets('renaming persists the cached source in Recent and session state',
      (tester) async {
    final bytes = Uint8List.fromList(buildClassicPdf());
    await recovery.write(
      UnsavedRecord(
        id: 'scan',
        title: 'Untitled.pdf',
        cachePath: '/private/scan-cache.pdf',
        length: bytes.length,
        savedLength: -1,
      ),
      bytes,
    );
    final recents = RecentsStore();
    addTearDown(recents.dispose);
    await recents.add(
        title: 'Untitled.pdf', cachePath: '/private/scan-cache.pdf');
    await pump(tester, initialTitle: null);
    await rename(tester, 'Site inspection');

    final restoredRecents = RecentsStore();
    addTearDown(restoredRecents.dispose);
    await restoredRecents.load();
    expect(restoredRecents.items.single.title, 'Site inspection.pdf');
    expect(restoredRecents.items.single.cachePath, '/private/scan-cache.pdf');
    final storedPrefs = await SharedPreferences.getInstance();
    final session =
        jsonDecode(storedPrefs.getString('dart_pdf_editor_app.session')!)
            as List;
    expect(session.single['t'], 'Site inspection.pdf');
    expect(session.single['c'], '/private/scan-cache.pdf');
    expect((await recovery.list()).single.title, 'Site inspection.pdf');
  });

  testWidgets('the active tablet tab also renames on a title tap',
      (tester) async {
    await pump(tester, wide: true);
    expect(title, findsNothing);
    await tester.tap(find.descendant(
      of: find.byKey(const ValueKey('tab-strip')),
      matching: findMiddleEllipsisText('Original.pdf'),
    ));
    await tester.pumpAndSettle();
    expect(name, findsOneWidget);
    await tester.enterText(name, 'Tablet scan');
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 500));
    expect(findMiddleEllipsisText('Tablet scan.pdf'), findsOneWidget);
  });

  testWidgets('a narrow desktop title does not open mobile rename',
      (tester) async {
    await pump(tester);
    expect(title, findsNothing);
    await tester.tap(findMiddleEllipsisText('Original.pdf'));
    await tester.pumpAndSettle();
    expect(name, findsNothing);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));
}
