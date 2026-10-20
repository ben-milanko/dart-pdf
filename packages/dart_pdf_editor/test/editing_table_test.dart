import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:dart_pdf_editor/src/editing/editing_overlay.dart';
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

  testWidgets(
      'table grid aligns cells and grows rows instead of scrolling text',
      (tester) async {
    final long = List.filled(8, 'Long clarification text').join('\n');
    await show(tester,
        initial: PdfTableData([
          ['Q', 'Clarifications'],
          ['1', long],
        ]));
    expect(find.text('A'), findsOneWidget);
    expect(find.text('B'), findsOneWidget);
    final first = find.byKey(const ValueKey('pdf-table-cell-1-0'));
    final second = find.byKey(const ValueKey('pdf-table-cell-1-1'));
    expect(tester.getRect(first).top, tester.getRect(second).top);
    expect(tester.getRect(first).height, tester.getRect(second).height);
    expect(tester.getRect(second).height, greaterThan(150));
    expect(tester.widget<TextField>(second).maxLines, isNull);
    for (final field in [first, second]) {
      final scrollable =
          find.descendant(of: field, matching: find.byType(Scrollable));
      final state = tester.state<ScrollableState>(scrollable.first);
      expect(state.position.maxScrollExtent, 0,
          reason: 'long text belongs in a growing row, not a cell viewport');
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('Tab and Shift-Tab traverse cells in row-major order',
      (tester) async {
    await show(tester,
        initial: PdfTableData([
          ['A1', 'B1'],
          ['A2', 'B2'],
        ]));
    Finder field(int r, int c) => find.byKey(ValueKey('pdf-table-cell-$r-$c'));
    bool focused(int r, int c) =>
        tester.widget<TextField>(field(r, c)).focusNode!.hasFocus;
    await tester.tap(field(0, 0));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(focused(0, 1), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(focused(1, 0), isTrue);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    expect(focused(0, 1), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('arrows navigate adjacent cells without losing edits',
      (tester) async {
    await show(tester,
        initial: PdfTableData([
          ['A1', 'B1'],
          ['A2', 'B2'],
        ]));
    Finder field(int r, int c) => find.byKey(ValueKey('pdf-table-cell-$r-$c'));
    bool focused(int r, int c) =>
        tester.widget<TextField>(field(r, c)).focusNode!.hasFocus;
    await tester.enterText(field(0, 0), 'Edited');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(focused(0, 1), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(focused(1, 1), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(focused(1, 0), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(focused(0, 0), isTrue);
    expect(tester.widget<TextField>(field(0, 0)).controller!.text, 'Edited');
  });

  testWidgets('arrow keys retain caret movement within a multiline cell',
      (tester) async {
    await show(tester,
        initial: PdfTableData([
          ['First\nSecond\nThird'],
          ['Next row'],
        ]));
    final field = find.byKey(const ValueKey('pdf-table-cell-0-0'));
    await tester.tap(field);
    final widget = tester.widget<TextField>(field);
    widget.controller!.selection = const TextSelection.collapsed(offset: 8);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(widget.focusNode!.hasFocus, isTrue);
    expect(widget.controller!.selection.extentOffset, lessThan(8));
  });

  testWidgets(
      'table drag preview reflows at fixed font size and resize is undoable',
      (tester) async {
    final editing = PdfEditingController(buildMultiPagePdf(1));
    editing.preferences.smartAlignmentGuides = false;
    editing.placeTable(
        0,
        200,
        600,
        PdfTableData([
          ['What do ARTC do when there is a train order working'],
        ], columnWidths: [
          160
        ], rowHeights: [
          120
        ], fontSize: 12));
    addTearDown(editing.dispose);
    final original = editing.selectedAnnotation!.rect;
    final geometry = PdfPageGeometry(
        cropBox: editing.document.page(0).cropBox,
        rotation: 0,
        viewSize: const Size(612, 792));
    await tester.pumpWidget(MaterialApp(
        home: Center(
            child: SizedBox(
                width: 612,
                height: 792,
                child: EditingPageOverlay(
                    controller: editing,
                    pageIndex: 0,
                    geometry: geometry,
                    rasterCurrent: false,
                    textPrompt: showPdfTextPrompt)))));
    await tester.pump();
    final origin = tester.getTopLeft(find.byType(EditingPageOverlay));
    final handle = origin +
        Offset(original.right, 792 - (original.bottom + original.top) / 2);
    final gesture =
        await tester.startGesture(handle, kind: PointerDeviceKind.mouse);
    await gesture.moveBy(const Offset(120, 0));
    await tester.pump();
    final preview = find.byKey(const ValueKey('pdf-table-resize-preview'));
    expect(preview, findsOneWidget);
    final label = tester.widget<Text>(
        find.descendant(of: preview, matching: find.byType(Text)).first);
    expect(label.style!.fontSize, 12);
    final painter = tester
        .widget<CustomPaint>(find
            .descendant(
                of: find.byType(EditingPageOverlay),
                matching: find.byType(CustomPaint))
            .first)
        .painter as dynamic;
    expect(painter.ghost, isNull);
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 400));
    expect(editing.selectedAnnotation!.rect.width,
        closeTo(original.width + 120, .1));
    expect(preview, findsOneWidget,
        reason: 'the reflowed afterimage survives until raster completion');
    final bytes = editing.bytes;
    editing.undo();
    expect(editing.document.page(0).annotations.single.rect, original);
    editing.redo();
    expect(
        PdfDocument.open(bytes).page(0).annotations.single.table!.fontSize, 12);
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
