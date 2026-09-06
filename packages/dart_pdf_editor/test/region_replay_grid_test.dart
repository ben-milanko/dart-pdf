// The grid spatial index must replay the exact same units in painter order as
// the full (uncalled) transcript replay — proven by byte-identical region
// rasters across a diverse corpus (clips, images, gradients, patterns, text,
// blend modes, soft masks).
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

const _fixtures = <String>[
  'rotation.pdf',
  'xobject-image.pdf',
  'gradientfill.pdf',
  'tiling_patterns_variations.pdf',
  'glyph_accent.pdf',
  'blendmode.pdf',
  'smaskdim.pdf',
  'knockout_isolated_overlap.pdf',
];

void main() {
  testWidgets('grid region replay is byte-identical to full replay',
      (tester) async {
    final prevRegion = PdfRetainedScene.spatialRegionReplay;
    final prevGrid = PdfRetainedScene.spatialGridReplay;
    final prevCeil = PdfRetainedScene.spatialRegionReplayMaxCommands;
    // Force the grid on these small fixtures: escalation triggers above the
    // linear ceiling, so drop it to 0 to exercise the grid path here.
    PdfRetainedScene.spatialRegionReplayMaxCommands = 0;
    addTearDown(() {
      PdfRetainedScene.spatialRegionReplay = prevRegion;
      PdfRetainedScene.spatialGridReplay = prevGrid;
      PdfRetainedScene.spatialRegionReplayMaxCommands = prevCeil;
    });

    await tester.runAsync(() async {
      var selective = 0;
      for (final name in _fixtures) {
        final bytes = File('../../test_corpora/pdfjs/$name').readAsBytesSync();
        final document = PdfDocument.open(Uint8List.fromList(bytes));
        if (document.pageCount == 0) continue;
        final scene = await PdfRetainedScene.record(document.page(0));
        try {
          final size = scene.pageSize;
          // Sample several sub-regions, including edges and a tiny tile, so a
          // grid cell-boundary bug can't hide.
          final regions = <Rect>[
            Rect.fromLTWH(size.width * .2, size.height * .2, size.width * .6,
                size.height * .6),
            Rect.fromLTWH(0, 0, size.width * .33, size.height * .33),
            Rect.fromLTWH(size.width * .55, size.height * .1, size.width * .4,
                size.height * .5),
            Rect.fromLTWH(size.width * .45, size.height * .45,
                size.width * .12, size.height * .12),
          ];
          for (final region in regions) {
            PdfRetainedScene.spatialRegionReplay = false;
            PdfRetainedScene.spatialGridReplay = false;
            final expected =
                await scene.rasterizeRegion(region, pixelRatio: 1.5);

            // Fresh scene so the region index rebuilds under the grid flag
            // (the index is memoized per scene).
            final gridScene = await PdfRetainedScene.record(document.page(0));
            PdfRetainedScene.spatialRegionReplay = true;
            PdfRetainedScene.spatialGridReplay = true;
            final actual =
                await gridScene.rasterizeRegion(region, pixelRatio: 1.5);
            final wasSelective = gridScene.debugLastRegionReplayWasSelective;
            if (wasSelective) selective++;
            try {
              expect(actual.width, expected.width, reason: name);
              expect(actual.height, expected.height, reason: name);
              expect(await _bytes(actual), await _bytes(expected),
                  reason: '$name region $region grid pixels');
            } finally {
              expected.dispose();
              actual.dispose();
              gridScene.dispose();
            }
          }
        } finally {
          scene.dispose();
        }
      }
      expect(selective, greaterThanOrEqualTo(3),
          reason: 'grid path must actually engage on non-group pages');
    });
  });
}

Future<Uint8List> _bytes(ui.Image image) async =>
    (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!
        .buffer
        .asUint8List();
