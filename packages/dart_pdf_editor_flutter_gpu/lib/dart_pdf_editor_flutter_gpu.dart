/// Opt-in flutter_gpu tile raster backend for dart_pdf_editor.
///
/// This companion stays outside dart_pdf_editor's dependency graph, preserving
/// its stable-SDK and web surface. On web the exported backend is an inert
/// capability stub whose `createSession` returns null, activating the Canvas
/// fallback automatically.
library;

export 'src/backend_stats.dart';
export 'src/text_outliner.dart';
export 'src/system_text_outliner_native.dart'
    if (dart.library.js_interop) 'src/system_text_outliner_stub.dart';
export 'src/backend_native.dart'
    if (dart.library.js_interop) 'src/backend_stub.dart';
