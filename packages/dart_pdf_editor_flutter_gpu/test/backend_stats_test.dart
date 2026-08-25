import 'package:dart_pdf_editor_flutter_gpu/dart_pdf_editor_flutter_gpu.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('proactive warm-up defaults to desktop and remains opt-in on mobile',
      () {
    final previous = debugDefaultTargetPlatformOverride;
    try {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final mobile = FlutterGpuTileRasterBackend();
      expect(mobile.supportsWarmUp, isFalse);
      expect(mobile.supportsSessionWarmUp, isFalse);

      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      final desktop = FlutterGpuTileRasterBackend();
      expect(desktop.supportsWarmUp, isTrue);
      expect(desktop.supportsSessionWarmUp, isTrue);

      final optedIn = FlutterGpuTileRasterBackend(enableProactiveWarmUp: true);
      expect(optedIn.supportsWarmUp, isTrue);
      expect(optedIn.supportsSessionWarmUp, isTrue);
      final optedOut =
          FlutterGpuTileRasterBackend(enableProactiveWarmUp: false);
      expect(optedOut.supportsWarmUp, isFalse);
      expect(optedOut.supportsSessionWarmUp, isFalse);
    } finally {
      debugDefaultTargetPlatformOverride = previous;
    }
  });

  test('JSON snapshot includes outcomes and reset preserves live gauges', () {
    final stats = FlutterGpuTileBackendStats()
      ..sessionsCreated = 4
      ..sessionsRejected = 2
      ..sessionsDisposed = 1
      ..rasterFallbacks = 1
      ..lastContextIdentity = 1234
      ..contextsSeen = 2
      ..contextSwitches = 3
      ..warmUpRequests = 2
      ..warmUpSubmissions = 1
      ..warmUpCompletions = 2
      ..warmUpMicros = 12000
      ..sceneWarmUpRequests = 3
      ..sceneWarmUpCompletions = 2
      ..sceneWarmUpFailures = 1
      ..sceneWarmUpCancellations = 1
      ..sceneWarmUpMicros = 18000
      ..lastSceneWarmUpError = 'test scene warm-up failure'
      ..activeSessions = 3
      ..peakActiveSessions = 4
      ..activeTextureLeases = 5
      ..textureBytes = 12 << 20
      ..peakTextureBytes = 18 << 20
      ..activeGeometryLeases = 2
      ..geometryBuffers = 3
      ..geometryBytes = 32 << 20
      ..peakGeometryBytes = 48 << 20
      ..analyticTextRuns = 7
      ..analyticGlyphQuads = 18
      ..analyticGlyphSlots = 4
      ..analyticAtlasBytes = 4096
      ..analyticAtlasFallbacks = 1
      ..analyticTextFallbackRuns = 2
      ..paperClearTiles = 6
      ..advancedBlendBlits = 5
      ..advancedBlendCroppedSources = 4
      ..offscreenGroupPasses = 3
      ..offscreenGroupAllocatedBytes = 6 << 20
      ..peakOffscreenGroupBytes = 4 << 20
      ..offscreenGroupBudgetFallbacks = 1
      ..completedSubmissions = 8
      ..completionMicros = 32000
      ..maxCompletionMicros = 9000
      ..failedSubmissions = 1
      ..inFlightSubmissions = 2
      ..peakInFlightSubmissions = 4
      ..lastTileRoute = 'canvas-fallback'
      ..lastRejection = 'test fallback';

    expect(stats.toJson(), containsPair('rasterFallbacks', 1));
    expect(stats.toJson(), containsPair('lastRejection', 'test fallback'));
    expect(stats.toJson(), containsPair('lastTileRoute', 'canvas-fallback'));
    expect(stats.toJson(), containsPair('completedSubmissions', 8));
    expect(stats.toJson(), containsPair('maxCompletionMicros', 9000));
    expect(stats.toJson(), containsPair('lastContextIdentity', 1234));
    expect(stats.toJson(), containsPair('contextsSeen', 2));
    expect(stats.toJson(), containsPair('contextSwitches', 3));
    expect(stats.toJson(), containsPair('warmUpSubmissions', 1));
    expect(stats.toJson(), containsPair('warmUpMicros', 12000));
    expect(stats.toJson(), containsPair('sceneWarmUpRequests', 3));
    expect(stats.toJson(), containsPair('sceneWarmUpCompletions', 2));
    expect(stats.toJson(), containsPair('sceneWarmUpFailures', 1));
    expect(stats.toJson(), containsPair('sceneWarmUpCancellations', 1));
    expect(stats.toJson(), containsPair('sceneWarmUpMicros', 18000));
    expect(stats.toJson(), containsPair('analyticTextRuns', 7));
    expect(stats.toJson(), containsPair('analyticGlyphQuads', 18));
    expect(stats.toJson(), containsPair('analyticGlyphSlots', 4));
    expect(stats.toJson(), containsPair('analyticAtlasBytes', 4096));
    expect(stats.toJson(), containsPair('analyticAtlasFallbacks', 1));
    expect(stats.toJson(), containsPair('analyticTextFallbackRuns', 2));
    expect(stats.toJson(), containsPair('paperClearTiles', 6));
    expect(stats.toJson(), containsPair('advancedBlendBlits', 5));
    expect(stats.toJson(), containsPair('advancedBlendCroppedSources', 4));
    expect(stats.toJson(), containsPair('offscreenGroupPasses', 3));
    expect(
        stats.toJson(), containsPair('offscreenGroupAllocatedBytes', 6 << 20));
    expect(stats.toJson(), containsPair('peakOffscreenGroupBytes', 4 << 20));
    expect(stats.toJson(), containsPair('offscreenGroupBudgetFallbacks', 1));

    stats.reset();
    expect(stats.sessionsCreated, 0);
    expect(stats.rasterFallbacks, 0);
    expect(stats.lastContextIdentity, 1234);
    expect(stats.contextsSeen, 2);
    expect(stats.contextSwitches, 0);
    expect(stats.warmUpRequests, 0);
    expect(stats.warmUpSubmissions, 0);
    expect(stats.warmUpCompletions, 0);
    expect(stats.warmUpMicros, 0);
    expect(stats.sceneWarmUpRequests, 0);
    expect(stats.sceneWarmUpCompletions, 0);
    expect(stats.sceneWarmUpFailures, 0);
    expect(stats.sceneWarmUpCancellations, 0);
    expect(stats.sceneWarmUpMicros, 0);
    expect(stats.lastSceneWarmUpError, isNull);
    expect(stats.lastRejection, isNull);
    expect(stats.lastTileRoute, isNull);
    expect(stats.activeSessions, 3);
    expect(stats.activeTextureLeases, 5);
    expect(stats.textureBytes, 12 << 20);
    expect(stats.peakTextureBytes, 12 << 20);
    expect(stats.activeGeometryLeases, 2);
    expect(stats.geometryBuffers, 3);
    expect(stats.geometryBytes, 32 << 20);
    expect(stats.peakGeometryBytes, 32 << 20);
    expect(stats.analyticTextRuns, 0);
    expect(stats.analyticGlyphQuads, 0);
    expect(stats.analyticGlyphSlots, 0);
    expect(stats.analyticAtlasBytes, 0);
    expect(stats.analyticAtlasFallbacks, 0);
    expect(stats.analyticTextFallbackRuns, 0);
    expect(stats.paperClearTiles, 0);
    expect(stats.advancedBlendBlits, 0);
    expect(stats.advancedBlendCroppedSources, 0);
    expect(stats.offscreenGroupPasses, 0);
    expect(stats.offscreenGroupAllocatedBytes, 0);
    expect(stats.peakOffscreenGroupBytes, 0);
    expect(stats.offscreenGroupBudgetFallbacks, 0);
    expect(stats.completedSubmissions, 0);
    expect(stats.completionMicros, 0);
    expect(stats.inFlightSubmissions, 2);
    expect(stats.peakInFlightSubmissions, 2);
  });
}
