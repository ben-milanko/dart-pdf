# pdf_ocr_ondevice

On-device, **downloadable** OCR for [`dart_pdf_editor`](https://pub.dev/packages/dart_pdf_editor).

Adds a selectable, searchable, *invisible* text layer over scanned (image-only)
PDF pages — running entirely on the device, with **no per-page network call**.
A small OCR model (PaddleOCR PP-OCRv5 *mobile*, ~15 MB) downloads once, is cached
under the app-support directory, and then runs locally on
[ONNX Runtime](https://onnxruntime.ai).

It implements `dart_pdf_editor`'s `PdfOcrEngine`, so the recognized text is
written by `PdfEditor.applyOcr` exactly like any other engine — the page looks
unchanged, but its text becomes selectable, searchable, copyable, and
extractable.

## Where this fits

dart-pdf has two OCR engines, two tiers:

| Engine | Where it runs | Best for |
| --- | --- | --- |
| [`pdf_ocr_vlm`](../pdf_ocr_vlm) | A server/cloud you call over HTTP (dots.ocr on vLLM, or any VLM) | Highest accuracy, layout/table parsing — when a GPU server or an API is available |
| **`pdf_ocr_ondevice`** (this) | The device, offline | Privacy, offline use, no infrastructure — a plain selectable text layer on every native platform |

The SOTA document-parsing models (dots.ocr 1.7B, PaddleOCR-VL 0.9B) are
billion-parameter VLMs that realistically need a GPU; this package uses the
small classic **detect → recognize** PP-OCR pipeline (~5M parameters) so it runs
on CPU on a phone or a laptop.

## Supported platforms

Android, iOS, macOS, Windows, Linux — wherever ONNX Runtime has prebuilt
binaries. **Not the web** (no local model store / native runtime): on the web,
`PdfOcrModelManager.isSupported` is `false`; use `pdf_ocr_vlm` against an HTTP
service there.

## Usage

```dart
import 'package:pdf_ocr_ondevice/pdf_ocr_ondevice.dart';

final manager = PdfOcrModelManager();
final model = PdfOcrModels.ppOcrV5Mobile;

// 1. Download the model once (cached afterwards).
if (PdfOcrModelManager.isSupported && !await manager.isDownloaded(model)) {
  await manager.download(model, onProgress: (p) {
    print('Downloading ${p.fileName}: ${((p.fraction ?? 0) * 100).round()}%');
  });
}

// 2. Build an engine from the downloaded files and run it over a page.
final engine = await OnDeviceOcrEngine.fromDownloadedModel(manager, model);
final editor = PdfEditor(PdfDocument.open(bytes));
for (var i = 0; i < editor.document.pageCount; i++) {
  await editor.applyOcr(i, engine, pixelRatio: 2);
}
final result = editor.save(); // selectable/searchable text layer added
await engine.dispose();
```

## Hosting the model bundle

ONNX OCR networks are binaries this repository does **not** ship in-tree, so
`PdfOcrModels.ppOcrV5Mobile` points its file URLs at a release you publish. To
produce the bundle:

1. Download PP-OCRv5 mobile detection + recognition inference models from
   [PaddleOCR](https://github.com/PaddlePaddle/PaddleOCR) (and the matching
   `ppocrv5_dict.txt`).
2. Convert each to ONNX with
   [`paddle2onnx`](https://github.com/PaddlePaddle/Paddle2ONNX):

   ```bash
   paddle2onnx --model_dir PP-OCRv5_mobile_det \
     --model_filename inference.json --params_filename inference.pdiparams \
     --save_file PP-OCRv5_mobile_det.onnx
   paddle2onnx --model_dir PP-OCRv5_mobile_rec \
     --model_filename inference.json --params_filename inference.pdiparams \
     --save_file PP-OCRv5_mobile_rec.onnx
   ```

3. Upload `PP-OCRv5_mobile_det.onnx`, `PP-OCRv5_mobile_rec.onnx`, and
   `ppocrv5_dict.txt` as assets on a GitHub release tagged `ocr-models-v1`
   (the default URLs), or anywhere else and supply your own `PdfOcrModel`.
4. Set each file's `sha256` in the descriptor so downloads are integrity
   checked. Until the assets exist the download 404s with a clear
   `PdfOcrModelException`.

### A custom model / hosting

```dart
final model = PdfOcrModel(
  id: 'my-ocr-en',
  displayName: 'My OCR',
  detection: PdfOcrModelFile(
    name: 'det.onnx',
    url: Uri.parse('https://example.com/det.onnx'),
    sha256: 'a1b2…',
  ),
  recognition: PdfOcrModelFile(
    name: 'rec.onnx',
    url: Uri.parse('https://example.com/rec.onnx'),
    sha256: 'c3d4…',
  ),
  dictionary: PdfOcrModelFile(
    name: 'dict.txt',
    url: Uri.parse('https://example.com/dict.txt'),
  ),
);
```

## How it works

`OnDeviceOcrEngine` reads the page raster into an `OcrImage`, runs an
`OcrModelRunner`, and maps each recognized line's pixel box to PDF user space
via `PdfOcrPageImage.userSpaceRect`. The default `OnnxOcrModelRunner`:

1. resizes the page for detection (longest side ≤ limit, multiples of 32) and
   normalizes it (`toNchwFloat32`);
2. runs the detection network → a probability map, from which
   `extractDetectionBoxes` derives text-line boxes (DB threshold + connected
   components + unclip), scaled back to the original raster;
3. crops each box, normalizes it for recognition (`recognitionInput`), runs the
   recognition network, and greedily CTC-decodes (`CtcDecoder`) the logits
   against the model's dictionary.

Everything except the two `OrtSession.run` calls is plain Dart and unit tested.

### Custom backend

`OnDeviceOcrEngine` takes any `OcrModelRunner`, so a platform-native recognizer
(Apple Vision, ML Kit, Windows.Media.Ocr) can stand in while reusing the
download lifecycle and the page-geometry mapping — return `RecognizedTextLine`s
in raster pixels and the engine does the rest.

## Native setup

ONNX Runtime is pulled in by the `onnxruntime` package; follow its platform
notes (it bundles the runtime for mobile/desktop). No extra steps are needed
for the Dart API.
