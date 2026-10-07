import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';

List<String> labelsOf(PdfDocument doc) => [
      for (var i = 0; i < doc.pageCount; i++)
        RegExp(r'\((Page \d+)\)')
                .firstMatch(String.fromCharCodes(doc.page(i).contentBytes()))
                ?.group(1) ??
            '',
    ];

void main() {
  test('pdfInsertIndex maps before/after the first, last or a page', () {
    int at(PdfInsertSide side, PdfInsertAnchor anchor, [int page = 1]) =>
        pdfInsertIndex(pageCount: 5, side: side, anchor: anchor, page: page);
    expect(at(PdfInsertSide.before, PdfInsertAnchor.firstPage), 0);
    expect(at(PdfInsertSide.after, PdfInsertAnchor.firstPage), 1);
    expect(at(PdfInsertSide.before, PdfInsertAnchor.lastPage), 4);
    expect(at(PdfInsertSide.after, PdfInsertAnchor.lastPage), 5);
    expect(at(PdfInsertSide.before, PdfInsertAnchor.page, 3), 2);
    expect(at(PdfInsertSide.after, PdfInsertAnchor.page, 3), 3);
  });

  group('insert pages dialog', () {
    late PdfEditingController controller;
    late List<PdfInsertFile> nextPick;
    ({int files, List<int> pages})? result;

    setUp(() {
      controller = PdfEditingController(buildMultiPagePdf(2));
      nextPick = const [];
      result = null;
    });
    tearDown(() => controller.dispose());

    Future<void> show(WidgetTester tester, List<PdfInsertFile> files) async {
      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Center(
            child: TextButton(
              key: const ValueKey('open'),
              onPressed: () async {
                result = await pdfInsertPagesInteractively(
                  context,
                  controller: controller,
                  pickFiles: () async => nextPick,
                  initialFiles: files,
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.byKey(const ValueKey('open')));
      await tester.pumpAndSettle();
    }

    Future<void> pickMenu(
        WidgetTester tester, String button, String item) async {
      await tester.tap(find.byKey(ValueKey(button)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey(item)).last);
      await tester.pumpAndSettle();
    }

    testWidgets('per-file range, even filter and reverse; one undo step',
        (tester) async {
      await show(tester, [PdfInsertFile('five.pdf', buildMultiPagePdf(5))]);
      expect(find.text('five.pdf'), findsOneWidget);
      expect(find.text('5 pages'), findsOneWidget);

      await tester.enterText(
          find.byKey(const ValueKey('pdf-insert-pages-range-0')), '2-5');
      await pickMenu(tester, 'pdf-insert-pages-subset-0',
          'pdf-insert-pages-subset-0-even');
      await tester
          .tap(find.byKey(const ValueKey('pdf-insert-pages-reverse-0')));
      await pickMenu(
          tester, 'pdf-insert-pages-anchor', 'pdf-insert-pages-anchor-last');
      await tester.pumpAndSettle();
      expect(find.text('Inserts 2 pages - the document will have 4 pages.'),
          findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('pdf-insert-pages-confirm')));
      await tester.pumpAndSettle();
      expect(result!.pages, [2, 3]);
      expect(labelsOf(controller.document),
          ['Page 1', 'Page 2', 'Page 4', 'Page 2']);
      controller.undo();
      expect(controller.document.pageCount, 2);
    });

    testWidgets('a bad range or page number blocks Insert', (tester) async {
      await show(tester, [PdfInsertFile('two.pdf', buildMultiPagePdf(2))]);
      FilledButton confirm() => tester.widget<FilledButton>(
          find.byKey(const ValueKey('pdf-insert-pages-confirm')));
      expect(confirm().onPressed, isNotNull);

      await tester.enterText(
          find.byKey(const ValueKey('pdf-insert-pages-range-0')), '3');
      await tester.pump();
      expect(find.text('Use pages 1–2, e.g. 1-3, 7'), findsOneWidget);
      expect(confirm().onPressed, isNull);
      await tester.enterText(
          find.byKey(const ValueKey('pdf-insert-pages-range-0')), '');
      await tester.enterText(
          find.byKey(const ValueKey('pdf-insert-pages-page')), '9');
      await tester.pump();
      expect(confirm().onPressed, isNull);
      await tester.enterText(
          find.byKey(const ValueKey('pdf-insert-pages-page')), '2');
      await tester.pump();
      expect(confirm().onPressed, isNotNull);

      await tester.tap(find.byKey(const ValueKey('pdf-insert-pages-cancel')));
      await tester.pumpAndSettle();
      expect(result, isNull);
      expect(controller.canUndo, isFalse);
    });

    testWidgets('add, reorder and remove files', (tester) async {
      await show(tester, [PdfInsertFile('one.pdf', buildMultiPagePdf(1))]);
      nextPick = [
        PdfInsertFile('three.pdf', buildMultiPagePdf(3)),
        PdfInsertFile('broken.pdf', buildMultiPagePdf(1).sublist(0, 20)),
      ];
      await tester.tap(find.byKey(const ValueKey('pdf-insert-pages-add')));
      await tester.pumpAndSettle();
      expect(find.text('three.pdf'), findsOneWidget);
      expect(find.byKey(const ValueKey('pdf-insert-pages-failed')),
          findsOneWidget);

      // three.pdf first, then drop one.pdf
      await tester.tap(find.byKey(const ValueKey('pdf-insert-pages-up-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('pdf-insert-pages-remove-1')));
      await tester.pumpAndSettle();
      expect(find.text('one.pdf'), findsNothing);

      // before the first page, interleaved one for one
      await pickMenu(
          tester, 'pdf-insert-pages-side', 'pdf-insert-pages-side-before');
      await pickMenu(
          tester, 'pdf-insert-pages-anchor', 'pdf-insert-pages-anchor-first');
      await tester
          .tap(find.byKey(const ValueKey('pdf-insert-pages-interleave')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('pdf-insert-pages-confirm')));
      await tester.pumpAndSettle();

      expect(result!.files, 1);
      expect(result!.pages, [0, 2, 4]);
      expect(labelsOf(controller.document),
          ['Page 1', 'Page 1', 'Page 2', 'Page 2', 'Page 3']);
    });
  });
}
