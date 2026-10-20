// Durable storage for the small first-page images shown by Recent files.
//
// Native apps use the application-support directory and the web uses
// IndexedDB. The bare stub keeps thumbnail rendering functional on targets
// with neither API; it just cannot retain the result across app launches.
export 'recent_thumbnail_store_stub.dart'
    if (dart.library.io) 'recent_thumbnail_store_io.dart'
    if (dart.library.js_interop) 'recent_thumbnail_store_web.dart';
