import 'dart:typed_data';

// documentScanSupported / scanDocumentToPdf are platform-specific: the real
// flutter_doc_scanner-backed implementation on native mobile, and a no-op stub
// on the web (and wherever `dart:io` is absent). The conditional import picks
// the right one at compile time so the plugin is never referenced on the web.
export 'doc_scan_stub.dart' if (dart.library.io) 'doc_scan_io.dart'
    show documentScanSupported, scanDocumentToPdf;

/// Runs a device document scan and returns the captured pages as a
/// ready-to-open PDF, or null when the user cancels the scan (or it fails).
///
/// This is the injectable seam [EditorScreen] uses for "Scan to new document"
/// and "Insert scan": production wires the platform scanner
/// ([scanDocumentToPdf]); tests supply a fake so the menu wiring can be
/// exercised without the native ML Kit / VisionKit channels.
typedef DocumentScanner = Future<Uint8List?> Function();
