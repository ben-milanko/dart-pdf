// Builds the PdfCacheStore backing the example's on-disk preview cache,
// picking a platform-appropriate backend.
//
// The library never touches storage itself (dart:io is banned in its
// lib/ so it keeps running on the web): persistence is a host-provided
// seam. This file is that host code. A conditional import gives native
// platforms a real filesystem-backed store and the web a non-persistent
// in-memory one — a production web app would swap in an IndexedDB-backed
// PdfCacheStore here instead.
export 'persistent_cache_memory.dart'
    if (dart.library.io) 'persistent_cache_io.dart';
