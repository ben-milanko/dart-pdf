// Builds the PdfCacheStore backing the example's on-disk caches, picking
// a platform-appropriate backend.
//
// The library never touches storage itself (dart:io is banned in its
// lib/ so it keeps running on the web): persistence is a host-provided
// seam. This file is that host code. A conditional import gives native
// platforms a real filesystem-backed store and the web an IndexedDB-backed
// one, so the on-disk caches persist across sessions everywhere. The
// in-memory store is only the ultimate fallback (a platform with neither
// dart:io nor JS interop).
//
// Conditions are evaluated in order, first match wins: native targets
// have dart:io, web targets have dart:js_interop (and not dart:io).
export 'persistent_cache_memory.dart'
    if (dart.library.io) 'persistent_cache_io.dart'
    if (dart.library.js_interop) 'persistent_cache_web.dart';
