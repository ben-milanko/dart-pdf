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
/// The pages are pulled back as images and stitched into a PDF by our own
/// pure-Dart [PdfImageDocument] (one page per shot, JPEGs passed through
/// verbatim) so page sizing stays under our control. If the image route yields
/// nothing we fall back to the scanner's own PDF export.
///
/// The plugin's result shape varies by version and platform (a Map keyed by
/// `images`/`pdfUri`, or a bare path/URI, or a list), so both the extraction
/// and the file reads are deliberately lenient: any failure degrades to null
/// and the caller shows a "couldn't scan" message rather than throwing.
Future<Uint8List?> scanDocumentToPdf() async {
  if (!documentScanSupported) return null;
  final scanner = FlutterDocScanner();

  try {
    final images =
        await _readImages(await scanner.getScannedDocumentAsImages());
    if (images.isNotEmpty) return PdfImageDocument.fromImageBytes(images);
  } catch (_) {
    // Fall through to the PDF route below.
  }

  try {
    final path = _pdfPath(await scanner.getScannedDocumentAsPdf());
    if (path != null) return _readLocalFile(path);
  } catch (_) {
    // Nothing usable came back.
  }

  return null;
}

Future<List<Uint8List>> _readImages(dynamic result) async {
  final images = <Uint8List>[];
  for (final location in _imagePaths(result)) {
    final bytes = await _readLocalFile(location);
    if (bytes != null) images.add(bytes);
  }
  return images;
}

/// Pulls the per-page image locations out of the scanner result, tolerating
/// the several shapes the plugin has used: a Map under `images`/`Uri`, or a
/// bare list/string of paths.
List<String> _imagePaths(dynamic result) {
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
String? _pdfPath(dynamic result) {
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
Future<Uint8List?> _readLocalFile(String location) async {
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
