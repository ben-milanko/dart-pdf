import 'dart:typed_data';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:file_selector_platform_interface/file_selector_platform_interface.dart'
    as fs;
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart' show PdfOutline;
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dart_pdf_editor_app/editor_screen.dart';
import 'package:dart_pdf_editor_app/unsaved_changes.dart';

import 'test_finders.dart';

class _Picker extends fs.FileSelectorPlatform {
  fs.XFile? file;
  List<fs.XFile> files = const [];
  List<fs.XTypeGroup>? groups;

  // Insert document picks through the multi-file dialog; a single [file]
  // stands in for a one-file pick.
  @override
  Future<List<fs.XFile>> openFiles(
      {List<fs.XTypeGroup>? acceptedTypeGroups,
      String? initialDirectory,
      String? confirmButtonText}) async {
    groups = acceptedTypeGroups;
    final one = file;
    return one != null ? [one] : files;
  }

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

  // Accepts the insert-pages dialog as it stands.
  Future<void> confirm(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('pdf-insert-pages-confirm')));
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
    // the dialog defaults to "after the current page"
    expect(
        find.byKey(const ValueKey('pdf-insert-pages-dialog')), findsOneWidget);
    await confirm(tester);

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
    await insert(tester); // picker returns nothing
    expect(find.byKey(const ValueKey('pdf-insert-pages-dialog')), findsNothing);
    expect(session.bytes, before);
    expect(session.canUndo, isFalse);
    picker.file = fs.XFile.fromData(Uint8List.fromList('not a PDF'.codeUnits),
        name: 'bad.pdf', path: 'bad.pdf');
    await insert(tester);
    // the unreadable file is reported in the dialog and nothing can insert
    expect(
        find.byKey(const ValueKey('pdf-insert-pages-failed')), findsOneWidget);
    expect(find.textContaining("Couldn't open bad.pdf"), findsOneWidget);
    final confirmButton = tester.widget<FilledButton>(
        find.byKey(const ValueKey('pdf-insert-pages-confirm')));
    expect(confirmButton.onPressed, isNull);
    await tester.tap(find.byKey(const ValueKey('pdf-insert-pages-cancel')));
    await tester.pumpAndSettle();
    expect(session.bytes, before);
    expect(session.canUndo, isFalse);
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
    await confirm(tester);
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

  testWidgets(
      'several documents interleave in one undo step, bookmarked per file',
      (tester) async {
    final session = await open(tester);
    final before = session.bytes;
    picker.files = [
      fs.XFile.fromData(buildMultiPagePdf(2), name: 'b.pdf', path: 'b.pdf'),
      fs.XFile.fromData(buildMultiPagePdf(1), name: 'a.pdf', path: 'a.pdf'),
    ];
    await insert(tester);
    expect(find.text('b.pdf'), findsOneWidget);
    expect(find.text('a.pdf'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('pdf-insert-pages-sort')));
    await tester.pumpAndSettle();
    // before the first page, weaving one new page between each old one
    await tester.tap(find.byKey(const ValueKey('pdf-insert-pages-side')));
    await tester.pumpAndSettle();
    await tester
        .tap(find.byKey(const ValueKey('pdf-insert-pages-side-before')).last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('pdf-insert-pages-anchor')));
    await tester.pumpAndSettle();
    await tester
        .tap(find.byKey(const ValueKey('pdf-insert-pages-anchor-first')).last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('pdf-insert-pages-interleave')));
    await tester
        .tap(find.byKey(const ValueKey('pdf-insert-pages-bookmark-files')));
    await tester.pumpAndSettle();
    expect(find.text('Inserts 3 pages - the document will have 5 pages.'),
        findsOneWidget);
    await confirm(tester);

    expect(session.document.pageCount, 5);
    final doc = PdfDocument.open(session.bytes);
    // a.pdf (1 page) sorts first, then b.pdf's 2: a1 b1 b2 woven into base
    expect([
      for (var i = 0; i < 5; i++)
        RegExp(r'\(Page (\d)\)')
            .firstMatch(String.fromCharCodes(doc.page(i).contentBytes()))!
            .group(1)
    ], [
      '1',
      '1',
      '1',
      '2',
      '2'
    ]);
    final outline = PdfOutline.of(doc).items;
    expect(outline.map((i) => i.title), ['a', 'b']);
    expect(outline.map((i) => i.destination!.pageIndex), [0, 2]);
    expect(
        find.textContaining('Inserted 2 PDFs into base.pdf'), findsOneWidget);

    session.undo();
    await tester.pumpAndSettle();
    expect(session.bytes, before);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('read-only mode hides Insert document', (tester) async {
    await open(tester);
    await tester.tap(find.byKey(const ValueKey('dartpdf-app-menu')));
    await tester.pumpAndSettle();
    // Read-only is a switch row now, not a "Switch to read-only" verb.
    final mode = find.byKey(const ValueKey('menu-read-only'));
    await tester.ensureVisible(mode);
    await tester.tap(mode);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('dartpdf-app-menu')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('menu-insert-document')), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
