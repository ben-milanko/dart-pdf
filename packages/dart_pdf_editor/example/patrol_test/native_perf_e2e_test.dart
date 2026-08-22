// Patrol targets live outside Flutter's conventional test/ directory, but
// this is still test code and deliberately exercises diagnostic seams.
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'dart:ui' as ui;

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patrol/patrol.dart';

const _buildCommit = String.fromEnvironment('PDF_BUILD_COMMIT');
const _mb = 1024 * 1024;

void main() {
  if (_buildCommit.isNotEmpty) {
    PdfPerfLog.buildTag = 'commit=$_buildCommit';
  }

  patrolTest('fills and settles the native mobile tile budget', ($) async {
    expect($.isWeb, isFalse);
    await $.pumpWidget(const MaterialApp(home: SizedBox()));
    await runNativeTilePerfScenario(pump: $.pump);
    await $.pumpWidget(const SizedBox());
    await $.pump(const Duration(milliseconds: 50));
  });
}

@visibleForTesting
Future<void> runNativeTilePerfScenario({
  required Future<void> Function(Duration duration) pump,
}) async {
  final platform = switch (defaultTargetPlatform) {
    TargetPlatform.android => 'android',
    TargetPlatform.iOS => 'ios',
    _ => defaultTargetPlatform.name,
  };
  final store = PdfTileStore(registerForMemoryPressure: false);
  final mobile = defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;
  final identity = PdfTilePageIdentity(
    cacheNamespace: Object(),
    pageIndex: 0,
    pageEpoch: 0,
    contentStamp: 0,
    destructiveStamp: 0,
    plan: const PdfPageRenderPlan(),
  );

  // Sixteen columns by four rows is exactly 64 MiB at the production
  // 512px RGBA tile size. Four viewport visits therefore exercise the real
  // mobile ceiling without relying on a corpus file or network provider.
  const pageSize = Size(8192, 2048);
  const windows = <Rect>[
    Rect.fromLTWH(0, 512, 1536, 1024),
    Rect.fromLTWH(2560, 512, 1536, 1024),
    Rect.fromLTWH(5120, 512, 1536, 1024),
    Rect.fromLTWH(6656, 512, 1536, 1024),
  ];
  var rasterCalls = 0;

  Future<ui.Image> rasterize(Rect region, double ratio) async {
    final clock = Stopwatch()..start();
    final width = (region.width * ratio).ceil().clamp(1, 1 << 14);
    final height = (region.height * ratio).ceil().clamp(1, 1 << 14);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      Paint()..color = const Color(0xFF102A1F),
    );
    final grid = Paint()
      ..color = const Color(0xFF4ADE80)
      ..strokeWidth = 2;
    final xOffset = -(region.left % 64) * ratio;
    final yOffset = -(region.top % 64) * ratio;
    for (var x = xOffset; x <= width; x += 64 * ratio) {
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, height.toDouble()),
        grid,
      );
    }
    for (var y = yOffset; y <= height; y += 64 * ratio) {
      canvas.drawLine(
        Offset(0, y),
        Offset(width.toDouble(), y),
        grid,
      );
    }
    final picture = recorder.endRecording();
    try {
      final image = await picture.toImage(width, height);
      rasterCalls++;
      PdfPerfLog.log(
        'raster page=0 kind=native-tile platform=$platform '
        'ms=${(clock.elapsedMicroseconds / 1000).toStringAsFixed(1)} '
        'img=${width}x$height',
      );
      return image;
    } finally {
      picture.dispose();
    }
  }

  PdfPerfLog.log(
    'scenario name=native-mobile-tiles phase=start platform=$platform '
    'budgetBytes=${store.maxBytes} tilePixels=${store.tilePixels}',
  );
  try {
    expect(store.maxBytes, mobile ? 64 * _mb : 96 * _mb,
        reason: 'the native store must use its platform policy ceiling');
    for (final window in windows) {
      final status = store.viewBudgetStatus(
        pageSize: pageSize,
        desiredRatio: 1,
        visiblePageRect: window,
      );
      expect(status, isNotNull);
      expect(status!.fits, isTrue,
          reason: 'each foreground viewport must fit the mobile budget');
      final view = await _settleWindow(
        pump,
        store,
        identity,
        pageSize,
        window,
        rasterize,
      );
      expect(view.complete, isTrue);
      expect(view.placements, hasLength(status.visibleTiles));
      expect(view.placements.every((tile) => !tile.isFallback), isTrue);
    }

    expect(store.inFlightCount, 0);
    expect(store.retainedBytes, 64 * _mb,
        reason: 'the journey must fill the mobile policy working set');
    expect(store.retainedBytes, lessThanOrEqualTo(store.maxBytes));
    if (mobile) {
      expect(store.retainedBytes, store.maxBytes,
          reason: 'the mobile journey must reach, but never exceed, its cap');
    }
    expect(store.tileCount, 64);
    expect(store.debugTilesDiscarded, 0);

    final scheduledBeforeStatic = store.debugTilesScheduled;
    for (var i = 0; i < 4; i++) {
      final view = store.viewFor(
        id: identity,
        pageSize: pageSize,
        desiredRatio: 1,
        visiblePageRect: windows.first,
        rasterize: rasterize,
      );
      expect(view.complete, isTrue);
      expect(view.placements.every((tile) => !tile.isFallback), isTrue);
      await pump(const Duration(milliseconds: 100));
    }
    final staticRescheduled = store.debugTilesScheduled - scheduledBeforeStatic;
    expect(staticRescheduled, 0,
        reason: 'a static sharp viewport must not restart tile work');

    PdfPerfLog.log(
      'tile stats platform=$platform budget=${store.maxBytes} '
      'retained=${store.retainedBytes} entries=${store.tileCount} '
      'scheduled=${store.debugTilesScheduled} '
      'landed=${store.debugTilesLanded} '
      'discarded=${store.debugTilesDiscarded} '
      'staticRescheduled=$staticRescheduled rasterCalls=$rasterCalls',
    );
    PdfPerfLog.log(
      'scenario name=native-mobile-tiles phase=validated '
      'platform=$platform budgetBytes=${store.maxBytes}',
    );
  } finally {
    store.dispose();
    await pump(const Duration(milliseconds: 50));
  }
}

Future<PdfTileView> _settleWindow(
  Future<void> Function(Duration duration) pump,
  PdfTileStore store,
  PdfTilePageIdentity identity,
  Size pageSize,
  Rect window,
  PdfTileRasterizer rasterize,
) async {
  PdfTileView? view;
  var stablePasses = 0;
  var previousScheduled = -1;
  for (var i = 0; i < 240; i++) {
    view = store.viewFor(
      id: identity,
      pageSize: pageSize,
      desiredRatio: 1,
      visiblePageRect: window,
      rasterize: rasterize,
    );
    await pump(const Duration(milliseconds: 50));
    if (view.complete &&
        store.inFlightCount == 0 &&
        store.debugTilesScheduled == previousScheduled) {
      stablePasses++;
      if (stablePasses == 2) return view;
    } else {
      stablePasses = 0;
    }
    previousScheduled = store.debugTilesScheduled;
  }
  fail(
    'native tile window did not settle: complete=${view?.complete} '
    'inFlight=${store.inFlightCount} scheduled=${store.debugTilesScheduled}',
  );
}
