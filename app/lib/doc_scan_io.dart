import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_doc_scanner/flutter_doc_scanner.dart';

/// The on-device document scanner is a phone/tablet feature - Google ML Kit's
/// Document Scanner on Android, VisionKit's `VNDocumentCameraViewController` on
/// iOS. It is absent on desktop (and on the web, which compiles the stub), so
/// the scan menu entries only surface on mobile.
bool get documentScanSupported =>
    defaultTargetPlatform == TargetPlatform.android ||
    defaultTargetPlatform == TargetPlatform.iOS;

/// Launches the platform document scanner and returns the captured pages as a
/// PDF. Returns null when the user cancels, when nothing readable comes back,
/// or on an unsupported platform.
///
/// **One scan session only.** Each `FlutterDocScanner` method launches its own
/// camera, so calling more than one re-opens the scanner after the user has
/// already accepted their pages. We ask for the ready-made PDF export - a plain
/// file path on iOS, a `file://` URI on Android - and read it back with
/// [readScannedFile]. A failure to read degrades to null (a "couldn't scan"
/// toast) rather than throwing.
Future<Uint8List?> scanDocumentToPdf() async {
  if (!documentScanSupported) return null;
  final result = await FlutterDocScanner().getScannedDocumentAsPdf();
  if (result == null) return null; // user cancelled
  return readScannedFile(result.pdfUri);
}

/// Reads a scanner-returned file location, normalising a `file://` URI to a
/// path. `content://` URIs can't be read through `dart:io`, and a missing file
/// yields null, so a stray entry degrades gracefully rather than throwing.
@visibleForTesting
Future<Uint8List?> readScannedFile(String location) async {
  var path = location;
  if (path.startsWith('file://')) {
    path = Uri.parse(path).toFilePath();
  } else if (path.startsWith('content://')) {
    return null;
  }
  final file = File(path);
  if (!await file.exists()) return null;
  return file.readAsBytes();
}
