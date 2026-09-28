import 'dart:typed_data';

import 'package:pdf_document/pdf_document.dart';

import 'signature_validation_worker.dart';

const offThread = false;

Future<Map<String, PdfSignatureCryptoCore>> computeSignatureCores(
        Uint8List bytes, String password, List<String> fieldNames) async =>
    signatureCoresOf(bytes, password, fieldNames);
