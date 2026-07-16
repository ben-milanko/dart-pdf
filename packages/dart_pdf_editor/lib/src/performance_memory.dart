export 'performance_memory_stub.dart'
    if (dart.library.io) 'performance_memory_io.dart'
    if (dart.library.js_interop) 'performance_memory_web.dart';
