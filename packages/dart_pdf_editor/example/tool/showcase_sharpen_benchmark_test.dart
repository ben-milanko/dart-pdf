import 'dart:convert';
import 'dart:ui' as ui;

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_viewer_example/demo_document.dart';

int _percentile(List<int> values, double fraction) {
  final sorted = [...values]..sort();
  return sorted[(sorted.length * fraction).ceil() - 1];
}

void main() {
  testWidgets('Feature Showcase page 6 exact-raster reuse latency',
      (tester) async {
    final document = PdfDocument.open(buildDemoPdf());
    final page = document.page(5); // Annotations & forms.
    final picture = await PdfPageRenderer.renderPicture(page);
    addTearDown(picture.dispose);
    final size = PdfPageRenderer.pageSize(page);
    const ratio = 1.25;

    // Warm the engine once, then measure the GPU readback a recycled page
    // used to repeat on every visit.
    final warmup = await PdfPageRenderer.rasterize(picture, size, ratio);
    warmup.dispose();
    final rasterMicros = <int>[];
    late ui.Image seed;
    for (var i = 0; i < 7; i++) {
      final stopwatch = Stopwatch()..start();
      final image = await PdfPageRenderer.rasterize(picture, size, ratio);
      stopwatch.stop();
      rasterMicros.add(stopwatch.elapsedMicroseconds);
      if (i == 0) {
        seed = image;
      } else {
        image.dispose();
      }
    }

    final cache = PdfPagePreviewCache();
    addTearDown(cache.dispose);
    cache.putFullImage(
      5,
      page,
      seed,
      pageColor: const ui.Color(0xFFFFFFFF),
      annotations: true,
      rotation: 0,
    );
    final width = seed.width;
    final height = seed.height;
    seed.dispose();

    // Clone lookup is the optimized revisit path. Use enough samples for
    // stable microsecond percentiles while keeping the opt-in run short.
    final restoreMicros = <int>[];
    for (var i = 0; i < 200; i++) {
      final stopwatch = Stopwatch()..start();
      final image = cache.fullImageFor(
        5,
        page,
        width: width,
        height: height,
        pageColor: const ui.Color(0xFFFFFFFF),
        annotations: true,
        rotation: 0,
      );
      stopwatch.stop();
      expect(image, isNotNull);
      restoreMicros.add(stopwatch.elapsedMicroseconds);
      image!.dispose();
    }

    final rasterP50 = _percentile(rasterMicros, 0.5);
    final rasterP90 = _percentile(rasterMicros, 0.9);
    final restoreP50 = _percentile(restoreMicros, 0.5);
    final restoreP90 = _percentile(restoreMicros, 0.9);
    // ignore: avoid_print
    print(const JsonEncoder.withIndent('  ').convert({
      'page': 'Feature Showcase / Annotations & forms',
      'raster': '${width}x$height',
      'coldRasterP50Ms': rasterP50 / 1000,
      'coldRasterP90Ms': rasterP90 / 1000,
      'cacheRestoreP50Ms': restoreP50 / 1000,
      'cacheRestoreP90Ms': restoreP90 / 1000,
      'speedupP50': rasterP50 / (restoreP50 == 0 ? 0.5 : restoreP50),
      'retainedMiB': width * height * 4 / (1 << 20),
    }));

    expect(restoreP90, lessThan(rasterP50));
  });
}
