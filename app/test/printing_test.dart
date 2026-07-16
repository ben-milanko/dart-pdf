// Unit coverage for the print wrapper: the job-name normaliser and the
// `printPdfBytes` hand-off to the native `native_print` channel (which every
// platform runner registers, replacing the printing plugin / PDFium). The real
// runner is unavailable under `flutter test`, so we mock the channel.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';

import 'package:dart_pdf_editor_app/printing.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  group('printJobName', () {
    test('strips a trailing .pdf, case-insensitively', () {
      expect(printJobName('Report.pdf'), 'Report');
      expect(printJobName('SCAN.PDF'), 'SCAN');
    });

    test('trims surrounding whitespace', () {
      expect(printJobName('  Quarterly.pdf  '), 'Quarterly');
    });

    test('keeps a name that has no extension', () {
      expect(printJobName('Untitled'), 'Untitled');
    });

    test('falls back to Document when nothing is left', () {
      expect(printJobName('   '), 'Document');
      expect(printJobName('.pdf'), 'Document');
    });
  });

  testWidgets('printPdfBytes renders and streams the document to the runner',
      (tester) async {
    await tester.runAsync(() async {
      const channel = MethodChannel('dev.milanko.dartpdf/native_print');
      final messenger = binding.defaultBinaryMessenger;

      var begins = 0;
      var pages = 0;
      var ends = 0;
      String? jobName;
      messenger.setMockMethodCallHandler(channel, (call) async {
        switch (call.method) {
          case 'beginJob':
            begins += 1;
            jobName = (call.arguments as Map)['name'] as String?;
            return {'dpi': 72};
          case 'printPage':
            pages += 1;
            return true;
          case 'endJob':
            ends += 1;
            return true;
        }
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

      final progress = <(int, int)>[];
      await printPdfBytes(
        bytes: buildClassicPdf(),
        title: 'Report.pdf',
        onProgress: (rendered, total) => progress.add((rendered, total)),
      );

      expect(begins, 1);
      expect(jobName, 'Report'); // the .pdf-stripped job name
      expect(pages, greaterThanOrEqualTo(1));
      expect(ends, 1);
      // Progress is reported per page and reaches total on the last page.
      expect(progress, isNotEmpty);
      expect(progress.last.$1, progress.last.$2);
    });
  });
}
