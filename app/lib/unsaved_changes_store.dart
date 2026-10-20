// The durable mirror behind crash recovery: while a document has unsaved
// edits, its bytes are kept outside the app's memory so a crash, an OOM kill,
// or a closed browser tab loses nothing.
//
// A conditional import picks the backing store, exactly as pdf_cache.dart does
// for opened-document snapshots: native targets write files under the app's
// private support directory (`dart:io`); the web keeps chunked bytes in
// IndexedDB (`dart:js_interop`), which - unlike `localStorage` (~5 MB,
// synchronous, string-only) - stores binary blobs and can hold a PDF. The bare
// stub (neither `dart:io` nor JS interop) has no store, and recovery is simply
// unavailable there.
//
// Conditions are evaluated in order, first match wins: native targets have
// dart:io, web targets have dart:js_interop (and not dart:io).
export 'unsaved_changes_store_stub.dart'
    if (dart.library.io) 'unsaved_changes_store_io.dart'
    if (dart.library.js_interop) 'unsaved_changes_store_web.dart';
