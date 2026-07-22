import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  PdfEditingController controller([int pages = 1]) {
    SharedPreferences.setMockInitialValues({});
    return PdfEditingController(buildMultiPagePdf(pages));
  }

  group('controller links', () {
    test('addLink over a box creates an external /Link with a border', () {
      final editing = controller();
      addTearDown(editing.dispose);
      editing.addLink(
        0,
        const [PdfRect(72, 715, 200, 735)],
        const PdfLinkTarget.uri('https://example.com'),
      );

      final link = editing.document.page(0).annotations.single;
      expect(link, isA<PdfLinkAnnotation>());
      expect((link.action as PdfUriAction).uri, 'https://example.com');
      // a bare box link is drawn with a visible border so it can be seen
      expect(link.color, isNotNull);
      expect(link.normalAppearance, isNotNull);
      expect(editing.canUndo, isTrue);
    });

    test('addLink with a page target jumps within the document', () {
      final editing = controller(3);
      addTearDown(editing.dispose);
      editing.addLink(
        0,
        const [PdfRect(72, 715, 200, 735)],
        const PdfLinkTarget.page(2),
      );

      final action =
          editing.document.page(0).annotations.single.action as PdfGoToAction;
      expect(action.destination.pageIndex, 2);
    });

    test('addLinkToSelection makes one underlined link per page', () {
      final editing = controller(2);
      addTearDown(editing.dispose);
      editing.addLinkToSelection(
        const {
          0: [PdfRect(72, 715, 200, 735)],
          1: [PdfRect(72, 715, 180, 735)],
        },
        const PdfLinkTarget.uri('mailto:team@example.com'),
      );

      for (final page in [0, 1]) {
        final link = editing.document.page(page).annotations.single;
        expect(link.subtype, 'Link');
        // selection links default to an underline decoration, no border
        expect(link.color, isNull);
        expect(link.normalAppearance, isNotNull);
      }
    });

    test('a negative decoration colour leaves the region invisible', () {
      final editing = controller();
      addTearDown(editing.dispose);
      editing.addLink(
        0,
        const [PdfRect(72, 715, 200, 735)],
        const PdfLinkTarget.uri('https://example.com'),
        borderColor: -1,
      );
      final link = editing.document.page(0).annotations.single;
      expect(link.normalAppearance, isNull);
      expect(link.color, isNull);
    });

    test('addLink with empty quads is a no-op', () {
      final editing = controller();
      addTearDown(editing.dispose);
      editing.addLink(0, const [], const PdfLinkTarget.uri('https://x.test'));
      expect(editing.document.page(0).annotations, isEmpty);
      expect(editing.canUndo, isFalse);
    });
  });

  group('add-link dialog', () {
    testWidgets('collects a web address', (tester) async {
      PdfLinkTarget? result;
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates:
            DartPdfEditorLocalizations.localizationsDelegates,
        supportedLocales: DartPdfEditorLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showPdfAddLinkDialog(context,
                    pageCount: 5, currentPage: 0);
              },
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'https://example.com');
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.isExternal, isTrue);
      expect(result!.uri, 'https://example.com');
    });

    testWidgets('collects an in-document page target', (tester) async {
      PdfLinkTarget? result;
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates:
            DartPdfEditorLocalizations.localizationsDelegates,
        supportedLocales: DartPdfEditorLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showPdfAddLinkDialog(context,
                    pageCount: 5, currentPage: 0);
              },
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // switch to the "page in document" mode
      await tester.tap(find.text('Page in document'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '3');
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.isExternal, isFalse);
      expect(result!.page, 2); // one-based 3 -> zero-based 2
    });
  });
}
