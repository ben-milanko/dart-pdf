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

## Performance

Pure Dart, and fast: on a real-world corpus (49 files / 255 pages of
CAD drawings, scans, reports, and forms) the parse + content-stream
**interpreter is ~1.9× faster than PDFium**: **13.3 ms/page vs 24.9 ms/page**
at scale 2. PDFium is the C++ engine Chrome uses. Full Flutter
rasterization is 52.0 ms/page (2.08× PDFium); that remaining gap is image
decoding and GPU raster, not the interpreter.

| engine | ms/page | vs PDFium |
|---|---|---|
| dart-pdf interpret (pure Dart) | **13.3** | **1.87× faster** |
| PDFium (open + rasterize) | 24.9 | 1.00× |
| dart-pdf render (full Flutter raster) | 52.0 | 2.08× slower |

Numbers and methodology are in
[`benchmark/`](https://github.com/ben-milanko/dart-pdf/tree/main/benchmark).
The harnesses diff dart-pdf against PDFium file by file.

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

## Viewing

- Zooming/panning viewer with fit-page and fit-width modes, deep-zoom
  detail rendering past the raster caps, and exact scroll metrics on
  long mixed-size documents.
- Smooth fast scrolling on heavy documents: pages flying past show
  low-res previews (filled in by a background prerender) instead of
  blank paper, and full rendering resumes the moment scrolling
  settles.
- Text selection (mouse, and touch with selection handles), full-text
  search with a results panel, link navigation, outlines.
- Theming via `PdfViewerTheme`, dark mode, arbitrary page colors, and a
  hide-all-annotations toggle.

## Editing

Every edit is an incremental save: undo/redo is built in, and revisions
are byte prefixes of one buffer.

- Annotation tools: highlight/underline/strikeout/squiggly, ink with
  stylus pressure and spline smoothing, shapes, free text with in-place
  editing, notes, stamps (including custom saved stamps), and a saved
  ink signature.
- Certificate-backed digital signatures: load an in-memory RSA private key
  and X.509 chain, then add a validated PAdES B-B signature as an undoable
  document revision. This is separate from the drawn ink-signature tool.
- Direct manipulation: select (single, marquee, ⌘A), move, resize, and
  rotate with live appearance previews, plus a slicing circle eraser,
  copy/cut/paste, z-order, restyling, and a context menu with
  host-extensible entries (right-click, or long-press on touch).
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

// Your own editor layout
final editing = PdfEditingController(bytes);
final viewer = PdfViewerController();

ListenableBuilder(
  listenable: editing,
  builder: (context, _) => Column(children: [
    Expanded(
      child: PdfViewer(
        document: editing.document, // rebuild with each revision
        controller: viewer,
        editing: editing,
      ),
    ),
    PdfEditingToolbar(controller: editing, viewerController: viewer),
  ]),
);

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

On the web, `PdfReader`/`PdfEditorView` use a bundled **Web Worker** package
asset by default, so page interpretation and image decode can run off the
browser main thread without app setup. If the worker cannot be loaded, rendering
degrades to the main thread.

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
