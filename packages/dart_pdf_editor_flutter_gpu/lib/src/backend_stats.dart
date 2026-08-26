/// Aggregated diagnostics for one flutter_gpu tile backend instance.
class FlutterGpuTileBackendStats {
  String? lastRejection;
  String? lastTileRoute;
  int? lastContextIdentity;
  int contextsSeen = 0;
  int contextSwitches = 0;
  int warmUpRequests = 0;
  int warmUpSubmissions = 0;
  int warmUpCompletions = 0;
  int warmUpFailures = 0;
  int warmUpMicros = 0;
  String? lastWarmUpError;
  int sceneWarmUpRequests = 0;
  int sceneWarmUpCompletions = 0;
  int sceneWarmUpFailures = 0;
  int sceneWarmUpCancellations = 0;
  int sceneWarmUpMicros = 0;
  String? lastSceneWarmUpError;
  int sessionsCreated = 0;
  int sessionsRejected = 0;
  int sessionsDisposed = 0;
  int overprintRetryRequests = 0;
  int overprintRetrySuccesses = 0;
  int overprintRetryFallbacks = 0;
  int overprintRetryMicros = 0;
  int rasterFallbacks = 0;
  int activeSessions = 0;
  int peakActiveSessions = 0;
  int overprintApproximationSessions = 0;
  int scenesCompiled = 0;
  int compileMicros = 0;
  int geometryBuffers = 0;
  int geometryVertices = 0;
  int analyticTextRuns = 0;
  int analyticGlyphQuads = 0;
  int analyticGlyphSlots = 0;
  int analyticAtlasBytes = 0;
  int analyticAtlasFallbacks = 0;
  int analyticSparseAtlasSkips = 0;
  int analyticTextFallbackRuns = 0;
  int clipPathsCompiled = 0;
  int clipMaskRebuilds = 0;
  int paperClearTiles = 0;
  int paperOnlyTiles = 0;
  int subpixelStrokeFallbacks = 0;
  int advancedBlendPasses = 0;
  int advancedBlendBlits = 0;
  int advancedBlendCroppedSources = 0;
  int advancedBlendAllocatedBytes = 0;
  int peakAdvancedBlendBytes = 0;
  int advancedBlendBudgetFallbacks = 0;
  int offscreenGroupPasses = 0;
  int offscreenGroupAllocatedBytes = 0;
  int peakOffscreenGroupBytes = 0;
  int offscreenGroupBudgetFallbacks = 0;
  int geometryBudgetFallbacks = 0;
  int activeGeometryLeases = 0;
  int geometryBytes = 0;
  int peakGeometryBytes = 0;
  int transientBuffers = 0;
  int transientEmplacedBytes = 0;
  int transientAllocatedBytes = 0;
  int peakTransientTileBytes = 0;
  int texturesUploaded = 0;
  int textureImports = 0;
  int textureDirectUploads = 0;
  int textureReadbacks = 0;
  int textureCacheHits = 0;
  int textureCacheMisses = 0;
  int textureEvictions = 0;
  int textureBudgetFallbacks = 0;
  int activeTextureLeases = 0;
  int textureBytes = 0;
  int peakTextureBytes = 0;
  int tilesRendered = 0;
  int selectedCommands = 0;
  int issueMicros = 0;
  int submitMicros = 0;
  int completedSubmissions = 0;
  int completionMicros = 0;
  int maxCompletionMicros = 0;
  int failedSubmissions = 0;
  int inFlightSubmissions = 0;
  int peakInFlightSubmissions = 0;

  /// A JSON-safe snapshot suitable for diagnostics and benchmark artifacts.
  Map<String, Object?> toJson() => {
        'lastRejection': lastRejection,
        'lastTileRoute': lastTileRoute,
        'lastContextIdentity': lastContextIdentity,
        'contextsSeen': contextsSeen,
        'contextSwitches': contextSwitches,
        'warmUpRequests': warmUpRequests,
        'warmUpSubmissions': warmUpSubmissions,
        'warmUpCompletions': warmUpCompletions,
        'warmUpFailures': warmUpFailures,
        'warmUpMicros': warmUpMicros,
        'lastWarmUpError': lastWarmUpError,
        'sceneWarmUpRequests': sceneWarmUpRequests,
        'sceneWarmUpCompletions': sceneWarmUpCompletions,
        'sceneWarmUpFailures': sceneWarmUpFailures,
        'sceneWarmUpCancellations': sceneWarmUpCancellations,
        'sceneWarmUpMicros': sceneWarmUpMicros,
        'lastSceneWarmUpError': lastSceneWarmUpError,
        'sessionsCreated': sessionsCreated,
        'sessionsRejected': sessionsRejected,
        'sessionsDisposed': sessionsDisposed,
        'overprintRetryRequests': overprintRetryRequests,
        'overprintRetrySuccesses': overprintRetrySuccesses,
        'overprintRetryFallbacks': overprintRetryFallbacks,
        'overprintRetryMicros': overprintRetryMicros,
        'rasterFallbacks': rasterFallbacks,
        'activeSessions': activeSessions,
        'peakActiveSessions': peakActiveSessions,
        'overprintApproximationSessions': overprintApproximationSessions,
        'scenesCompiled': scenesCompiled,
        'compileMicros': compileMicros,
        'geometryBuffers': geometryBuffers,
        'geometryVertices': geometryVertices,
        'analyticTextRuns': analyticTextRuns,
        'analyticGlyphQuads': analyticGlyphQuads,
        'analyticGlyphSlots': analyticGlyphSlots,
        'analyticAtlasBytes': analyticAtlasBytes,
        'analyticAtlasFallbacks': analyticAtlasFallbacks,
        'analyticSparseAtlasSkips': analyticSparseAtlasSkips,
        'analyticTextFallbackRuns': analyticTextFallbackRuns,
        'clipPathsCompiled': clipPathsCompiled,
        'clipMaskRebuilds': clipMaskRebuilds,
        'paperClearTiles': paperClearTiles,
        'paperOnlyTiles': paperOnlyTiles,
        'subpixelStrokeFallbacks': subpixelStrokeFallbacks,
        'advancedBlendPasses': advancedBlendPasses,
        'advancedBlendBlits': advancedBlendBlits,
        'advancedBlendCroppedSources': advancedBlendCroppedSources,
        'advancedBlendAllocatedBytes': advancedBlendAllocatedBytes,
        'peakAdvancedBlendBytes': peakAdvancedBlendBytes,
        'advancedBlendBudgetFallbacks': advancedBlendBudgetFallbacks,
        'offscreenGroupPasses': offscreenGroupPasses,
        'offscreenGroupAllocatedBytes': offscreenGroupAllocatedBytes,
        'peakOffscreenGroupBytes': peakOffscreenGroupBytes,
        'offscreenGroupBudgetFallbacks': offscreenGroupBudgetFallbacks,
        'geometryBudgetFallbacks': geometryBudgetFallbacks,
        'activeGeometryLeases': activeGeometryLeases,
        'geometryBytes': geometryBytes,
        'peakGeometryBytes': peakGeometryBytes,
        'transientBuffers': transientBuffers,
        'transientEmplacedBytes': transientEmplacedBytes,
        'transientAllocatedBytes': transientAllocatedBytes,
        'peakTransientTileBytes': peakTransientTileBytes,
        'texturesUploaded': texturesUploaded,
        'textureImports': textureImports,
        'textureDirectUploads': textureDirectUploads,
        'textureReadbacks': textureReadbacks,
        'textureCacheHits': textureCacheHits,
        'textureCacheMisses': textureCacheMisses,
        'textureEvictions': textureEvictions,
        'textureBudgetFallbacks': textureBudgetFallbacks,
        'activeTextureLeases': activeTextureLeases,
        'textureBytes': textureBytes,
        'peakTextureBytes': peakTextureBytes,
        'tilesRendered': tilesRendered,
        'selectedCommands': selectedCommands,
        'issueMicros': issueMicros,
        'submitMicros': submitMicros,
        'completedSubmissions': completedSubmissions,
        'completionMicros': completionMicros,
        'maxCompletionMicros': maxCompletionMicros,
        'failedSubmissions': failedSubmissions,
        'inFlightSubmissions': inFlightSubmissions,
        'peakInFlightSubmissions': peakInFlightSubmissions,
      };

  /// Clears lifetime counters without corrupting live resource gauges.
  ///
  /// Active sessions and cache/pool ownership continue to exist after a
  /// diagnostics reset, so their current values are retained and become the
  /// new peak baseline.
  void reset() {
    sessionsCreated = 0;
    sessionsRejected = 0;
    sessionsDisposed = 0;
    overprintRetryRequests = 0;
    overprintRetrySuccesses = 0;
    overprintRetryFallbacks = 0;
    overprintRetryMicros = 0;
    rasterFallbacks = 0;
    contextSwitches = 0;
    warmUpRequests = 0;
    warmUpSubmissions = 0;
    warmUpCompletions = 0;
    warmUpFailures = 0;
    warmUpMicros = 0;
    lastWarmUpError = null;
    sceneWarmUpRequests = 0;
    sceneWarmUpCompletions = 0;
    sceneWarmUpFailures = 0;
    sceneWarmUpCancellations = 0;
    sceneWarmUpMicros = 0;
    lastSceneWarmUpError = null;
    peakActiveSessions = activeSessions;
    overprintApproximationSessions = 0;
    scenesCompiled = 0;
    compileMicros = 0;
    geometryVertices = 0;
    analyticTextRuns = 0;
    analyticGlyphQuads = 0;
    analyticGlyphSlots = 0;
    analyticAtlasBytes = 0;
    analyticAtlasFallbacks = 0;
    analyticSparseAtlasSkips = 0;
    analyticTextFallbackRuns = 0;
    clipPathsCompiled = 0;
    clipMaskRebuilds = 0;
    paperClearTiles = 0;
    paperOnlyTiles = 0;
    subpixelStrokeFallbacks = 0;
    advancedBlendPasses = 0;
    advancedBlendBlits = 0;
    advancedBlendCroppedSources = 0;
    advancedBlendAllocatedBytes = 0;
    peakAdvancedBlendBytes = 0;
    advancedBlendBudgetFallbacks = 0;
    offscreenGroupPasses = 0;
    offscreenGroupAllocatedBytes = 0;
    peakOffscreenGroupBytes = 0;
    offscreenGroupBudgetFallbacks = 0;
    geometryBudgetFallbacks = 0;
    peakGeometryBytes = geometryBytes;
    transientBuffers = 0;
    transientEmplacedBytes = 0;
    transientAllocatedBytes = 0;
    peakTransientTileBytes = 0;
    texturesUploaded = 0;
    textureImports = 0;
    textureDirectUploads = 0;
    textureReadbacks = 0;
    textureCacheHits = 0;
    textureCacheMisses = 0;
    textureEvictions = 0;
    textureBudgetFallbacks = 0;
    peakTextureBytes = textureBytes;
    tilesRendered = 0;
    selectedCommands = 0;
    issueMicros = 0;
    submitMicros = 0;
    completedSubmissions = 0;
    completionMicros = 0;
    maxCompletionMicros = 0;
    failedSubmissions = 0;
    peakInFlightSubmissions = inFlightSubmissions;
    lastRejection = null;
    lastTileRoute = null;
  }

  @override
  String toString() => 'sessions=$sessionsCreated rejected=$sessionsRejected '
      'disposed=$sessionsDisposed rasterFallbacks=$rasterFallbacks '
      'contexts=$contextsSeen contextSwitches=$contextSwitches '
      'warmUpRequests=$warmUpRequests warmUpSubmissions=$warmUpSubmissions '
      'warmUpCompletions=$warmUpCompletions warmUpFailures=$warmUpFailures '
      'warmUpUs=$warmUpMicros '
      'sceneWarmUpRequests=$sceneWarmUpRequests '
      'sceneWarmUpCompletions=$sceneWarmUpCompletions '
      'sceneWarmUpFailures=$sceneWarmUpFailures '
      'sceneWarmUpCancellations=$sceneWarmUpCancellations '
      'sceneWarmUpUs=$sceneWarmUpMicros '
      'lastContext=$lastContextIdentity '
      'activeSessions=$activeSessions peakActiveSessions=$peakActiveSessions '
      'overprintApprox=$overprintApproximationSessions '
      'compiled=$scenesCompiled compileUs=$compileMicros '
      'buffers=$geometryBuffers vertices=$geometryVertices '
      'analyticRuns=$analyticTextRuns analyticQuads=$analyticGlyphQuads '
      'analyticSlots=$analyticGlyphSlots atlasBytes=$analyticAtlasBytes '
      'analyticAtlasFallbacks=$analyticAtlasFallbacks '
      'analyticSparseSkips=$analyticSparseAtlasSkips '
      'analyticFallbackRuns=$analyticTextFallbackRuns '
      'clips=$clipPathsCompiled clipRebuilds=$clipMaskRebuilds '
      'paperClearTiles=$paperClearTiles '
      'paperOnlyTiles=$paperOnlyTiles '
      'subpixelStrokeFallbacks=$subpixelStrokeFallbacks '
      'advancedBlendPasses=$advancedBlendPasses '
      'advancedBlendBlits=$advancedBlendBlits '
      'advancedBlendCroppedSources=$advancedBlendCroppedSources '
      'advancedBlendAllocatedBytes=$advancedBlendAllocatedBytes '
      'peakAdvancedBlendBytes=$peakAdvancedBlendBytes '
      'advancedBlendBudgetFallbacks=$advancedBlendBudgetFallbacks '
      'groupPasses=$offscreenGroupPasses '
      'groupAllocatedBytes=$offscreenGroupAllocatedBytes '
      'peakGroupBytes=$peakOffscreenGroupBytes '
      'groupBudgetFallbacks=$offscreenGroupBudgetFallbacks '
      'geometryBudgetFallbacks=$geometryBudgetFallbacks '
      'activeGeometryLeases=$activeGeometryLeases '
      'geometryBytes=$geometryBytes peakGeometryBytes=$peakGeometryBytes '
      'transientBuffers=$transientBuffers '
      'transientEmplacedBytes=$transientEmplacedBytes '
      'transientAllocatedBytes=$transientAllocatedBytes '
      'peakTransientTileBytes=$peakTransientTileBytes '
      'uploads=$texturesUploaded imports=$textureImports '
      'directUploads=$textureDirectUploads '
      'readbacks=$textureReadbacks textureHits=$textureCacheHits '
      'textureMisses=$textureCacheMisses evictions=$textureEvictions '
      'budgetFallbacks=$textureBudgetFallbacks '
      'activeLeases=$activeTextureLeases '
      'textureBytes=$textureBytes peakTextureBytes=$peakTextureBytes '
      'tiles=$tilesRendered lastRoute=$lastTileRoute '
      'selected=$selectedCommands issueUs=$issueMicros '
      'submitUs=$submitMicros completed=$completedSubmissions '
      'completionUs=$completionMicros maxCompletionUs=$maxCompletionMicros '
      'failedSubmissions=$failedSubmissions '
      'inFlightSubmissions=$inFlightSubmissions '
      'peakInFlightSubmissions=$peakInFlightSubmissions';
}
