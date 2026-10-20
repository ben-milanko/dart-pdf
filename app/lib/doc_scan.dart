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

/// The title a fresh scan opens under: "Scan YYYY-MM-DD.pdf" for the local
/// date [now], with " (2)", " (3)", ... appended while [taken] already holds
/// that name. ISO order so a folder of scans sorts by date.
String scanDocumentTitle(DateTime now, Set<String> taken) {
  String two(int n) => n.toString().padLeft(2, '0');
  final date = '${now.year}-${two(now.month)}-${two(now.day)}';
  var title = 'Scan $date.pdf';
  for (var n = 2; taken.contains(title); n++) {
    title = 'Scan $date ($n).pdf';
  }
  return title;
}
