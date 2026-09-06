import 'dart:typed_data';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:file_selector_platform_interface/file_selector_platform_interface.dart'
    as fs;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dart_pdf_editor_app/editor_screen.dart';
import 'package:dart_pdf_editor_app/unsaved_changes.dart';

import 'test_finders.dart';

class _Picker extends fs.FileSelectorPlatform {
  fs.XFile? file;
  List<fs.XTypeGroup>? groups;

  @override
  Future<fs.XFile?> openFile(
      {List<fs.XTypeGroup>? acceptedTypeGroups,
      String? initialDirectory,
      String? confirmButtonText}) async {
    groups = acceptedTypeGroups;
    return file;
  }
}

void main() {
  late PdfEditingPreferences prefs;
  late _Picker picker;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    prefs = PdfEditingPreferences();
    picker = _Picker();
    final old = fs.FileSelectorPlatform.instance;
    fs.FileSelectorPlatform.instance = picker;
    addTearDown(() {
      fs.FileSelectorPlatform.instance = old;
      prefs.dispose();
    });
  });

  Future<PdfEditingController> open(WidgetTester tester,
      {InMemoryUnsavedChangesStore? store}) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
        home: EditorScreen(
      prefs: prefs,
      initialDocument: (title: 'base.pdf', bytes: buildMultiPagePdf(2)),
      unsavedChangesStore: store,
    )));
    await tester.pumpAndSettle();
    return tester.widget<PdfViewer>(find.byType(PdfViewer).first).editing!;
  }

  Future<void> insert(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('dartpdf-app-menu')));
    await tester.pumpAndSettle();
    final item = find.byKey(const ValueKey('menu-insert-document'));
    await tester.ensureVisible(item);
    await tester.tap(item);
    await tester.pumpAndSettle();
  }

  Finder getDirtyDot() => find.descendant(
        of: find.byKey(const ValueKey('tab-strip')),
        matching: find.byWidgetPredicate(
            (w) => w is Icon && w.icon == Icons.circle && w.size == 8),
      );

  testWidgets(
      'Insert document uses bytes on every native platform and is one undo step',
      (tester) async {
    final session = await open(tester);
    final before = session.bytes;
    picker.file = fs.XFile.fromData(buildMultiPagePdf(3),
        name: 'inserted.pdf', mimeType: 'application/pdf');
    await insert(tester);

    expect(session.document.pageCount, 5);
    expect(session.canUndo, isTrue);
    expect(getDirtyDot(), findsOneWidget);
    expect(findMiddleEllipsisText('base.pdf'), findsWidgets);
    expect(findMiddleEllipsisText('inserted.pdf'), findsNothing);
    final reopened = PdfDocument.open(session.bytes);
    expect([
      for (var i = 0; i < 5; i++)
        String.fromCharCodes(reopened.page(i).contentBytes())
    ], [
      for (final n in [1, 1, 2, 3, 2]) contains('(Page $n)')
    ]);
    final filter = picker.groups!.single;
    expect(filter.extensions, contains('pdf'));
    expect(filter.mimeTypes, contains('application/pdf'));
    expect(filter.uniformTypeIdentifiers, contains('com.adobe.pdf'));

    session.undo();
    await tester.pumpAndSettle();
    expect(session.bytes, before);
    expect(session.canUndo, isFalse);
    expect(getDirtyDot(), findsNothing);
    session.redo();
    await tester.pumpAndSettle();
    expect(session.document.pageCount, 5);
    expect(getDirtyDot(), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpWidget(const SizedBox());
  }, variant: TargetPlatformVariant.all());

  testWidgets('cancelled and invalid picks leave the current document intact',
      (tester) async {
    final session = await open(tester);
    final before = session.bytes;
    await insert(tester); // picker returns null
    expect(session.bytes, before);
    expect(session.canUndo, isFalse);
    picker.file = fs.XFile.fromData(Uint8List.fromList('not a PDF'.codeUnits),
        name: 'bad.pdf');
    await insert(tester);
    expect(session.bytes, before);
    expect(session.canUndo, isFalse);
    expect(find.textContaining("Couldn't insert that file."), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'merged pages and the original tab identity survive session recovery',
      (tester) async {
    final store = InMemoryUnsavedChangesStore();
    final session = await open(tester, store: store);
    picker.file = fs.XFile.fromData(buildMultiPagePdf(3), name: 'inserted.pdf');
    await insert(tester);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    final merged = session.bytes;
    final records = await store.list();
    expect(records, hasLength(1));
    expect(records.single.title, 'base.pdf');
    expect(records.single.length, merged.length);
    expect(PdfDocument.open((await store.read(records.single))!).pageCount, 5);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(MaterialApp(
        home: EditorScreen(prefs: prefs, unsavedChangesStore: store)));
    await tester.pumpAndSettle();
    final restored =
        tester.widget<PdfViewer>(find.byType(PdfViewer).first).editing!;
    expect(restored.document.pageCount, 5);
    expect(restored.bytes, merged);
    expect(findMiddleEllipsisText('base.pdf'), findsWidgets);
    expect(getDirtyDot(), findsOneWidget);
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('read-only mode hides Insert document', (tester) async {
    await open(tester);
    await tester.tap(find.byKey(const ValueKey('dartpdf-app-menu')));
    await tester.pumpAndSettle();
    final mode = find.text('Switch to read-only');
    await tester.ensureVisible(mode);
    await tester.tap(mode);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('dartpdf-app-menu')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('menu-insert-document')), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
