import 'dart:async';
import 'package:dart_pdf_printing/dart_pdf_printing.dart';
// Unit coverage for the print wrapper: the job-name normaliser and the
// `printPdfBytes` hand-off to the native `native_print` channel (which every
// platform runner registers, replacing the printing plugin / PDFium). The real
// runner is unavailable under `flutter test`, so we mock the channel.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';

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
    const channel = MethodChannel('dev.milanko.dart_pdf_printing');
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

  test('overlapping jobs fail without replacing the active job', () async {
    const channel = MethodChannel('dev.milanko.dart_pdf_printing');
    final messenger = binding.defaultBinaryMessenger;
    final first = Completer<bool>();
    var calls = 0;
    messenger.setMockMethodCallHandler(channel, (call) {
      calls++;
      return calls == 1 ? first.future : Future.value(true);
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final pending = printPdfBytes(bytes: buildClassicPdf(), title: 'First');
    await expectLater(
      printPdfBytes(bytes: buildClassicPdf(), title: 'Second'),
      throwsA(isA<PlatformException>()
          .having((e) => e.code, 'code', 'print_in_progress')),
    );
    expect(calls, 1);
    first.complete(false);
    await pending;
    await printPdfBytes(bytes: buildClassicPdf(), title: 'Next');
    expect(calls, 2);
  });

  test('a failed native job releases the next print attempt', () async {
    const channel = MethodChannel('dev.milanko.dart_pdf_printing');
    final messenger = binding.defaultBinaryMessenger;
    var fail = true;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (fail) throw PlatformException(code: 'native_failure');
      return true;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    await expectLater(printPdfBytes(bytes: buildClassicPdf(), title: 'First'),
        throwsA(isA<PlatformException>()));
    fail = false;
    await printPdfBytes(bytes: buildClassicPdf(), title: 'Next');
  });

  test('prepared sheets opt out of another native fit', () async {
    const channel = MethodChannel('dev.milanko.dart_pdf_printing');
    final messenger = binding.defaultBinaryMessenger;
    Map? args;
    messenger.setMockMethodCallHandler(channel, (call) async {
      args = call.arguments as Map;
      return true;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    await printPdfBytes(
      bytes: buildMultiPagePdf(1),
      title: 'Prepared.pdf',
      useDocumentPageSize: true,
    );
    expect(args?['useDocumentPageSize'], isTrue);
    expect(args?['pageWidth'], 612);
    expect(args?['pageHeight'], 792);
  });
}
