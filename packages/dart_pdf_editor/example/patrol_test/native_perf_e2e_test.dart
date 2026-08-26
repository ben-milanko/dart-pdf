// Patrol targets live outside Flutter's conventional test/ directory, but
// this is still test code and deliberately exercises diagnostic seams.
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'dart:ui' as ui;

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:dart_pdf_editor_flutter_gpu/dart_pdf_editor_flutter_gpu.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patrol/patrol.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';

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

  patrolTest('warms and rasterizes a real native flutter_gpu scene', ($) async {
    expect($.isWeb, isFalse);
    await $.pumpWidget(const MaterialApp(home: SizedBox()));
    await runNativeGpuPerfScenario();
    await $.pumpWidget(const SizedBox());
    await $.pump(const Duration(milliseconds: 50));
  });
}

typedef _NativeGpuRaster = ({
  ByteData pixels,
  int width,
  int height,
});

@visibleForTesting
Future<void> runNativeGpuPerfScenario() async {
  final platform = _platformName();
  final document = PdfDocument.open(buildEmbeddedFontImagePdf());
  final scene = await PdfRetainedScene.record(document.page(0));
  final backend = FlutterGpuTileRasterBackend(enableProactiveWarmUp: true);
  PdfTileRasterSession? session;
  try {
    await _measureNativeGpuScenario(
      'gpu-native-pipeline-warm',
      platform,
      () async {
        await backend.warmUp();
        return null;
      },
    );
    expect(backend.stats.warmUpRequests, 1);
    expect(backend.stats.warmUpCompletions, 1);
    expect(backend.stats.warmUpFailures, 0);

    session = backend.createSession(scene);
    expect(session, isA<PdfTileRasterWarmUp>(),
        reason: backend.lastSessionRejection);
    final accelerated = session!;
    await _measureNativeGpuScenario(
      'gpu-native-page-0-scene-warm',
      platform,
      () async {
        await (accelerated as PdfTileRasterWarmUp).warmUp();
        return null;
      },
    );
    expect(backend.stats.sceneWarmUpRequests, 1);
    expect(backend.stats.sceneWarmUpCompletions, 1);
    expect(backend.stats.sceneWarmUpFailures, 0);
    expect(backend.stats.scenesCompiled, 1);
    expect(backend.stats.tilesRendered, 0,
        reason: 'the one-pixel scene warm-up is not a visible tile');

    const firstRegion = Rect.fromLTWH(40, 40, 256, 192);
    final firstGpu = await _measureNativeGpuScenario(
      'gpu-native-page-0-first-tile',
      platform,
      () => _rasterAndReadback(
        () => accelerated.rasterizeRegion(
          firstRegion,
          pixelRatio: 2,
          tracePage: 0,
        ),
      ),
    );
    final canvas = await _measureNativeGpuScenario(
      'gpu-native-page-0-canvas-tile',
      platform,
      () => _rasterAndReadback(
        () => scene.rasterizeRegion(firstRegion, pixelRatio: 2),
      ),
    );
    expect(firstGpu, isNotNull);
    expect(canvas, isNotNull);
    expect(firstGpu!.width, canvas!.width);
    expect(firstGpu.height, canvas.height);
    final meanDifference =
        _meanChannelDifference(firstGpu.pixels, canvas.pixels);
    expect(
      meanDifference,
      lessThan(12),
      reason: 'native GPU pixels must agree with Canvas apart from AA edges',
    );

    const reusedRegion = Rect.fromLTWH(72, 64, 256, 192);
    await _measureNativeGpuScenario(
      'gpu-native-page-0-reused-tile',
      platform,
      () => _rasterAndReadback(
        () => accelerated.rasterizeRegion(
          reusedRegion,
          pixelRatio: 2,
          tracePage: 0,
        ),
      ),
    );

    expect(backend.stats.contextsSeen, 1);
    expect(backend.stats.sessionsCreated, 1);
    expect(backend.stats.sessionsRejected, 0);
    expect(backend.stats.rasterFallbacks, 0);
    expect(backend.stats.tilesRendered, 2);
    expect(backend.stats.completedSubmissions, greaterThanOrEqualTo(3));
    expect(backend.stats.failedSubmissions, 0);
    expect(backend.stats.inFlightSubmissions, 0,
        reason: 'the readbacks must settle every GPU submission');
    expect(backend.stats.lastTileRoute, 'flutter_gpu');
    PdfPerfLog.log(
      'gpu native stats platform=$platform '
      'warmUs=${backend.stats.warmUpMicros} '
      'sceneWarmUs=${backend.stats.sceneWarmUpMicros} '
      'compileUs=${backend.stats.compileMicros} '
      'completeUs=${backend.stats.completionMicros} '
      'tiles=${backend.stats.tilesRendered} '
      'submissions=${backend.stats.completedSubmissions} '
      'fallbacks=${backend.stats.rasterFallbacks} '
      'meanDifference=${meanDifference.toStringAsFixed(3)}',
    );
  } finally {
    session?.dispose();
    backend.clearImageCache();
    scene.dispose();
  }
}

Future<_NativeGpuRaster?> _measureNativeGpuScenario(
  String name,
  String platform,
  Future<_NativeGpuRaster?> Function() operation,
) async {
  PdfPerfLog.log(
    'scenario name=$name phase=start platform=$platform',
  );
  final clock = Stopwatch()..start();
  final result = await operation();
  clock.stop();
  PdfPerfLog.log(
    'raster page=${name.contains('page-0') ? 0 : '-'} kind=$name '
    'platform=$platform '
    'ms=${(clock.elapsedMicroseconds / 1000).toStringAsFixed(1)}'
    '${result == null ? '' : ' img=${result.width}x${result.height}'}',
  );
  PdfPerfLog.log(
    'scenario name=$name phase=validated platform=$platform',
  );
  return result;
}

Future<_NativeGpuRaster> _rasterAndReadback(
  Future<ui.Image> Function() rasterize,
) async {
  final image = await rasterize();
  try {
    final pixels = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (pixels == null) fail('native raster RGBA readback returned null');
    return (pixels: pixels, width: image.width, height: image.height);
  } finally {
    image.dispose();
  }
}

double _meanChannelDifference(ByteData a, ByteData b) {
  final aa = a.buffer.asUint8List(a.offsetInBytes, a.lengthInBytes);
  final bb = b.buffer.asUint8List(b.offsetInBytes, b.lengthInBytes);
  expect(aa, hasLength(bb.length));
  var total = 0;
  for (var i = 0; i < aa.length; i++) {
    total += (aa[i] - bb[i]).abs();
  }
  return total / aa.length;
}

String _platformName() => switch (defaultTargetPlatform) {
      TargetPlatform.android => 'android',
      TargetPlatform.iOS => 'ios',
      _ => defaultTargetPlatform.name,
    };

@visibleForTesting
Future<void> runNativeTilePerfScenario({
  required Future<void> Function(Duration duration) pump,
}) async {
  final platform = _platformName();
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
