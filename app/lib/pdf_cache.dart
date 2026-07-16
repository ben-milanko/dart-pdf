// A private snapshot store for opened PDFs on platforms that don't hand back a
// reusable file path.
//
// Desktop picks come with a real on-disk path, so Recent entries and session
// restore there just re-read it. Mobile picks hand back a sandboxed copy with
// no durable path - historically that left the Recent list showing "Pick again
// to reopen" and dead to the tap. To fix that we copy the opened bytes into the
// app's private support directory and remember that path; reopening reads it
// straight back. A conditional import gives native targets a real filesystem
// store and the web (no `dart:io`) a no-op stub, where re-opening still needs a
// fresh pick.
export 'pdf_cache_stub.dart' if (dart.library.io) 'pdf_cache_io.dart';
