/// Computes signature crypto cores ([PdfSignatureCryptoCore]) - the hash of
/// the covered bytes and the signature verification - off the UI isolate
/// where the platform has isolates, inline on the web.
library;

import 'dart:typed_data';

import 'package:pdf_document/pdf_document.dart';

import 'signature_validation_worker_native.dart'
    if (dart.library.js_interop) 'signature_validation_worker_stub.dart'
    as platform;

/// Whether [computeSignatureCores] runs off the calling isolate. False on the
/// web, where there is no isolate to hand the bytes to and the caller may as
/// well let validation compute each core inline.
bool get signatureCoresOffThread => platform.offThread;

/// The crypto cores of the signatures named [fieldNames] in [bytes] (a whole
/// revision, opened with [password]), by field name. See [signatureCoresOf].
Future<Map<String, PdfSignatureCryptoCore>> computeSignatureCores(
  Uint8List bytes, {
  required String password,
  required List<String> fieldNames,
}) =>
    platform.computeSignatureCores(bytes, password, fieldNames);

/// Opens [bytes] and computes the core of each signature named in
/// [fieldNames]. A signature without one (a malformed /ByteRange) or whose
/// computation throws is left out: validating it computes the core inline,
/// which reports the same problem.
Map<String, PdfSignatureCryptoCore> signatureCoresOf(
    Uint8List bytes, String password, List<String> fieldNames) {
  final wanted = fieldNames.toSet();
  final cores = <String, PdfSignatureCryptoCore>{};
  final document = PdfDocument.open(bytes, password: password);
  for (final signature in PdfSignature.of(document)) {
    final name = signature.field.name;
    if (!wanted.contains(name)) continue;
    try {
      final core = signature.cryptoCore();
      if (core != null) cores[name] = core;
    } on Object {
      // validated (and reported) inline instead
    }
  }
  return cores;
}
