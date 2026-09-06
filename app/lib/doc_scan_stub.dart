import 'dart:typed_data';

/// The web build (and any platform without `dart:io`) has no device document
/// scanner, so the "Scan to new document" / "Insert scan" menu entries are
/// hidden.
bool get documentScanSupported => false;

/// No scanner on this platform - always null.
Future<Uint8List?> scanDocumentToPdf() async => null;
