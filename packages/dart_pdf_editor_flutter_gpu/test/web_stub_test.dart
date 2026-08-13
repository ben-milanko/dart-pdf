import 'package:dart_pdf_editor_flutter_gpu/dart_pdf_editor_flutter_gpu.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('unsupported-platform backend keeps the public API available', () {
    final stats = FlutterGpuTileBackendStats();
    final backend = FlutterGpuTileRasterBackend(msaa: false, stats: stats);

    expect(backend.debugLabel, contains('flutter_gpu'));
    expect(backend.msaa, isFalse);
    expect(backend.stats, same(stats));
  });
}
