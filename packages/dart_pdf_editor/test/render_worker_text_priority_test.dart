import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';

void main() {
  for (final wrapped in [false, true]) {
    testWidgets(
        'search promotes queued text without another walk (wrapped=$wrapped)',
        (tester) async {
      await tester.runAsync(() async {
        final backend = PdfRenderWorker.startUncached(buildMultiPagePdf(2));
        final worker = wrapped
            ? PdfCachingRenderWorker(
                PdfPooledRenderWorker.fromWorkers([backend]))
            : backend;
        try {
          // Queue before yielding to any reply. An urgent record occupies the
          // worker; ordinary records precede a speculative text request.
          final order = <String>[];
          final pending = <Future<void>>[
            worker.record(0, priority: -1).then((_) => order.add('first')),
            for (var i = 0; i < 3; i++)
              worker
                  .record(0, priority: 1, imagePixelRatio: i + 1.0)
                  .then((_) => order.add('record$i')),
            worker.extractText(1, priority: 3).then((text) {
              expect(text!.text, contains('Page 2'));
              order.add('text');
            }),
          ];
          worker.promoteTextExtraction(1);
          worker.promoteTextExtraction(1, priority: 9); // never demote
          await Future.wait(pending);
          expect(order, hasLength(5));
          expect(order.indexOf('text'), 1,
              reason: 'search must precede queued ordinary/background records');
        } finally {
          worker.dispose();
        }
      });
    });
  }
}
