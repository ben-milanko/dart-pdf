// Encoding evaluation for the persistent full-raster disk tier (#615).
//
// The tier stores exact page rasters so a reopened document paints without
// interpreting the page again. Whether that is a win depends entirely on the
// stored representation, and PNG is *not* unconditionally the right answer:
// on a photo/scan page it barely compresses while costing a real encode, and
// on a vector/CAD page it compresses 10x+ and the encode pays for itself in
// how much of the document survives the byte budget.
//
// Two halves:
//
//  * `raster codec characterisation` always runs. It synthesises the three
//    page shapes that matter (vector linework, a form, a photo/scan) and
//    reports encode ms, decode ms, and bytes for each PdfRasterDiskFormat.
//    It asserts only the invariant (a round trip is byte-exact in size and
//    dimensions); the numbers are the output.
//
//  * `disk restore vs fresh render` is skipped unless PDF_BENCHMARK_PDF is
//    set. It renders every page of a real document, stores the raster, then
//    restores it, so the two costs sit side by side on the same machine:
//
//      cd packages/dart_pdf_editor
//      PDF_BENCHMARK_PDF=/path/to/doc.pdf fvm flutter test \
//        test/benchmark_full_raster_disk_test.dart
//
//      PDF_BENCHMARK_SCALE=1        # raster pixel ratio
//      PDF_BENCHMARK_PAGES=12       # cap on pages measured
//
// Run it on each platform you care about: the encode, the decode, and the
// store are all platform work (a GPU readback on desktop/mobile, a canvas
// readback plus IndexedDB on web), so the crossover moves.
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';

import 'render_smoke_test.dart' show loadSystemFonts;

/// Synthesises a raster with the statistics of a real page of [kind].
Future<ui.Image> _syntheticPage(String kind, int width, int height) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final size = Size(width.toDouble(), height.toDouble());
  canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFFFFFFFF));
  // Deterministic: the numbers must be comparable between runs.
  final random = math.Random(20260729);

  switch (kind) {
    case 'vector':
      // A CAD sheet: mostly paper, dense thin linework, a handful of colours.
      final stroke = Paint()
        ..color = const Color(0xFF101010)
        ..strokeWidth = 1
        ..style = PaintingStyle.stroke;
      for (var i = 0; i < 4000; i++) {
        final x = random.nextDouble() * width;
        final y = random.nextDouble() * height;
        canvas.drawLine(
          Offset(x, y),
          Offset(x + random.nextDouble() * 60 - 30,
              y + random.nextDouble() * 60 - 30),
          stroke,
        );
      }
    case 'form':
      // Ruled boxes and filled label bands - large flat areas, hard edges.
      final rule = Paint()
        ..color = const Color(0xFF404040)
        ..strokeWidth = 1
        ..style = PaintingStyle.stroke;
      final band = Paint()..color = const Color(0xFFE8E8EE);
      for (var row = 0; row < height ~/ 24; row++) {
        final y = row * 24.0;
        canvas.drawRect(Rect.fromLTWH(20, y, width - 40.0, 18), band);
        canvas.drawRect(Rect.fromLTWH(20, y, width - 40.0, 18), rule);
        for (var glyph = 0; glyph < 40; glyph++) {
          canvas.drawRect(
            Rect.fromLTWH(28 + glyph * 9.0, y + 5, 5, 8),
            Paint()..color = const Color(0xFF202020),
          );
        }
      }
    case 'photo':
      // A scan: every pixel different, which is what defeats PNG.
      final pixels = Uint8List(width * height * 4);
      for (var i = 0; i < pixels.length; i += 4) {
        pixels[i] = random.nextInt(256);
        pixels[i + 1] = random.nextInt(256);
        pixels[i + 2] = random.nextInt(256);
        pixels[i + 3] = 255;
      }
      final buffer = await ui.ImmutableBuffer.fromUint8List(pixels);
      final descriptor = ui.ImageDescriptor.raw(buffer,
          width: width, height: height, pixelFormat: ui.PixelFormat.rgba8888);
      final codec = await descriptor.instantiateCodec();
      final frame = await codec.getNextFrame();
      codec.dispose();
      descriptor.dispose();
      buffer.dispose();
      recorder.endRecording().dispose();
      return frame.image;
    default:
      throw ArgumentError('unknown page kind $kind');
  }

  final picture = recorder.endRecording();
  try {
    return picture.toImage(width, height);
  } finally {
    picture.dispose();
  }
}

String _ms(int micros) => (micros / 1000).toStringAsFixed(1).padLeft(7);
String _kb(int bytes) => (bytes / 1024).toStringAsFixed(0).padLeft(7);

void main() {
  testWidgets('raster codec characterisation', (tester) async {
    const width = 1200;
    const height = 1600;
    const megapixels = width * height / 1000000;
    final raw = width * height * 4;

    // ignore: avoid_print
    print('\nfull-raster disk codecs  ${width}x$height '
        '(${megapixels.toStringAsFixed(1)} MP, raw ${_kb(raw)} KB)');
    // ignore: avoid_print
    print('  page kind  format    encode      decode      stored   vs raw');

    for (final kind in const ['vector', 'form', 'photo']) {
      await tester.runAsync(() async {
        final image = await _syntheticPage(kind, width, height);
        try {
          for (final format in PdfRasterDiskFormat.values) {
            final store = PdfMemoryCacheStore();
            final cache = PdfRasterCache(
              PdfDiskCache(store, namespace: 'previews'),
              fullRasters: PdfDiskCache(store,
                  namespace: 'page-rasters', maxBytes: 1 << 30),
              fullRasterFormat: format,
            ).forDocument('bench');

            await cache.storeFullRaster(0, image,
                pageColor: 0xFFFFFFFF, annotations: true, rotation: null);
            final restored = await cache.loadFullRaster(0,
                width: width,
                height: height,
                pageColor: 0xFFFFFFFF,
                annotations: true,
                rotation: null);

            expect(restored, isNotNull, reason: '$kind/${format.name}');
            expect(restored!.width, width);
            expect(restored.height, height);
            restored.dispose();

            final stats = cache.fullRasterStats;
            // ignore: avoid_print
            print('  ${kind.padRight(9)}  ${format.name.padRight(8)}'
                '${_ms(stats.encodeMicros)}ms ${_ms(stats.decodeMicros)}ms '
                '${_kb(stats.bytesWritten)} KB '
                '${(stats.bytesWritten / raw * 100).toStringAsFixed(0).padLeft(5)}%');
          }
        } finally {
          image.dispose();
        }
      });
    }
  });

  final path = Platform.environment['PDF_BENCHMARK_PDF'];
  final scale =
      double.tryParse(Platform.environment['PDF_BENCHMARK_SCALE'] ?? '') ?? 1.0;
  final pageCap =
      int.tryParse(Platform.environment['PDF_BENCHMARK_PAGES'] ?? '') ?? 12;

  testWidgets('disk restore vs fresh render', (tester) async {
    await loadSystemFonts();
    final bytes = await File(path!).readAsBytes();
    final document = PdfDocument.open(bytes);
    final pageCount = math.min(document.pageCount, pageCap);

    // ignore: avoid_print
    print('\ndisk restore vs fresh render  ${path.split('/').last}  '
        '$pageCount pages @ ratio $scale');

    for (final format in PdfRasterDiskFormat.values) {
      final store = PdfMemoryCacheStore();
      final disk = PdfDiskCache(store,
          namespace: 'page-rasters', maxBytes: 2 * 1024 * 1024 * 1024);
      final cache = PdfRasterCache(
        PdfDiskCache(store, namespace: 'previews'),
        fullRasters: disk,
        fullRasterFormat: format,
      ).forDocument(pdfContentKey(bytes));

      var renderMicros = 0;
      var restoreMicros = 0;
      var pixels = 0;

      await tester.runAsync(() async {
        for (var index = 0; index < pageCount; index++) {
          final page = document.page(index);
          final sw = Stopwatch()..start();
          final image = await PdfPageRenderer.renderImage(page,
              pixelRatio: scale, recorded: true);
          sw.stop();
          renderMicros += sw.elapsedMicroseconds;
          pixels += image.width * image.height;

          await cache.storeFullRaster(index, image,
              pageColor: 0xFFFFFFFF, annotations: true, rotation: null);

          final restoreClock = Stopwatch()..start();
          final restored = await cache.loadFullRaster(index,
              width: image.width,
              height: image.height,
              pageColor: 0xFFFFFFFF,
              annotations: true,
              rotation: null);
          restoreClock.stop();
          restoreMicros += restoreClock.elapsedMicroseconds;
          expect(restored, isNotNull);
          restored!.dispose();
          image.dispose();
        }
      });

      final stats = cache.fullRasterStats;
      final speedup = restoreMicros == 0 ? 0.0 : renderMicros / restoreMicros;
      // ignore: avoid_print
      print('  ${format.name.padRight(8)} '
          'render ${_ms(renderMicros)}ms  restore ${_ms(restoreMicros)}ms  '
          '${speedup.toStringAsFixed(1)}x  '
          'stored ${_kb(stats.bytesWritten)} KB for '
          '${(pixels / 1000000).toStringAsFixed(1)} MP  '
          'encode ${_ms(stats.encodeMicros)}ms');
      // ignore: avoid_print
      print('    ${disk.debugStats}');
    }
  }, skip: path == null);
}
