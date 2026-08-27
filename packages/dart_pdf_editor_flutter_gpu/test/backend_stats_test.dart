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
      expect(desktop.overprintRetryMaxDimension, 512);
      expect(desktop.maxTransientAttachmentBytes, 64 << 20);
      expect(
        FlutterGpuTileRasterBackend(overprintRetryMaxDimension: null)
            .overprintRetryMaxDimension,
        isNull,
      );
      expect(
        FlutterGpuTileRasterBackend(maxTransientAttachmentBytes: 0)
            .maxTransientAttachmentBytes,
        0,
      );

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
      ..overprintRetryRequests = 3
      ..overprintRetrySuccesses = 2
      ..overprintRetryFallbacks = 1
      ..overprintRetryMicros = 24000
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
      ..standaloneUniformBuffers = 9
      ..transientBuffers = 5
      ..transientBufferReuses = 11
      ..transientEmplacedBytes = 768 << 10
      ..transientAllocatedBytes = 1 << 20
      ..transientResidentBytes = 2 << 20
      ..peakTransientResidentBytes = 3 << 20
      ..peakTransientTileBytes = 896 << 10
      ..transientAttachmentTextures = 4
      ..transientAttachmentReuses = 12
      ..transientAttachmentAllocatedBytes = 20 << 20
      ..transientAttachmentResidentBytes = 24 << 20
      ..peakTransientAttachmentResidentBytes = 32 << 20
      ..peakTransientAttachmentTileBytes = 16 << 20
      ..textureImports = 6
      ..analyticTextRuns = 7
      ..analyticGlyphQuads = 18
      ..analyticGlyphSlots = 4
      ..analyticAtlasBytes = 4096
      ..analyticAtlasFallbacks = 1
      ..analyticSparseAtlasSkips = 3
      ..analyticTextFallbackRuns = 2
      ..coalescedDrawBatches = 8
      ..drawCallsSaved = 120
      ..drawCalls = 64
      ..directRectangleDraws = 96
      ..paperClearTiles = 6
      ..paperOnlyTiles = 3
      ..subpixelStrokeFallbacks = 2
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
    expect(stats.toJson(), containsPair('overprintRetryRequests', 3));
    expect(stats.toJson(), containsPair('overprintRetrySuccesses', 2));
    expect(stats.toJson(), containsPair('overprintRetryFallbacks', 1));
    expect(stats.toJson(), containsPair('overprintRetryMicros', 24000));
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
    expect(stats.toJson(), containsPair('standaloneUniformBuffers', 9));
    expect(stats.toJson(), containsPair('transientBuffers', 5));
    expect(stats.toJson(), containsPair('transientBufferReuses', 11));
    expect(stats.toJson(), containsPair('transientEmplacedBytes', 768 << 10));
    expect(stats.toJson(), containsPair('transientAllocatedBytes', 1 << 20));
    expect(stats.toJson(), containsPair('transientResidentBytes', 2 << 20));
    expect(stats.toJson(), containsPair('peakTransientResidentBytes', 3 << 20));
    expect(stats.toJson(), containsPair('peakTransientTileBytes', 896 << 10));
    expect(stats.toJson(), containsPair('transientAttachmentTextures', 4));
    expect(stats.toJson(), containsPair('transientAttachmentReuses', 12));
    expect(stats.toJson(),
        containsPair('transientAttachmentAllocatedBytes', 20 << 20));
    expect(stats.toJson(),
        containsPair('transientAttachmentResidentBytes', 24 << 20));
    expect(stats.toJson(),
        containsPair('peakTransientAttachmentResidentBytes', 32 << 20));
    expect(stats.toJson(),
        containsPair('peakTransientAttachmentTileBytes', 16 << 20));
    expect(stats.toJson(), containsPair('textureImports', 6));
    expect(stats.toJson(), containsPair('analyticGlyphQuads', 18));
    expect(stats.toJson(), containsPair('analyticGlyphSlots', 4));
    expect(stats.toJson(), containsPair('analyticAtlasBytes', 4096));
    expect(stats.toJson(), containsPair('analyticAtlasFallbacks', 1));
    expect(stats.toJson(), containsPair('analyticSparseAtlasSkips', 3));
    expect(stats.toJson(), containsPair('analyticTextFallbackRuns', 2));
    expect(stats.toJson(), containsPair('coalescedDrawBatches', 8));
    expect(stats.toJson(), containsPair('drawCallsSaved', 120));
    expect(stats.toJson(), containsPair('drawCalls', 64));
    expect(stats.toJson(), containsPair('directRectangleDraws', 96));
    expect(stats.toJson(), containsPair('paperClearTiles', 6));
    expect(stats.toJson(), containsPair('paperOnlyTiles', 3));
    expect(stats.toJson(), containsPair('subpixelStrokeFallbacks', 2));
    expect(stats.toJson(), containsPair('advancedBlendBlits', 5));
    expect(stats.toJson(), containsPair('advancedBlendCroppedSources', 4));
    expect(stats.toJson(), containsPair('offscreenGroupPasses', 3));
    expect(
        stats.toJson(), containsPair('offscreenGroupAllocatedBytes', 6 << 20));
    expect(stats.toJson(), containsPair('peakOffscreenGroupBytes', 4 << 20));
    expect(stats.toJson(), containsPair('offscreenGroupBudgetFallbacks', 1));

    stats.reset();
    expect(stats.sessionsCreated, 0);
    expect(stats.overprintRetryRequests, 0);
    expect(stats.overprintRetrySuccesses, 0);
    expect(stats.overprintRetryFallbacks, 0);
    expect(stats.overprintRetryMicros, 0);
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
    expect(stats.standaloneUniformBuffers, 0);
    expect(stats.transientBuffers, 0);
    expect(stats.transientBufferReuses, 0);
    expect(stats.transientEmplacedBytes, 0);
    expect(stats.transientAllocatedBytes, 0);
    expect(stats.transientResidentBytes, 2 << 20);
    expect(stats.peakTransientResidentBytes, 2 << 20);
    expect(stats.peakTransientTileBytes, 0);
    expect(stats.transientAttachmentTextures, 0);
    expect(stats.transientAttachmentReuses, 0);
    expect(stats.transientAttachmentAllocatedBytes, 0);
    expect(stats.transientAttachmentResidentBytes, 24 << 20);
    expect(stats.peakTransientAttachmentResidentBytes, 24 << 20);
    expect(stats.peakTransientAttachmentTileBytes, 0);
    expect(stats.textureImports, 0);
    expect(stats.analyticTextRuns, 0);
    expect(stats.analyticGlyphQuads, 0);
    expect(stats.analyticGlyphSlots, 0);
    expect(stats.analyticAtlasBytes, 0);
    expect(stats.analyticAtlasFallbacks, 0);
    expect(stats.analyticSparseAtlasSkips, 0);
    expect(stats.analyticTextFallbackRuns, 0);
    expect(stats.coalescedDrawBatches, 0);
    expect(stats.drawCallsSaved, 0);
    expect(stats.drawCalls, 0);
    expect(stats.directRectangleDraws, 0);
    expect(stats.paperClearTiles, 0);
    expect(stats.paperOnlyTiles, 0);
    expect(stats.subpixelStrokeFallbacks, 0);
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
