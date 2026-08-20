// Puts a number on #699: what the two background surfaces - the thumbnail
// strip and the preview LoD ladder - cost when they re-interpret a page the
// viewer has already interpreted, against what they cost when they reuse that
// work.
//
// Both halves are measured the way the surfaces actually pay them, on the
// platform thread:
//
//   ladder   base/400px/800px previews of one page, warmed rung by rung (a
//            content-stream walk each), against the whole ladder rasterized
//            from a single record, against the whole ladder rasterized from
//            the retained scene the viewer is already holding (no walk at all)
//   tile     a 128px thumbnail from a local interpret+raster against the same
//            tile replayed out of the page's retained scene
//
// The synthetic profiles and the committed letterhead report run by default,
// so the numbers exist on any machine. Point this at another document with:
//
//   cd packages/dart_pdf_editor
//   PDF_SURFACE_BENCHMARK_PDF=/path/to/report.pdf fvm flutter test \
//     test/benchmark_background_surfaces_test.dart
//
//   PDF_SURFACE_BENCHMARK_PAGES=6   # pages sampled from the front of the file
//
// This is the VM half. The web half is the real-Chrome harness: run
// `tool/perf.sh web wheel-letterhead` (and the `read-*` scenarios) for the
// dart2js/CanvasKit picture of the same journey.
import 'dart:io';
import 'dart:typed_data';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_cos/perf.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';

void main() {
  const pageColor = Color(0xFFFFFFFF);
  const levels = [400.0, 800.0];
  const lodPolicy = PdfPagePreviewLodPolicy(
    intermediateLongestSides: levels,
    maxBytes: 256 * 1024 * 1024,
    maxEntryBytes: 64 * 1024 * 1024,
  );

  PdfPagePreviewCache newCache() => PdfPagePreviewCache(lodPolicy: lodPolicy);

  /// Warms the whole ladder of [index] one rung per call - what the viewer
  /// did before #699: one content-stream walk per rung.
  Future<int> perRungMicros(int index, PdfPage page) async {
    final cache = newCache();
    final clock = Stopwatch()..start();
    await cache.renderPreview(index, page, pageColor: pageColor);
    for (final side in levels) {
      await cache.renderPreview(index, page,
          pageColor: pageColor, targetLongestSide: side);
    }
    clock.stop();
    expect(cache.hasIntermediate(index, targetLongestSide: levels.last), isTrue);
    cache.dispose();
    return clock.elapsedMicroseconds;
  }

  /// Warms the same ladder from one record.
  Future<int> ladderMicros(int index, PdfPage page) async {
    final cache = newCache();
    final clock = Stopwatch()..start();
    await cache.renderPreview(index, page,
        pageColor: pageColor, alsoFillLongestSides: levels);
    clock.stop();
    expect(cache.hasIntermediate(index, targetLongestSide: levels.last), isTrue);
    cache.dispose();
    return clock.elapsedMicroseconds;
  }

  /// The same ladder built from the scene the viewer is already holding. As
  /// with the tile below, the record is deliberately outside the clock - the
  /// viewer paid for it when the page was on screen - and the tokenized
  /// content operations are reported beside the wall time, because that is
  /// what the reuse actually removes and it reads the same on every machine.
  Future<({int micros, int ops})> retainedLadderMicros(
      int index, PdfPage page) async {
    Future<int> run() async {
      final cache = newCache();
      final plan = PdfPageRenderPlan(
        pageColor: pageColor,
        annotations: true,
        rotation: page.rotation,
      );
      final scene = await PdfRetainedScene.record(page, plan: plan);
      cache
          .retainScene(index, page, scene,
              plan: plan, fromWorker: false, estimatedBytes: 1 << 20)
          .dispose(); // the cache keeps its own reference
      // The viewer paid for the record when the page was on screen; neither
      // the clock nor the operation count is about it.
      PdfPerf.reset();
      final clock = Stopwatch()..start();
      await cache.renderPreview(index, page,
          pageColor: pageColor, alsoFillLongestSides: levels);
      clock.stop();
      expect(
          cache.hasIntermediate(index, targetLongestSide: levels.last), isTrue);
      cache.dispose();
      return clock.elapsedMicroseconds;
    }

    // Two passes, and the clock runs in the uninstrumented one. PdfPerf turns
    // every phase in the render/raster stack into a live Stopwatch, which on
    // this profile is worth more than the saving being measured - the first
    // version of this timed an instrumented run against uninstrumented ones
    // and reported the reuse as a regression on the letterhead report.
    final micros = await run();
    PdfPerf.enabled = true;
    await run(); // resets the counters past its own scene record
    final ops = PdfPerf.snapshot().count(PdfPerfCount.contentOps);
    PdfPerf.enabled = false;
    return (micros: micros, ops: ops);
  }

  /// A tile rendered the way a worker-less session rendered it: interpret the
  /// whole page to fill 128 px.
  Future<int> localTileMicros(PdfEditingController controller, int index) async {
    final clock = Stopwatch()..start();
    final image = await rasterizeThumbnail(
      controller: controller,
      pageIndex: index,
      pageColor: pageColor,
      annotations: true,
      pixelWidth: 128,
      worker: null,
    );
    clock.stop();
    expect(image, isNotNull);
    image!.dispose();
    return clock.elapsedMicroseconds;
  }

  /// The same tile replayed from the scene the viewer already holds. The
  /// record is deliberately outside the clock: the viewer paid for it when the
  /// page was on screen. Returns the tile's wall time and the content-stream
  /// operations it tokenized - which is what the reuse actually removes, and
  /// unlike the wall time is the same number on every machine.
  Future<({int micros, int ops})> retainedTileMicros(
      PdfEditingController controller, int index) async {
    Future<int> run() async {
      // The scene has to be recorded from the page object the tile will ask
      // about - the cache's freshness test is page identity, and the
      // controller caches its own PdfPage per index. Recording from a second
      // PdfDocument over the same bytes looks identical and misses every time.
      final page = controller.pageAt(index);
      final cache = newCache();
      final plan = PdfPageRenderPlan(
        pageColor: pageColor,
        annotations: true,
        rotation: page.rotation,
      );
      final scene = await PdfRetainedScene.record(page, plan: plan);
      cache
          .retainScene(index, page, scene,
              plan: plan, fromWorker: false, estimatedBytes: 1 << 20)
          .dispose();
      PdfPerf.reset();
      final clock = Stopwatch()..start();
      final image = await rasterizeThumbnail(
        controller: controller,
        pageIndex: index,
        pageColor: pageColor,
        annotations: true,
        pixelWidth: 128,
        worker: null,
        previews: cache,
      );
      clock.stop();
      expect(image, isNotNull);
      image!.dispose();
      cache.dispose();
      return clock.elapsedMicroseconds;
    }

    // Uninstrumented for the clock, instrumented for the ops - see
    // [retainedLadderMicros].
    final micros = await run();
    PdfPerf.enabled = true;
    await run(); // resets the counters past its own scene record
    final ops = PdfPerf.snapshot().count(PdfPerfCount.contentOps);
    PdfPerf.enabled = false;
    return (micros: micros, ops: ops);
  }

  Future<void> report(String label, Uint8List bytes, {required int pages}) async {
    final document = PdfDocument.open(bytes);
    final controller = PdfEditingController(bytes);
    addTearDown(controller.dispose);
    final sampled = pages < document.pageCount ? pages : document.pageCount;
    var perRung = 0;
    var ladder = 0;
    var retainedLadder = 0;
    var retainedLadderOps = 0;
    var localTile = 0;
    var retainedTile = 0;
    var retainedTileOps = 0;
    for (var i = 0; i < sampled; i++) {
      final page = document.page(i);
      perRung += await perRungMicros(i, page);
      ladder += await ladderMicros(i, page);
      final retainedRungs = await retainedLadderMicros(i, page);
      retainedLadder += retainedRungs.micros;
      retainedLadderOps += retainedRungs.ops;
      localTile += await localTileMicros(controller, i);
      final retained = await retainedTileMicros(controller, i);
      retainedTile += retained.micros;
      retainedTileOps += retained.ops;
    }
    double ms(int micros) => micros / sampled / 1000;
    // ignore: avoid_print
    print('background-surfaces $label: pages=$sampled '
        'ladderPerRung=${ms(perRung).toStringAsFixed(1)}ms/page '
        'ladderOneRecord=${ms(ladder).toStringAsFixed(1)}ms/page '
        '(-${(100 * (perRung - ladder) / perRung).toStringAsFixed(0)}%) '
        'ladderRetained=${ms(retainedLadder).toStringAsFixed(1)}ms/page '
        '(-${(100 * (perRung - retainedLadder) / perRung).toStringAsFixed(0)}%) '
        'tileLocal=${ms(localTile).toStringAsFixed(1)}ms/tile '
        'tileRetained=${ms(retainedTile).toStringAsFixed(1)}ms/tile '
        '(-${(100 * (localTile - retainedTile) / localTile).toStringAsFixed(0)}%)');

    // The point of both changes. If either stops holding, the surfaces are
    // paying for work they already have and this benchmark should fail rather
    // than print a number nobody reads.
    //
    // Rung-per-call against one record is gated on wall time: the saving is
    // an interpret per rung, large on every profile here. The other two are
    // gated on the interpret itself instead. On the VM a readback can be most
    // of a small page's work - the whole 128px tile, and on a page whose
    // sharpest rung is already 1x (the letterhead report, 792pt tall against
    // an 800px rung) most of the ladder too, since the record it removes was
    // decoding at that same ratio anyway. The ms columns there are real but
    // too close to call on a fast host, so gating them would buy a flake
    // rather than a signal. What must always hold is that neither surface
    // walked the page.
    expect(ladder, lessThan(perRung),
        reason: 'one record for the whole ladder must beat one per rung');
    expect(retainedLadderOps, 0,
        reason: 'a ladder built from a retained scene tokenizes nothing');
    expect(retainedTileOps, 0,
        reason: 'a tile served from a retained scene tokenizes nothing');
  }

  testWidgets('ordinary text pages', (tester) async {
    await tester.runAsync(
        () => report('ordinary', buildMultiPagePdf(4), pages: 4));
  });

  testWidgets('dense vector linework (CAD profile)', (tester) async {
    await tester.runAsync(() => report(
        'cad-vector', buildSyntheticCadStrip(ops: 20000, streams: 4),
        pages: 1));
  });

  testWidgets('letterhead report (the #699 document class)', (tester) async {
    final file = File('../../test_corpora/dartpdf/letterhead-report-40p.pdf');
    if (!file.existsSync()) {
      markTestSkipped('missing ${file.path}');
      return;
    }
    await tester.runAsync(
        () => report('letterhead-report', file.readAsBytesSync(), pages: 6));
  });

  testWidgets('real document sweep', (tester) async {
    final path = Platform.environment['PDF_SURFACE_BENCHMARK_PDF'];
    if (path == null) {
      markTestSkipped('set PDF_SURFACE_BENCHMARK_PDF');
      return;
    }
    final pages = int.tryParse(
            Platform.environment['PDF_SURFACE_BENCHMARK_PAGES'] ?? '') ??
        6;
    await tester.runAsync(() => report(
        path.split(Platform.pathSeparator).last,
        File(path).readAsBytesSync(),
        pages: pages));
  });
}
