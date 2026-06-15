# Changelog

## 0.1.0

- Initial release. On-device, downloadable OCR for `dart_pdf_editor`.
- `PdfOcrModelManager` downloads, caches (under the app-support directory),
  integrity-checks (SHA-256), and removes OCR model bundles, reporting
  progress as bytes arrive. Native platforms only (`isSupported` is false on
  the web).
- `OnDeviceOcrEngine` implements `PdfOcrEngine`, mapping a backend's
  pixel-space text lines into PDF user space — so `PdfEditor.applyOcr` writes
  an invisible, selectable layer with no per-page network call.
- `OnnxOcrModelRunner` runs a PP-OCR detect+recognize pipeline on ONNX
  Runtime (det resize/normalize, DB box extraction, CRNN/CTC decode), all of
  the pre/post-processing in pure, unit-tested Dart.
- `PdfOcrModels.ppOcrV5Mobile` describes the recommended lightweight model;
  point its file URLs at a bundle you host (see the README).
