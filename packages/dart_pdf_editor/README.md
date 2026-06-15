![dart-pdf — pure-Dart PDF renderer & editor for Flutter](https://raw.githubusercontent.com/ben-milanko/dart-pdf/main/doc/banner.png)

# dart_pdf_editor

[![pub package](https://img.shields.io/pub/v/dart_pdf_editor.svg)](https://pub.dev/packages/dart_pdf_editor)
[![pub points](https://img.shields.io/pub/points/dart_pdf_editor)](https://pub.dev/packages/dart_pdf_editor/score)
[![CI](https://github.com/ben-milanko/dart-pdf/actions/workflows/ci.yml/badge.svg)](https://github.com/ben-milanko/dart-pdf/actions/workflows/ci.yml)
[![codecov](https://codecov.io/gh/ben-milanko/dart-pdf/branch/main/graph/badge.svg?flag=dart_pdf_editor)](https://codecov.io/gh/ben-milanko/dart-pdf)
[![License: Apache-2.0](https://img.shields.io/github/license/ben-milanko/dart-pdf)](https://github.com/ben-milanko/dart-pdf/blob/main/LICENSE)

A Flutter PDF viewer and editor rendered natively in Dart, with no
platform views or native PDF libraries. The same code runs on iOS,
Android, macOS, Windows, Linux, and the web.

![The example app: PdfEditorView showing the feature showcase document](https://raw.githubusercontent.com/ben-milanko/dart-pdf/main/doc/dart_pdf_editor_example.jpg)

Two drop-in widgets carry the whole UI — give them bytes and bounded
space, and everything in the screenshot above (search, page navigation,
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

Try the [live demo](https://dart-pdf-demo.web.app) of the example app
on Flutter web, with a built-in feature showcase document.

Built on the pure-Dart
[dart-pdf suite](https://github.com/ben-milanko/dart-pdf): `pdf_cos`
(file syntax) ← `pdf_document` (document semantics + editing) ←
`pdf_graphics` (interpreter + fonts) ← `dart_pdf_editor` (Flutter widgets).

## Performance

Pure Dart, and fast: on a real-world corpus (49 files / 245 pages of
CAD drawings, scans, reports, and forms) the parse + content-stream
**interpreter is ~1.5× faster than PDFium** — the C++ engine Chrome
uses — at **13.6 ms/page vs 20.6 ms/page** (scale 2). Full Flutter
rasterization is 53.7 ms/page (2.6× PDFium); that remaining gap is image
decoding and GPU raster, not the interpreter.

| engine | ms/page | vs PDFium |
|---|---|---|
| dart-pdf interpret (pure Dart) | **13.6** | **1.52× faster** |
| PDFium (open + rasterize) | 20.6 | 1.00× |
| dart-pdf render (full Flutter raster) | 53.7 | 2.60× slower |

Numbers and methodology — including reproducible harnesses that diff
dart-pdf against PDFium file-by-file — are in
[`benchmark/`](https://github.com/ben-milanko/dart-pdf/tree/main/benchmark).

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
- Direct manipulation: select (single, marquee, ⌘A), move, resize, and
  rotate with live appearance previews, plus a slicing circle eraser,
  copy/cut/paste, z-order, restyling, and a context menu with
  host-extensible entries (right-click, or long-press on touch).
- Forms: fill text/checkbox/radio/choice fields in place, set button
  images, and administer fields (add, rename, retype, delete, flatten).
  Fields are highlighted with a translucent wash by default
  (`PdfViewer.highlightFormFields`).
- Panels: thumbnail sidebar with drag-reorder, annotation sidebar with
  search and multi-select, properties panel, and search results panel,
  all resizable and persisted.
- Permissions: `/F` read-only and locked flags are honored, and a
  `canEditAnnotation` predicate implements policies like "users may
  only edit their own annotations" in one line.
- Sync: an `annotationChanges` feed plus `applyRemoteChange` for wiring
  annotations to a collaborative store (Firestore, websockets, etc.).

## Composing your own UI

`PdfEditorView` and `PdfReader` are assembled from public parts —
`PdfViewer`, `PdfEditingController`, `PdfEditingToolbar`, the panels —
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
```

The [example app](example) is a thin shell over `PdfEditorView` (with a
toggle that swaps in `PdfReader`) plus the app-side concerns: file
open/save dialogs, theme mode, and Flutter overlays pinned onto PDF
pages. It runs on all six platforms.

## Web rendering

On the web the viewer renders on the main thread by default — nothing to
configure. For heavy/CAD documents you can move page interpretation and
image decode onto a **Web Worker** (the web counterpart of the native
background isolate): build the worker bundle, then point the app at it.

```sh
dart run dart_pdf_editor:build_web_worker   # writes web/pdf_render_worker.dart.js
```

```dart
void main() {
  if (kIsWeb) {
    pdfRenderWorkerScriptUrl = 'pdf_render_worker.dart.js';
  }
  runApp(...);
}
```

`PdfReader`/`PdfEditorView` pick it up automatically, and if the script is
missing it degrades to main-thread rendering — it's a pure opt-in upgrade.
For multithreaded WebAssembly raster, build with `flutter build web --wasm`
and serve the cross-origin-isolation headers (`Cross-Origin-Opener-Policy:
same-origin`, `Cross-Origin-Embedder-Policy: require-corp`). Full setup, the
dart2wasm-host notes, and the worker protocol are in
[doc/render_worker_web.md](https://github.com/ben-milanko/dart-pdf/blob/main/doc/render_worker_web.md).

## Under the hood

Encrypted files (RC4/AES-128/AES-256, encrypt-on-write), digital
signature validation, the full shading and blend-mode set, ICC color,
CCITT/JBIG2/JPEG 2000 images, and lenient parsing of broken real-world
files, with conformance pinned against the Ghent Output Suite and the
PDF.js test corpus. Checked-in PDF.js visual comparisons are available at
[`../../test_corpora/pdfjs/_renders/README.md`](../../test_corpora/pdfjs/_renders/README.md).
