import 'dart:typed_data';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> openSplit(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('pdf-thumbnail-page-actions')),
        kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('pdf-thumbnail-split-pages')));
    await tester.pumpAndSettle();
  }

  test('batch export leaves selection, revision and undo state untouched', () {
    final controller = PdfEditingController(buildMultiPagePdf(4));
    addTearDown(controller.dispose);
    controller.selectPage(2);
    final document = controller.document;
    final outputs = controller
        .exportPageRanges(const [PdfPageRange(2, 3), PdfPageRange(0, 0)]);
    expect(outputs.map((b) => PdfDocument.open(b).pageCount), [2, 1]);
    expect(controller.document, same(document));
    expect(controller.selectedPages, [2]);
    expect(controller.canUndo, isFalse);
  });

  for (final grid in [false, true]) {
    testWidgets(
        'split delivers every output once from ${grid ? 'grid' : 'strip'}',
        (tester) async {
      final controller = PdfEditingController(buildMultiPagePdf(12));
      addTearDown(controller.dispose);
      controller.preferences.showThumbnailView = grid;
      List<Uint8List>? outputs;
      var calls = 0;
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: PdfEditorView(
        controller: controller,
        features: const PdfEditorFeatures(pageEditing: false),
        onSplitPages: (parts) {
          outputs = parts;
          calls++;
        },
      ))));
      await tester.pump();
      await openSplit(tester);
      await tester.enterText(
          find.byKey(const ValueKey('pdf-split-ranges')), '1-3, 7, 10-12');
      await tester.tap(find.byKey(const ValueKey('pdf-split-confirm')));
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(outputs!.map((b) => PdfDocument.open(b).pageCount), [3, 1, 3]);
      expect(
          String.fromCharCodes(
              PdfDocument.open(outputs![1]).page(0).contentBytes()),
          contains('(Page 7)'));
      expect(controller.document.pageCount, 12);
      expect(controller.canUndo, isFalse);
    });
  }

  testWidgets(
      'invalid ranges stay open, correction succeeds, cancel emits nothing',
      (tester) async {
    var calls = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: PdfEditorView(
      bytes: buildMultiPagePdf(4),
      onSplitPages: (_) => calls++,
    ))));
    await tester.pump();
    await openSplit(tester);
    for (final input in ['1,', '0', '2-1', '1-5']) {
      await tester.enterText(
          find.byKey(const ValueKey('pdf-split-ranges')), input);
      await tester.tap(find.byKey(const ValueKey('pdf-split-confirm')));
      await tester.pumpAndSettle();
      expect(calls, 0);
      expect(find.byKey(const ValueKey('pdf-split-dialog')), findsOneWidget);
      expect(find.textContaining('Use pages 1–4'), findsOneWidget);
    }
    await tester.enterText(
        find.byKey(const ValueKey('pdf-split-ranges')), '1-2, 4');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(calls, 1);
    await openSplit(tester);
    await tester.tap(find.byKey(const ValueKey('pdf-split-cancel')));
    await tester.pumpAndSettle();
    expect(calls, 1);
  });

  testWidgets('split is hidden without a batch callback', (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: PdfEditorView(
      bytes: buildMultiPagePdf(2),
      onExportPages: (_) {},
    ))));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('pdf-thumbnail-page-actions')),
        kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    expect(
        find.byKey(const ValueKey('pdf-thumbnail-split-pages')), findsNothing);
    expect(find.byKey(const ValueKey('pdf-thumbnail-export-pages')),
        findsOneWidget);
  });

  testWidgets('a revision during the dialog cannot export a different range',
      (tester) async {
    final controller = PdfEditingController(buildMultiPagePdf(4));
    addTearDown(controller.dispose);
    var calls = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: PdfEditorView(
      controller: controller,
      onSplitPages: (_) => calls++,
    ))));
    await tester.pump();
    await openSplit(tester);
    await tester.enterText(
        find.byKey(const ValueKey('pdf-split-ranges')), '1-2');
    controller.removePage(0);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('pdf-split-confirm')));
    await tester.pumpAndSettle();
    expect(calls, 0);
    expect(tester.takeException(), isNull);
  });
}
