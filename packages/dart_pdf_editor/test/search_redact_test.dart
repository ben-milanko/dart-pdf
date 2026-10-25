// Find to redact (#1160): turning search hits into /Redact marks from the
// search panel ("Mark" / "Mark all"), the controller API behind it, and the
// redact tool's "Find text to redact" entry point.

import 'dart:async';
import 'dart:convert';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

const redactToggle = ValueKey('pdf-search-redact-toggle');
const redactOne = ValueKey('pdf-search-redact-one');
const redactAll = ValueKey('pdf-search-redact-all');

List<PdfAnnotation> redactsOn(PdfEditingController editing, int page) => [
      for (final a in editing.document.page(page).annotations)
        if (a.subtype == 'Redact') a,
    ];

int redactCount(PdfEditingController editing) => [
      for (var i = 0; i < editing.document.pageCount; i++)
        ...redactsOn(editing, i),
    ].length;

/// Every hit of [query] in [editing]'s current revision, as the viewer's
/// search would report them.
List<PdfTextMatch> matchesOf(PdfEditingController editing, String query) => [
      for (var i = 0; i < editing.document.pageCount; i++)
        ...PdfTextExtractor.extract(editing.document, i).findAll(query),
    ];

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('markMatchesForRedaction', () {
    test('marks one /Redact per hit as a single undo step', () {
      final editing = PdfEditingController(
          buildTextLinesPdf(['Jane Doe signed', 'witness Jane Doe']));
      addTearDown(editing.dispose);
      final hits = matchesOf(editing, 'Jane Doe');
      expect(hits, hasLength(2));

      expect(editing.markMatchesForRedaction(hits), 2);
      final marks = redactsOn(editing, 0);
      expect(marks, hasLength(2));
      for (final hit in hits) {
        expect(editing.isMarkedForRedaction(hit), isTrue);
      }
      // the mark phase removes nothing
      expect(latin1.decode(editing.bytes, allowInvalid: true),
          contains('Jane Doe'));

      editing.undo();
      expect(redactCount(editing), 0);
    });

    test('a hit already under a mark is not marked twice', () {
      final editing = PdfEditingController(
          buildTextLinesPdf(['Jane Doe signed', 'witness Jane Doe']));
      addTearDown(editing.dispose);
      final hits = matchesOf(editing, 'Jane Doe');
      expect(editing.markMatchesForRedaction(hits.take(1)), 1);
      expect(editing.isMarkedForRedaction(hits[1]), isFalse);

      // the second pass only adds the hit the first one missed
      expect(editing.markMatchesForRedaction(hits), 1);
      expect(redactCount(editing), 2);
      // and a third adds nothing - no revision either
      final revisions = editing.bytes.length;
      expect(editing.markMatchesForRedaction(hits), 0);
      expect(editing.bytes.length, revisions);
    });

    test('marks spread across pages and burn the matched text', () {
      final editing = PdfEditingController(buildMultiPagePdf(3));
      addTearDown(editing.dispose);
      final hits = matchesOf(editing, 'Page');
      expect({for (final h in hits) h.pageIndex}, {0, 1, 2});

      expect(editing.markMatchesForRedaction(hits), hits.length);
      for (var i = 0; i < 3; i++) {
        expect(redactsOn(editing, i), isNotEmpty);
      }
      expect(editing.applyRedactions(), isTrue);
      expect(matchesOf(editing, 'Page'), isEmpty);
    });

    test('hits with no geometry or off the document are ignored', () {
      final editing = PdfEditingController(buildMultiPagePdf(1));
      addTearDown(editing.dispose);
      expect(
          editing.markMatchesForRedaction(const [
            PdfTextMatch(pageIndex: 0, start: 0, end: 1, rects: [], quads: []),
            PdfTextMatch(
                pageIndex: 7,
                start: 0,
                end: 1,
                rects: [PdfRect(0, 0, 10, 10)],
                quads: []),
          ]),
          0);
      expect(editing.canUndo, isFalse);
    });
  });

  group('search panel find to redact', () {
    Future<void> pumpPanel(
      WidgetTester tester,
      PdfViewerController controller,
      PdfEditingController editing, {
      PdfEditingPreferences? preferences,
    }) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Row(children: [
            PdfSearchResultsPanel(
                controller: controller,
                editing: editing,
                preferences: preferences),
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

    testWidgets('a read-only panel has no redact controls', (tester) async {
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
      expect(find.byKey(redactToggle), findsNothing);
      expect(find.byKey(redactAll), findsNothing);
    });

    testWidgets('collapsed by default; the toggle persists', (tester) async {
      final controller = PdfViewerController();
      final editing = PdfEditingController(buildTextLinesPdf(['alpha beta']));
      final prefs = PdfEditingPreferences();
      addTearDown(controller.dispose);
      addTearDown(editing.dispose);
      addTearDown(prefs.dispose);
      await pumpPanel(tester, controller, editing, preferences: prefs);

      expect(find.byKey(redactAll), findsNothing);
      await tester.tap(find.byKey(redactToggle));
      await tester.pump();
      expect(find.byKey(redactAll), findsOneWidget);
      expect(prefs.searchRedactExpanded, isTrue);
    });

    testWidgets('Mark all marks every hit, once, as one undo step',
        (tester) async {
      final controller = PdfViewerController();
      final editing = PdfEditingController(
          buildTextLinesPdf(['Jane Doe one', 'Jane Doe two', 'Ann Roe']));
      addTearDown(controller.dispose);
      addTearDown(editing.dispose);
      await pumpPanel(tester, controller, editing);
      await tester.tap(find.byKey(redactToggle));
      await tester.pump();
      expect(tester.getSemantics(find.byKey(redactAll)),
          isSemantics(isEnabled: false));

      unawaited(controller.search('Jane Doe'));
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      expect(find.text('2 matches'), findsOneWidget);

      await tester.tap(find.byKey(redactAll));
      await tester.pumpAndSettle(const Duration(milliseconds: 200));
      expect(redactCount(editing), 2);
      expect(find.text('2 matches marked for redaction'), findsOneWidget);
      // the search survives the new revision, and both hits read as marked
      expect(controller.matchCount, 2);
      expect(find.byKey(const ValueKey('pdf-search-result-marked-0')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('pdf-search-result-marked-1')),
          findsOneWidget);

      // marking again adds nothing
      await tester.tap(find.byKey(redactAll));
      await tester.pumpAndSettle(const Duration(milliseconds: 200));
      expect(redactCount(editing), 2);

      editing.undo();
      expect(redactCount(editing), 0);
    });

    testWidgets('a regex search marks every pattern hit', (tester) async {
      final controller = PdfViewerController();
      final editing = PdfEditingController(buildTextLinesPdf(
          ['call 555-0101 today', 'or 555-0199', 'no number here']));
      addTearDown(controller.dispose);
      addTearDown(editing.dispose);
      await pumpPanel(tester, controller, editing);
      await tester.tap(find.byKey(redactToggle));
      await tester.pump();

      unawaited(controller.search(r'\d{3}-\d{4}',
          options: const PdfSearchOptions(regex: true)));
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      expect(controller.matchCount, 2);

      await tester.tap(find.byKey(redactAll));
      await tester.pumpAndSettle(const Duration(milliseconds: 200));
      expect(redactCount(editing), 2);
      expect(editing.applyRedactions(), isTrue);
      expect(matchesOf(editing, '555'), isEmpty);
      expect(matchesOf(editing, 'no number here'), hasLength(1));
    });

    testWidgets('Mark marks the current hit and steps to the next',
        (tester) async {
      final controller = PdfViewerController();
      final editing = PdfEditingController(
          buildTextLinesPdf(['Jane Doe one', 'Jane Doe two', 'Jane Doe 3']));
      addTearDown(controller.dispose);
      addTearDown(editing.dispose);
      await pumpPanel(tester, controller, editing);
      await tester.tap(find.byKey(redactToggle));
      await tester.pump();

      unawaited(controller.search('Jane Doe'));
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      controller.goToMatch(1);
      await tester.pumpAndSettle(const Duration(milliseconds: 100));

      await tester.tap(find.byKey(redactOne));
      await tester.pumpAndSettle(const Duration(milliseconds: 200));
      expect(redactCount(editing), 1);
      final results = controller.searchResults;
      expect(editing.isMarkedForRedaction(results[0].match), isFalse);
      expect(editing.isMarkedForRedaction(results[1].match), isTrue);
      expect(editing.isMarkedForRedaction(results[2].match), isFalse);
      // review walks on to the next hit
      expect(controller.currentMatch, 2);
    });
  });

  group('redact tool entry point', () {
    testWidgets('Find text to redact opens the panel with marking ready',
        (tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final editing = PdfEditingController(buildTextLinesPdf(['Jane Doe']))
        ..tool = PdfEditTool.redact;
      addTearDown(editing.dispose);
      await tester.pumpWidget(MaterialApp(
        home:
            PdfEditorView(controller: editing, initialFit: PdfViewerFit.width),
      ));
      await tester.pumpAndSettle(const Duration(milliseconds: 100));

      final button = find.byKey(const ValueKey('pdf-find-to-redact'));
      expect(button, findsOneWidget);
      expect(find.byKey(redactAll), findsNothing);
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      expect(find.byKey(redactToggle), findsOneWidget);
      expect(find.byKey(redactAll), findsOneWidget);
    });

    testWidgets('a standalone toolbar without a panel shows no button',
        (tester) async {
      final editing = PdfEditingController(buildMultiPagePdf(1))
        ..tool = PdfEditTool.redact;
      final viewer = PdfViewerController();
      addTearDown(editing.dispose);
      addTearDown(viewer.dispose);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          bottomNavigationBar:
              PdfEditingToolbar(controller: editing, viewerController: viewer),
        ),
      ));
      await tester.pump();
      expect(
          find.byKey(const ValueKey('pdf-apply-redactions')), findsOneWidget);
      expect(find.byKey(const ValueKey('pdf-find-to-redact')), findsNothing);
    });
  });
}
