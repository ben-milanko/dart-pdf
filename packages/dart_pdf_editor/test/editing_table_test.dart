import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'support/pump_host.dart';

void main() {
  String? clipboard;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    clipboard = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.getData') return {'text': clipboard};
      if (call.method == 'Clipboard.setData') {
        clipboard = (call.arguments as Map)['text'] as String;
      }
      return null;
    });
  });
  tearDown(() => TestDefaultBinaryMessengerBinding
      .instance.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, null));

  Future<void> show(WidgetTester tester,
      {PdfTableData? initial, void Function(PdfTableData?)? done}) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Builder(
                builder: (context) => TextButton(
                    onPressed: () async {
                      final result = await showDialog<PdfTableData>(
                          context: context,
                          builder: (_) =>
                              PdfTableEditorDialog(initial: initial));
                      done?.call(result);
                    },
                    child: const Text('Open'))))));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'paste an Excel range, select all and copy exact cell values back',
      (tester) async {
    PdfTableData? result;
    await show(tester, done: (table) => result = table);
    clipboard = 'Name\tNotes\r\nBen\t"First\nSecond"\r\n';
    await tester.tap(find.byKey(const ValueKey('pdf-table-paste')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('pdf-table-cell-2-0')), findsNothing,
        reason: 'a first paste into a new empty table adopts the range size');
    await tester.tap(find.byKey(const ValueKey('pdf-table-select-all')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('pdf-table-copy')));
    await tester.pumpAndSettle();
    expect(clipboard, 'Name\tNotes\r\nBen\t"First\nSecond"');
    await tester.tap(find.byKey(const ValueKey('pdf-table-apply')));
    await tester.pumpAndSettle();
    expect(result!.cells, [
      ['Name', 'Notes'],
      ['Ben', 'First\nSecond']
    ]);
  });

  testWidgets('row/column changes and edits remain a draft until Apply',
      (tester) async {
    PdfTableData? result;
    await show(tester,
        initial: PdfTableData([
          ['Original']
        ]),
        done: (table) => result = table);
    await tester.tap(find.byKey(const ValueKey('pdf-table-add-row')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('pdf-table-add-column')));
    await tester.pump();
    await tester.enterText(
        find.byKey(const ValueKey('pdf-table-cell-1-1')), 'Edited');
    expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('pdf-table-cell-1-1')))
            .controller!
            .text,
        'Edited');
    await tester.pump();
    expect(result, isNull);
    await tester.tap(find.byKey(const ValueKey('pdf-table-apply')));
    await tester.pumpAndSettle();
    expect(result!.cells, [
      ['Original', ''],
      ['', 'Edited']
    ]);
  });

  testWidgets('cancel leaves the caller table unchanged', (tester) async {
    final original = PdfTableData([
      ['Original']
    ]);
    PdfTableData? result;
    await show(tester, initial: original, done: (table) => result = table);
    await tester.enterText(
        find.byKey(const ValueKey('pdf-table-cell-0-0')), 'Changed');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(result, isNull);
    expect(original.cells, [
      ['Original']
    ]);
  });

  test('table paste, edit, undo and reopen preserve the cell model', () async {
    final editing = PdfEditingController(buildMultiPagePdf(1));
    addTearDown(editing.dispose);
    expect(editing.placeFreeText(0, 300, 400, 'A\tB\r\n1\t2'), isTrue);
    expect(editing.selectedAnnotation!.table!.cells, [
      ['A', 'B'],
      ['1', '2']
    ]);
    final revision = editing.revisionId;
    expect(
        editing.updateTable(
            0,
            0,
            PdfTableData([
              ['X']
            ]),
            expectedRevision: revision),
        isTrue);
    expect(editing.document.page(0).annotations.single.table!.cells, [
      ['X']
    ]);
    editing.undo();
    expect(editing.document.page(0).annotations.single.table!.cells, [
      ['A', 'B'],
      ['1', '2']
    ]);
    editing.redo();
    expect(
        PdfDocument.open(editing.bytes).page(0).annotations.single.table!.cells,
        [
          ['X']
        ]);
    expect(
        editing.updateTable(
            0,
            0,
            PdfTableData([
              ['Stale']
            ]),
            expectedRevision: revision),
        isFalse);
  });

  testWidgets('table editor fits a narrow mobile dialog', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await show(tester);
    expect(tester.takeException(), isNull);
  });

  test('copying Excel values replaces an older PDF annotation clipboard',
      () async {
    final editing = PdfEditingController(buildMultiPagePdf(1));
    addTearDown(editing.dispose);
    addTearDown(editing.annotationClipboard.clear);
    editing.placeTable(
        0,
        200,
        400,
        PdfTableData([
          ['A', 'B']
        ]));
    expect(editing.copySelectedAnnotations(), 1);
    expect(editing.hasAnnotationClipboard, isTrue);
    final revision = editing.revisionId;
    await editing
        .copyTableCellsText(editing.selectedAnnotation!.table!.toTsv());
    expect(clipboard, 'A\tB');
    expect(editing.hasAnnotationClipboard, isFalse);
    expect(editing.revisionId, revision);
  });

  testWidgets(
      'Insert table opens the editor and creates one undoable annotation',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final editing = PdfEditingController(buildMultiPagePdf(1));
    final viewer = PdfViewerController();
    addTearDown(editing.dispose);
    addTearDown(viewer.dispose);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Align(
                alignment: Alignment.topCenter,
                child: PdfEditingToolbar(
                    controller: editing,
                    viewerController: viewer,
                    compact: false)))));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('pdf-group-insert')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('pdf-insert-table')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('pdf-table-cell-0-0')), 'Header');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('pdf-table-apply')));
    await tester.pumpAndSettle();
    expect(editing.document.page(0).annotations.single.table!.cells[0][0],
        'Header');
    editing.undo();
    expect(editing.document.page(0).annotations, isEmpty);
  });

  testWidgets('table dialog edits cells under a plain WidgetsApp host',
      (tester) async {
    final editing = PdfEditingController(buildMultiPagePdf(1));
    addTearDown(editing.dispose);
    await pumpPdfHost(
        tester,
        PdfMaterialHost(
            child: Builder(
                builder: (context) => TextButton(
                    onPressed: () => showPdfTableEditor(context,
                        controller: editing, pageIndex: 0),
                    child: const Text('Open table')))),
        host: PdfTestHost.widgets);
    await tester.tap(find.text('Open table'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('pdf-table-cell-0-0')), 'Plain host');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('pdf-table-apply')));
    await tester.pumpAndSettle();
    expect(editing.document.page(0).annotations.single.table!.cells[0][0],
        'Plain host');
    expectNoHostErrors(tester);
  });
}
