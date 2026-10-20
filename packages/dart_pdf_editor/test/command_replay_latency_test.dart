// Main-isolate worker-buffer diagnostic for issue #216.
//
// Skips without the local corpus. Run from packages/dart_pdf_editor:
//
//   COMMAND_REPLAY_PDF=../../corpus/ly9-far-cad.pdf \
//   COMMAND_REPLAY_PAGE=4 \
//     fvm flutter test test/command_replay_latency_test.dart
import 'dart:io';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_cos/perf.dart';
import 'package:pdf_graphics/pdf_graphics.dart';

void main() {
  final path = Platform.environment['COMMAND_REPLAY_PDF'] ??
      '../../corpus/ly9-far-cad.pdf';
  final requestedPage =
      int.tryParse(Platform.environment['COMMAND_REPLAY_PAGE'] ?? '') ?? 4;
  final passes =
      int.tryParse(Platform.environment['COMMAND_REPLAY_PASSES'] ?? '') ?? 8;

  testWidgets('worker command decode and replay latency', (tester) async {
    final file = File(path);
    if (!file.existsSync()) {
      markTestSkipped('missing corpus PDF: $path');
      return;
    }

    await tester.runAsync(() async {
      PdfPerf.enabled = true;
      PdfPerf.reset();
      final bytes = file.readAsBytesSync();
      final document = PdfDocument.open(bytes);
      final pageIndex = requestedPage.clamp(0, document.pageCount - 1);
      final page = document.page(pageIndex);
      final offThreadVector = PdfRenderTrace.captureOffThread(
        document,
        pageIndex,
        decodeImages: false,
      );
      final offThreadFull = PdfRenderTrace.captureOffThread(
        PdfDocument.open(bytes),
        pageIndex,
        decodeImages: true,
      );
      final rawSizes = <(int, int)>[
        for (var i = 0; i < document.pageCount; i++)
          (i, document.page(i).rawContentLength),
      ]..sort((a, b) => b.$2.compareTo(a.$2));
      final coldWorker = PdfRenderWorker.startUncached(bytes);
      final coldClock = Stopwatch()..start();
      final coldCommands = await coldWorker.record(
        pageIndex,
        imagePixelRatio: 1.3,
      );
      coldClock.stop();
      final coldTrace = coldWorker.lastRenderTrace?.copy();
      coldWorker.dispose();
      final worker = PdfRenderWorker.startUncached(bytes);
      addTearDown(worker.dispose);
      addTearDown(() {
        CanvasPdfDevice.debugReuseSolidPaints = true;
        CanvasPdfDevice.debugDrawSimpleLines = true;
      });

      Future<List<PdfRenderCommand>> record(bool decodeImages) async {
        final commands = await worker.record(
          pageIndex,
          decodeImages: decodeImages,
        );
        expect(commands, isNotNull);
        return commands!;
      }

      Future<(List<PdfRenderCommand>, double)> measure(
          bool decodeImages) async {
        const samples = 3;
        await record(decodeImages); // warm the decoder/JIT for this shape
        final before = deserializeCommandsMicros;
        late List<PdfRenderCommand> commands;
        for (var i = 0; i < samples; i++) {
          commands = await record(decodeImages);
        }
        return (
          commands,
          (deserializeCommandsMicros - before) / samples / 1000,
        );
      }

      final vector = await measure(false);
      final full = await measure(true);
      Future<double> replay(
          {required bool reusePaints, required bool simpleLines}) async {
        CanvasPdfDevice.debugReuseSolidPaints = reusePaints;
        CanvasPdfDevice.debugDrawSimpleLines = simpleLines;
        var micros = 0;
        for (var pass = -2; pass < passes; pass++) {
          final sw = Stopwatch()..start();
          final picture = await PdfPageRenderer.pictureFromCommands(
            page,
            vector.$1,
            includeImages: false,
          );
          final elapsed = sw.elapsedMicroseconds;
          picture.dispose();
          if (pass >= 0) micros += elapsed;
        }
        return micros / passes / 1000;
      }

      final baseline = await replay(reusePaints: false, simpleLines: false);
      final preparedPaint = await replay(reusePaints: true, simpleLines: false);
      final optimized = await replay(reusePaints: true, simpleLines: true);
      CanvasPdfDevice.debugReuseSolidPaints = true;
      CanvasPdfDevice.debugDrawSimpleLines = true;

      final histogram = <String, int>{};
      var nestedCommands = 0;
      var tiledOrigins = 0;
      var outlinedTextRuns = 0;
      var substitutedTextRuns = 0;
      var outlineGlyphs = 0;
      var batchableOutlineRuns = 0;
      var outlineBatches = 0;
      String? outlineBatchKey;
      void countCommands(List<PdfRenderCommand> commands,
          {bool nested = false}) {
        for (final command in commands) {
          final name = command.runtimeType.toString();
          histogram[name] = (histogram[name] ?? 0) + 1;
          if (nested) nestedCommands++;
          switch (command) {
            case PdfDrawTextCommand(:final run):
              final glyphs = run.glyphs;
              if (glyphs == null) {
                substitutedTextRuns++;
                outlineBatchKey = null;
                break;
              }
              outlinedTextRuns++;
              outlineGlyphs += glyphs.length;
              if (!run.invisible &&
                  run.fill &&
                  run.gradient == null &&
                  run.strokeColor == null) {
                batchableOutlineRuns++;
                final color = run.color;
                final key = '${color.red},${color.green},${color.blue}';
                if (outlineBatchKey != key) outlineBatches++;
                outlineBatchKey = key;
              } else {
                outlineBatchKey = null;
              }
            case PdfEndSoftMaskedCommand(:final maskCommands):
              outlineBatchKey = null;
              countCommands(maskCommands, nested: true);
            case PdfDrawTiledCellCommand(
                :final cellCommands,
                :final originsX,
              ):
              outlineBatchKey = null;
              tiledOrigins += originsX.length;
              countCommands(cellCommands, nested: true);
            default:
              outlineBatchKey = null;
              break;
          }
        }
      }

      countCommands(full.$1);
      final orderedHistogram = histogram.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      // ignore: avoid_print
      print(
          '\nworker command latency: ${file.uri.pathSegments.last}#$pageIndex');
      // ignore: avoid_print
      print('portable cold vector=${offThreadVector?.format() ?? 'declined'}');
      // ignore: avoid_print
      print('portable vector COS=${offThreadVector?.cosStats?.format()}');
      // ignore: avoid_print
      print('portable cold full=${offThreadFull?.format() ?? 'declined'}');
      // ignore: avoid_print
      print('native worker cold full='
          '${(coldClock.elapsedMicroseconds / 1000).toStringAsFixed(1)}ms '
          '${coldTrace?.format() ?? 'declined'} '
          'commands=${coldCommands?.length ?? 0}');
      // ignore: avoid_print
      print('vector commands=${vector.$1.length} '
          'decode=${vector.$2.toStringAsFixed(1)}ms; '
          'full commands=${full.$1.length} '
          'decode=${full.$2.toStringAsFixed(1)}ms; '
          'canvas baseline=${baseline.toStringAsFixed(1)}ms '
          'preparedPaint=${preparedPaint.toStringAsFixed(1)}ms '
          'directLines=${optimized.toStringAsFixed(1)}ms');
      // ignore: avoid_print
      print('command histogram (nested=$nestedCommands, '
          'tiledOrigins=$tiledOrigins): '
          '${orderedHistogram.map((entry) => '${entry.key}=${entry.value}').join(', ')}');
      // ignore: avoid_print
      print('text outlines=$outlinedTextRuns substituted=$substitutedTextRuns '
          'glyphs=$outlineGlyphs batchable=$batchableOutlineRuns '
          'batches=$outlineBatches');
      final rawSummary = rawSizes
          .take(16)
          .map((entry) => 'p${entry.$1}=${entry.$2}B')
          .join(', ');
      // ignore: avoid_print
      print('largest raw streams: $rawSummary');
    });
  }, timeout: const Timeout(Duration(minutes: 10)));
}
