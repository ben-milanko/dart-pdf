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
  int sessionsCreated = 0;
  int sessionsRejected = 0;
  int sessionsDisposed = 0;
  int rasterFallbacks = 0;
  int activeSessions = 0;
  int peakActiveSessions = 0;
  int overprintApproximationSessions = 0;
  int scenesCompiled = 0;
  int compileMicros = 0;
  int geometryBuffers = 0;
  int geometryVertices = 0;
  int clipPathsCompiled = 0;
  int clipMaskRebuilds = 0;
  int geometryBudgetFallbacks = 0;
  int activeGeometryLeases = 0;
  int geometryBytes = 0;
  int peakGeometryBytes = 0;
  int texturesUploaded = 0;
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
        'sessionsCreated': sessionsCreated,
        'sessionsRejected': sessionsRejected,
        'sessionsDisposed': sessionsDisposed,
        'rasterFallbacks': rasterFallbacks,
        'activeSessions': activeSessions,
        'peakActiveSessions': peakActiveSessions,
        'overprintApproximationSessions': overprintApproximationSessions,
        'scenesCompiled': scenesCompiled,
        'compileMicros': compileMicros,
        'geometryBuffers': geometryBuffers,
        'geometryVertices': geometryVertices,
        'clipPathsCompiled': clipPathsCompiled,
        'clipMaskRebuilds': clipMaskRebuilds,
        'geometryBudgetFallbacks': geometryBudgetFallbacks,
        'activeGeometryLeases': activeGeometryLeases,
        'geometryBytes': geometryBytes,
        'peakGeometryBytes': peakGeometryBytes,
        'texturesUploaded': texturesUploaded,
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
    rasterFallbacks = 0;
    contextSwitches = 0;
    warmUpRequests = 0;
    warmUpSubmissions = 0;
    warmUpCompletions = 0;
    warmUpFailures = 0;
    warmUpMicros = 0;
    lastWarmUpError = null;
    peakActiveSessions = activeSessions;
    overprintApproximationSessions = 0;
    scenesCompiled = 0;
    compileMicros = 0;
    geometryVertices = 0;
    clipPathsCompiled = 0;
    clipMaskRebuilds = 0;
    geometryBudgetFallbacks = 0;
    peakGeometryBytes = geometryBytes;
    texturesUploaded = 0;
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
      'lastContext=$lastContextIdentity '
      'activeSessions=$activeSessions peakActiveSessions=$peakActiveSessions '
      'overprintApprox=$overprintApproximationSessions '
      'compiled=$scenesCompiled compileUs=$compileMicros '
      'buffers=$geometryBuffers vertices=$geometryVertices '
      'clips=$clipPathsCompiled clipRebuilds=$clipMaskRebuilds '
      'geometryBudgetFallbacks=$geometryBudgetFallbacks '
      'activeGeometryLeases=$activeGeometryLeases '
      'geometryBytes=$geometryBytes peakGeometryBytes=$peakGeometryBytes '
      'uploads=$texturesUploaded directUploads=$textureDirectUploads '
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
