// Build the real worker before running this browser-only integration test:
// dart run dart_pdf_editor:build_web_worker --out lib/src/sparse_test_worker.js
// flutter test --platform chrome --no-cross-origin-isolation \
//   test/render_worker_sparse_web_test.dart
// Delete the generated lib/src/sparse_test_worker.js after the run.
// The shared-buffer case also runs when hosted with isolation headers. Flutter
// 3.47's test server omits COEP on the generated suite iframe, so its isolation
// flag blocks that iframe; CI exercises transferable buffers until that is fixed.
@TestOn('browser')
library;

import 'dart:typed_data';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:dart_pdf_editor/src/render_worker_web.dart' as platform;
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_graphics/pdf_graphics.dart';
import 'package:web/web.dart' as web;

import 'fixtures/sparse_worker_pdf.dart';

void main() {
  for (final shared in [false, true]) {
    test('web worker preserves sparse ranges (shared=$shared)', () async {
      final oldUrl = pdfRenderWorkerScriptUrl;
      final oldShared = platform.pdfRenderWorkerUseSharedArrayBuffer;
      pdfRenderWorkerScriptUrl = '${Uri.base.origin}'
          '/packages/dart_pdf_editor/src/sparse_test_worker.js';
      platform.pdfRenderWorkerUseSharedArrayBuffer = shared;
      addTearDown(() {
        pdfRenderWorkerScriptUrl = oldUrl;
        platform.pdfRenderWorkerUseSharedArrayBuffer = oldShared;
      });
      final fixture = sparseWorkerPdf();
      final whole =
          PdfRenderWorker.startUncached(Uint8List.fromList(fixture.bytes));
      addTearDown(whole.dispose);
      final wholeCommands = await whole.record(0);
      expect(wholeCommands, isNotNull);
      expect(wholeCommands!.whereType<PdfStrokePathCommand>(), isNotEmpty);
      expect((await whole.extractText(1))!.text, contains('Page 2'));

      final explicit = PdfRenderWorker.startUncached(fixture.bytes,
          populatedRanges: fixture.ranges);
      addTearDown(explicit.dispose);
      PdfDocument.open(fixture.bytes, populatedRanges: fixture.ranges);
      final inherited = PdfPooledRenderWorker(fixture.bytes, 2);
      addTearDown(inherited.dispose);
      for (final worker in [explicit, inherited]) {
        for (final priority in [0, -2000]) {
          final commands = await worker.record(0, priority: priority);
          expect(commands, isNotNull);
          expect(commands!.whereType<PdfStrokePathCommand>(), isEmpty,
              reason: 'worker=${worker.runtimeType}, priority=$priority');
          expect(
              (await worker.extractText(1, priority: priority))!.text, isEmpty);
          expect((await worker.extractText(2, priority: priority))!.text,
              contains('Page 3'));
        }
      }
    },
        skip: shared && !web.window.crossOriginIsolated
            ? 'SharedArrayBuffer requires an isolated test page'
            : false);
  }
}
