import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:pdf_cos/pdf_cos.dart';

import 'document.dart';

/// The first element of the trailer /ID array (§14.4, the "permanent"
/// identifier written when the file was created), or null when the file
/// has no usable /ID.
///
/// Incremental saves carry /ID forward unchanged, so this stays the same
/// across every revision an editor appends. Copies of a file share it too:
/// it identifies a document, not one file on disk.
Uint8List? pdfTrailerPermanentId(PdfDocument document) {
  final cos = document.cos;
  final id = cos.resolve(cos.trailer['ID']);
  if (id is! CosArray || id.length == 0) return null;
  final first = cos.resolve(id[0]);
  if (first is! CosString || first.bytes.isEmpty) return null;
  return first.bytes;
}

/// A stable identity for [document]: its trailer /ID first element
/// ([pdfTrailerPermanentId]) or, when the file has none, the SHA-256 of
/// [bytes] (defaulting to the bytes the document was opened from).
///
/// The fallback is only stable while the bytes are. A caller that files
/// something under a fallback identity and then saves should also write
/// the identity as the new file's /ID (see
/// `PdfFormFilling.setPasswordValue`'s `documentId`), so the saved file
/// keeps answering to the same key.
Uint8List pdfPermanentDocumentId(PdfDocument document, {Uint8List? bytes}) =>
    pdfTrailerPermanentId(document) ??
    Uint8List.fromList(
        crypto.sha256.convert(bytes ?? document.cos.bytes).bytes);
