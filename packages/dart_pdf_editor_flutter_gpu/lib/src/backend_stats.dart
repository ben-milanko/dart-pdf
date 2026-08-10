/// Aggregated diagnostics for one flutter_gpu tile backend instance.
class FlutterGpuTileBackendStats {
  String? lastRejection;
  int sessionsCreated = 0;
  int sessionsRejected = 0;
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

  void reset() {
    sessionsCreated = 0;
    sessionsRejected = 0;
    overprintApproximationSessions = 0;
    scenesCompiled = 0;
    compileMicros = 0;
    geometryBuffers = 0;
    geometryVertices = 0;
    geometryBudgetFallbacks = 0;
    activeGeometryLeases = 0;
    geometryBytes = 0;
    peakGeometryBytes = 0;
    texturesUploaded = 0;
    textureDirectUploads = 0;
    textureReadbacks = 0;
    textureCacheHits = 0;
    textureCacheMisses = 0;
    textureEvictions = 0;
    textureBudgetFallbacks = 0;
    activeTextureLeases = 0;
    textureBytes = 0;
    peakTextureBytes = 0;
    tilesRendered = 0;
    selectedCommands = 0;
    submitMicros = 0;
    lastRejection = null;
  }

  @override
  String toString() => 'sessions=$sessionsCreated rejected=$sessionsRejected '
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
      'tiles=$tilesRendered '
      'selected=$selectedCommands submitUs=$submitMicros';
}
