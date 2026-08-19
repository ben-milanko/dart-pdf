// Find *and replace* from the search panel: the replacement field, the
// targeted single "Replace", and the page-wide "Replace all".

import 'dart:async';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Every text run on page 0 of [editing]'s current revision.
List<String> runsOf(PdfEditingController editing) => [
      for (final e in PdfPageElements.of(editing.document, 0).elements)
        if (e.kind == PdfElementKind.text) e.text!,
    ];

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pumpPanel(
    WidgetTester tester,
    PdfViewerController controller,
    PdfEditingController editing,
  ) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Row(children: [
          PdfSearchResultsPanel(controller: controller, editing: editing),
          Expanded(
            child: PdfViewer(
              initialFit: PdfViewerFit.width,
              editing: editing,
              controller: controller,
            ),
          ),
        ]),
      ),
    ));
    await tester.pump();
  }

  group('search panel replace', () {
    testWidgets('without an editing session there are no replace controls',
        (tester) async {
      final controller = PdfViewerController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Row(children: [
            PdfSearchResultsPanel(controller: controller),
            Expanded(
              child: PdfViewer(
                initialFit: PdfViewerFit.width,
                document: PdfDocument.open(buildTextLinesPdf(['alpha beta'])),
                controller: controller,
              ),
            ),
          ]),
        ),
      ));
      await tester.pump();
      expect(find.byKey(const ValueKey('pdf-search-replace-field')), findsNothing);
      expect(find.byKey(const ValueKey('pdf-search-replace-all')), findsNothing);
    });

    testWidgets('the buttons stay disabled until a query has hits',
        (tester) async {
      final controller = PdfViewerController();
      final editing = PdfEditingController(buildTextLinesPdf(['alpha beta']));
      addTearDown(controller.dispose);
      addTearDown(editing.dispose);
      await pumpPanel(tester, controller, editing);

      expect(find.byKey(const ValueKey('pdf-search-replace-field')),
          findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
                find.byKey(const ValueKey('pdf-search-replace-all')))
            .onPressed,
        isNull,
      );

      unawaited(controller.search('beta'));
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      expect(
        tester
            .widget<FilledButton>(
                find.byKey(const ValueKey('pdf-search-replace-all')))
            .onPressed,
        isNotNull,
      );
    });

    testWidgets('Replace all rewrites every hit as one undo step',
        (tester) async {
      final controller = PdfViewerController();
      final editing = PdfEditingController(
          buildTextLinesPdf(['draft one', 'draft two', 'final three']));
      addTearDown(controller.dispose);
      addTearDown(editing.dispose);
      await pumpPanel(tester, controller, editing);

      unawaited(controller.search('draft'));
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      expect(find.text('2 matches'), findsOneWidget);

      await tester.enterText(
          find.byKey(const ValueKey('pdf-search-replace-field')), 'issued');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('pdf-search-replace-all')));
      await tester.pumpAndSettle(const Duration(milliseconds: 200));

      expect(runsOf(editing), ['issued one', 'issued two', 'final three']);
      expect(find.text('2 matches replaced'), findsOneWidget);

      // one undo step puts both back
      editing.undo();
      expect(runsOf(editing), ['draft one', 'draft two', 'final three']);
    });

    testWidgets('Replace rewrites only the current match', (tester) async {
      final controller = PdfViewerController();
      final editing = PdfEditingController(
          buildTextLinesPdf(['draft one', 'draft two', 'final three']));
      addTearDown(controller.dispose);
      addTearDown(editing.dispose);
      await pumpPanel(tester, controller, editing);

      unawaited(controller.search('draft'));
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      // step to the second hit, then replace just it
      controller.goToMatch(1);
      await tester.pumpAndSettle(const Duration(milliseconds: 100));

      await tester.enterText(
          find.byKey(const ValueKey('pdf-search-replace-field')), 'issued');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('pdf-search-replace-one')));
      await tester.pumpAndSettle(const Duration(milliseconds: 200));

      expect(runsOf(editing), ['draft one', 'issued two', 'final three']);
    });
  });

  group('controller replace API', () {
    test('replaceTextOnPages is page-wide and one edit', () {
      final editing = PdfEditingController(
          buildTextLinesPdf(['draft one', 'draft two', 'final three']));
      addTearDown(editing.dispose);
      expect(editing.replaceTextOnPages([0], 'draft', 'issued'), 2);
      expect(runsOf(editing), ['issued one', 'issued two', 'final three']);
      editing.undo();
      expect(runsOf(editing), ['draft one', 'draft two', 'final three']);
    });

    test('replaceMatchText declines a hit it cannot pin to one run', () {
      final editing =
          PdfEditingController(buildTextLinesPdf(['draft one', 'draft two']));
      addTearDown(editing.dispose);
      // an empty rect list can overlap nothing, so the hit is unresolvable
      expect(editing.replaceMatchText(0, const [], 'draft', 'issued'), 0);
      expect(runsOf(editing), ['draft one', 'draft two']);
    });
  });
}
