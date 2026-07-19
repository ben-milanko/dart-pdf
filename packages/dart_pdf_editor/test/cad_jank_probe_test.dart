// Baseline + fix probe for the "iPad janky pan" report on a huge single-page
// CAD drawing (Cathodic Protection MTM Electrolysis CSR): 8504x842 pt, ~2.6M
// content ops in 8 concatenated content streams.
//
// Drives the EXACT retained-scene / region-replay pipeline the viewer uses,
// on the test isolate, so the tile cull + text-extract costs can be measured
// against the real file without a device.
//
//   cd packages/dart_pdf_editor
//   CAD_PDF=../../corpus/cathodic-cad.pdf \
//     fvm flutter test test/cad_jank_probe_test.dart
//
// Knobs:
//   CAD_PDF        path to the PDF (default ../../corpus/cathodic-cad.pdf)
//   CAD_RATIO      device px per point for the tile raster (default 2.0)
//   CAD_TILE       tile size in device px (default 256)
//   CAD_PAN_TILES  number of tiles sampled across the pan (default 16)
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_graphics/pdf_graphics.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';

import 'render_smoke_test.dart' show loadSystemFonts;

void main() {
  final path = Platform.environment['CAD_PDF'] ?? '../../corpus/cathodic-cad.pdf';
  final ratio = double.tryParse(Platform.environment['CAD_RATIO'] ?? '') ?? 2.0;
  final tilePx = double.tryParse(Platform.environment['CAD_TILE'] ?? '') ?? 256;
  final panTiles = int.tryParse(Platform.environment['CAD_PAN_TILES'] ?? '') ?? 16;

  testWidgets('CAD jank baseline probe', (tester) async {
    final file = File(path);
    if (!file.existsSync()) {
      markTestSkipped('set CAD_PDF to a real file (missing: $path)');
      return;
    }

    await tester.runAsync(() async {
      await loadSystemFonts();
      final bytes = file.readAsBytesSync();
      final doc = PdfDocument.open(bytes);
      _line('opened ${_mb(bytes.length)} - ${doc.pageCount} pages');

      final rss0 = ProcessInfo.currentRss;
      _line('RSS at open: ${_mb(rss0)}');
      final page = doc.page(0);
      final size = PdfPageRenderer.pageSize(page);
      _line('page 0 size: ${size.width.toStringAsFixed(0)} x '
          '${size.height.toStringAsFixed(0)} pt  '
          '(aspect ${(size.width / size.height).toStringAsFixed(1)}:1)');

      // --- Record the retained scene (interpret + decode), as the viewer does.
      final recSw = Stopwatch()..start();
      final scene = await PdfRetainedScene.record(page);
      recSw.stop();
      _line('record (interpret+decode): ${recSw.elapsedMilliseconds} ms, '
          '${scene.commands.length} render commands');
      _line('RSS after record (transcript retained): '
          '${_mb(ProcessInfo.currentRss)} (+${_mb(ProcessInfo.currentRss - rss0)})');

      // Grid escalation is the default now; CAD_NOGRID=1 restores the old
      // full-transcript-replay behaviour for an A/B baseline.
      if (Platform.environment['CAD_NOGRID'] == '1') {
        PdfRetainedScene.spatialGridReplay = false;
        _line('*** GRID DISABLED (CAD_NOGRID) — old full-replay baseline ***');
      } else {
        _line('*** GRID escalation active (default; >linear ceiling) '
            'maxCommands=${PdfRetainedScene.spatialGridReplayMaxCommands} ***');
      }

      // --- The pivotal gate: does the tile/cull path engage for this page?
      //     First access builds the index (O(commands)); time it, since that
      //     build is pure data (no dart:ui) and thus worker-offloadable.
      final idxSw = Stopwatch()..start();
      final supported = scene.supportsRegionRaster;
      idxSw.stop();
      _line('region-index build (first raster, UI-isolate today): '
          '${idxSw.elapsedMilliseconds} ms  [worker-offloadable: pure data]');
      _line('linear ceiling = '
          '${PdfRetainedScene.spatialRegionReplayMaxCommands}');
      _line('supportsRegionRaster = $supported  '
          '(=> viewer ${supported ? "USES tiles + cull" : "DISABLES tiles, "
              "full-transcript replay per raster"})');
      if (supported) {
        _line('region index: ${scene.debugRegionReplayUnitCount} units, '
            'est ${_mb(scene.debugRegionReplayEstimatedBytes)}');
      }

      // --- Simulate a pan: rasterize tile-sized regions sliding across the
      //     8504pt-wide page, timing each and recording units replayed.
      final tilePt = tilePx / ratio;
      final yMid = (size.height / 2 - tilePt / 2).clamp(0.0, size.height);
      final maxX = (size.width - tilePt).clamp(0.0, size.width);
      final perTileMs = <double>[];
      final perTileCpuMs = <double>[]; // cull + build picture (offloadable CPU)
      final perTileGpuMs = <double>[]; // toImage readback (UI-isolate only)
      final perTileCmds = <int>[];
      var selectiveCount = 0;
      for (var i = 0; i < panTiles; i++) {
        final x = maxX * i / (panTiles - 1);
        final region = Rect.fromLTWH(x, yMid, tilePt, tilePt);
        final sw = Stopwatch()..start();
        // Split the cost: replayRegion = grid cull + canvas ops (CPU, the only
        // part a worker could take); toImage = GPU readback (must stay here).
        final cpu = Stopwatch()..start();
        final picture = scene.replayRegion(region, pixelRatio: ratio);
        cpu.stop();
        final gpu = Stopwatch()..start();
        final img = await picture.toImage(
            (tilePt * ratio).ceil(), (tilePt * ratio).ceil());
        gpu.stop();
        sw.stop();
        picture.dispose();
        perTileMs.add(sw.elapsedMicroseconds / 1000.0);
        perTileCpuMs.add(cpu.elapsedMicroseconds / 1000.0);
        perTileGpuMs.add(gpu.elapsedMicroseconds / 1000.0);
        perTileCmds.add(scene.debugLastRegionReplayCommandCount);
        if (scene.debugLastRegionReplayWasSelective) selectiveCount++;
        img.dispose();
      }
      _line('--- pan: $panTiles tiles of ${tilePx}px @${ratio}x '
          '(${tilePt.toStringAsFixed(0)}pt) across the width ---');
      _line('per-tile rasterize ${_dist(perTileMs)}');
      _line('  CPU (cull+build, offloadable) ${_dist(perTileCpuMs)}');
      _line('  GPU (toImage, UI-isolate only) ${_dist(perTileGpuMs)}');
      _line('per-tile commands replayed: min=${_min(perTileCmds)} '
          'max=${_max(perTileCmds)} '
          'mean=${(_sum(perTileCmds) / perTileCmds.length).round()} '
          '(selective=$selectiveCount/$panTiles, '
          'transcript=${scene.commands.length})');
      _line('RSS after pan sweep: ${_mb(ProcessInfo.currentRss)}');

      // --- Text extraction cost (the 478ms UI-isolate stall on first hover).
      final txtSw = Stopwatch()..start();
      final text = PdfTextExtractor.extract(doc, 0);
      txtSw.stop();
      _line('textExtract: ${txtSw.elapsedMilliseconds} ms '
          '(${text.runs.length} runs, ${text.text.length} chars)');

      scene.dispose();
    });
  }, timeout: const Timeout(Duration(minutes: 20)));
}

String _mb(int bytes) => '${(bytes / (1 << 20)).toStringAsFixed(1)} MB';
int _min(List<int> v) => v.reduce((a, b) => a < b ? a : b);
int _max(List<int> v) => v.reduce((a, b) => a > b ? a : b);
int _sum(List<int> v) => v.fold(0, (a, b) => a + b);

String _dist(List<double> values) {
  if (values.isEmpty) return 'n/a';
  final sorted = [...values]..sort();
  double at(double q) => sorted[(q * (sorted.length - 1)).round()];
  return 'p50=${at(0.50).toStringAsFixed(1)}ms '
      'p95=${at(0.95).toStringAsFixed(1)}ms '
      'max=${sorted.last.toStringAsFixed(1)}ms '
      'sum=${_sumd(values).toStringAsFixed(0)}ms';
}

double _sumd(List<double> v) => v.fold(0.0, (a, b) => a + b);

void _line(String s) {
  // ignore: avoid_print
  print('[cad-jank] $s');
}
