// Batch-renders the first page of every PDF in a directory to PNGs.
// Not a CI test: skipped unless CORPUS_DIR is set.
//
//   CORPUS_DIR=../../corpus RENDER_OUT=../../corpus/renders \
//     flutter test test/corpus_render_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';

import 'render_smoke_test.dart' show loadSystemFonts;

void main() {
  final corpusDir = Platform.environment['CORPUS_DIR'];

  testWidgets('renders page 1 of every corpus PDF', (tester) async {
    if (corpusDir == null) {
      markTestSkipped('set CORPUS_DIR to run the corpus render');
      return;
    }
    await tester.runAsync(() async {
      await loadSystemFonts();
      final outDir =
          Directory(Platform.environment['RENDER_OUT'] ?? '$corpusDir/renders')
            ..createSync(recursive: true);

      final files = Directory(corpusDir)
          .listSync()
          .whereType<File>()
          .where((f) => f.path.toLowerCase().endsWith('.pdf'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

      var ok = 0;
      final failures = <String>[];
      for (final file in files) {
        final name = file.uri.pathSegments.last;
        try {
          final doc = PdfDocument.open(file.readAsBytesSync());
          final image =
              await PdfPageRenderer.renderImage(doc.page(0), pixelRatio: 1.5)
                  .timeout(const Duration(seconds: 60));
          final png = await image.toByteData(format: ui.ImageByteFormat.png);
          File('${outDir.path}/$name.png')
              .writeAsBytesSync(png!.buffer.asUint8List());
          image.dispose();
          ok++;
        } catch (e) {
          failures.add('$name: $e');
        }
      }
      // ignore: avoid_print
      print('rendered $ok/${files.length} into ${outDir.path}');
      for (final failure in failures) {
        // ignore: avoid_print
        print('FAILED $failure');
      }
    });
  }, timeout: const Timeout(Duration(minutes: 30)));
}
