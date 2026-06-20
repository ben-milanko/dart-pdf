// Unit coverage for the print wrapper: the job-name normaliser and the
// `printPdfBytes` hand-off to the `printing` plugin. The real plugin talks over
// the `net.nfet.printing` method channel, which we mock here — driving the
// `onCompleted` callback so `Printing.layoutPdf` resolves without a platform.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

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

  test('printPdfBytes hands the document to the print plugin', () async {
    const channel = MethodChannel('net.nfet.printing');
    final messenger = binding.defaultBinaryMessenger;
    final bytes = Uint8List.fromList('%PDF-1.7'.codeUnits);

    String? sentName;
    var printPdfCalls = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method != 'printPdf') return null;
      printPdfCalls += 1;
      final args = call.arguments as Map;
      sentName = args['name'] as String?;
      // Mimic the platform finishing the job so layoutPdf's completer resolves.
      await messenger.handlePlatformMessage(
        channel.name,
        channel.codec.encodeMethodCall(
          MethodCall('onCompleted', <String, dynamic>{
            'job': args['job'],
            'completed': true,
          }),
        ),
        (_) {},
      );
      return 1;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    await printPdfBytes(bytes: bytes, title: 'Report.pdf');

    expect(printPdfCalls, 1);
    expect(sentName, 'Report'); // the .pdf-stripped job name
  });
}
