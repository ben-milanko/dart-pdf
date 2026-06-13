import 'dart:typed_data';

import 'document.dart';

/// A host-provided converter from a non-PDF document format into PDF bytes.
///
/// **This is an interface seam, not an engine.** dart-pdf deliberately does
/// not implement OOXML (DOCX/XLSX/PPTX), RTF, or other office-format layout
/// in Dart — faithful conversion is a large native/cloud subsystem and a
/// poor fit for a pure-Dart, web-capable library. Instead, a host supplies
/// the conversion (a server endpoint, a platform plugin like Apple's
/// `NSAttributedString`/Quick Look, LibreOffice headless, a cloud API) and
/// dart-pdf consumes the resulting PDF bytes through the rest of the
/// pipeline — viewing, editing, signing.
///
/// For the one ingestion path that *is* feasible in pure Dart — assembling
/// a stack of raster images into a PDF — see `PdfImageDocument`, which
/// needs no host engine.
///
/// Example:
/// ```dart
/// class MyServerConverter implements PdfImportSource {
///   @override
///   Future<Uint8List> convertToPdf(Uint8List bytes,
///       {String? mimeType, String? fileName}) async {
///     final response = await http.post(uri, body: bytes);
///     return response.bodyBytes;
///   }
/// }
///
/// final doc = await MyServerConverter().importDocument(docxBytes,
///     fileName: 'report.docx');
/// ```
abstract class PdfImportSource {
  /// Converts [bytes] of an input document into a PDF byte stream.
  ///
  /// [mimeType] and [fileName] are hints a converter may use to pick a
  /// format; either may be null. Implementations should throw on an
  /// unsupported or unconvertible input rather than return non-PDF bytes.
  Future<Uint8List> convertToPdf(Uint8List bytes,
      {String? mimeType, String? fileName});
}

/// Opening the result of a [PdfImportSource] directly as a [PdfDocument].
extension PdfImportSourceDocument on PdfImportSource {
  /// Converts [bytes] and opens the produced PDF as a [PdfDocument].
  Future<PdfDocument> importDocument(Uint8List bytes,
          {String? mimeType, String? fileName}) async =>
      PdfDocument.open(
          await convertToPdf(bytes, mimeType: mimeType, fileName: fileName));
}
