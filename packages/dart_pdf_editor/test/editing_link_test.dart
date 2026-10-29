import 'package:material_ui/material_ui.dart';
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

    test('a box link carries a link badge; a text link does not', () {
      final editing = controller();
      addTearDown(editing.dispose);
      editing.addLink(
        0,
        const [PdfRect(72, 640, 272, 735)],
        const PdfLinkTarget.uri('https://example.com'),
      );
      editing.addLinkToSelection(
        const {
          0: [PdfRect(72, 500, 272, 520)],
        },
        const PdfLinkTarget.uri('https://example.com'),
      );
      String appearance(PdfAnnotation link) {
        return String.fromCharCodes(
            editing.document.cos.decodeStreamData(link.normalAppearance!));
      }

      final links = editing.document.page(0).annotations;
      expect(appearance(links[0]), contains(' cm'));
      expect(appearance(links[1]), isNot(contains(' cm')));
    });

    test('iconColor: -1 drops the badge but keeps the border', () {
      final editing = controller();
      addTearDown(editing.dispose);
      editing.addLink(
        0,
        const [PdfRect(72, 640, 272, 735)],
        const PdfLinkTarget.uri('https://example.com'),
        borderColor: PdfAnnotationEditing.defaultLinkColor,
        iconColor: -1,
      );
      final link = editing.document.page(0).annotations.single;
      final content = String.fromCharCodes(
          editing.document.cos.decodeStreamData(link.normalAppearance!));
      expect(content, isNot(contains(' cm')));
      expect(link.color, PdfAnnotationEditing.defaultLinkColor);
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

    test('linkAnnotationAt + editLink re-point an existing link', () {
      final editing = controller(3);
      addTearDown(editing.dispose);
      editing.addLink(
        0,
        const [PdfRect(72, 715, 200, 735)],
        const PdfLinkTarget.uri('https://example.com'),
      );
      expect(editing.linkAnnotationAt(0, 10, 10), isNull);
      final (slot, _) = editing.linkAnnotationAt(0, 100, 720)!;
      expect(editing.linkTargetAt(0, slot)?.uri, 'https://example.com');

      expect(
          editing.editLink(0, slot, const PdfLinkTarget.uri('https://b.test')),
          isTrue);
      var link = editing.document.page(0).annotations.single;
      expect((link.action as PdfUriAction).uri, 'https://b.test');
      // the decoration and region stay
      expect(link.rect, const PdfRect(72, 715, 200, 735));
      expect(link.normalAppearance, isNotNull);

      expect(editing.editLink(0, slot, const PdfLinkTarget.page(2)), isTrue);
      link = editing.document.page(0).annotations.single;
      expect((link.action as PdfGoToAction).destination.pageIndex, 2);
      expect(editing.linkTargetAt(0, slot)?.page, 2);

      editing.undo();
      link = editing.document.page(0).annotations.single;
      expect((link.action as PdfUriAction).uri, 'https://b.test');
    });

    test('editLink refuses a non-link slot and an empty URI', () {
      final editing = controller();
      addTearDown(editing.dispose);
      editing.addNote(0, 100, 100, 'note');
      editing.addLink(
        0,
        const [PdfRect(72, 715, 200, 735)],
        const PdfLinkTarget.uri('https://example.com'),
      );
      expect(editing.editLink(0, 0, const PdfLinkTarget.uri('https://x')),
          isFalse);
      expect(editing.editLink(0, 1, const PdfLinkTarget.uri('')), isFalse);
      expect(editing.linkTargetAt(0, 0), isNull);
    });
  });

  group('edit-link menu', () {
    Future<void> openMenu(
        WidgetTester tester, PdfEditingController editing) async {
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates:
            DartPdfEditorLocalizations.localizationsDelegates,
        supportedLocales: DartPdfEditorLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showPdfAnnotationMenu(
                context: context,
                position: const Offset(100, 100),
                controller: editing,
                pageIndex: 0,
                linkTarget: (0, 0),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('Edit link pre-fills the dialog and re-points the link',
        (tester) async {
      final editing = controller(3);
      addTearDown(editing.dispose);
      editing.addLink(
        0,
        const [PdfRect(72, 715, 200, 735)],
        const PdfLinkTarget.uri('https://old.test'),
      );
      await openMenu(tester, editing);
      await tester.tap(find.byKey(const ValueKey('pdf-annot-menu-edit-link')));
      await tester.pumpAndSettle();

      expect(find.text('Edit link'), findsOneWidget);
      final field = find.byKey(const ValueKey('pdf-link-url'));
      expect(
          tester.widget<TextField>(field).controller!.text, 'https://old.test');
      await tester.enterText(field, 'https://new.test');
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      final link = editing.document.page(0).annotations.single;
      expect((link.action as PdfUriAction).uri, 'https://new.test');
    });

    testWidgets('an internal link opens on its page', (tester) async {
      final editing = controller(3);
      addTearDown(editing.dispose);
      editing.addLink(
        0,
        const [PdfRect(72, 715, 200, 735)],
        const PdfLinkTarget.page(1),
      );
      await openMenu(tester, editing);
      await tester.tap(find.byKey(const ValueKey('pdf-annot-menu-edit-link')));
      await tester.pumpAndSettle();

      final field = find.byKey(const ValueKey('pdf-link-page'));
      expect(tester.widget<TextField>(field).controller!.text, '2');
      await tester.enterText(field, '3');
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      final link = editing.document.page(0).annotations.single;
      expect((link.action as PdfGoToAction).destination.pageIndex, 2);
    });

    testWidgets('Remove link deletes it', (tester) async {
      final editing = controller();
      addTearDown(editing.dispose);
      editing.addLink(
        0,
        const [PdfRect(72, 715, 200, 735)],
        const PdfLinkTarget.uri('https://old.test'),
      );
      await openMenu(tester, editing);
      await tester
          .tap(find.byKey(const ValueKey('pdf-annot-menu-remove-link')));
      await tester.pumpAndSettle();
      expect(editing.document.page(0).annotations, isEmpty);
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

      await tester.enterText(
          find.byKey(const ValueKey('pdf-link-url')), 'https://example.com');
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
      await tester.enterText(find.byKey(const ValueKey('pdf-link-page')), '3');
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.isExternal, isFalse);
      expect(result!.page, 2); // one-based 3 -> zero-based 2
    });
  });
}
