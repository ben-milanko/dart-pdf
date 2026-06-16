# pdf_ocr_ondevice

On-device, **downloadable** OCR for [`dart_pdf_editor`](https://pub.dev/packages/dart_pdf_editor).

Adds a selectable, searchable, *invisible* text layer over scanned (image-only)
PDF pages. It runs entirely on the device, with **no per-page network call**.
A small OCR model (PaddleOCR PP-OCRv5 *mobile*, ~21 MB) downloads once, is cached
under the app-support directory, and then runs locally on
[ONNX Runtime](https://onnxruntime.ai).

It implements `dart_pdf_editor`'s `PdfOcrEngine`, so the recognized text is
written by `PdfEditor.applyOcr` exactly like any other engine. The page looks
unchanged, but its text becomes selectable, searchable, copyable, and
extractable.

## Where this fits

dart-pdf has two OCR engines, two tiers:

| Engine | Where it runs | Best for |
| --- | --- | --- |
| [`pdf_ocr_vlm`](../pdf_ocr_vlm) | A server/cloud you call over HTTP (dots.ocr on vLLM, or any VLM) | Highest accuracy and layout/table parsing when a GPU server or an API is available |
| **`pdf_ocr_ondevice`** (this) | The device, offline | Privacy, offline use, and no infrastructure; a plain selectable text layer on every native platform |

The SOTA document-parsing models (dots.ocr 1.7B, PaddleOCR-VL 0.9B) are
billion-parameter VLMs that realistically need a GPU; this package uses the
small classic **detect → recognize** PP-OCR pipeline (~5M parameters) so it runs
on CPU on a phone or a laptop.

## Supported platforms

Android, iOS, macOS, Windows, and Linux, wherever ONNX Runtime has prebuilt
binaries. **Not the web** (no local model store / native runtime): on the web,
`PdfOcrModelManager.isSupported` is `false`; use `pdf_ocr_vlm` against an HTTP
service there.

## Install

```sh
flutter pub add dart_pdf_editor pdf_ocr_ondevice
```

No model files need to be bundled in your app. The default bundle downloads
from the `ocr-models-v1` GitHub release on first use, verifies each file by
SHA-256, and then runs from the device cache.

## Usage

```dart
import 'dart:typed_data';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_ocr_ondevice/pdf_ocr_ondevice.dart';

Future<Uint8List> addSearchableTextLayer(Uint8List bytes) async {
  if (!PdfOcrModelManager.isSupported) return bytes; // web/fuchsia fallback

  final manager = PdfOcrModelManager();
  final model = PdfOcrModels.ppOcrV5Mobile;
  OnDeviceOcrEngine? engine;
  try {
    // 1. Download the model once (cached afterwards).
    if (!await manager.isDownloaded(model)) {
      await manager.download(model, onProgress: (p) {
        final pct = ((p.fraction ?? 0) * 100).round();
        print('Downloading ${p.fileName}: $pct%');
      });
    }

    // 2. Build an engine from the downloaded files and run it over each page.
    engine = await OnDeviceOcrEngine.fromDownloadedModel(manager, model);
    final editor = PdfEditor(PdfDocument.open(bytes));
    for (var page = 0; page < editor.document.pageCount; page++) {
      await editor.applyOcr(page, engine, pixelRatio: 2);
    }
    return editor.save(); // selectable/searchable text layer added
  } finally {
    await engine?.dispose();
    manager.close();
  }
}
```

Open the returned bytes, or replace the bytes in `PdfReader` /
`PdfEditorView`, after the function returns. Long documents should run this
from your app flow with progress and cancellation; the DartPDF app's
`app/lib/ocr_native.dart` is the reference orchestration.

## The default model bundle

`PdfOcrModels.ppOcrV5Mobile` downloads its files from the
[`ocr-models-v1`](https://github.com/ben-milanko/dart-pdf/releases/tag/ocr-models-v1)
GitHub release. There is nothing to host, and it works out of the box. Each file's
`sha256` is pinned in the descriptor, so a corrupted or tampered download is
rejected.

The bundle is the official PaddleOCR **PP-OCRv5 mobile** detection +
recognition models converted to ONNX with
[`paddle2onnx`](https://github.com/PaddlePaddle/Paddle2ONNX), plus the
recognizer's character dictionary. See **Model license & attribution** below.

### Rolling your own bundle

To host elsewhere (or ship a different model), reproduce the conversion and
supply your own `PdfOcrModel`:

1. Download PP-OCRv5 mobile detection + recognition inference models from
   [PaddleOCR](https://github.com/PaddlePaddle/PaddleOCR) (and the matching
   `ppocrv5_dict.txt`).
2. Convert each to ONNX with `paddle2onnx`:

   ```bash
   paddle2onnx --model_dir PP-OCRv5_mobile_det \
     --model_filename inference.json --params_filename inference.pdiparams \
     --save_file PP-OCRv5_mobile_det.onnx
   paddle2onnx --model_dir PP-OCRv5_mobile_rec \
     --model_filename inference.json --params_filename inference.pdiparams \
     --save_file PP-OCRv5_mobile_rec.onnx
   ```

3. Upload the two `.onnx` files and `ppocrv5_dict.txt` as release assets (or
   anywhere reachable) and point a custom `PdfOcrModel` at them.
4. Set each file's `sha256` in your descriptor so downloads are integrity
   checked.

## Model license & attribution

The default bundle is a **derivative work of PaddleOCR PP-OCRv5 mobile**
(Copyright © PaddlePaddle Authors), redistributed under the **Apache License
2.0**, the same license as this package. The `.onnx` files are the official
PaddlePaddle inference models converted to ONNX with `paddle2onnx` (opset 14;
no weights retrained or altered); `ppocrv5_dict.txt` is the recognizer's
character dictionary extracted verbatim from the official config. The
[`ocr-models-v1`](https://github.com/ben-milanko/dart-pdf/releases/tag/ocr-models-v1)
release carries the full `LICENSE.txt` + `NOTICE.txt`.

Sources:
[PP-OCRv5_mobile_det](https://huggingface.co/PaddlePaddle/PP-OCRv5_mobile_det) ·
[PP-OCRv5_mobile_rec](https://huggingface.co/PaddlePaddle/PP-OCRv5_mobile_rec) ·
[PaddleOCR](https://github.com/PaddlePaddle/PaddleOCR).

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
download lifecycle and the page-geometry mapping. Return `RecognizedTextLine`s
in raster pixels and the engine does the rest.

## Native setup

ONNX Runtime is pulled in by the `onnxruntime` package; follow its platform
notes (it bundles the runtime for mobile/desktop). No extra steps are needed
for the Dart API.

For web apps, use `pdf_ocr_vlm` or your own browser/JavaScript
`PdfOcrEngine`. The product app demonstrates a browser-local bridge in
`app/lib/ocr_web.dart`, but this package intentionally stays native because
ONNX Runtime is FFI-backed.
