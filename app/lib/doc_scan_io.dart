import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_doc_scanner/flutter_doc_scanner.dart';
import 'package:pdf_document/pdf_document.dart';

/// The on-device document scanner is a phone/tablet feature - Google ML Kit's
/// Document Scanner on Android, VisionKit's `VNDocumentCameraViewController` on
/// iOS. It is absent on desktop (and on the web, which compiles the stub), so
/// the scan menu entries only surface on mobile.
bool get documentScanSupported =>
    defaultTargetPlatform == TargetPlatform.android ||
    defaultTargetPlatform == TargetPlatform.iOS;

/// Launches the platform document scanner and assembles the captured pages
/// into a PDF. Returns null when the user cancels, when nothing readable comes
/// back, or on an unsupported platform.
///
/// The plugin call and file access live here; the shape-tolerant parsing and
/// PDF assembly are factored into [scanResultToPdf] so they can be unit-tested
/// without the native ML Kit / VisionKit channels.
Future<Uint8List?> scanDocumentToPdf() async {
  if (!documentScanSupported) return null;
  final scanner = FlutterDocScanner();
  return scanResultToPdf(
    getImages: () => scanner.getScannedDocumentAsImages(),
    getPdf: () => scanner.getScannedDocumentAsPdf(),
  );
}

/// Turns the scanner's results into PDF bytes - the testable core of
/// [scanDocumentToPdf].
///
/// The captured pages are pulled back as images (via [getImages]) and stitched
/// into a PDF by our own pure-Dart [PdfImageDocument] (one page per shot,
/// JPEGs passed through verbatim) so page sizing stays under our control. If
/// the image route yields nothing, it falls back to the scanner's own PDF
/// export ([getPdf]).
///
/// The plugin's result shape varies by version and platform (a Map keyed by
/// `images`/`pdfUri`, or a bare path/URI, or a list), so both the extraction
/// ([scanImageLocations] / [scanPdfLocation]) and the file reads ([readFile],
/// defaulting to [readScannedFile]) are deliberately lenient: any failure
/// degrades to null rather than throwing.
@visibleForTesting
Future<Uint8List?> scanResultToPdf({
  required Future<dynamic> Function() getImages,
  required Future<dynamic> Function() getPdf,
  Future<Uint8List?> Function(String location) readFile = readScannedFile,
}) async {
  try {
    final images = <Uint8List>[];
    for (final location in scanImageLocations(await getImages())) {
      final bytes = await readFile(location);
      if (bytes != null) images.add(bytes);
    }
    if (images.isNotEmpty) return PdfImageDocument.fromImageBytes(images);
  } catch (_) {
    // Fall through to the PDF route below.
  }

  try {
    final path = scanPdfLocation(await getPdf());
    if (path != null) return readFile(path);
  } catch (_) {
    // Nothing usable came back.
  }

  return null;
}

/// Pulls the per-page image locations out of the scanner result, tolerating
/// the several shapes the plugin has used: a Map under `images`/`Uri`, or a
/// bare list/string of paths.
@visibleForTesting
List<String> scanImageLocations(dynamic result) {
  dynamic value = result;
  if (result is Map) {
    value = result['images'] ?? result['Uri'] ?? result['uri'];
  }
  if (value is List) return [for (final e in value) e.toString()];
  if (value is String) return [value];
  return const [];
}

/// Pulls the PDF location out of the scanner result (a Map under `pdfUri`/
/// `Uri`, or a bare path string).
@visibleForTesting
String? scanPdfLocation(dynamic result) {
  if (result is Map) {
    final value = result['pdfUri'] ?? result['Uri'] ?? result['uri'];
    if (value != null) return value.toString();
  }
  if (result is String) return result;
  return null;
}

/// Reads a scanner-returned file location, normalising a `file://` URI to a
/// path. `content://` URIs can't be read through `dart:io`, and a missing file
/// yields null, so a stray entry is skipped rather than fatal.
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
