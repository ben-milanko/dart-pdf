// Print settings preview the same composed sheets that reach the system
// printer. The document remains unchanged throughout settings and file merges.
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dart_pdf_editor_app/editor_screen.dart';
import 'package:dart_pdf_editor_app/print_preview_dialog.dart';
import 'package:dart_pdf_editor_app/printing.dart';
import 'package:dart_pdf_editor_app/print_settings.dart';
import 'package:dart_pdf_editor_app/print_composer.dart';

void main() {
  test('page range parser validates every component and preserves order', () {
    expect(parsePrintPageRange('1, 3-5, 3', 5), [0, 2, 3, 4]);
    expect(parsePrintPageRange('5-3,1', 5), [4, 3, 2, 0]);
    for (final invalid in ['', '0', '6', '1,,2', '1-', '1.2', '1-6']) {
      expect(parsePrintPageRange(invalid, 5), isNull, reason: invalid);
    }
  });
  group('platformProvidesPrintPreview', () {
    test('is false exactly where the OS print flow shows nothing', () {
      expect(platformProvidesPrintPreview(platform: TargetPlatform.windows),
          isFalse);
      expect(platformProvidesPrintPreview(platform: TargetPlatform.linux),
          isFalse);
      for (final platform in [
        TargetPlatform.macOS,
        TargetPlatform.iOS,
        TargetPlatform.android,
      ]) {
        expect(platformProvidesPrintPreview(platform: platform), isTrue,
            reason: '$platform previews the job itself');
      }
    });
  });

  group('PrintPreviewDialog', () {
    late PdfDocument document;

    setUp(() => document = PdfDocument.open(buildMultiPagePdf(5)));

    /// Opens the preview over a bare app and returns a getter for its result.
    Future<PrintPreviewResult? Function()> openPreview(
      WidgetTester tester, {
      int currentPage = 0,
      List<int> selectedPages = const [],
      Future<List<PdfDocument>> Function()? addFiles,
    }) async {
      PrintPreviewResult? result;
      var closed = false;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await showPrintPreviewDialog(
                  context,
                  document: document,
                  title: 'Report.pdf',
                  currentPage: currentPage,
                  selectedPages: selectedPages,
                  addFiles: addFiles,
                );
                closed = true;
              },
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(
          find.byKey(const ValueKey('print-preview-dialog')), findsOneWidget);
      return () {
        expect(closed, isTrue, reason: 'the preview is still open');
        return result;
      };
    }

    testWidgets('previews the current page and renders it', (tester) async {
      await openPreview(tester, currentPage: 2);

      expect(find.text('Page 3 of 5'), findsOneWidget);
      expect(find.byKey(const ValueKey('print-preview-page')), findsOneWidget);
    });

    testWidgets('the arrows walk the pages', (tester) async {
      await openPreview(tester);

      expect(find.text('Page 1 of 5'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('print-preview-next')));
      await tester.pumpAndSettle();
      expect(find.text('Page 2 of 5'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('print-preview-previous')));
      await tester.pumpAndSettle();
      expect(find.text('Page 1 of 5'), findsOneWidget);
    });

    testWidgets('Print returns every page by default', (tester) async {
      final result = await openPreview(tester);

      await tester.tap(find.byKey(const ValueKey('print-preview-print')));
      await tester.pumpAndSettle();

      expect(result()!.settings.pages, [0, 1, 2, 3, 4]);
    });

    testWidgets('Current prints only the page the viewer is on',
        (tester) async {
      final result = await openPreview(tester, currentPage: 3);

      await tester
          .ensureVisible(find.byKey(const ValueKey('print-preview-current')));
      await tester.tap(find.byKey(const ValueKey('print-preview-current')));
      await tester.pumpAndSettle();
      expect(find.text('Page 4 of 5'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('print-preview-print')));
      await tester.pumpAndSettle();

      expect(result()!.settings.pages, [3]);
    });

    testWidgets('a typed range prints just that span', (tester) async {
      final result = await openPreview(tester);

      await tester
          .ensureVisible(find.byKey(const ValueKey('print-preview-range')));
      await tester.enterText(
          find.byKey(const ValueKey('print-preview-range')), '2-4');
      await tester.pumpAndSettle();
      expect(find.text('Pages to print: 3'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('print-preview-print')));
      await tester.pumpAndSettle();

      expect(result()!.settings.pages, [1, 2, 3]);
    });

    testWidgets('the preview follows a range that excludes it', (tester) async {
      await openPreview(tester, currentPage: 0);

      await tester
          .ensureVisible(find.byKey(const ValueKey('print-preview-range')));
      await tester.enterText(
          find.byKey(const ValueKey('print-preview-range')), '4-5');
      await tester.pumpAndSettle();

      // Slot 0 of the selection, not page 1 - the preview only ever shows a
      // page that will actually print.
      expect(find.text('Page 4 of 5'), findsOneWidget);
    });

    testWidgets('an out-of-bounds range is refused, not printed',
        (tester) async {
      await openPreview(tester);

      await tester
          .ensureVisible(find.byKey(const ValueKey('print-preview-range')));
      await tester.enterText(
          find.byKey(const ValueKey('print-preview-range')), '9');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('print-preview-print')));
      await tester.pumpAndSettle();

      expect(
          find.byKey(const ValueKey('print-preview-dialog')), findsOneWidget);
      expect(find.text('Enter a page range between 1 and 5.'), findsWidgets);
    });

    testWidgets('selected pages and comma-separated ranges are available',
        (tester) async {
      final result = await openPreview(tester, selectedPages: [3, 1]);
      await tester
          .ensureVisible(find.byKey(const ValueKey('print-preview-selected')));
      await tester.tap(find.byKey(const ValueKey('print-preview-selected')));
      await tester.pumpAndSettle();
      expect(find.text('Pages to print: 2'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('print-preview-print')));
      await tester.pumpAndSettle();
      expect(result()!.settings.pages, [1, 3]);
    });

    testWidgets('copies and layout are returned; Defaults resets both',
        (tester) async {
      final result = await openPreview(tester);
      await tester
          .ensureVisible(find.byKey(const ValueKey('print-options-copies')));
      await tester.enterText(
          find.byKey(const ValueKey('print-options-copies')), '3');
      await tester
          .ensureVisible(find.byKey(const ValueKey('print-options-scaling')));
      await tester.tap(find.byKey(const ValueKey('print-options-scaling')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Multiple pages per sheet').last);
      await tester.pumpAndSettle();
      expect(find.text('Sheet 1 of 3'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('print-options-defaults')));
      await tester.pumpAndSettle();
      expect(find.text('None (actual size)'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('print-preview-print')));
      await tester.pumpAndSettle();
      expect(result()!.settings.copies, 1);
      expect(result()!.settings.scaling, PrintScaling.none);
      expect(identical(result()!.document.cos, document.cos), isFalse);
      expect(document.pageCount, 5);
    });

    testWidgets('invalid numeric settings remain open until fixed',
        (tester) async {
      final result = await openPreview(tester);
      await tester
          .ensureVisible(find.byKey(const ValueKey('print-options-copies')));
      await tester.enterText(
          find.byKey(const ValueKey('print-options-copies')), '0');
      await tester.tap(find.byKey(const ValueKey('print-preview-print')));
      await tester.pumpAndSettle();
      expect(
          find.byKey(const ValueKey('print-preview-dialog')), findsOneWidget);
      expect(find.text('Enter valid numbers before printing.'), findsOneWidget);
      await tester.enterText(
          find.byKey(const ValueKey('print-options-copies')), '2');
      await tester.tap(find.byKey(const ValueKey('print-preview-print')));
      await tester.pumpAndSettle();
      expect(result()!.settings.copies, 2);
    });

    testWidgets('switching scaling modes resets invalid hidden numeric text',
        (tester) async {
      final result = await openPreview(tester);
      Future<void> scaling(String label) async {
        await tester
            .ensureVisible(find.byKey(const ValueKey('print-options-scaling')));
        await tester.tap(find.byKey(const ValueKey('print-options-scaling')));
        await tester.pumpAndSettle();
        await tester.tap(find.text(label).last);
        await tester.pumpAndSettle();
      }

      await scaling('Custom scale');
      await tester
          .ensureVisible(find.byKey(const ValueKey('print-options-scale')));
      await tester.enterText(
          find.byKey(const ValueKey('print-options-scale')), 'abc');
      await scaling('None (actual size)');
      await scaling('Custom scale');
      final scale = tester
          .widget<TextField>(find.byKey(const ValueKey('print-options-scale')));
      expect(scale.controller!.text, '100');
      await tester.tap(find.byKey(const ValueKey('print-preview-print')));
      await tester.pumpAndSettle();
      expect(result()!.settings.customScale, 100);
    });

    testWidgets(
        'margins invalid on a later smaller sheet keep the options open',
        (tester) async {
      document =
          PdfDocument.open(buildMultiPagePdf(1, width: 200, height: 250));
      final result = await openPreview(tester);
      await tester
          .ensureVisible(find.byKey(const ValueKey('print-options-scaling')));
      await tester.tap(find.byKey(const ValueKey('print-options-scaling')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Fit to margins').last);
      await tester.pumpAndSettle();
      await tester
          .ensureVisible(find.byKey(const ValueKey('print-options-margin')));
      await tester.enterText(
          find.byKey(const ValueKey('print-options-margin')), '200');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('print-preview-print')));
      await tester.pumpAndSettle();
      expect(
          find.byKey(const ValueKey('print-preview-dialog')), findsOneWidget);
      expect(
          find.text(
              'This layout could not be prepared. Check the paper size, margins and scale.'),
          findsOneWidget);
      await tester.enterText(
          find.byKey(const ValueKey('print-options-margin')), '10');
      await tester.tap(find.byKey(const ValueKey('print-preview-print')));
      await tester.pumpAndSettle();
      expect(result()!.settings.margin, 10);
    });

    testWidgets('failed additional files preserve the open job',
        (tester) async {
      final result = await openPreview(tester,
          addFiles: () async => throw const FormatException('Invalid PDF'));
      await tester
          .ensureVisible(find.byKey(const ValueKey('print-options-add-files')));
      await tester.tap(find.byKey(const ValueKey('print-options-add-files')));
      await tester.pumpAndSettle();
      expect(find.text('Could not add the selected files.'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('print-preview-print')));
      await tester.pumpAndSettle();
      expect(result()!.document.cos.bytes, document.cos.bytes);
      expect(result()!.settings.pages, [0, 1, 2, 3, 4]);
    });

    testWidgets('adding files changes only the print document', (tester) async {
      final result = await openPreview(tester,
          addFiles: () async => [PdfDocument.open(buildMultiPagePdf(2))]);
      await tester
          .ensureVisible(find.byKey(const ValueKey('print-options-add-files')));
      await tester.tap(find.byKey(const ValueKey('print-options-add-files')));
      await tester.pumpAndSettle();
      expect(find.text('Pages to print: 7'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('print-preview-print')));
      await tester.pumpAndSettle();
      expect(result()!.document.pageCount, 7);
      expect(result()!.settings.pages, [0, 1, 2, 3, 4, 5, 6]);
      expect(document.pageCount, 5);
    });

    testWidgets('a later source revision cannot change the previewed print job',
        (tester) async {
      final result = await openPreview(tester);
      final editor = PdfEditor(document);
      editor.addFreeText(0, const PdfRect(100, 100, 400, 180), 'Later edit');
      document.withIncrementalUpdate(editor.save());
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('print-preview-print')));
      await tester.pumpAndSettle();
      final job = result()!;
      expect(job.document.page(0).annotations, isEmpty);
      expect(document.page(0).annotations, hasLength(1));
      final printed =
          PdfDocument.open(preparePrintDocument(job.document, job.settings));
      expect(PdfTextExtractor.extract(printed, 0).text,
          isNot(contains('Later edit')));
    });

    testWidgets('adding a file keeps the original hidden PDF layers hidden',
        (tester) async {
      document = _layeredPrintDocument();
      final result = await openPreview(tester,
          addFiles: () async => [PdfDocument.open(buildMultiPagePdf(1))]);
      await tester
          .ensureVisible(find.byKey(const ValueKey('print-options-add-files')));
      await tester.tap(find.byKey(const ValueKey('print-options-add-files')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('print-preview-print')));
      await tester.pumpAndSettle();
      final job = result()!;
      final printed =
          PdfDocument.open(preparePrintDocument(job.document, job.settings));
      expect(printed.pageCount, 2);
      expect(PdfTextExtractor.extract(printed, 0).text,
          isNot(contains('Hidden layer')));
      expect(PdfTextExtractor.extract(printed, 1).text, contains('Page 1'));
    });

    testWidgets(
        'an encrypted snapshot retains separate document and markup choices',
        (tester) async {
      final encrypted = PdfDocument.open(
          buildEncryptedPdf(revision: 4, userPassword: 'secret'),
          password: 'secret');
      final editor = PdfEditor(encrypted)
        ..addFreeText(0, const PdfRect(100, 100, 400, 180), 'Private markup');
      document = PdfDocument.open(editor.save(), password: 'secret');
      final result = await openPreview(tester);
      await tester
          .ensureVisible(find.byKey(const ValueKey('print-options-content')));
      await tester.tap(find.byKey(const ValueKey('print-options-content')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Markups only').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('print-preview-print')));
      await tester.pumpAndSettle();
      final job = result()!;
      expect(job.document.cos.isEncrypted, isFalse);
      expect(document.cos.isEncrypted, isTrue);
      expect(job.document.page(0).annotations, hasLength(1));
      final printed =
          PdfDocument.open(preparePrintDocument(job.document, job.settings));
      final text = PdfTextExtractor.extract(printed, 0).text;
      expect(text, contains('Private markup'));
      expect(text, isNot(contains('Hello, world!')));
    });

    testWidgets('narrow screens and keyboard keep print controls reachable',
        (tester) async {
      tester.view.physicalSize = const Size(390, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final result = await openPreview(tester);
      await tester
          .ensureVisible(find.byKey(const ValueKey('print-preview-range')));
      await tester.enterText(
          find.byKey(const ValueKey('print-preview-range')), '1, 3-4');
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
          tester
              .getBottomRight(find.byKey(const ValueKey('print-preview-print')))
              .dy,
          lessThanOrEqualTo(420));
      await tester.tap(find.byKey(const ValueKey('print-preview-print')));
      await tester.pumpAndSettle();
      expect(result()!.settings.pages, [0, 2, 3]);
    });

    testWidgets('Get window crops a rectangle on the source current page',
        (tester) async {
      tester.view.physicalSize = const Size(1100, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final result = await openPreview(tester, currentPage: 2);
      await tester
          .ensureVisible(find.byKey(const ValueKey('print-options-window')));
      await tester.tap(find.byKey(const ValueKey('print-options-window')));
      await tester.pumpAndSettle();
      final page =
          tester.getRect(find.byKey(const ValueKey('print-preview-page')));
      final gesture = await tester.startGesture(
          page.topLeft + Offset(page.width * .2, page.height * .2));
      await gesture.moveBy(Offset(page.width * .5, page.height * .5));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('print-options-clear-window')),
          findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('print-preview-print')));
      await tester.pumpAndSettle();
      expect(result()!.settings.pages, [2]);
      final region = result()!.settings.region!;
      expect(region.left, closeTo(612 * .2, 1));
      expect(region.bottom, closeTo(792 * .2, 1));
      expect(region.width, closeTo(612 * .5, 1));
      expect(region.height, closeTo(792 * .5, 1));
    });

    testWidgets('Cancel prints nothing', (tester) async {
      final result = await openPreview(tester);

      await tester.tap(find.byKey(const ValueKey('print-preview-cancel')));
      await tester.pumpAndSettle();

      expect(result(), isNull);
    });
  });

  group('the editor prints through the preview', () {
    late PdfEditingPreferences prefs;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      prefs = PdfEditingPreferences();
    });
    tearDown(() => prefs.dispose());

    /// Runs [body] as Windows, where the OS print dialog previews nothing.
    /// The override has to be undone inside the test body - the framework
    /// checks for leaked debug variables before tearDown runs.
    Future<void> onWindows(Future<void> Function() body) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      try {
        await body();
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    }

    /// Opens a 4-page document and taps Print in the app menu, returning a
    /// getter for whatever eventually reaches the printer.
    Future<Uint8List? Function()> tapPrint(WidgetTester tester) async {
      Uint8List? printed;
      await tester.pumpWidget(MaterialApp(
        home: EditorScreen(
          prefs: prefs,
          initialDocument: (bytes: buildMultiPagePdf(4), title: 'Report.pdf'),
          printDocument: ({required bytes, required title}) async {
            printed = bytes;
          },
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byTooltip('DartPDF menu'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('menu-print')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('menu-print')));
      await tester.pumpAndSettle();
      return () => printed;
    }

    testWidgets('Print opens the preview before the OS print dialog',
        (tester) async {
      await onWindows(() async {
        final printed = await tapPrint(tester);

        expect(
            find.byKey(const ValueKey('print-preview-dialog')), findsOneWidget);
        expect(printed(), isNull,
            reason: 'nothing prints until the preview does');
      });
    });

    testWidgets('cancelling the preview prints nothing', (tester) async {
      await onWindows(() async {
        final printed = await tapPrint(tester);

        await tester.tap(find.byKey(const ValueKey('print-preview-cancel')));
        await tester.pumpAndSettle();

        expect(printed(), isNull);
      });
    });

    testWidgets('the whole document prints unchanged', (tester) async {
      await onWindows(() async {
        final printed = await tapPrint(tester);

        await tester.tap(find.byKey(const ValueKey('print-preview-print')));
        await tester.pumpAndSettle();

        expect(printed(), isNotNull);
        expect(PdfDocument.open(printed()!).pageCount, 4);
      });
    });

    testWidgets('a narrowed range prints an extract of those pages',
        (tester) async {
      await onWindows(() async {
        final printed = await tapPrint(tester);

        await tester
            .ensureVisible(find.byKey(const ValueKey('print-preview-range')));
        await tester.enterText(
            find.byKey(const ValueKey('print-preview-range')), '2-3');
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('print-preview-print')));
        await tester.pumpAndSettle();

        final bytes = printed();
        expect(bytes, isNotNull);
        expect(PdfDocument.open(bytes!).pageCount, 2);
      });
    });
  });
}

PdfDocument _layeredPrintDocument() {
  final builder = CosDocumentBuilder();
  final pages = CosDictionary({'Type': const CosName('Pages')});
  final parent = builder.add(pages);
  final layer = builder.add(CosDictionary({
    'Type': const CosName('OCG'),
    'Name': CosString.fromText('Hidden'),
  }));
  final bytes = Uint8List.fromList(
      '/OC /Layer BDC BT /F1 20 Tf 100 500 Td (Hidden layer) Tj ET EMC'
          .codeUnits);
  final page = builder.add(CosDictionary({
    'Type': const CosName('Page'),
    'Parent': parent,
    'MediaBox': CosArray([
      const CosInteger(0),
      const CosInteger(0),
      const CosInteger(612),
      const CosInteger(792)
    ]),
    'Contents': builder.add(
        CosStream(CosDictionary({'Length': CosInteger(bytes.length)}), bytes)),
    'Resources': CosDictionary({
      'Properties': CosDictionary({'Layer': layer}),
      'Font': CosDictionary({
        'F1': CosDictionary({
          'Type': const CosName('Font'),
          'Subtype': const CosName('Type1'),
          'BaseFont': const CosName('Helvetica'),
        })
      }),
    }),
  }));
  pages['Kids'] = CosArray([page]);
  pages['Count'] = const CosInteger(1);
  return PdfDocument.open(builder.build(
      root: builder.add(CosDictionary({
    'Type': const CosName('Catalog'),
    'Pages': parent,
    'OCProperties': CosDictionary({
      'OCGs': CosArray([layer]),
      'D': CosDictionary({
        'BaseState': const CosName('ON'),
        'OFF': CosArray([layer])
      }),
    }),
  }))));
}
