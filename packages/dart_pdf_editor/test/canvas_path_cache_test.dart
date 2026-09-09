import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:dart_pdf_editor/src/canvas_path_cache.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_graphics/pdf_graphics.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';

void main() {
  const path = PdfPath([
    PdfMoveTo(20, 20),
    PdfLineTo(180, 20),
    PdfLineTo(180, 180),
    PdfLineTo(20, 180),
    PdfClosePath(),
    PdfMoveTo(60, 60),
    PdfLineTo(140, 60),
    PdfLineTo(140, 140),
    PdfLineTo(60, 140),
    PdfClosePath(),
  ]);

  test('geometry is reused per fill rule and released under memory pressure',
      () {
    final cache = PdfCanvasPathCache();
    addTearDown(cache.dispose);
    var builds = 0;
    ui.Path build() {
      builds++;
      return ui.Path();
    }

    final a = cache.pathFor(path, PdfFillRule.nonzero, build);
    expect(cache.pathFor(path, PdfFillRule.nonzero, build), same(a));
    final b = cache.pathFor(path, PdfFillRule.evenOdd, build);
    expect(b, isNot(same(a)));
    expect(builds, 2);
    PdfCacheRegistry.instance.handleMemoryPressure();
    expect(cache.pathFor(path, PdfFillRule.nonzero, build), isNot(same(a)));
    expect(builds, 3);
  });

  test('entry and weight caps bound retained native geometry', () {
    final cache = PdfCanvasPathCache(maxEntries: 1);
    addTearDown(cache.dispose);
    final a = cache.pathFor(path, PdfFillRule.nonzero, ui.Path.new);
    cache.pathFor(path, PdfFillRule.evenOdd, ui.Path.new);
    expect(cache.pathFor(path, PdfFillRule.nonzero, ui.Path.new), same(a),
        reason: 'a full cache retains its reusable subset');

    final tiny = PdfCanvasPathCache(maxWeight: 1);
    addTearDown(tiny.dispose);
    final large = tiny.pathFor(path, PdfFillRule.nonzero, ui.Path.new);
    expect(tiny.pathFor(path, PdfFillRule.nonzero, ui.Path.new),
        isNot(same(large)),
        reason: 'oversize paths must be returned uncached');
  });

  test('repeated scans past the entry cap keep admitted paths warm', () {
    final cache = PdfCanvasPathCache(maxEntries: 2);
    addTearDown(cache.dispose);
    final sources = List.generate(4, (_) => PdfPath(path.segments));
    final builds = List.filled(4, 0);
    final initial = <ui.Path>[];
    for (var scan = 0; scan < 3; scan++) {
      for (var i = 0; i < sources.length; i++) {
        final result = cache.pathFor(sources[i], PdfFillRule.nonzero, () {
          builds[i]++;
          return ui.Path();
        });
        if (scan == 0) {
          initial.add(result);
        } else {
          expect(result, i < 2 ? same(initial[i]) : isNot(same(initial[i])));
        }
      }
    }
    expect(builds, [1, 1, 3, 3]);
  });

  test('weight admission preserves the subset and fills smaller free slots',
      () {
    // The first path weighs 512; the next 320 cannot fit, but the final 224
    // can. Total retained weight reaches 736 without evicting the first path.
    final sources = [
      path,
      PdfPath(path.segments.take(4).toList()),
      PdfPath(path.segments.take(1).toList()),
    ];
    final cache = PdfCanvasPathCache(maxEntries: 2, maxWeight: 736);
    addTearDown(cache.dispose);
    final builds = List.filled(3, 0);
    for (var scan = 0; scan < 3; scan++) {
      for (var i = 0; i < sources.length; i++) {
        cache.pathFor(sources[i], PdfFillRule.nonzero, () {
          builds[i]++;
          return ui.Path();
        });
      }
    }
    expect(builds, [1, 3, 1]);
    final occupancy = PdfCacheRegistry.instance
        .snapshot()
        .singleWhere((entry) => entry.label == 'canvas-paths');
    expect(occupancy.length, 2);
    expect(occupancy.weight, 736);
    expect(occupancy.evictions, 0);
  });

  test('pressure reopens admission and disposal leaves all paths uncached', () {
    final cache = PdfCanvasPathCache(maxEntries: 1);
    addTearDown(cache.dispose);
    final first = cache.pathFor(path, PdfFillRule.nonzero, ui.Path.new);
    final declined = cache.pathFor(path, PdfFillRule.evenOdd, ui.Path.new);
    PdfCacheRegistry.instance.handleMemoryPressure();
    final replacement = cache.pathFor(path, PdfFillRule.evenOdd, ui.Path.new);
    expect(replacement, isNot(same(declined)));
    expect(cache.pathFor(path, PdfFillRule.evenOdd, ui.Path.new),
        same(replacement));
    expect(cache.pathFor(path, PdfFillRule.nonzero, ui.Path.new),
        isNot(same(first)));
    cache.dispose();
    final uncached = cache.pathFor(path, PdfFillRule.evenOdd, ui.Path.new);
    expect(uncached, isNot(same(replacement)));
    expect(cache.pathFor(path, PdfFillRule.evenOdd, ui.Path.new),
        isNot(same(uncached)));
  });

  testWidgets('retained paths keep fills, dashes and clips exact across zooms',
      (tester) async {
    await tester.runAsync(() async {
      final page = PdfDocument.open(buildClassicPdf()).page(0);
      // The same geometry appears under both rules, and as both a stroke and
      // a clip. Caching must never let a fill type or dashed derivative leak
      // into another use of the path.
      final commands = <PdfRenderCommand>[
        const PdfFillPathCommand(
            path, PdfColor(1, 0, 0), PdfFillRule.nonzero, 1),
        const PdfFillPathCommand(
            path, PdfColor(0, 0, 1), PdfFillRule.evenOdd, 1),
        const PdfStrokePathCommand(path, PdfColor(0, 1, 0),
            PdfStroke(width: 3, dashArray: [7, 3], dashPhase: 2), 0.7),
        const PdfSaveCommand(),
        const PdfClipPathCommand(path, PdfFillRule.evenOdd),
        const PdfFillPathCommand(
            PdfPath([
              PdfMoveTo(0, 0),
              PdfCubicTo(0, 200, 200, 0, 200, 200),
              PdfLineTo(0, 200),
              PdfClosePath(),
            ]),
            PdfColor(1, 1, 0),
            PdfFillRule.nonzero,
            0.5),
        const PdfRestoreCommand(),
      ];
      final scene = await PdfRetainedScene.fromCommands(page, commands);
      try {
        for (final ratio in [1.0, 2.5, 1.0]) {
          final picture =
              await PdfPageRenderer.pictureFromCommands(page, commands);
          final direct =
              await PdfPageRenderer.rasterize(picture, scene.pageSize, ratio);
          final retained = await scene.rasterize(pixelRatio: ratio);
          try {
            expect(await pixels(retained), await pixels(direct),
                reason: 'ratio $ratio');
          } finally {
            direct.dispose();
            retained.dispose();
            picture.dispose();
          }
        }
      } finally {
        scene.dispose();
      }
    });
  });
}

Future<Uint8List> pixels(ui.Image image) async =>
    (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!
        .buffer
        .asUint8List();
