// DartPDF previews a print job itself on the platforms whose print flow has no
// preview of its own - Windows (whose modern dialog answers a legacy print API
// with "This app doesn't support print preview") and Linux. These cover the
// preview dialog's own behaviour and the editor wiring around it: the range
// chosen here is what reaches the printer.
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dart_pdf_editor_app/editor_screen.dart';
import 'package:dart_pdf_editor_app/print_preview_dialog.dart';
import 'package:dart_pdf_editor_app/printing.dart';

void main() {
  group('platformProvidesPrintPreview', () {
    test('is false exactly where the OS print flow shows nothing', () {
      expect(platformProvidesPrintPreview(platform: TargetPlatform.windows),
          isFalse);
      expect(
          platformProvidesPrintPreview(platform: TargetPlatform.linux), isFalse);
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
    Future<List<int>? Function()> openPreview(
      WidgetTester tester, {
      int currentPage = 0,
    }) async {
      List<int>? result;
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
      expect(find.byKey(const ValueKey('print-preview-dialog')), findsOneWidget);
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

      expect(result(), [0, 1, 2, 3, 4]);
    });

    testWidgets('Current prints only the page the viewer is on',
        (tester) async {
      final result = await openPreview(tester, currentPage: 3);

      await tester.tap(find.byKey(const ValueKey('print-preview-current')));
      await tester.pumpAndSettle();
      expect(find.text('Page 4 of 5'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('print-preview-print')));
      await tester.pumpAndSettle();

      expect(result(), [3]);
    });

    testWidgets('a typed range prints just that span', (tester) async {
      final result = await openPreview(tester);

      await tester.enterText(
          find.byKey(const ValueKey('print-preview-from')), '2');
      await tester.enterText(
          find.byKey(const ValueKey('print-preview-to')), '4');
      await tester.pumpAndSettle();
      expect(find.text('Pages to print: 3'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('print-preview-print')));
      await tester.pumpAndSettle();

      expect(result(), [1, 2, 3]);
    });

    testWidgets('the preview follows a range that excludes it', (tester) async {
      await openPreview(tester, currentPage: 0);

      await tester.enterText(
          find.byKey(const ValueKey('print-preview-from')), '4');
      await tester.enterText(
          find.byKey(const ValueKey('print-preview-to')), '5');
      await tester.pumpAndSettle();

      // Slot 0 of the selection, not page 1 - the preview only ever shows a
      // page that will actually print.
      expect(find.text('Page 4 of 5'), findsOneWidget);
    });

    testWidgets('an out-of-bounds range is refused, not printed',
        (tester) async {
      await openPreview(tester);

      await tester.enterText(
          find.byKey(const ValueKey('print-preview-from')), '9');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('print-preview-print')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('print-preview-dialog')), findsOneWidget);
      expect(find.text('Enter a page range between 1 and 5.'), findsOneWidget);
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

        await tester.enterText(
            find.byKey(const ValueKey('print-preview-from')), '2');
        await tester.enterText(
            find.byKey(const ValueKey('print-preview-to')), '3');
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
