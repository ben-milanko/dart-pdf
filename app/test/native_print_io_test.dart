// printDocumentPages prints a PDF through the platform runner: natively as
// vector where the OS can (printPdf), else by rasterising each page and
// streaming it (beginJob/printPage/endJob) on Windows/Linux. The real channel
// needs a runner, so here we mock it and assert both paths.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';

import 'package:dart_pdf_editor_app/native_print_io.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dev.milanko.dartpdf/native_print');
  final messenger = binding.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('prints the PDF as vector via printPdf when supported', () async {
    Uint8List? sentPdf;
    String? name;
    var beginJobs = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'printPdf':
          final args = call.arguments as Map;
          sentPdf = args['pdf'] as Uint8List;
          name = args['name'] as String?;
          return true;
        case 'beginJob':
          beginJobs += 1;
          return {'dpi': 72};
      }
      return null;
    });

    final pdf = Uint8List.fromList('%PDF-1.7 vector'.codeUnits);
    await printDocumentPages(pdf, name: 'Report');

    expect(sentPdf, pdf); // the whole document went over verbatim
    expect(name, 'Report');
    expect(beginJobs, 0); // never rasterised
  });

  test('a cancelled vector dialog completes without rasterising', () async {
    var beginJobs = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'printPdf':
          return false; // user cancelled the native print dialog
        case 'beginJob':
          beginJobs += 1;
          return {'dpi': 72};
      }
      return null;
    });

    await printDocumentPages(
        Uint8List.fromList('%PDF-1.7'.codeUnits), name: 'Report');
    expect(beginJobs, 0);
  });

  testWidgets('falls back to rasterising when printPdf is unimplemented',
      (tester) async {
    await tester.runAsync(() async {
      var ends = 0;
      final images = <Uint8List>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        switch (call.method) {
          case 'printPdf':
            throw MissingPluginException('no printPdf on this platform');
          case 'beginJob':
            return {'dpi': 72};
          case 'printPage':
            images.add((call.arguments as Map)['image'] as Uint8List);
            return true;
          case 'endJob':
            ends += 1;
            return true;
        }
        return null;
      });

      final progress = <(int, int)>[];
      await printDocumentPages(buildMultiPagePdf(2), name: 'Report',
          onProgress: (rendered, total) => progress.add((rendered, total)));

      expect(images, hasLength(2));
      for (final image in images) {
        expect(image[0], 0xFF); // JPEG SOI
        expect(image[1], 0xD8);
      }
      expect(ends, 1);
      expect(progress, [(1, 2), (2, 2)]);
    });
  });

  testWidgets('propagates MissingPluginException when there is no printer',
      (tester) async {
    await tester.runAsync(() async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        // Neither native PDF printing nor rasterising is available.
        throw MissingPluginException('no native printer');
      });

      await expectLater(
        printDocumentPages(buildMultiPagePdf(1), name: 'Report'),
        throwsA(isA<MissingPluginException>()),
      );
    });
  });

  testWidgets('aborts and throws when the printer rejects a rastered page',
      (tester) async {
    await tester.runAsync(() async {
      var cancels = 0;
      messenger.setMockMethodCallHandler(channel, (call) async {
        switch (call.method) {
          case 'printPdf':
            throw MissingPluginException('no printPdf');
          case 'beginJob':
            return {'dpi': 72};
          case 'printPage':
            return false; // rejected
          case 'cancelJob':
            cancels += 1;
            return null;
        }
        return null;
      });

      await expectLater(
        printDocumentPages(buildMultiPagePdf(1), name: 'Report'),
        throwsA(isA<PlatformException>()),
      );
      expect(cancels, 1);
    });
  });
}
