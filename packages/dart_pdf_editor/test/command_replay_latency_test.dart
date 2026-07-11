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
import 'package:pdf_document/pdf_document.dart';
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
      final bytes = file.readAsBytesSync();
      final document = PdfDocument.open(bytes);
      final pageIndex = requestedPage.clamp(0, document.pageCount - 1);
      final page = document.page(pageIndex);
      final worker = PdfRenderWorker.startUncached(bytes);
      addTearDown(worker.dispose);

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
      var replayMicros = 0;
      for (var pass = -2; pass < passes; pass++) {
        final sw = Stopwatch()..start();
        final picture = await PdfPageRenderer.pictureFromCommands(
          page,
          vector.$1,
          includeImages: false,
        );
        final elapsed = sw.elapsedMicroseconds;
        picture.dispose();
        if (pass >= 0) replayMicros += elapsed;
      }

      // ignore: avoid_print
      print(
          '\nworker command latency: ${file.uri.pathSegments.last}#$pageIndex');
      // ignore: avoid_print
      print('vector commands=${vector.$1.length} '
          'decode=${vector.$2.toStringAsFixed(1)}ms; '
          'full commands=${full.$1.length} '
          'decode=${full.$2.toStringAsFixed(1)}ms; '
          'vector picture='
          '${(replayMicros / passes / 1000).toStringAsFixed(1)}ms');
    });
  }, timeout: const Timeout(Duration(minutes: 10)));
}
