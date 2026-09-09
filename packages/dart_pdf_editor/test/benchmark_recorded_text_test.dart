// Opt-in text-reuse benchmark; the document stays local.
// PDF_PATH=/path/to/drawing.pdf PDF_TEXT_BENCHMARK_OUT=/tmp/text-reuse.json \
//   fvm flutter test --no-pub test/benchmark_recorded_text_test.dart
// Optional PDF_TEXT_BENCHMARK_TRIALS=7. One warmup pair is excluded.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_graphics/pdf_graphics.dart';

void main() {
  testWidgets('paired recorded-text reuse on a local PDF', (tester) async {
    final path = Platform.environment['PDF_PATH'];
    if (path == null) {
      markTestSkipped('set PDF_PATH');
      return;
    }
    await tester.runAsync(() async {
      final bytes = File(path).readAsBytesSync();
      final pageIndex = int.parse(Platform.environment['PDF_PAGE'] ?? '0');
      final trials =
          int.parse(Platform.environment['PDF_TEXT_BENCHMARK_TRIALS'] ?? '7');
      expect(trials, greaterThan(0));
      final recordTimes = {false: <double>[], true: <double>[]};
      final captureTimes = <double>[];
      final recordAndCaptureTimes = <double>[];
      PdfRecordedText? metadata;
      Uint8List? renderOracle;
      var commandsCount = 0;
      var renderWireBytes = 0;
      for (var trial = 0; trial <= trials; trial++) {
        for (final collect in trial.isEven ? [false, true] : [true, false]) {
          // Both variants start from a fresh COS/font cache. File IO and
          // opening the document/page are outside the recording clock.
          final document = PdfDocument.open(bytes);
          final page = document.page(pageIndex);
          final recorder = RecordingPdfDevice();
          final clock = Stopwatch()..start();
          PdfInterpreter(
                  cos: document.cos,
                  device: recorder,
                  collectCharOffsets: collect)
              .drawPage(page);
          final recordMs = clock.elapsedMicroseconds / 1000;
          clock.reset();
          if (collect) metadata = PdfRecordedText.capture(recorder.commands);
          final captureMs = clock.elapsedMicroseconds / 1000;
          commandsCount = recorder.commands.length;
          if (trial > 0) {
            recordTimes[collect]!.add(recordMs);
            if (collect) {
              captureTimes.add(captureMs);
              recordAndCaptureTimes.add(recordMs + captureMs);
            }
          } else {
            // Render serialization intentionally omits extraction-only
            // metadata; exact byte equality catches any visible-wire drift.
            final wire = serializeCommands(recorder.commands,
                cos: document.cos, compactStateScopes: true)!;
            if (renderOracle == null) {
              renderOracle = wire;
            } else {
              expect(_sameBytes(renderOracle, wire), isTrue,
                  reason: 'capturing text must not change render wire bytes');
              renderWireBytes = wire.length;
              renderOracle = null;
            }
          }
        }
      }
      final captured = metadata!;
      final freshTimes = <double>[];
      final reuseTimes = <double>[];
      final extractionDocument = PdfDocument.open(bytes);
      Uint8List? textOracle;
      var runCount = 0, textCharacters = 0;
      for (var trial = 0; trial <= trials; trial++) {
        for (final reuse in trial.isEven ? [false, true] : [true, false]) {
          final clock = Stopwatch()..start();
          final text = reuse
              ? PdfTextExtractor.fromRecordedText(captured, pageIndex)
              : PdfTextExtractor.extract(extractionDocument, pageIndex);
          final elapsed = clock.elapsedMicroseconds / 1000;
          runCount = text.runs.length;
          textCharacters = text.text.length;
          final serialized = serializePageText(text);
          textOracle ??= serialized;
          expect(_sameBytes(textOracle, serialized), isTrue,
              reason: 'reused text must preserve exact extraction bytes');
          if (trial > 0) (reuse ? reuseTimes : freshTimes).add(elapsed);
        }
      }
      // Separate uncached workers rule out the UI wrapper's extraction cache.
      // Recording is complete (with images), and only the immediate extraction
      // after it benefits from metadata published inside that worker.
      final workerFreshTimes = <double>[];
      final workerRecordTimes = <double>[];
      final workerReuseTimes = <double>[];
      for (var trial = 0; trial <= trials; trial++) {
        for (final reuse in trial.isEven ? [false, true] : [true, false]) {
          final worker = PdfRenderWorker.startUncached(bytes);
          try {
            var recordMs = 0.0;
            if (reuse) {
              final clock = Stopwatch()..start();
              final commands = await worker.record(pageIndex,
                  imagePixelRatio: 2, annotations: false);
              expect(commands, isNotNull);
              recordMs = clock.elapsedMicroseconds / 1000;
            }
            final clock = Stopwatch()..start();
            final text = await worker.extractText(pageIndex);
            final elapsed = clock.elapsedMicroseconds / 1000;
            expect(text, isNotNull);
            expect(_sameBytes(textOracle!, serializePageText(text!)), isTrue,
                reason: 'the real worker must preserve exact extraction bytes');
            if (trial > 0) {
              if (reuse) {
                workerRecordTimes.add(recordMs);
                workerReuseTimes.add(elapsed);
              } else {
                workerFreshTimes.add(elapsed);
              }
            }
          } finally {
            worker.dispose();
          }
        }
      }
      final result = {
        'pageIndex': pageIndex,
        'commands': commandsCount,
        'textRuns': runCount,
        'textCharacters': textCharacters,
        'warmupPairs': 1,
        'measuredPairs': trials,
        'renderWireIdentical': true,
        'renderWireBytes': renderWireBytes,
        'textBytesIdentical': true,
        'textWireBytes': textOracle!.length,
        'recordedTextEstimatedBytes': captured.estimatedBytes,
        'recordWithoutOffsetsMs': _stats(recordTimes[false]!),
        'recordWithOffsetsMs': _stats(recordTimes[true]!),
        'captureMs': _stats(captureTimes),
        'recordWithOffsetsAndCaptureMs': _stats(recordAndCaptureTimes),
        'freshExtractionMs': _stats(freshTimes),
        'reusedExtractionMs': _stats(reuseTimes),
        'workerColdExtractionMs': _stats(workerFreshTimes),
        'workerRecordMs': _stats(workerRecordTimes),
        'workerExtractionAfterRecordMs': _stats(workerReuseTimes),
        'estimatedRecordPlusTextMs': {
          'before': _median(recordTimes[false]!) + _median(freshTimes),
          'after': _median(recordAndCaptureTimes) + _median(reuseTimes),
          'note':
              'Sum of separately measured phase medians, not an end-to-end elapsed sample.',
        },
        'workerTimingNote':
            'Cold extraction includes worker startup. Record includes startup, image decoding and wire transfer; extraction after record uses the already-running worker.',
      };
      final json = const JsonEncoder.withIndent('  ').convert(result);
      final out = Platform.environment['PDF_TEXT_BENCHMARK_OUT'];
      if (out != null) File(out).writeAsStringSync(json);
      // ignore: avoid_print
      print(json);
    });
  }, timeout: const Timeout(Duration(minutes: 10)));
}

Map<String, Object> _stats(List<double> values) {
  return {'median': _median(values), 'samples': values};
}

double _median(List<double> values) {
  final sorted = values.toList()..sort();
  return sorted[sorted.length ~/ 2];
}

bool _sameBytes(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
