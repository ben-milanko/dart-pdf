import 'dart:isolate';
import 'dart:typed_data';

import 'package:pdf_document/pdf_document.dart';

import 'signature_validation_worker.dart';

const offThread = true;

Future<Map<String, PdfSignatureCryptoCore>> computeSignatureCores(
    Uint8List bytes, String password, List<String> fieldNames) {
  // One copy of just this revision (the view may sit in a larger, amortised
  // session buffer that a plain send would copy whole); the helper isolate
  // then takes the buffer over without another copy. The cores come back by
  // ownership transfer.
  final transfer = TransferableTypedData.fromList([bytes]);
  return Isolate.run(
    () => signatureCoresOf(
        transfer.materialize().asUint8List(), password, fieldNames),
    debugName: 'PDF signature validation',
  );
}
