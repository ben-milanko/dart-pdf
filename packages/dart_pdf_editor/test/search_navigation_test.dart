// The navigation/search chrome: the jump-to-page number field, the
// compact search field, the search results panel, and the controller's
// snippet-carrying results API they all read.

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One page whose single text line is long on both sides of the word
/// "sentinel" — long enough that a search snippet truncates both ways.
Uint8List buildLongLinePdf() {
  const line = 'AAAA BBBB CCCC DDDD EEEE FFFF GGGG HHHH sentinel '
      'IIII JJJJ KKKK LLLL MMMM NNNN OOOO PPPP QQQQ RRRR SSSS TTTT';
  const content = 'BT /F1 12 Tf 36 720 Td ($line) Tj ET';
  final objects = <String>[
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R '
        '/Resources << /Font << /F1 5 0 R >> >> >>',
    '<< /Length ${content.length} >>\nstream\n$content\nendstream',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
  ];
  final buffer = StringBuffer('%PDF-1.4\n');
  final offsets = <int>[];
  for (var i = 0; i < objects.length; i++) {
    offsets.add(buffer.length);
    buffer.write('${i + 1} 0 obj\n${objects[i]}\nendobj\n');
  }
  final xrefOffset = buffer.length;
  buffer
    ..write('xref\n0 ${objects.length + 1}\n')
    ..write('0000000000 65535 f \n');
  for (final offset in offsets) {
    buffer.write('${offset.toString().padLeft(10, '0')} 00000 n \n');
  }
  buffer
    ..write('trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\n')
    ..write('startxref\n$xrefOffset\n%%EOF\n');
  return ascii(buffer.toString());
}

void main() {
  setUp(() {
    // the mock store is process-global: start every test from defaults
    SharedPreferences.setMockInitialValues({});
  });

  /// Mounts a viewer with optional chrome above (app-bar style) and a
  /// panel beside it.
  Future<void> pumpViewer(
    WidgetTester tester,
    PdfViewerController controller,
    Uint8List bytes, {
    Widget? above,
    Widget? beside,
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(children: [
          if (above != null) above,
          Expanded(
            child: Row(children: [
              if (beside != null) beside,
              Expanded(
                child: PdfViewer(
                  initialFit: PdfViewerFit.width,
                  document: PdfDocument.open(bytes),
                  controller: controller,
                ),
              ),
            ]),
          ),
        ]),
      ),
    ));
    await tester.pump();
  }

  group('search results API', () {
    testWidgets('results carry snippets in document order', (tester) async {
      final controller = PdfViewerController();
      addTearDown(controller.dispose);
      await pumpViewer(tester, controller, buildMultiPagePdf(3));

      unawaited(controller.search('Page'));
      await tester.pump();
      expect(controller.searchResults, hasLength(3));
      final first = controller.searchResults.first;
      expect(first.pageIndex, 0);
      expect(first.prefix, '');
      expect(first.matchText, 'Page');
      expect(first.suffix, ' 1');
      expect(controller.searchResults[2].pageIndex, 2);
      expect(controller.currentMatch, 0);
      await tester.pumpAndSettle(const Duration(milliseconds: 100));

      controller.clearSearch();
      expect(controller.searchResults, isEmpty);
      expect(controller.matchCount, 0);
    });

    testWidgets('long lines truncate with ellipses, keeping the page case',
        (tester) async {
      final controller = PdfViewerController();
      addTearDown(controller.dispose);
      await pumpViewer(tester, controller, buildLongLinePdf());

      // case-insensitive search; the snippet shows the page's own case
      unawaited(controller.search('SENTINEL'));
      await tester.pump();
      expect(controller.searchResults, hasLength(1));
      final result = controller.searchResults.single;
      expect(result.matchText, 'sentinel');
      expect(result.prefix, startsWith('… '));
      expect(result.prefix, endsWith('HHHH '));
      expect(result.suffix, startsWith(' IIII'));
      expect(result.suffix, endsWith(' …'));
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
    });

    testWidgets('goToMatch makes a match current and navigates there',
        (tester) async {
      final controller = PdfViewerController();
      addTearDown(controller.dispose);
      await pumpViewer(tester, controller, buildMultiPagePdf(3));

      unawaited(controller.search('Page'));
      await tester.pump();
      await tester.pumpAndSettle(const Duration(milliseconds: 100));

      controller.goToMatch(2);
      expect(controller.currentMatch, 2);
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      expect(controller.currentPage, 2);

      // out of range is ignored
      controller.goToMatch(7);
      expect(controller.currentMatch, 2);
    });
  });

  group('PdfPageNumberField', () {
    const fieldKey = ValueKey('pdf-page-number-field');

    testWidgets('shows the current page and follows the viewer',
        (tester) async {
      final controller = PdfViewerController();
      addTearDown(controller.dispose);
      await pumpViewer(tester, controller, buildMultiPagePdf(5),
          above: PdfPageNumberField(controller: controller));

      expect(find.text(' / 5'), findsOneWidget);
      expect(
          tester.widget<TextField>(find.byKey(fieldKey)).controller!.text, '1');

      unawaited(controller.jumpToPage(2));
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      expect(
          tester.widget<TextField>(find.byKey(fieldKey)).controller!.text, '3');
    });

    testWidgets('submitting a number jumps; clamps and junk snap back',
        (tester) async {
      final controller = PdfViewerController();
      addTearDown(controller.dispose);
      await pumpViewer(tester, controller, buildMultiPagePdf(5),
          above: PdfPageNumberField(controller: controller));

      await tester.enterText(find.byKey(fieldKey), '4');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      expect(controller.currentPage, 3);

      // out of range clamps to the last page
      await tester.enterText(find.byKey(fieldKey), '99');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      expect(controller.currentPage, 4);
      expect(
          tester.widget<TextField>(find.byKey(fieldKey)).controller!.text, '5');

      // non-digits never reach the field; the empty submit snaps back
      await tester.enterText(find.byKey(fieldKey), 'abc');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      expect(controller.currentPage, 4);
      expect(
          tester.widget<TextField>(find.byKey(fieldKey)).controller!.text, '5');
    });
  });

  group('PdfSearchField', () {
    const fieldKey = ValueKey('pdf-search-field');

    testWidgets('typing searches after the debounce', (tester) async {
      final controller = PdfViewerController();
      addTearDown(controller.dispose);
      await pumpViewer(tester, controller, buildMultiPagePdf(3),
          above: PdfSearchField(controller: controller));

      await tester.enterText(find.byKey(fieldKey), 'page');
      await tester.pump(const Duration(milliseconds: 200));
      expect(controller.query, isEmpty); // still waiting
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump();
      expect(controller.query, 'page');
      expect(controller.matchCount, 3);
      expect(find.text('1/3'), findsOneWidget);
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
    });

    testWidgets('submit searches immediately; stepping and clearing work',
        (tester) async {
      final controller = PdfViewerController();
      addTearDown(controller.dispose);
      await pumpViewer(tester, controller, buildMultiPagePdf(3),
          above: PdfSearchField(controller: controller));

      await tester.enterText(find.byKey(fieldKey), 'page');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();
      expect(controller.query, 'page');
      await tester.pumpAndSettle(const Duration(milliseconds: 100));

      await tester.tap(find.byKey(const ValueKey('pdf-search-next')));
      await tester.pump();
      expect(controller.currentMatch, 1);
      expect(find.text('2/3'), findsOneWidget);
      await tester.pumpAndSettle(const Duration(milliseconds: 100));

      await tester.tap(find.byKey(const ValueKey('pdf-search-prev')));
      await tester.pump();
      expect(controller.currentMatch, 0);
      await tester.pumpAndSettle(const Duration(milliseconds: 100));

      await tester.tap(find.byKey(const ValueKey('pdf-search-clear')));
      await tester.pump();
      expect(controller.query, isEmpty);
      expect(find.text('1/3'), findsNothing);
      expect(tester.widget<TextField>(find.byKey(fieldKey)).controller!.text,
          isEmpty);
    });

    testWidgets('enter steps to the next match once the query is live',
        (tester) async {
      final controller = PdfViewerController();
      addTearDown(controller.dispose);
      await pumpViewer(tester, controller, buildMultiPagePdf(3),
          above: PdfSearchField(controller: controller));

      // first enter searches and lands on the first match
      await tester.enterText(find.byKey(fieldKey), 'page');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      expect(controller.query, 'page');
      expect(controller.currentMatch, 0);
      expect(find.text('1/3'), findsOneWidget);

      // subsequent enters step forward through the matches, wrapping
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();
      expect(controller.currentMatch, 1);
      expect(find.text('2/3'), findsOneWidget);
      await tester.pumpAndSettle(const Duration(milliseconds: 100));

      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();
      expect(controller.currentMatch, 2);
      await tester.pumpAndSettle(const Duration(milliseconds: 100));

      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();
      expect(controller.currentMatch, 0); // wrapped around
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
    });

    testWidgets('enter on a changed query searches afresh', (tester) async {
      final controller = PdfViewerController();
      addTearDown(controller.dispose);
      await pumpViewer(tester, controller, buildMultiPagePdf(3),
          above: PdfSearchField(controller: controller));

      await tester.enterText(find.byKey(fieldKey), 'page');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      // step forward so currentMatch is non-zero
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();
      expect(controller.currentMatch, 1);

      // a new query re-searches and resets to the first match
      await tester.enterText(find.byKey(fieldKey), 'Page 2');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      expect(controller.query, 'Page 2');
      expect(controller.matchCount, 1);
      expect(controller.currentMatch, 0);
    });
  });

  group('PdfSearchResultsPanel', () {
    testWidgets('hint, grouped results, tap navigates', (tester) async {
      final controller = PdfViewerController();
      addTearDown(controller.dispose);
      await pumpViewer(tester, controller, buildMultiPagePdf(3),
          beside: PdfSearchResultsPanel(controller: controller));

      expect(find.text('Search the document to list every match here'),
          findsOneWidget);

      unawaited(controller.search('Page'));
      await tester.pump();
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      expect(find.text('3 matches'), findsOneWidget);
      // each page shows twice: its group header and the snippet itself
      expect(find.text('Page 1'), findsNWidgets(2));
      expect(find.text('Page 3'), findsNWidgets(2));

      await tester.tap(find.byKey(const ValueKey('pdf-search-result-2')));
      await tester.pump();
      expect(controller.currentMatch, 2);
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      expect(controller.currentPage, 2);
      expect(
          tester
              .widget<ListTile>(
                  find.byKey(const ValueKey('pdf-search-result-2')))
              .selected,
          isTrue);
      // any touch gesture leaves the viewer's double-tap timer pending
      await tester.pump(const Duration(milliseconds: 400));
    });

    testWidgets('an unmatched query says so', (tester) async {
      final controller = PdfViewerController();
      addTearDown(controller.dispose);
      await pumpViewer(tester, controller, buildMultiPagePdf(2),
          beside: PdfSearchResultsPanel(controller: controller));

      unawaited(controller.search('zzz'));
      await tester.pump();
      expect(find.text('No matches for “zzz”'), findsOneWidget);
    });

    testWidgets('the dragged width persists as a preference', (tester) async {
      final controller = PdfViewerController();
      final preferences = PdfEditingPreferences();
      addTearDown(controller.dispose);
      addTearDown(preferences.dispose);
      await pumpViewer(tester, controller, buildMultiPagePdf(2),
          beside: PdfSearchResultsPanel(
              controller: controller, preferences: preferences));

      final grip = find.byKey(const ValueKey('pdf-search-resize-grip'));
      expect(grip, findsOneWidget);
      final before = tester.getSize(find.byType(PdfSearchResultsPanel)).width;
      final gesture = await tester.startGesture(tester.getCenter(grip),
          kind: PointerDeviceKind.mouse);
      // docked left: rightward drag grows the panel (slop eats some)
      await gesture.moveBy(const Offset(60, 0));
      await gesture.up();
      await tester.pump();

      final after = tester.getSize(find.byType(PdfSearchResultsPanel)).width;
      expect(after, greaterThan(before));
      expect(preferences.searchPanelWidth, after);
    });
  });
}
