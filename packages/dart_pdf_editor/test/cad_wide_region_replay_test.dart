// Exercises retained region replay on the pathological single-sheet CAD shape
// behind the "iPad janky pan" report - one ultra-wide strip page (~8504 x 842
// pt) whose transcript overflows the linear region-replay ceiling, so the
// viewer escalates to the grid spatial index. The real client file is
// confidential; this drives the identical pipeline on the deterministic
// synthetic strip (`buildSyntheticCadStrip`), so the win is regression-gated in
// CI without shipping the drawing.
//
// It asserts the three properties that keep a deep-zoom pan on this shape
// interactive AND alive:
//   1. the grid cull is byte-identical to a full-transcript replay (no
//      cell-boundary or painter-order bug), swept across the whole width;
//   2. each tile replays only a tiny fraction of the transcript (the cull
//      actually engages - the CPU win); and
//   3. the grid index stays compact on a wide page - the broad-cell guard
//      keeps page-spanning ops out of the bins, so the index can't balloon into
//      the memory trap that a naive smear-across-every-cell grid would hit.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';

Future<Uint8List> _bytes(ui.Image image) async =>
    (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!
        .buffer
        .asUint8List();

void main() {
  testWidgets('grid region replay culls a wide CAD strip, byte-identically',
      (tester) async {
    final prevRegion = PdfRetainedScene.spatialRegionReplay;
    final prevGrid = PdfRetainedScene.spatialGridReplay;
    final prevCeil = PdfRetainedScene.spatialRegionReplayMaxCommands;
    addTearDown(() {
      PdfRetainedScene.spatialRegionReplay = prevRegion;
      PdfRetainedScene.spatialGridReplay = prevGrid;
      PdfRetainedScene.spatialRegionReplayMaxCommands = prevCeil;
    });

    await tester.runAsync(() async {
      // Enough primitives to make the grid worthwhile and the geometry genuinely
      // wide, but small enough to record quickly in CI. The grid engages by
      // dropping the linear ceiling to 0 (escalation is proven separately in
      // retained_scene_test); here we exercise the wide-page cull itself.
      final bytes = buildSyntheticCadStrip(ops: 120000, streams: 8);
      final document = PdfDocument.open(bytes);
      expect(document.pageCount, 1);

      final scene = await PdfRetainedScene.record(document.page(0));
      addTearDown(scene.dispose);
      final size = scene.pageSize;
      expect(size.width / size.height, greaterThan(8),
          reason: 'the exercise must be the ultra-wide strip shape');
      final transcript = scene.commands.length;
      expect(transcript, greaterThan(100000),
          reason: 'transcript should be dense enough to need culling');

      // A tile-sized region slid across the full 8504pt width - the pan the
      // report was about. Each is a small square at mid-height.
      const tilePt = 140.0;
      final yMid = (size.height - tilePt) / 2;
      final regions = <Rect>[
        for (var i = 0; i < 8; i++)
          Rect.fromLTWH(
            (size.width - tilePt) * i / 7,
            yMid,
            tilePt,
            tilePt,
          ),
      ];

      var maxTileCommands = 0;
      var gridIndexBytes = 0;
      for (final region in regions) {
        // Full-transcript replay (grid + linear cull both off) is the oracle.
        PdfRetainedScene.spatialRegionReplay = false;
        PdfRetainedScene.spatialGridReplay = false;
        final expected = await scene.rasterizeRegion(region, pixelRatio: 2);

        // Fresh scene so the index rebuilds under the grid flag with the ceiling
        // dropped to 0 (the index memoizes per scene).
        final gridScene = await PdfRetainedScene.record(document.page(0));
        PdfRetainedScene.spatialRegionReplay = true;
        PdfRetainedScene.spatialGridReplay = true;
        PdfRetainedScene.spatialRegionReplayMaxCommands = 0;
        final actual = await gridScene.rasterizeRegion(region, pixelRatio: 2);

        try {
          expect(gridScene.debugLastRegionReplayWasSelective, isTrue,
              reason: 'grid must cull, not full-replay, region $region');
          maxTileCommands = maxTileCommands >
                  gridScene.debugLastRegionReplayCommandCount
              ? maxTileCommands
              : gridScene.debugLastRegionReplayCommandCount;
          gridIndexBytes = gridScene.debugRegionReplayEstimatedBytes;
          expect(actual.width, expected.width);
          expect(actual.height, expected.height);
          expect(await _bytes(actual), await _bytes(expected),
              reason: 'grid raster diverges from full replay at $region');
        } finally {
          expected.dispose();
          actual.dispose();
          gridScene.dispose();
        }
      }

      // The cull is the whole point: a tile touches a small slice of a wide
      // strip, so it must replay far fewer than the whole transcript.
      expect(maxTileCommands, lessThan(transcript ~/ 5),
          reason: 'per-tile cull replayed $maxTileCommands of $transcript - '
              'the grid is not culling a wide strip effectively');

      // The broad-cell guard must keep the grid index compact on a wide page: a
      // naive grid that smears page-spanning ops across every cell is the memory
      // trap. ~112 B/unit is the healthy figure (units + CSR bins + broad list);
      // a smear bug would push this into thousands of bytes per unit, so 256 is
      // a wide margin that still fails loudly on a regression.
      expect(gridIndexBytes, lessThan(transcript * 256),
          reason: 'grid index ballooned to $gridIndexBytes bytes for '
              '$transcript commands - broad-cell smear on the wide page');
    });
  }, timeout: const Timeout(Duration(minutes: 5)));
}
