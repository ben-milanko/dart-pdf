// A private snapshot store for opened PDFs on platforms that don't hand back a
// reusable file path.
//
// Desktop picks come with a real on-disk path, so Recent entries and session
// restore there just re-read it. Mobile and web picks hand back only bytes with
// no durable path - historically that left the Recent list showing "Pick again
// to reopen" and dead to the tap. To fix that we snapshot the opened bytes and
// remember a key for them; reopening reads them straight back. A conditional
// import picks the backing store: native targets copy the bytes into the app's
// private support directory (`dart:io`); the web keeps them in IndexedDB
// (`dart:js_interop`), which - unlike `localStorage` (~5 MB, synchronous,
// string-only) - stores binary blobs and is the right home for PDF bytes. The
// bare stub (neither `dart:io` nor JS interop) is a no-op where re-opening still
// needs a fresh pick.
//
// Conditions are evaluated in order, first match wins: native targets have
// dart:io, web targets have dart:js_interop (and not dart:io).
export 'pdf_cache_stub.dart'
    if (dart.library.io) 'pdf_cache_io.dart'
    if (dart.library.js_interop) 'pdf_cache_web.dart';
