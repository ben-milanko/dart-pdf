import 'memory_snapshot.dart';
import 'memory_probe_stub.dart'
    if (dart.library.io) 'memory_probe_io.dart'
    if (dart.library.js_interop) 'memory_probe_web.dart' as implementation;

/// Reads the best memory snapshot this platform exposes.
Future<AppMemorySnapshot?> readAppMemorySnapshot() =>
    implementation.readAppMemorySnapshot();
