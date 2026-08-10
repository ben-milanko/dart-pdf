/// Aggregated diagnostics for one flutter_gpu tile backend instance.
class FlutterGpuTileBackendStats {
  String? lastRejection;
  String? lastTileRoute;
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
  int submitMicros = 0;

  /// A JSON-safe snapshot suitable for diagnostics and benchmark artifacts.
  Map<String, Object?> toJson() => {
        'lastRejection': lastRejection,
        'lastTileRoute': lastTileRoute,
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
        'submitMicros': submitMicros,
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
    peakActiveSessions = activeSessions;
    overprintApproximationSessions = 0;
    scenesCompiled = 0;
    compileMicros = 0;
    geometryVertices = 0;
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
    submitMicros = 0;
    lastRejection = null;
    lastTileRoute = null;
  }

  @override
  String toString() => 'sessions=$sessionsCreated rejected=$sessionsRejected '
      'disposed=$sessionsDisposed rasterFallbacks=$rasterFallbacks '
      'activeSessions=$activeSessions peakActiveSessions=$peakActiveSessions '
      'overprintApprox=$overprintApproximationSessions '
      'compiled=$scenesCompiled compileUs=$compileMicros '
      'buffers=$geometryBuffers vertices=$geometryVertices '
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
      'selected=$selectedCommands submitUs=$submitMicros';
}
