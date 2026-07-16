// printDocumentPages is platform-specific: an app-owned method channel on
// native (the OS print system, no PDFium), and the browser's own print dialog
// on web. Conditional import picks the right one at compile time.
export 'native_print_io.dart'
    if (dart.library.js_interop) 'native_print_web.dart' show printDocumentPages;
