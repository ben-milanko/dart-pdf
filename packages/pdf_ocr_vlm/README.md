# pdf_ocr_vlm

[![License: Apache-2.0](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](https://github.com/ben-milanko/dart-pdf/blob/main/LICENSE)

A pluggable **OCR engine** for the
[dart-pdf suite](https://github.com/ben-milanko/dart-pdf). It adds an
invisible, selectable, searchable text layer over scanned (image-only) PDF
pages. It can call a self-hosted vision-language OCR model or any HTTP OCR
service you wrap to a small JSON contract.

`dart_pdf_editor` ships the OCR *seam* (`PdfOcrEngine`,
`PdfEditor.applyOcr`) but no engine. OCR is a large native/GPU/cloud
subsystem that doesn't belong inside a pure-Dart PDF toolkit. This package
fills that seam over HTTP, so the heavy model runs out of process (a Docker
container, a GPU box, a cloud endpoint) and your Flutter app stays thin.

```
┌──────────────┐   page raster (PNG)    ┌──────────────────────┐
│ dart_pdf_*   │ ─────────────────────► │  OCR service (HTTP)  │
│ applyOcr()   │                        │  e.g. dots.ocr/vLLM  │
│              │ ◄───────────────────── │  on a GPU / cloud    │
└──────────────┘   words + pixel boxes  └──────────────────────┘
        │
        ▼  inject invisible text at the recognized boxes
   selectable · searchable · copyable · extractable PDF
```

---

## Why a VLM, and which one? (SOTA, mid-2026)

Document OCR has moved from detector+recognizer pipelines (Tesseract,
EasyOCR) to **vision-language models** that read layout, reading order, and
text in one pass and return structured JSON with bounding boxes. The
current leaders (open-weight, self-hostable, and returning boxes, which is
what an over-the-scan text layer needs):

| Model | Size | Notes |
| --- | --- | --- |
| **dots.ocr** (`rednote-hilab/dots.ocr`) | ~1.7B | Layout + reading order + text in one model, 100+ languages, returns `bbox`+`category`+`text` JSON. **This package's default preset.** |
| **PaddleOCR-VL** | ~0.9B | Strong multilingual; OpenAI-compatible serving. |
| **GOT-OCR 2.0** | 580M | Runs on ~4 GB VRAM; Markdown/LaTeX output. |
| **Qwen3-VL / DeepSeek-OCR / GLM-OCR** | 0.9-3B | General VLMs / OCR-specialized; box quality varies. |
| Cloud frontier (Gemini 3 Flash, Claude, GPT) | n/a | Highest accuracy, no GPU to run, per-call cost; box support varies. |

This package defaults to **dots.ocr on [vLLM](https://docs.vllm.ai)**: it is
open, small enough for a single consumer GPU, multilingual, and, crucially,
returns per-block pixel bounding boxes that map cleanly onto the page. You
can point the same engine at any of the others (see
[Other backends](#other-backends)).

> Sources for the landscape above: the
> [definitive OCR-in-2026 guide](https://slavadubrov.github.io/blog/2026/03/04/the-definitive-guide-to-ocr-in-2026-from-pipelines-to-vlms/),
> [best open-source OCR tools](https://unstract.com/blog/best-opensource-ocr-tools/),
> [dots.ocr on GitHub](https://github.com/rednote-hilab/dots.ocr) /
> [Hugging Face](https://huggingface.co/rednote-hilab/dots.ocr), and
> [vLLM OCR recipes](https://docs.vllm.ai/projects/recipes/en/latest/).

---

## Install

```yaml
dependencies:
  dart_pdf_editor: ^1.2.0
  pdf_ocr_vlm: ^1.2.0
```

`pdf_ocr_vlm` works wherever Flutter runs: mobile, desktop, and **web**. It
only does an HTTP POST, so the model can live anywhere reachable. Make sure
the OCR service is CORS-enabled if you call it from a web build.

---

## Quick start

```dart
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_ocr_vlm/pdf_ocr_vlm.dart';

Future<Uint8List> ocrEntirePdf(Uint8List bytes) async {
  final editor = PdfEditor(PdfDocument.open(bytes));

  // Talk to a vLLM server hosting dots.ocr (see "Run the model" below).
  final engine = VlmOcrEngine.dotsOcr(
    endpoint: Uri.parse('http://localhost:8000/v1/chat/completions'),
  );

  for (var page = 0; page < editor.document.pageCount; page++) {
    final spans = await editor.applyOcr(page, engine, pixelRatio: 2);
    debugPrint('page $page: wrote $spans text spans');
  }
  engine.close();

  return editor.save(); // the scan now has a selectable/searchable layer
}
```

`applyOcr` rasterizes the page, hands the raster to the engine, and writes
each recognized word as **invisible text (render mode 3)** placed exactly
over the scan. The page looks identical, but text can now be selected,
searched, copied, and extracted. Pass `visible: true` to burn the layer in
(useful for debugging the box alignment).

### Try it in the example app

The suite's example app (`packages/dart_pdf_editor/example`) wires this in:
**More actions ▸ Add OCR text layer…** opens a dialog to supply the service
endpoint, model name, and an optional API key/token (sent as
`Authorization: Bearer …`), then OCRs every page and opens the result in a
new tab. Point it at a server from [Run the model](#run-the-model-dotsocr-on-vllm).

### Wire it into the editor UI

```dart
IconButton(
  icon: const Icon(Icons.document_scanner),
  tooltip: 'OCR this page',
  onPressed: () async {
    final editor = PdfEditor(PdfDocument.open(currentBytes));
    await editor.applyOcr(
      pageIndex,
      engine,
      pixelRatio: 2.5,      // raise for small type
      minConfidence: 0.30,  // drop junk
    );
    // applyOcr mutates the editor's document in place; save the bytes and
    // re-open them in your viewer/editor as the new document.
    final ocrdBytes = editor.save();
    onDocumentReady(ocrdBytes);
  },
)
```

---

## Run the model (dots.ocr on vLLM)

The official image serves an **OpenAI-compatible** chat endpoint, which
`VlmOcrEngine.dotsOcr` speaks directly. No adapter server is needed.

With Docker + an NVIDIA GPU:

```bash
docker run --gpus all -p 8000:8000 \
  rednotehilab/dots.ocr:vllm-openai-v0.9.1 \
  vllm serve /workspace/weights/DotsOCR \
    --served-model-name model \
    --tensor-parallel-size 1 \
    --gpu-memory-utilization 0.95 \
    --chat-template-content-format string \
    --trust-remote-code
```

Or with a local vLLM install:

```bash
pip install -U vllm transformers
huggingface-cli download rednote-hilab/dots.ocr --local-dir ./DotsOCR
vllm serve ./DotsOCR \
  --served-model-name model \
  --gpu-memory-utilization 0.95 \
  --chat-template-content-format string \
  --trust-remote-code
```

Then point the engine at it:

```dart
final engine = VlmOcrEngine.dotsOcr(
  endpoint: Uri.parse('http://YOUR_GPU_HOST:8000/v1/chat/completions'),
  model: 'model',          // must match --served-model-name
  apiKey: null,            // set if you front it with an auth proxy
  // categories: {...},    // which dots.ocr layout blocks become text
  // minConfidence: 0.0,   // dots.ocr returns no per-cell score → keep 0
);
```

`dotsOcr` sends the page image plus the dots.ocr layout prompt, then reads
the JSON array the model returns (`[{bbox, category, text}, ...]`),
keeps the text-bearing blocks (`Text`, `Title`, `Section-header`,
`List-item`, `Caption`, `Footnote`, `Page-header`, `Page-footer`; `Picture`
and `Table` are skipped by default), and maps each pixel `bbox` onto the
page. Override `categories:` to include tables/formulas.

> **No GPU?** dots.ocr also runs (slowly) on CPU via vLLM/transformers for
> trials, and the same preset works against a cloud-hosted dots.ocr or any
> OpenAI-compatible OCR VLM. Change `endpoint`, `model`, and `apiKey`.

---

## The simple JSON contract (any OCR server)

If you'd rather front your own engine (PaddleOCR, Surya, docTR, Tesseract, a
custom pipeline), wrap it in a tiny HTTP service that speaks this contract
and use the **default constructor**. No preset or custom Dart is needed.

**Request:** `POST <endpoint>`, `Content-Type: application/json`:

```json
{
  "image": "<base64 PNG of the page>",
  "image_format": "png",
  "width": 1224,
  "height": 1584,
  "page": 0,
  "languages": ["en"]      // present only if you pass languages:
}
```

**Response:** `200`, a list of recognized fragments. Boxes are in **raster
pixels, top-left origin** (the same `width`×`height` you were sent):

```json
{
  "spans": [
    { "text": "Invoice",  "bbox": [96, 110, 320, 156], "confidence": 0.98 },
    { "text": "Total",    "bbox": [96, 980, 240, 1020], "confidence": 0.95 }
  ]
}
```

```dart
final engine = VlmOcrEngine(
  endpoint: Uri.parse('http://localhost:8001/ocr'),
  languages: const ['en'],
  minConfidence: 0.3,
);
```

The default parser is lenient: the list may be top-level or under any of
`spans` / `words` / `lines` / `results` / `regions` / `cells` / `data`; text
may be `text` / `transcription` / `content`; a box may be a 4-number
`bbox` / `box` / `bounding_box` / `rect`, **or** a polygon under
`polygon` / `poly` / `points` / `quad`; confidence may be
`confidence` / `score` / `conf` (default `1.0`). So most off-the-shelf OCR
JSON drops in unchanged.

### Reference adapter (≈30 lines, FastAPI + PaddleOCR)

```python
# pip install fastapi uvicorn paddleocr pillow
import base64, io
from fastapi import FastAPI, Request
from PIL import Image
from paddleocr import PaddleOCR

app = FastAPI()
ocr = PaddleOCR(use_angle_cls=True, lang="en")

@app.post("/ocr")
async def recognize(req: Request):
    body = await req.json()
    img = Image.open(io.BytesIO(base64.b64decode(body["image"]))).convert("RGB")
    import numpy as np
    result = ocr.ocr(np.array(img), cls=True)
    spans = []
    for line in (result[0] or []):
        poly, (text, conf) = line
        spans.append({"text": text, "polygon": poly, "confidence": float(conf)})
    return {"spans": spans}
# uvicorn server:app --host 0.0.0.0 --port 8001
```

---

## Other backends

`requestBody` and `responseParser` are the two seams; override either to
target a different service without leaving Dart.

### A cloud VLM (custom prompt + parser)

```dart
final engine = VlmOcrEngine(
  endpoint: Uri.parse('https://api.example.com/v1/chat/completions'),
  headers: {'authorization': 'Bearer $apiKey'},
  model: 'some-vision-model',
  prompt: 'Return a JSON array of {bbox:[x0,y0,x1,y1] in pixels, text}.',
  requestBody: openAiChatRequestBody,          // reuse the chat encoder
  responseParser: (json, page) {
    // navigate choices[0].message.content yourself, then build words…
    // return List<VlmOcrWord> with pixel-space Rects.
  },
);
```

`VlmOcrWord` carries a **pixel-space** `Rect`; `applyOcr` maps it to PDF
user space for you (`PdfOcrPageImage.userSpaceRect` undoes the crop box and
`/Rotate` that the raster already baked in), so a parser never does page
geometry.

---

## API surface

| Symbol | Purpose |
| --- | --- |
| `VlmOcrEngine(...)` | Generic engine for the simple JSON contract. |
| `VlmOcrEngine.dotsOcr(...)` | Preset for dots.ocr on an OpenAI-compatible vLLM endpoint. |
| `VlmOcrInput` | The rendered page (base64 PNG + dims + hints) given to a request builder. |
| `VlmOcrWord` | One recognized fragment in **pixel** coordinates. |
| `defaultVlmRequestBody` / `defaultVlmResponseParser` | The simple-contract default hooks. |
| `openAiChatRequestBody` | Chat-completions request encoder (image + prompt). |
| `dotsOcrResponseParser`, `dotsOcrLayoutPrompt`, `dotsOcrTextCategories` | dots.ocr building blocks. |
| `VlmOcrException` | Thrown on transport / status / parse failures. |

`applyOcr`'s own options live in `dart_pdf_editor`: `pixelRatio` (OCR raster
resolution; 2 ≈ 144 dpi, raise for small type), `minConfidence`, `visible`,
and `font`.

---

## Tips & limitations

- **Resolution drives accuracy.** Start at `pixelRatio: 2`; small or dense
  type wants `2.5`-`3`. Higher = larger PNG = slower request.
- **The layer is byte-encoded text.** Code points outside Latin-1 still
  position correctly (selection/search boxes line up) but render as `?` if
  you make the layer `visible`; invisible layers extract the original text.
- **Already-digital PDFs don't need OCR.** They have real text already.
  Use this for scans and image-only pages.
- **Box granularity** follows the model. dots.ocr returns block/line boxes,
  so selection snaps to lines, not individual words. That is fine for search and
  copy. A word-level engine (PaddleOCR/Tesseract) over the simple contract
  gives word boxes.
- **Network & privacy.** Page rasters leave the device. For sensitive
  documents, self-host the model on infrastructure you control.

## License

Apache-2.0. See [LICENSE](LICENSE).
