# Changelog

## 8.1.0

- Align dependency constraints with the dart-pdf 8.1.0 suite.

## 8.0.0

- Align dependency constraints with the dart-pdf 8.0.0 suite.


## 7.0.0

- Much better accuracy on small print and technical drawings, and ~4x
  faster. On a synthetic A3 signalling sheet (`buildOcrDrawingSheet` in
  `pdf_test_fixtures`) exact label reads go from 18% to 95% (CER 69% -> 1.4%).
  - Detection no longer squeezes the page to 960 px: `detectionSideLimit`
    defaults to 4000 (PaddleOCR's PP-OCRv5 cap). At 960 a drawing's ~5pt
    labels fused with the symbols beside them and read as garbage.
  - DB unclip is DB's own distance offset (`area * ratio / perimeter`,
    ratio 1.5) instead of scaling the box 1.6x about its centre; box score
    threshold 0.6 (PaddleOCR's).
  - Recognition keeps each line's aspect, padding to at least 320 px
    (`recognitionInput(minWidth:)`; the record gains `paddedWidth`), instead
    of squashing every line into 512 px. `OnnxOcrModelRunner` gains
    `recognitionMinWidth`; `recognitionMaxWidth` is now only a safety cap
    (default 3200).
  - Recognized lines go through `cleanRecognizedText`: drawing symbols
    (Geometric Shapes, `● ▲ ▼`) are removed and symbol-only lines dropped
    (`OnnxOcrModelRunner(cleanText: false)` keeps the raw output).
  - New `OnDeviceOcrEngine.pixelRatioFor(page)`: 216 dpi, capped at 4000 px a
    side - pass it to `applyOcr` instead of `pixelRatio: 2`.
  - Model outputs are read straight from ONNX Runtime's buffer instead of
    through `OrtValueTensor.value`'s nested lists, which cost ~3x the
    inference itself. Adds a direct `ffi` dependency.
- New web-safe library `package:pdf_ocr_ondevice/pp_ocr.dart`: the
  pipeline is now `PpOcrPipeline` (plain Dart) over a `PpOcrInference`
  backend - `OnnxOcrModelRunner` is that pipeline over native ONNX Runtime,
  and a browser can supply onnxruntime-web (the DartPDF app now does, in place
  of Florence-2). `OcrRunnerEngine` is the backend-agnostic `PdfOcrEngine`
  (`OnDeviceOcrEngine` extends it; `pixelRatioFor` lives there too).
- Recognition runs in aspect-sorted batches of 6 lines
  (`recognitionBatchSize`, PaddleOCR's default), each padded to its own widest
  line: identical readings, page time halved again (37 s -> 19 s on the
  benchmark sheet).
- Raise the Flutter floor to `flutter: '>=3.47.0'`, matching
  `dart_pdf_editor` 7.0.0 (material_ui 1.4's floor).

## 6.0.0

- Declare the real Flutter floor: `flutter: '>=3.44.0'` (was `>=3.24.0`),
  matching `dart_pdf_editor`. 5.0.0 already needed Flutter 3.44
  (`ReorderableListView.onReorderItem`), so this strands nobody.

## 5.1.1

- Version bump to track the 5.1.1 suite.

## 5.1.0

- Version bump to track the 5.1.0 suite.

## 5.0.0

- Version bump to track the 5.0.0 suite.

## 4.5.0

- Align dependency constraints with the dart-pdf 4.5.0 package suite.

## 4.4.0

- Align dependency constraints with the dart-pdf 4.4.0 package suite.

## 4.3.0

- Align dependency constraints with the dart-pdf 4.3.0 package suite.

## 4.2.0

- Lockstep minor release aligned with `dart_pdf_editor` 4.2.0. No public
  on-device OCR API changes since 4.1.0.

## 4.1.0

- Lockstep minor release aligned with `dart_pdf_editor` 4.1.0. No public
  on-device OCR API changes since 4.0.0.

## 4.0.0

- Lockstep major release to align with `dart_pdf_editor` 4.0.0. No public
  on-device OCR API changes since 3.8.0.

## 3.8.0

- Lockstep minor release to align with `dart_pdf_editor` 3.8.0. No public
  on-device OCR API changes since 3.7.0.

## 3.7.0

- Lockstep minor release to align with `dart_pdf_editor` 3.7.0. No public
  on-device OCR API changes since 3.6.0.

## 3.6.0

- Lockstep minor release to align with `dart_pdf_editor` 3.6.0. No public
  on-device OCR API changes since 3.5.1.

## 3.5.1

- Lockstep patch release to align with `dart_pdf_editor` 3.5.1. No public
  on-device OCR API changes since 3.5.0.

## 3.5.0

- Lockstep minor release to align with `dart_pdf_editor` 3.5.0. No public
  on-device OCR API changes since 3.4.0.

## 3.4.0

- Lockstep minor release to align with `dart_pdf_editor` 3.4.0. No public
  on-device OCR API changes since 3.3.1.

## 3.3.1

- Lockstep patch release to align with `dart_pdf_editor` 3.3.1. No public
  on-device OCR API changes since 3.3.0.

## 3.3.0

- Lockstep minor release to align with `dart_pdf_editor` 3.3.0. No public
  on-device OCR API changes since 3.2.0.

## 3.2.0

- Lockstep minor release to align with `dart_pdf_editor` 3.2.0. No public
  on-device OCR API changes since 3.1.1.

## 3.1.1

- Lockstep patch release to align with `dart_pdf_editor` 3.1.1. No public
  on-device OCR API changes since 3.1.0.

## 3.1.0

- Lockstep release to align with `dart_pdf_editor` 3.1.0. No public on-device
  OCR API changes since 3.0.0.

## 3.0.0

- Lockstep major release to align with `dart_pdf_editor` 3.0.0. No public
  on-device OCR API changes since 2.1.0.

## 2.1.0

- Version bump to align with `dart_pdf_editor` 2.1.0. No public on-device OCR API
  changes since 2.0.0.

## 2.0.0

- Version bump to align with `dart_pdf_editor` 2.0.0. No public on-device OCR
  API changes since 1.4.7.

## 1.4.7

- Version bump to align with `dart_pdf_editor` 1.4.7. No public on-device OCR
  API changes since 1.4.6.

## 1.4.6

- Version bump to align with `dart_pdf_editor` 1.4.6. No public on-device OCR
  API changes since 1.4.5.

## 1.4.5

- Version bump to align with `dart_pdf_editor` 1.4.5. No public on-device OCR
  API changes since 1.4.4.

## 1.4.4

- Version bump to align with `dart_pdf_editor` 1.4.4. No public on-device OCR
  API changes since 1.4.3.

## 1.4.3

- Version bump to align with `dart_pdf_editor` 1.4.3. No public on-device OCR
  API changes since 1.4.2.

## 1.4.2

- Version bump to align with `dart_pdf_editor` 1.4.2. No public on-device OCR
  API changes since 1.4.1.

## 1.4.1

- Run downloaded ONNX OCR models on a long-lived worker isolate by default.
  Page RGBA buffers transfer without a structured-message copy, and model
  loading, preprocessing, inference, and post-processing no longer block the
  UI isolate.

## 1.4.0

- Version bump to align with `dart_pdf_editor` 1.4.0. Runtime maintenance keeps
  the on-device OCR package compatible with the 1.4.0 editor/app release.

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
  wide `wchar_t*`, mangling every path - even pure-ASCII ones - into CJK
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
