import 'package:dart_pdf_editor_flutter_gpu/dart_pdf_editor_flutter_gpu.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('JSON snapshot includes outcomes and reset preserves live gauges', () {
    final stats = FlutterGpuTileBackendStats()
      ..sessionsCreated = 4
      ..sessionsRejected = 2
      ..sessionsDisposed = 1
      ..rasterFallbacks = 1
      ..lastContextIdentity = 1234
      ..contextsSeen = 2
      ..contextSwitches = 3
      ..activeSessions = 3
      ..peakActiveSessions = 4
      ..activeTextureLeases = 5
      ..textureBytes = 12 << 20
      ..peakTextureBytes = 18 << 20
      ..activeGeometryLeases = 2
      ..geometryBuffers = 3
      ..geometryBytes = 32 << 20
      ..peakGeometryBytes = 48 << 20
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

    stats.reset();
    expect(stats.sessionsCreated, 0);
    expect(stats.rasterFallbacks, 0);
    expect(stats.lastContextIdentity, 1234);
    expect(stats.contextsSeen, 2);
    expect(stats.contextSwitches, 0);
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
    expect(stats.completedSubmissions, 0);
    expect(stats.completionMicros, 0);
    expect(stats.inFlightSubmissions, 2);
    expect(stats.peakInFlightSubmissions, 2);
  });
}
