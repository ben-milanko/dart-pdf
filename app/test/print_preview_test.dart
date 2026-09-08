// Print settings preview the same composed sheets that reach the system
// printer. The document remains unchanged throughout settings and file merges.
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dart_pdf_editor_app/editor_screen.dart';

void main() {
  group('the editor prints through the preview', () {
    late PdfEditingPreferences prefs;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      prefs = PdfEditingPreferences();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
              const MethodChannel('dev.milanko.dart_pdf_printing'),
              (call) async => switch (call.method) {
                    'listPrinters' => [
                        {'name': 'Office', 'isDefault': true}
                      ],
                    'printerSettings' => {
                        'color': true,
                        'duplex': 'simplex',
                        'tray': 0,
                      },
                    _ => null,
                  });
    });
    tearDown(() {
      prefs.dispose();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
              const MethodChannel('dev.milanko.dart_pdf_printing'), null);
    });

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

    testWidgets('Print opens the preview before printing', (tester) async {
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
