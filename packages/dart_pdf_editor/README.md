![dart-pdf, pure-Dart PDF renderer & editor for Flutter](https://raw.githubusercontent.com/ben-milanko/dart-pdf/main/doc/banner.png)

# dart_pdf_editor

[![pub package](https://img.shields.io/pub/v/dart_pdf_editor.svg)](https://pub.dev/packages/dart_pdf_editor)
[![pub points](https://img.shields.io/pub/points/dart_pdf_editor)](https://pub.dev/packages/dart_pdf_editor/score)
[![CI](https://github.com/ben-milanko/dart-pdf/actions/workflows/ci.yml/badge.svg)](https://github.com/ben-milanko/dart-pdf/actions/workflows/ci.yml)
[![codecov](https://codecov.io/gh/ben-milanko/dart-pdf/branch/main/graph/badge.svg?flag=dart_pdf_editor)](https://codecov.io/gh/ben-milanko/dart-pdf)
[![License: Apache-2.0](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](https://github.com/ben-milanko/dart-pdf/blob/main/LICENSE)

A Flutter PDF viewer and editor rendered natively in Dart, with no
platform views or native PDF libraries. The same code runs on iOS,
Android, macOS, Windows, Linux, and the web.

![The example app: PdfEditorView showing the feature showcase document](https://raw.githubusercontent.com/ben-milanko/dart-pdf/main/doc/dart_pdf_editor_example.jpg)

## Install

```sh
flutter pub add dart_pdf_editor
```

Two drop-in widgets carry the whole UI. Give them bytes and bounded
space; everything in the screenshot above (search, page navigation,
panels, tools, undo/redo, save) is wired up:

```dart
import 'package:dart_pdf_editor/dart_pdf_editor.dart';

// A complete PDF editor
PdfEditorView(
  bytes: pdfBytes,
  onSave: (bytes) => /* write the file */,
)

// A view-only reader
PdfReader(bytes: pdfBytes)
```

Both follow the ambient Material `Theme` (dark mode included), persist
user preferences on the device, and pare down with feature flags:

```dart
PdfEditorView(
  bytes: pdfBytes,
  features: const PdfEditorFeatures(
    propertiesPanel: false,
    flatten: false,
    tools: {PdfEditTool.select, PdfEditTool.ink, PdfEditTool.freeText},
  ),
  toolbarTrailing: [
    (context, editing, viewer) => IconButton(
      icon: const Icon(Icons.cloud_upload_outlined),
      tooltip: 'Publish',
      onPressed: () => publish(editing.bytes),
    ),
  ],
)
```

For fully custom editor chrome, replace the stock toolbar and drive the
controller directly:

```dart
PdfEditorView(
  bytes: pdfBytes,
  toolbarBuilder: (context, editing, viewer) => BottomAppBar(
    child: IconButton(
      icon: const Icon(Icons.crop_square),
      tooltip: 'Rectangle',
      onPressed: () => editing.tool = PdfEditTool.rectangle,
    ),
  ),
)
```

Try the [live demo](https://dart-pdf-demo.web.app) of the example app
on Flutter web, with a built-in feature showcase document.

Built on the pure-Dart
[dart-pdf suite](https://github.com/ben-milanko/dart-pdf): `pdf_cos`
(file syntax) ← `pdf_document` (document semantics + editing) ←
`pdf_graphics` (interpreter + fonts) ← `dart_pdf_editor` (Flutter widgets).

## Optional bundled assets

The editor's six bundled fonts and its web render worker (~1.8 MB package
download) ship in a separate opt-in package,
[`dart_pdf_editor_assets`](../dart_pdf_editor_assets), rather than in
`dart_pdf_editor` itself. Flutter bundles a package's declared assets on every
build target, so keeping them out of the always-depended-on package is the only
way to let a viewer-only app avoid downloading and installing them.

To get the historical full-featured editor, add the package and register it once
at startup, before opening a viewer:

```sh
flutter pub add dart_pdf_editor dart_pdf_editor_assets
```

```dart
import 'package:dart_pdf_editor_assets/dart_pdf_editor_assets.dart';

void main() {
  registerBundledEditorAssets(); // bundled fonts + web worker
  runApp(const MyApp());
}
```

Pick the tier that fits your build:

| Tier | Depend on | Register | Bundled fonts + web worker |
| --- | --- | --- | --- |
| Viewer / editor, size-minimal | `dart_pdf_editor` | – | not shipped |
| + Off-main-thread web rendering | both | `registerBundledEditorAssets(fonts: false)` | worker only |
| Full editor, app-provided fonts | `dart_pdf_editor` | assign `pdfBundledFonts` yourself | your fonts |
| Full editor (historical default) | both | `registerBundledEditorAssets()` | both |

What each optional group powers - everything else works without them:

| Capability | Needs |
| --- | --- |
| Font menu's "bundled" group (DejaVu, Fira Sans, Spectral, Lobster) | bundled fonts |
| Fallback glyphs when editing composite (/Type0) text a subset font can't draw | bundled fonts (DejaVu trio) |
| Off-main-thread page rendering on **web** | web worker |

Missing assets degrade gracefully: the font menu simply drops the bundled group
(base-14, document, platform and custom fonts still work), composite-text
fallback is skipped, and web rendering falls back to the main thread. An app can
also supply its own catalogue - set `pdfBundledFonts` to your own
`PdfBundledFont`s (each backed by an asset key or a `loadBytes` byte loader).

## Performance

**The default viewer has not reached PDFium interaction parity yet.** The most
recent real-document checkpoint (11 August 2026) used five interleaved
DartPDF/PDFium runs in Chrome 151 on an M1 Pro, a 1400×1000 viewport, and the
default JS/CanvasKit web build. The input was a locally supplied 62-page,
24.1 MB illustrated PDF; the journey opened it, jumped to pages 3 and 47,
zoomed to 1.72×, and drove matched wheel gestures. Lower ratios are better.

| user-visible metric | DartPDF p50 / p95 | PDFium p50 / p95 | ratio p50 / p95 |
|---|---:|---:|---:|
| open to stable visual | 1680 / 1932 ms | 1531 / 1716 ms | **1.10× / 1.13×** |
| page first visual change | 17 / 63 ms | 12 / 21 ms | 1.45× / 2.95× |
| page stable visual | 303 / 419 ms | 129 / 142 ms | **2.34× / 2.95×** |
| zoom stable visual | 30 / 47 ms | 9 / 16 ms | **3.17× / 2.89×** |
| wheel journey | 320 / 397 ms | 1097 / 1237 ms | 0.29× / 0.32× |
| wheel rAF interval p95 | 25 ms | 10 ms | **2.50×** |
| peak browser RSS p50 | 1478 MiB | 1287 MiB | 1.15× |

The wheel journey completes sooner, but its worse rAF tail means it is not yet
as smooth; total duration alone would be a misleading win. Open and memory are
inside the current provisional budgets, while stable navigation, zoom, and
scroll cadence are not. These numbers describe desktop web only and are not a
native-desktop or mobile parity claim. See the
[full methodology and historical checkpoints](https://github.com/ben-milanko/dart-pdf/blob/main/doc/benchmarks/pdfium-parity.md).

The offline corpus benchmark remains useful as a subsystem diagnostic, not as
evidence of viewer latency: over 49 files / 255 pages at scale 2, pure-Dart
interpretation takes 9.6 ms/page, PDFium rasterization takes 23.1 ms/page, and
the complete Flutter raster plus readback takes 45.2 ms/page. Reproducible
offline harnesses and file-by-file diffs live in
[`benchmark/`](https://github.com/ben-milanko/dart-pdf/tree/main/benchmark).

The drop-in shells use adaptive performance tuning by default. Auto selects a
platform-, core-, and document-aware worker count, then adjusts safe preview
and image-resolution knobs from observed render latency, result sizes, and
frame jank. Use a controller to inspect it or choose a fixed configuration:

```dart
final performance = PdfPerformanceController(); // Auto

PdfReader(bytes: pdfBytes, performance: performance);
debugPrint('${performance.diagnostics}');

// Applied when the document worker next starts; never resized mid-scroll.
performance.mode = const PdfPerformanceMode.fixed(workerCount: 2);
```

Deep zoom uses a 512 px, byte-budgeted LoD tile pyramid with coarse-tile
fallback and visible-first scheduling. Hosts can give `PdfRasterCache` a
separate persistent `tiles` store; disk reads race live rasterization and disk
writes start only after the fresh tile is displayable, so persistence never
extends first paint. For supported native targets, the optional
`dart_pdf_editor_flutter_gpu` companion compiles a conservative subset of a
retained page scene once, reuses scene-spanning image textures, and replays
tiles through Impeller. Unsupported pages and all web builds keep the Canvas
backend automatically.

## Viewing

- Zooming/panning viewer with fit-page and fit-width modes, deep-zoom
  detail rendering past the raster caps, and exact scroll metrics on
  long mixed-size documents.
- Smooth fast scrolling on heavy documents: pages flying past show
  low-res previews (filled in by a background prerender) instead of
  blank paper, and full rendering resumes the moment scrolling
  settles.
- Progressive rendering records pages in a default worker, streams partial
  records as they are produced, and reveals complex pages top-down.
- Text selection (mouse, and touch with selection handles), full-text
  search with page-text and annotation-content results, link navigation,
  outlines.
- Faithful print-oriented overprint and spot-color rendering, including
  colorants sampled from images.
- Theming via `PdfViewerTheme`, dark mode, arbitrary page colors, and a
  hide-all-annotations toggle.

## Editing

Every edit is an incremental save: undo/redo is built in, and revisions
are byte prefixes of one buffer.

- Annotation tools: highlight/underline/strikeout/squiggly, ink with
  stylus pressure and spline smoothing, shapes, free text with in-place
  editing, notes, stamps (including custom saved stamps), and a saved
  ink signature. The hyperlink tool authors URI and in-document links, and
  placed images and raster snapshots can be cropped interactively.
- A stamp on the page saves back into the stamp collection from its
  right-click menu (`Save to stamps`), so a design that arrived in a
  document is reusable. Stamps this editor placed carry their vector
  design, so they come back with their `{{date}}`-style fields still live.
- Certificate-backed digital signatures: load an in-memory RSA private key
  and X.509 chain, then add a validated PAdES B-B signature as an undoable
  document revision. This is separate from the drawn ink-signature tool.
- True redaction: place `/Redact` marks, then burn them per §12.5.6.23 —
  covered text and images are removed from the file bytes with a compacted
  save (not painted over), so the redacted content is unrecoverable.
- Direct manipulation: select (single, marquee, ⌘A), move, resize, and
  rotate with live appearance previews, plus a slicing circle eraser,
  copy/cut/paste, z-order, restyling, and a context menu with
  host-extensible entries (right-click, or long-press on touch).
- Lock/unlock annotations with Acrobat/Bluebeam-compatible PDF flags and
  assign custom keyboard shortcuts to every editing tool.
- Forms: fill text/checkbox/radio/choice fields in place, set button
  images, and administer fields (add, rename, retype, delete, flatten).
  Fields are highlighted with a translucent wash by default
  (`PdfViewer.highlightFormFields`).
- OCR seam: `PdfOcrEngine` plus `PdfEditor.applyOcr` rasterizes a page,
  runs any recognizer you provide, and injects an invisible selectable text
  layer. Use `pdf_ocr_ondevice` for native offline OCR, or `pdf_ocr_vlm` for
  HTTP OCR services and Flutter web.
- Panels: thumbnail sidebar with drag-reorder, annotation sidebar with
  search and multi-select, properties panel, and search results panel,
  all resizable and persisted.
- Permissions: `/F` read-only and locked flags are honored, and a
  `canEditAnnotation` predicate implements policies like "users may
  only edit their own annotations" in one line.
- Sync: an `annotationChanges` feed plus `applyRemoteChange` for wiring
  annotations to a collaborative store (Firestore, websockets, etc.). A
  remote apply is a non-crossable undo checkpoint; later local edits remain
  undoable without removing the remote state.

## Composing your own UI

`PdfEditorView` and `PdfReader` are assembled from public parts:
`PdfViewer`, `PdfEditingController`, `PdfEditingToolbar`, and the panels,
so apps wanting custom chrome can wire those directly:

```dart
import 'package:pdf_document/pdf_document.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';

// Just the viewer
PdfViewer(document: PdfDocument.open(bytes));

// Your own editor layout. The controller owns the document revisions, and
// the viewer reads the current one from it and follows its edits itself -
// no need to pass `document` or rebuild the viewer as revisions land.
final editing = PdfEditingController(bytes);
final viewer = PdfViewerController();

Column(children: [
  Expanded(
    child: PdfViewer(
      controller: viewer,
      editing: editing,
    ),
  ),
  PdfEditingToolbar(controller: editing, viewerController: viewer),
]);

// Saving
final Uint8List saved = editing.bytes;

// Cryptographically sign with PEM/DER key and certificate files.
final identity = PdfDigitalSignatureIdentity.fromFiles(
  privateKey: privateKeyBytes,
  certificates: certificateFileBytes,
);
await editing.addDigitalSignature(
  identity,
  reason: 'Approved',
  location: 'Melbourne',
);
final Uint8List signed = editing.bytes; // PAdES B-B, validated on commit
```

The [example app](example) is a thin shell over `PdfEditorView` (with a
toggle that swaps in `PdfReader`) plus the app-side concerns: file
open/save dialogs, theme mode, and Flutter overlays pinned onto PDF
pages. It runs on all six platforms.

## OCR

`dart_pdf_editor` owns the PDF side of OCR: it renders a page image,
hands it to a `PdfOcrEngine`, and writes the returned text boxes back as
invisible text. It deliberately does not bundle a recognizer in the core
viewer package.

For native offline OCR:

```sh
flutter pub add pdf_ocr_ondevice
```

```dart
import 'dart:typed_data';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_ocr_ondevice/pdf_ocr_ondevice.dart';

Future<Uint8List> addOcrNative(Uint8List bytes) async {
  if (!PdfOcrModelManager.isSupported) return bytes;

  final manager = PdfOcrModelManager();
  final model = PdfOcrModels.ppOcrV5Mobile;

  if (!await manager.isDownloaded(model)) {
    await manager.download(model);
  }

  final engine = await OnDeviceOcrEngine.fromDownloadedModel(manager, model);
  try {
    final editor = PdfEditor(PdfDocument.open(bytes));
    for (var page = 0; page < editor.document.pageCount; page++) {
      await editor.applyOcr(page, engine, pixelRatio: 2);
    }
    return editor.save();
  } finally {
    await engine.dispose();
    manager.close();
  }
}
```

For web or server-backed OCR:

```sh
flutter pub add pdf_ocr_vlm
```

```dart
import 'dart:typed_data';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_ocr_vlm/pdf_ocr_vlm.dart';

Future<Uint8List> addOcrViaHttp(Uint8List bytes) async {
  final engine = VlmOcrEngine(
    endpoint: Uri.parse('https://ocr.example.com/ocr'),
    minConfidence: 0.3,
  );
  try {
    final editor = PdfEditor(PdfDocument.open(bytes));
    for (var page = 0; page < editor.document.pageCount; page++) {
      await editor.applyOcr(page, engine, pixelRatio: 2.5);
    }
    return editor.save();
  } finally {
    engine.close();
  }
}
```

After saving, reopen or replace the document bytes in `PdfReader` /
`PdfEditorView`. The layer is invisible by default, so the scan looks the
same, but text selection, search, copy, and extraction work. Pass
`visible: true` to `applyOcr` while debugging box alignment.

## Web rendering

On the web, `PdfReader`/`PdfEditorView` can run page interpretation and image
decode off the browser main thread in a **Web Worker**. The worker script ships
in the optional [`dart_pdf_editor_assets`](../dart_pdf_editor_assets) package;
depend on it and call `registerBundledEditorAssets()` once at startup to enable
off-main-thread rendering with no further setup (see
[Optional bundled assets](#optional-bundled-assets)). Without it, web rendering
runs on the main thread. If the worker URL is set but the script cannot be
loaded, rendering degrades to the main thread too.

Apps that want to self-host the worker under their own URL can build a custom
bundle from the app root and override the URL before opening a viewer:

```sh
dart run dart_pdf_editor:build_web_worker   # writes web/pdf_render_worker.dart.js
```

```dart
pdfRenderWorkerScriptUrl = 'pdf_render_worker.dart.js';
```

Set `pdfRenderWorkerScriptUrl = null` to force main-thread rendering.
The worker does not require COOP/COEP headers, but a cross-origin isolated
host lets pooled workers share the document bytes through `SharedArrayBuffer`
instead of cloning them per worker. Full setup, dart2wasm-host notes, and the
worker protocol are in
[doc/render_worker_web.md](https://github.com/ben-milanko/dart-pdf/blob/main/doc/render_worker_web.md).

## Under the hood

Encrypted files (RC4/AES-128/AES-256, encrypt-on-write), digital
signature validation, the full shading and blend-mode set, ICC color,
CCITT/JBIG2/JPEG 2000 images, and lenient parsing of broken real-world
files, with conformance pinned against the Ghent Output Suite and the
PDF.js test corpus. Checked-in PDF.js visual comparisons are available at
[`../../test_corpora/pdfjs/_renders/README.md`](../../test_corpora/pdfjs/_renders/README.md).
