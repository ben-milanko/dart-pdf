// printDocumentPages renders each page with our own engine and streams it to
// the runner's `native_print` channel - the path that replaces the printing
// plugin (and its PDFium) on every native platform. The real channel needs a
// platform runner, so here we mock it and assert the begin/stream/end
// handshake.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';

import 'package:dart_pdf_editor_app/native_print_io.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dev.milanko.dartpdf/native_print');
  final messenger = binding.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  testWidgets('opens a job, streams one JPEG per page, then ends it',
      (tester) async {
    await tester.runAsync(() async {
      var begins = 0;
      var ends = 0;
      final images = <Uint8List>[];
      String? jobName;
      messenger.setMockMethodCallHandler(channel, (call) async {
        switch (call.method) {
          case 'beginJob':
            begins += 1;
            jobName = (call.arguments as Map)['name'] as String?;
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

      final doc = PdfDocument.open(buildMultiPagePdf(2));
      await printDocumentPages(doc, name: 'Report');

      expect(begins, 1);
      expect(jobName, 'Report');
      expect(ends, 1);
      expect(images, hasLength(2));
      // Each page is a JPEG: SOI marker 0xFFD8.
      for (final image in images) {
        expect(image.length, greaterThan(2));
        expect(image[0], 0xFF);
        expect(image[1], 0xD8);
      }
    });
  });

  testWidgets('a cancelled dialog (endJob false) completes without throwing',
      (tester) async {
    await tester.runAsync(() async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        switch (call.method) {
          case 'beginJob':
            return {'dpi': 72};
          case 'printPage':
            return true;
          case 'endJob':
            return false; // user cancelled the print dialog
        }
        return null;
      });

      final doc = PdfDocument.open(buildMultiPagePdf(1));
      await printDocumentPages(doc, name: 'Report'); // no throw
    });
  });

  testWidgets('propagates MissingPluginException when the channel is absent',
      (tester) async {
    await tester.runAsync(() async {
      // No mock handler: the channel is unregistered, as on a platform whose
      // runner lacks the native printer.
      final doc = PdfDocument.open(buildMultiPagePdf(1));
      await expectLater(
        printDocumentPages(doc, name: 'Report'),
        throwsA(isA<MissingPluginException>()),
      );
    });
  });

  testWidgets('aborts and throws when the printer rejects a page',
      (tester) async {
    await tester.runAsync(() async {
      var cancels = 0;
      messenger.setMockMethodCallHandler(channel, (call) async {
        switch (call.method) {
          case 'beginJob':
            return {'dpi': 72};
          case 'printPage':
            return false; // the printer rejected the page
          case 'cancelJob':
            cancels += 1;
            return null;
        }
        return null;
      });

      final doc = PdfDocument.open(buildMultiPagePdf(1));
      await expectLater(
        printDocumentPages(doc, name: 'Report'),
        throwsA(isA<PlatformException>()),
      );
      expect(cancels, 1); // the half-accumulated job is torn down
    });
  });
}
