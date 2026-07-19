// Issue #384: the region-replay grid index is built on the render-worker
// isolate and shipped back across the seam. Two invariants matter:
//
//  1. serialize -> deserialize round-trips the whole index (grid arrays, unit
//     metadata, and the clip-state tree) losslessly, so a region raster driven
//     by the reconstructed index is BYTE-IDENTICAL to one driven by the index
//     built in-isolate.
//  2. the same holds end-to-end through a real background-isolate worker's
//     buildRegionIndex, whose transcript re-record lines its unit indices up
//     with the worker-recorded scene.
//
// Both are proven the same way #383 proved the grid itself: byte-identical
// region rasters across a diverse fixture corpus.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:dart_pdf_editor/src/region_replay_index.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';

const _fixtures = <String>[
  'rotation.pdf',
  'xobject-image.pdf',
  'gradientfill.pdf',
  'tiling_patterns_variations.pdf',
  'glyph_accent.pdf',
  'blendmode.pdf',
];

/// A [PdfRenderWorker] that builds the region index on the calling isolate but
/// forces it through the real serialize -> deserialize codec, so a widget test
/// exercises the wire format deterministically (no background isolate to spawn
/// or await). The scene it is handed to must have been built from an identical
/// transcript for the unit indices to line up - here that is guaranteed by
/// passing the SAME command list to both the scene and the index build.
class _RoundTripIndexWorker extends PdfRenderWorker {
  _RoundTripIndexWorker(this._commands);

  final List<PdfRenderCommand> _commands;
  bool _disposed = false;
  int builds = 0;

  @override
  bool get isActive => !_disposed;

  @override
  Future<List<PdfRenderCommand>?> record(int pageIndex,
          {bool annotations = true,
          int priority = 0,
          double? imagePixelRatio,
          bool decodeImages = true,
          int? commandLimit,
          PdfRect? imageDecodeRegion}) async =>
      null;

  @override
  void cancel(int pageIndex, {int priority = 0}) {}

  @override
  Future<PdfRegionReplayIndex?> buildRegionIndex(
    int pageIndex, {
    required bool annotations,
    required int maxCommands,
    required bool buildGrid,
    int priority = 0,
  }) async {
    builds++;
    final index = PdfRegionReplayIndex.build(
      _commands,
      maxCommands: maxCommands,
      buildGrid: buildGrid,
    );
    final bytes = serializeRegionReplayIndex(index);
    if (bytes == null) return null;
    return deserializeRegionReplayIndex(bytes);
  }

  @override
  void dispose() => _disposed = true;
}

void main() {
  final prevRegion = PdfRetainedScene.spatialRegionReplay;
  final prevGrid = PdfRetainedScene.spatialGridReplay;
  final prevCeil = PdfRetainedScene.spatialRegionReplayMaxCommands;

  setUp(() {
    // Force grid escalation (>linear ceiling) on these small fixtures, so the
    // heavy build path - the one that gets offloaded - is what we serialize.
    PdfRetainedScene.spatialRegionReplayMaxCommands = 0;
    PdfRetainedScene.spatialRegionReplay = true;
    PdfRetainedScene.spatialGridReplay = true;
  });
  tearDown(() {
    PdfRetainedScene.spatialRegionReplay = prevRegion;
    PdfRetainedScene.spatialGridReplay = prevGrid;
    PdfRetainedScene.spatialRegionReplayMaxCommands = prevCeil;
  });

  testWidgets('serialized region index rasters identically to in-isolate build',
      (tester) async {
    await tester.runAsync(() async {
      var offloaded = 0;
      for (final name in _fixtures) {
        final bytes =
            File('../../test_corpora/pdfjs/$name').readAsBytesSync();
        final document = PdfDocument.open(Uint8List.fromList(bytes));
        if (document.pageCount == 0) continue;
        final page = document.page(0);

        // In-isolate baseline: a scene that builds and uses its own index.
        final local = await PdfRetainedScene.record(page);
        // The worker-offloaded scene shares the identical transcript, so a
        // round-tripped index built over it lines up unit-for-unit.
        final offload = await PdfRetainedScene.record(page);
        final worker = _RoundTripIndexWorker(offload.commands);
        await offload.warmRegionIndex(worker, pageIndex: 0);
        expect(worker.builds, 1, reason: '$name should offload the build');
        expect(offload.debugHasRegionReplayIndex, isTrue, reason: name);

        try {
          final size = local.pageSize;
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
            final expected =
                await local.rasterizeRegion(region, pixelRatio: 1.5);
            final actual =
                await offload.rasterizeRegion(region, pixelRatio: 1.5);
            if (offload.debugLastRegionReplayWasSelective) offloaded++;
            try {
              expect(actual.width, expected.width, reason: name);
              expect(actual.height, expected.height, reason: name);
              expect(await _bytes(actual), await _bytes(expected),
                  reason: '$name region $region');
            } finally {
              expected.dispose();
              actual.dispose();
            }
          }
        } finally {
          local.dispose();
          offload.dispose();
          worker.dispose();
        }
      }
      expect(offloaded, greaterThanOrEqualTo(3),
          reason: 'the serialized grid index must actually cull');
    });
  });

  testWidgets('background-isolate worker builds a byte-identical region index',
      (tester) async {
    await tester.runAsync(() async {
      final raw = Uint8List.fromList(
          File('../../test_corpora/pdfjs/gradientfill.pdf').readAsBytesSync());
      final document = PdfDocument.open(raw);
      final page = document.page(0);
      // The real native background-isolate backend.
      final worker = PdfRenderWorker.startUncached(raw);
      addTearDown(worker.dispose);

      // Record the page through the worker: this is the wire transcript the
      // retained scene holds, and the worker re-records the identical one when
      // it builds the index (so unit indices line up).
      final commands = await worker.record(0, annotations: true);
      if (commands == null) {
        markTestSkipped('worker declined this page');
        return;
      }

      final local =
          await PdfRetainedScene.fromCommands(page, commands, includeImages: true);
      await local.warmRegionIndex(null, pageIndex: 0); // in-isolate build
      final offload =
          await PdfRetainedScene.fromCommands(page, commands, includeImages: true);
      await offload.warmRegionIndex(worker, pageIndex: 0); // worker build
      addTearDown(local.dispose);
      addTearDown(offload.dispose);
      expect(offload.debugHasRegionReplayIndex, isTrue);
      expect(offload.debugRegionReplaySupported, isTrue,
          reason: 'a worker index must reconstruct as supported');

      final size = local.pageSize;
      final region = Rect.fromLTWH(
          size.width * .15, size.height * .15, size.width * .5, size.height * .5);
      final expected = await local.rasterizeRegion(region, pixelRatio: 2);
      final actual = await offload.rasterizeRegion(region, pixelRatio: 2);
      expect(offload.debugLastRegionReplayWasSelective, isTrue);
      try {
        expect(actual.width, expected.width);
        expect(actual.height, expected.height);
        expect(await _bytes(actual), await _bytes(expected));
      } finally {
        expected.dispose();
        actual.dispose();
      }
    });
  });

  testWidgets('unsupported (grouped) index round-trips its verdict',
      (tester) async {
    await tester.runAsync(() async {
      final commands = <PdfRenderCommand>[
        const PdfBeginGroupCommand(.5),
        PdfFillPathCommand(
          const PdfPath([
            PdfMoveTo(20, 650),
            PdfLineTo(100, 650),
            PdfLineTo(100, 740),
            PdfClosePath(),
          ]),
          const PdfColor(1, 0, 0),
          PdfFillRule.nonzero,
          1,
        ),
        const PdfEndGroupCommand(),
      ];
      final index = PdfRegionReplayIndex.build(commands, maxCommands: 1 << 20);
      expect(index.supported, isFalse);
      final bytes = serializeRegionReplayIndex(index)!;
      final restored = deserializeRegionReplayIndex(bytes);
      expect(restored.supported, isFalse);
      expect(restored.units, isEmpty);
    });
  });

  testWidgets('dropRegionIndex releases the index and it rebuilds',
      (tester) async {
    await tester.runAsync(() async {
      final bytes =
          File('../../test_corpora/pdfjs/gradientfill.pdf').readAsBytesSync();
      final page = PdfDocument.open(Uint8List.fromList(bytes)).page(0);
      final scene = await PdfRetainedScene.record(page);
      addTearDown(scene.dispose);
      await scene.warmRegionIndex(null, pageIndex: 0); // in-isolate build
      expect(scene.debugHasRegionReplayIndex, isTrue);
      scene.dropRegionIndex();
      expect(scene.debugHasRegionReplayIndex, isFalse);
      // The next region raster silently rebuilds it.
      final image = await scene.rasterizeRegion(
          const Rect.fromLTWH(0, 0, 100, 100),
          pixelRatio: 1);
      image.dispose();
      expect(scene.debugHasRegionReplayIndex, isTrue);
    });
  });
}

Future<Uint8List> _bytes(ui.Image image) async =>
    (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!
        .buffer
        .asUint8List();
