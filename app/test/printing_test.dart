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

  test('printPdfBytes hands the document to the runner as vector', () async {
    const channel = MethodChannel('dev.milanko.dartpdf/native_print');
    final messenger = binding.defaultBinaryMessenger;

    Uint8List? sentPdf;
    String? jobName;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'printPdf') {
        final args = call.arguments as Map;
        sentPdf = args['pdf'] as Uint8List;
        jobName = args['name'] as String?;
        return true;
      }
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    final bytes = buildClassicPdf();
    await printPdfBytes(bytes: bytes, title: 'Report.pdf');

    expect(sentPdf, bytes); // the document went over as vector
    expect(jobName, 'Report'); // the .pdf-stripped job name
  });
}
