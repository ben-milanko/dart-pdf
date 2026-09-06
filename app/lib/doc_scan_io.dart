import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_doc_scanner/flutter_doc_scanner.dart';
import 'package:pdf_document/pdf_document.dart';

import 'pdf_mobile_source.dart' show mobileFileChannel;

/// The on-device document scanner is a phone/tablet feature - Google ML Kit's
/// Document Scanner on Android, VisionKit's `VNDocumentCameraViewController` on
/// iOS. It is absent on desktop (and on the web, which compiles the stub), so
/// the scan menu entries only surface on mobile.
bool get documentScanSupported =>
    defaultTargetPlatform == TargetPlatform.android ||
    defaultTargetPlatform == TargetPlatform.iOS;

/// Thrown when the scanner captured pages but the app could not read the PDF it
/// wrote. Distinct from a cancelled scan (which is a null result and a silent
/// no-op) so the caller can toast rather than appear to do nothing.
class DocumentScanException implements Exception {
  const DocumentScanException(this.location);

  /// The scanner-returned location we failed to read, for the dev log.
  final String location;

  @override
  String toString() => 'DocumentScanException: could not read the scan at '
      '"$location"';
}

/// The effective DPI used when captured page images are assembled into a PDF.
/// ML Kit and VisionKit return print-resolution images; 300 dpi preserves an
/// A4/Letter-like physical page size instead of treating every pixel as a PDF
/// point.
const double scannedDocumentDpi = 300;

/// Launches the platform document scanner and returns the captured pages as a
/// PDF. Returns null when the user cancels; throws [DocumentScanException] when
/// a captured page could not be read back.
///
/// **One scan session only.** Each `FlutterDocScanner` method launches its own
/// camera, so calling more than one re-opens the scanner after the user has
/// already accepted their pages. We request images exactly once and assemble
/// the PDF ourselves. In particular, this avoids ML Kit's PDF export, which
/// fails on some Android devices even though their captured page images are
/// available.
Future<Uint8List?> scanDocumentToPdf({FlutterDocScanner? scanner}) async {
  if (!documentScanSupported) return null;
  final result =
      await (scanner ?? FlutterDocScanner()).getScannedDocumentAsImages();
  if (result == null) return null; // user cancelled
  return scannedImagesToPdf(result.images);
}

/// Reads scanner-returned page locations before the platform scanner can
/// reclaim them and assembles a standalone PDF in capture order.
@visibleForTesting
Future<Uint8List> scannedImagesToPdf(
  List<String> locations, {
  MethodChannel? channel,
}) async {
  if (locations.isEmpty) {
    throw const DocumentScanException('(scanner returned no pages)');
  }
  final images = <Uint8List>[];
  for (final location in locations) {
    final bytes = await readScannedFile(location, channel: channel);
    if (bytes == null) throw DocumentScanException(location);
    images.add(bytes);
  }
  return PdfImageDocument.fromImageBytes(images, dpi: scannedDocumentDpi);
}

/// Reads a scanner-returned file location.
///
/// iOS hands back a bare filesystem path. Android hands back whatever
/// `GmsDocumentScanningResult.Pdf.getUri()` produced, which is *not* reliably a
/// `dart:io`-readable path: depending on the Play Services build it is either a
/// `file://` URI into the app's cache or a `content://` URI served by ML Kit's
/// own FileProvider, and even the `file://` form points into a scratch
/// directory the app has no business opening by path. Reading it by path
/// therefore fails on some devices, and (before this was split from a cancelled
/// scan) failed silently: no page, no error.
///
/// So: try the plain path first (the iOS shape, and the Android shape that
/// happens to be readable), and on Android fall back to the runner's
/// `ContentResolver`, which resolves `content://` and `file://` alike. Returns
/// null when neither route yields bytes.
@visibleForTesting
Future<Uint8List?> readScannedFile(String location,
    {MethodChannel? channel}) async {
  final direct = await _readLocalFile(location);
  if (direct != null) return direct;
  if (defaultTargetPlatform != TargetPlatform.android) return null;
  return _readThroughContentResolver(location, channel ?? mobileFileChannel);
}

/// Reads [location] as a filesystem path, normalising a `file://` URI first.
/// Null when the location isn't a path we can open (a `content://` URI, an
/// unparseable URI, a missing file) or when the file is empty.
Future<Uint8List?> _readLocalFile(String location) async {
  var path = location;
  if (path.startsWith('content://')) return null;
  if (path.startsWith('file://')) {
    try {
      path = Uri.parse(path).toFilePath();
    } on FormatException {
      return null;
    } on UnsupportedError {
      return null;
    }
  }
  try {
    final file = File(path);
    if (!await file.exists()) return null;
    final bytes = await file.readAsBytes();
    return bytes.isEmpty ? null : bytes;
  } on FileSystemException {
    return null;
  }
}

/// Reads [location] whole through the Android runner's `ContentResolver`
/// (`mobile_file`'s `readUri`), which opens `content://` and `file://` URIs the
/// same way. Null on any failure - an older runner without the method included.
Future<Uint8List?> _readThroughContentResolver(
  String location,
  MethodChannel channel,
) async {
  try {
    final bytes = await channel.invokeMethod<Uint8List>(
      'readUri',
      {'token': location},
    );
    if (bytes == null || bytes.isEmpty) return null;
    return bytes;
  } on PlatformException {
    return null;
  } on MissingPluginException {
    return null;
  }
}
