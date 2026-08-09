// Puts a number on the trade the idle full-raster warm (#614) makes: what one
// warmed page costs to produce and to hold, against what arriving on it costs
// when it was not warmed.
//
// Both halves of the trade are measured the way the viewer actually pays them:
//
//   cold   interpret the page + rasterize it at display size (what a page does
//          on its first arrival, on the platform thread)
//   warm   look the baked raster up by signature and clone it (what
//          PdfPageView._restoreFullRaster does instead, synchronously, ahead of
//          the render scheduler)
//   bytes  what that page then occupies in the exact-raster cache
//
// The synthetic profiles run by default and are deliberately small, so the
// numbers exist on any machine without a corpus. This is the VM half of the
// measurement; the web half is the perf harness's `warm` workload kind - run
// `tool/perf.sh web warm-plan-document` against `warm-plan-off` (they differ
// only in `?warm=`). Point this at a real document to characterise one:
//
//   cd packages/dart_pdf_editor
//   PDF_WARM_BENCHMARK_PDF=/path/to/cad.pdf fvm flutter test \
//     test/benchmark_raster_warm_test.dart
//
//   PDF_WARM_BENCHMARK_PAGES=8    # pages sampled from the front of the file
//   PDF_WARM_BENCHMARK_WIDTH=1600 # on-screen page width in logical px
//   PDF_WARM_BENCHMARK_DPR=2      # device pixel ratio
import 'dart:io';
import 'dart:typed_data';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';

/// One measured page.
typedef _Sample = ({int coldMicros, int warmMicros, int bytes});

void main() {
  const pageColor = Color(0xFFFFFFFF);

  /// Measures [page] end to end: the cold interpret + rasterize the viewer
  /// pays on arrival, then the warmed cache lookup that replaces it.
  Future<_Sample> measure(
    PdfPagePreviewCache cache,
    int index,
    PdfPage page, {
    required double layoutWidth,
    required double devicePixelRatio,
  }) async {
    final size = PdfPageRenderer.pageSize(page);
    final ratio = PdfPageRasterGeometry.effectiveRatio(
      pageSize: size,
      layoutWidth: layoutWidth,
      devicePixelRatio: devicePixelRatio,
    );
    final dimensions = PdfPageRasterGeometry.dimensions(size, ratio);
    final signature = PdfPageRasterSignature(
      pageIndex: index,
      width: dimensions.$1,
      height: dimensions.$2,
      pageColor: pageColor,
      annotations: true,
      rotation: null,
    );

    final cold = Stopwatch()..start();
    await cache.warmFullRaster(
      index,
      page,
      signature: signature,
      pixelRatio: ratio,
    );
    cold.stop();

    final warm = Stopwatch()..start();
    final hit = cache.fullImageForSignature(signature, page);
    warm.stop();
    expect(hit, isNotNull,
        reason: 'the warm must produce exactly the raster the page asks for');
    hit!.dispose();
    return (
      coldMicros: cold.elapsedMicroseconds,
      warmMicros: warm.elapsedMicroseconds,
      bytes: signature.bytes,
    );
  }

  Future<void> report(
    String label,
    Uint8List bytes, {
    required int pages,
    required double layoutWidth,
    required double devicePixelRatio,
  }) async {
    final document = PdfDocument.open(bytes);
    final cache = PdfPagePreviewCache()
      ..configureFullRasterCache(const PdfPageRasterCachePolicy(
        maxBytes: 4 * 1024 * 1024 * 1024,
        maxEntryBytes: 256 * 1024 * 1024,
      ));
    addTearDown(cache.dispose);
    final samples = <_Sample>[];
    for (var i = 0; i < pages && i < document.pageCount; i++) {
      samples.add(await measure(
        cache,
        i,
        document.page(i),
        layoutWidth: layoutWidth,
        devicePixelRatio: devicePixelRatio,
      ));
    }
    expect(samples, isNotEmpty);
    int total(int Function(_Sample s) of) =>
        samples.fold(0, (sum, s) => sum + of(s));
    final n = samples.length;
    final cold = total((s) => s.coldMicros) / n / 1000;
    final warm = total((s) => s.warmMicros) / n / 1000;
    final mb = total((s) => s.bytes) / n / (1 << 20);
    // ignore: avoid_print
    print('raster-warm $label: pages=$n '
        'cold=${cold.toStringAsFixed(1)}ms/page '
        'warmHit=${warm.toStringAsFixed(3)}ms/page '
        'retained=${mb.toStringAsFixed(1)}MB/page '
        'speedup=${(cold / (warm == 0 ? 0.001 : warm)).toStringAsFixed(0)}x');

    // The point of the feature: reading a baked raster back is not in the same
    // class of cost as producing one. If that ever stops holding, warming is
    // buying nothing and this benchmark should fail rather than print a number
    // nobody reads.
    expect(warm, lessThan(cold),
        reason: 'a cache hit must be cheaper than the render it replaces');
  }

  testWidgets('ordinary text pages', (tester) async {
    await tester.runAsync(() => report(
          'ordinary',
          buildMultiPagePdf(8),
          pages: 8,
          layoutWidth: 800,
          devicePixelRatio: 2,
        ));
  });

  testWidgets('dense vector linework (CAD profile)', (tester) async {
    await tester.runAsync(() => report(
          'cad-vector',
          buildSyntheticCadStrip(ops: 20000, streams: 4),
          pages: 1,
          layoutWidth: 1600,
          devicePixelRatio: 2,
        ));
  });

  testWidgets('raster underlay sheet (scan profile)', (tester) async {
    await tester.runAsync(() => report(
          'scan-underlay',
          buildSyntheticRasterUnderlaySheet(
            underlays: const [PdfUnderlaySpec(width: 1200, height: 800)],
            layers: 8,
            ops: 2000,
          ),
          pages: 1,
          layoutWidth: 1600,
          devicePixelRatio: 2,
        ));
  });

  testWidgets('real document sweep', (tester) async {
    final path = Platform.environment['PDF_WARM_BENCHMARK_PDF'];
    if (path == null) {
      markTestSkipped('set PDF_WARM_BENCHMARK_PDF');
      return;
    }
    final pages =
        int.tryParse(Platform.environment['PDF_WARM_BENCHMARK_PAGES'] ?? '') ??
            8;
    final width = double.tryParse(
            Platform.environment['PDF_WARM_BENCHMARK_WIDTH'] ?? '') ??
        1600;
    final dpr =
        double.tryParse(Platform.environment['PDF_WARM_BENCHMARK_DPR'] ?? '') ??
            2;
    await tester.runAsync(() => report(
          path.split(Platform.pathSeparator).last,
          File(path).readAsBytesSync(),
          pages: pages,
          layoutWidth: width,
          devicePixelRatio: dpr,
        ));
  });
}
