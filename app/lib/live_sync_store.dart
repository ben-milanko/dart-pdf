// The platform side of live sync: where the sidecar folder next to a PDF
// lives and how it is read and written. A conditional export picks it, as
// unsaved_changes_store.dart does: native desktop targets use the file
// system (`dart:io`); everywhere else - the web, and for now phones, whose
// documents arrive as provider URIs or private copies rather than a folder
// the app may write beside - live sync is unavailable.
export 'live_sync_store_stub.dart'
    if (dart.library.io) 'live_sync_store_io.dart';
