// ignore_for_file: avoid_print

import 'package:pdf_ocr_vlm/pdf_ocr_vlm.dart';

void main() {
  final engine = VlmOcrEngine.dotsOcr(
    endpoint: Uri.parse('http://localhost:8000/v1/chat/completions'),
    model: 'model',
  );

  print('OCR endpoint: ${engine.endpoint}');
  print('Languages: ${engine.languages}');
  engine.close();
}
