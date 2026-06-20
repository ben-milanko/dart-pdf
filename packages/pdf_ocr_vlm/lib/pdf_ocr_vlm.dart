/// A pluggable OCR engine for [`dart_pdf_editor`](https://pub.dev/packages/dart_pdf_editor)
/// backed by a vision-language-model (VLM) OCR service.
///
/// Implements `PdfOcrEngine` so `PdfEditor.applyOcr` can turn a scanned,
/// image-only page into one whose text can be selected, searched, copied,
/// and extracted — without changing how the page looks.
///
/// Point [VlmOcrEngine] at a self-hosted state-of-the-art OCR model (see
/// [VlmOcrEngine.dotsOcr]) or any HTTP service you wrap to the documented
/// JSON contract.
library;

export 'src/vlm_ocr_engine.dart';
