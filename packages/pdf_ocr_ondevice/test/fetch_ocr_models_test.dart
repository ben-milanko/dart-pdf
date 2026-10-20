// tool/fetch_ocr_models.sh puts the web build's copy of the OCR models in
// place and verifies them by SHA-256; this keeps its pins identical to the
// native download's (PdfOcrModels.ppOcrV5Mobile), so the two platforms can
// never run different model bytes.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_ocr_ondevice/pdf_ocr_ondevice.dart';

void main() {
  test('the web model fetch pins the same files as the native download', () {
    final script = File('../../tool/fetch_ocr_models.sh').readAsStringSync();
    final model = PdfOcrModels.ppOcrV5Mobile;
    for (final file in model.files) {
      final asset = file.url.pathSegments.last;
      expect(script, contains('"${file.name}|$asset|${file.sha256}"'),
          reason: '${file.name} ($asset)');
    }
    final base = model.detection.url.resolve('.').toString();
    expect(
        script, contains('BASE_URL="${base.substring(0, base.length - 1)}"'));
  });
}
