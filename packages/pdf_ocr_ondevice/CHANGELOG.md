# Changelog

## 1.3.2

- Version bump to align with `dart_pdf_editor` 1.3.2. No API changes since
  1.3.1.

## 1.3.1

- Version bump to align with `dart_pdf_editor` 1.3.1. No API changes since
  1.2.3.

## 1.2.3

- Added `PdfOcrDownloadCancelToken` so hosts can wire a Cancel button to
  in-flight model downloads; cancellation removes partial files and throws
  `PdfOcrModelDownloadCanceled`.
- Expanded the README download example to display file/overall progress and
  show where to call `cancel()`.
- Fix on-device OCR failing on Windows with a garbled "Load model from … File
  doesn't exist" error. The ONNX Runtime session is now created from the model
  *bytes* (`OrtSession.fromBuffer`) instead of a file path: on Windows the
  binding passed the path as a narrow UTF-8 string where ONNX Runtime expects a
  wide `wchar_t*`, mangling every path — even pure-ASCII ones — into CJK
  mojibake. This supersedes the 1.2.2 ASCII path-staging workaround, which could
  not help because the corruption happened regardless of the path's contents.

## 1.2.2

- Fix on-device OCR model path staging on Windows so the downloaded PP-OCR
  ONNX model resolves correctly.

## 1.2.1

- Add a package example and shorten the pubspec description for pub.dev
  scoring.

## 1.2.0

- Downloadable on-device OCR package for the DartPDF app, with model-manager
  integration and native-platform OCR engine wiring.
- Version bump to align with `dart_pdf_editor` 1.2.0.

## 0.1.0

- Initial release. On-device, downloadable OCR for `dart_pdf_editor`.
- `PdfOcrModelManager` downloads, caches (under the app-support directory),
  integrity-checks (SHA-256), and removes OCR model bundles, reporting
  progress as bytes arrive. Native platforms only (`isSupported` is false on
  the web).
- `OnDeviceOcrEngine` implements `PdfOcrEngine`, mapping a backend's
  pixel-space text lines into PDF user space. `PdfEditor.applyOcr` writes
  an invisible, selectable layer with no per-page network call.
- `OnnxOcrModelRunner` runs a PP-OCR detect+recognize pipeline on ONNX
  Runtime (det resize/normalize, DB box extraction, CRNN/CTC decode), all of
  the pre/post-processing in pure, unit-tested Dart.
- `PdfOcrModels.ppOcrV5Mobile` describes the recommended lightweight model;
  point its file URLs at a bundle you host (see the README).
