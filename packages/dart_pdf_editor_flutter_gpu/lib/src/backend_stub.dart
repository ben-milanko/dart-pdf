import 'package:dart_pdf_editor/dart_pdf_editor.dart';

import 'backend_stats.dart';

/// Web/unsupported compile-time stub for [FlutterGpuTileRasterBackend].
class FlutterGpuTileRasterBackend extends PdfTileRasterBackend {
  FlutterGpuTileRasterBackend({
    this.msaa = true,
    this.allowOverprintApproximation = false,
    this.maxTextureBytes = 256 << 20,
    this.maxGeometryBytes = 256 << 20,
    FlutterGpuTileBackendStats? stats,
  }) : stats = stats ?? FlutterGpuTileBackendStats();

  final bool msaa;
  final bool allowOverprintApproximation;
  final int maxTextureBytes;
  final int maxGeometryBytes;
  final FlutterGpuTileBackendStats stats;

  /// False for the compile-time web/unsupported implementation.
  bool get isPlatformSupported => false;

  void clearImageCache() {}

  @override
  String get debugLabel => 'flutter_gpu-unavailable';

  @override
  PdfTileRasterSession? createSession(PdfRetainedScene scene) {
    stats.lastRejection = 'flutter_gpu is unavailable on this platform';
    stats.lastTileRoute = 'canvas-fallback';
    stats.sessionsRejected++;
    return null;
  }
}
