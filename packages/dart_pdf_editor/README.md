![dart-pdf, an open-source Flutter PDF editor and pure-Dart renderer](https://raw.githubusercontent.com/ben-milanko/dart-pdf/main/doc/banner.png)

# Flutter PDF editor: dart_pdf_editor

[![pub package](https://img.shields.io/pub/v/dart_pdf_editor.svg)](https://pub.dev/packages/dart_pdf_editor)
[![pub points](https://img.shields.io/pub/points/dart_pdf_editor)](https://pub.dev/packages/dart_pdf_editor/score)
[![CI](https://github.com/ben-milanko/dart-pdf/actions/workflows/ci.yml/badge.svg)](https://github.com/ben-milanko/dart-pdf/actions/workflows/ci.yml)
[![codecov](https://codecov.io/gh/ben-milanko/dart-pdf/branch/main/graph/badge.svg?flag=dart_pdf_editor)](https://codecov.io/gh/ben-milanko/dart-pdf)
[![License: Apache-2.0](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](https://github.com/ben-milanko/dart-pdf/blob/main/LICENSE)

`dart_pdf_editor` is a complete, open-source Flutter PDF editor and viewer
rendered natively in Dart, with no platform views or native PDF libraries. The
same code runs on iOS, Android, macOS, Windows, Linux, and the web.

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

The stock editor's Settings popup includes cursor-guide and grid controls.
Custom chrome can configure the same persisted preferences directly (grid
units are PDF points):

```dart
editing.preferences
  ..showVerticalCursorGuide = true
  ..showHorizontalCursorGuide = true
  ..showSnapGrid = true
  ..snapToGrid = true
  ..gridSpacing = 10;
```

The visible grid and snapping are independent. Grid snapping covers annotation
placement, movement, resizing, and line or polygon vertices. Hold Alt during a
gesture for a temporary off-grid edit.

Try the [live demo](https://dart-pdf-demo.web.app) of the example app
on Flutter web, with a built-in feature showcase document.

The [Flutter PDF editor overview](https://dart-pdf.com/flutter-pdf-editor)
covers the architecture, supported editing features, package layout, and
measured performance.

For a complete first integration, follow
[How to add PDF editing to a Flutter app](https://dart-pdf.com/guides/add-pdf-editing-to-flutter).

Built on the pure-Dart
[dart-pdf suite](https://github.com/ben-milanko/dart-pdf): `pdf_cos`
(file syntax) ← `pdf_document` (document semantics + editing) ←
`pdf_graphics` (interpreter + fonts) ← `dart_pdf_editor` (Flutter widgets).

## Optional bundled assets

The editor's six bundled fonts, the metric-compatible faces it substitutes into
unembedded standard-14 text, and its web render worker (~4.2 MB package
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
| Unembedded standard-14 text spaced as the page was typeset (TeX Gyre Heros / Termes / Cursor) | bundled fonts |
| Font menu's "bundled" group (DejaVu, Fira Sans, Spectral, Lobster) | bundled fonts |
| Fallback glyphs when editing composite (/Type0) text a subset font can't draw | bundled fonts (DejaVu trio) |
| Off-main-thread page rendering on **web** | web worker |

Missing assets degrade gracefully: the font menu simply drops the bundled group
(base-14, document, platform and custom fonts still work), composite-text
fallback is skipped, unembedded standard-14 text is drawn in the closest face
the host has (Arial, Liberation Sans, Nimbus Sans and their serif/mono
counterparts, then any sans), and web rendering falls back to the main thread. An app can
also supply its own catalogue - set `pdfBundledFonts` to your own
`PdfBundledFont`s (each backed by an asset key or a `loadBytes` byte loader).

## Performance

**The default viewer has not reached PDFium interaction parity yet.** The most
recent real-document checkpoint (2 October 2026, commit `fadf7760`) used five
interleaved DartPDF/PDFium runs in Chrome 154 on an M1 Pro, a 1400×1000
viewport, and the default JS/CanvasKit web build. The input was a locally
supplied 62-page, 24.1 MB illustrated PDF; the journey opened it, jumped to
pages 3 and 47, zoomed to 1.72×, and drove matched wheel gestures. Lower
ratios are better.

| user-visible metric | DartPDF p50 / p95 | PDFium p50 / p95 | ratio p50 / p95 |
|---|---:|---:|---:|
| open to stable visual | 711 / 757 ms | 1264 / 1411 ms | **0.56× / 0.54×** |
| page first visual change | 24 / 31 ms | 19 / 22 ms | 1.26× / 1.39× |
| page stable visual | 271 / 357 ms | 118 / 121 ms | **2.30× / 2.95×** |
| zoom stable visual | 44 / 47 ms | 19 / 25 ms | **2.32× / 1.92×** |
| wheel journey | 413 / 919 ms | 972 / 1022 ms | 0.42× / 0.90× |
| wheel rAF interval p95 | 83 ms | 17 ms | **4.96×** |
| peak browser RSS p50 | 2167 MiB | 1887 MiB | 1.15× |

The wheel journey completes sooner, but its worse rAF tail means it is not yet
as smooth; total duration alone would be a misleading win. Headless Chrome 154
appears to pace frames at 60 Hz on this host (PDFium's rAF p95 is 17 ms, where
it was 10 ms in August), so the cadence ratio is not directly comparable with
earlier checkpoints. Open and memory are inside the current provisional budgets
(memory with less headroom than in August), while stable navigation, zoom, and
scroll cadence are not. These numbers describe desktop web only and are not a
native-desktop or mobile parity claim. See the
[full methodology and historical checkpoints](https://github.com/ben-milanko/dart-pdf/blob/main/doc/benchmarks/pdfium-parity.md).

The offline corpus benchmark remains useful as a subsystem diagnostic, not as
evidence of viewer latency: over the 52-file / 268-page common subset at scale
2, pure-Dart interpretation takes 10.3 ms/page, PDFium rasterization takes
31.1 ms/page, and the complete Flutter raster plus readback takes 54.0 ms/page.
Reproducible offline harnesses and file-by-file diffs live in
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
[`dart_pdf_editor_flutter_gpu`](https://pub.dev/packages/dart_pdf_editor_flutter_gpu)
companion compiles a conservative subset of a retained page scene once, reuses
scene-spanning image textures, and replays tiles through Impeller. Unsupported
pages and all web builds keep the Canvas backend automatically.

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

## Splitting and exporting pages

Provide `onSplitPages` to enable **Split PDF…** in the thumbnail sidebar/grid's
page-actions menu. Enter `1-3, 7, 10-12` to create three separate PDFs; the host
receives the complete batch in range order. `onExportPages` enables the existing
single-range export and exporting a thumbnail selection into one PDF.

```dart
PdfEditorView(
  bytes: bytes,
  onSplitPages: (documents) {
    for (final output in documents) {
      // Save/share output, upload it, or open it in another editor tab.
    }
  },
  onExportPages: (output) {
    // Handle a single extracted PDF.
  },
)
```

For custom chrome, use `showPdfSplitDialog`, then
`controller.exportPageRanges(ranges)`. The controller also provides
`exportPages(indices)`, `exportPageRange(start, end)`, and `exportSelectedPages()`.
Programmatic ranges are zero-based and inclusive; dialog page numbers start at
1. Exports leave the source, selection, and undo history unchanged.

The [example app](example/lib/main.dart) opens each split result in its own
editable tab and opens single-file exports in a new tab too. Use the normal Save
action on a result tab to save, download, or share that PDF.

Extraction deep-copies page annotations and reachable resources, remaps links
between retained pages in each output, and retains the document information
dictionary. It omits document-level outlines/bookmarks, the AcroForm field list,
and named destinations; copied widgets are not registered in an output AcroForm.
Resources can remain shared within one output; separate outputs own their copies.
Encrypted sources produce **unencrypted outputs**. See the
[core splitting API](../pdf_document/README.md#splitting-and-extracting-pages)
for the bytes-only `PdfSplitter` facade and full extraction semantics.

## Customising the UI

Control comes in layers. Each works on its own, and each later one goes
further: **tokens** restyle the stock chrome, **surfaces** let you rebuild
the header, menus and floating chips from stock parts, the **presenter**
replaces how dialogs, menus and notices appear, **commands** let your own
controls drive the editor, and the **headless** parts let you assemble an
editor from scratch. None of them needs a `MaterialApp`.

### Setup

The stock chrome draws Material Icons, so the host app's `pubspec.yaml` must
bundle that font:

```yaml
flutter:
  uses-material-design: true
```

The library is built on [material_ui](https://pub.dev/packages/material_ui)
(since 7.0; see [doc/MIGRATING-7.0.0.md](https://github.com/ben-milanko/dart-pdf/blob/main/doc/MIGRATING-7.0.0.md)).
Register the editor's localizations so its strings follow the app's locale
(without them it falls back to English). `PdfEditorLocalizations.delegates`
carries the editor's delegate plus material_ui's Material, Cupertino and
widgets delegates:

```dart
import 'package:material_ui/material_ui.dart';

MaterialApp(
  localizationsDelegates: PdfEditorLocalizations.delegates,
  supportedLocales: PdfEditorLocalizations.supportedLocales,
  // If the app has its own bundle, spread both:
  // localizationsDelegates: [
  //   DartPdfEditorLocalizations.delegate,
  //   ...AppLocalizations.localizationsDelegates,
  // ],
  themeMode: switch (prefs.themePreference) {
    PdfThemePreference.system => ThemeMode.system,
    PdfThemePreference.light => ThemeMode.light,
    PdfThemePreference.dark => ThemeMode.dark,
  },
  home: ...,
)
```

`PdfEditingPreferences.themePreference` is the user's saved theme choice in
a design-system-neutral enum. The generated
`DartPdfEditorLocalizations.localizationsDelegates` lists the legacy
`flutter_localizations` delegates, which suit an app still on
`package:flutter/material.dart`; a material_ui app should use
`PdfEditorLocalizations.delegates` (or spread material_ui's
`GlobalMaterialLocalizations.delegates` itself, if its own gen-l10n list
brings the legacy ones). Either way the editor fills in whichever Material
and Cupertino localizations the host lacks. Your own dialogs opened with `showPdfDialog` get Enter-to-submit
by wrapping the primary action in `PdfDialogSubmit.action(onSubmit: ...,
child: ...)`, which takes any widget.

### 1. Tokens

`PdfEditorThemeData` holds the editor's design tokens - status colours
(`success`, `warning`, `danger`, `info`), the small section-label style, the
compact-layout width (`compactWidth`, 700 by default - `pdfShellCompactWidth`)
and how far notices float above the toolbar (`toastLift`) - plus the canvas
tokens in `viewer` (`PdfViewerThemeData`: selection and search washes,
annotation and element chrome, the marquee, snap grid and alignment guides,
redaction hatching, rulers, readout chips, handle size, diff colours,
scrollbar markers). Every field is optional; a null keeps the stock value.
They are plain colours, text styles and lengths, so they read the same under
any design system.

```dart
PdfEditorView(
  bytes: bytes,
  theme: const PdfEditorThemeData(
    danger: Color(0xFFB00020),
    compactWidth: 600,
    viewer: PdfViewerThemeData(
      annotationChromeColor: Color(0xFF00897B),
      alignmentGuideColor: Color(0xFF00897B),
    ),
  ),
);
```

Or set them once for several editors with
`PdfEditorScope(presenter: ..., theme: ..., child: ...)`, and read the
effective values with `PdfEditorThemeData.of(context)`. `PdfViewerTheme`
still works on its own for the canvas tokens. Both data classes have
`merge`, `copyWith` and `lerp`.

### 2. Surfaces

**Header.** `headerBuilder` receives the stock header's parts - page number,
zoom, search, view options, panel switch, save, the compact Controls button
- so you can lay out your own header, add your own controls, or turn it into
a platform nav bar. `parts.stock` is the stock header; `parts.bar(...)`
gives you its look with your own children:

```dart
PdfEditorView(
  bytes: bytes,
  onSave: save,
  headerBuilder: (context, parts) => parts.bar(
    leading: [parts.pageNumber, parts.search].nonNulls.toList(),
    trailing: [
      IconButton(icon: const Icon(Icons.ios_share), onPressed: share),
      if (parts.compact) ...[parts.save, parts.controls(includeSave: false)]
          .nonNulls
      else ...[parts.viewOptions, parts.panelSwitch, parts.save].nonNulls,
    ],
  ),
);
```

`PdfReader` takes the same `headerBuilder` (its parts have no save). Where
your save button shares or exports, `parts.saveButton(enabledWhenUnchanged:
true)` keeps it enabled before the first edit; ⌘S / Ctrl+S still saves only
when there is something to save.

**Panels.** `extraPanels` adds your own dock panels beside the stock ones.
Each gets a toggle in the panel switch (unless `showInPanelSwitch: false`), a
resizable frame on its dock with a move handle that drags it to another
edge, and a bottom sheet on a compact layout. Its dock, width and visibility
persist by `id`; pass `open:` a `ValueNotifier<bool>` to keep visibility
yourself. The builder gets the frame's geometry, for the stock header
controls:

```dart
PdfEditorView(
  bytes: bytes,
  extraPanels: [
    PdfEditorPanel(
      id: 'comments',
      icon: Icons.forum_outlined,
      label: 'Comments',
      builder: (context, geometry) => Column(children: [
        Row(children: [
          if (geometry.moveHandle() case final handle?) handle,
          const Expanded(child: Text('Comments')),
          if (geometry.closeButton() case final close?) close,
        ]),
        const Expanded(child: CommentsList()),
      ]),
    ),
  ],
);
```

**Menus.** `annotationMenuEntries`, `textMenuEntries` and
`formFieldMenuEntries` receive each context menu's stock rows and return the
rows to show. Find stock rows by `PdfMenuEntry.id` (their `pdf-*` keys) and
build new ones with `pdfAnnotationMenuEntry` / `pdfTextMenuEntry`:

```dart
annotationMenuEntries: (context, request, stock) => [
  ...stock.where((e) => e.id != 'pdf-annot-menu-flatten'),
  const PdfMenuDivider(),
  pdfAnnotationMenuEntry(PdfAnnotationMenuItem(
    label: 'Share',
    icon: Icons.ios_share,
    onSelected: (request) => shareAnnotation(request.primary),
  )),
],
```

**Floating chips.** The chips the editor floats over the page - beside a
touch selection, a touch text selection or an image crop, and the
measurement and style readouts - are drawn by the presenter's `actionBar`
and `readout` (below), which get the stock chip plus its actions as data.
`showSelectionChip: false` and `showInlineTextStyleChip: false` turn the
selection chip and the touch text-style chip off when you show your own UI;
`PdfViewerController.selectionGlobalRect` (a `ValueListenable<Rect?>`) and
`globalRectOf(page, rect)` tell you where to put it.

### 3. Presenter

`PdfEditorPresenter` decides how the editor shows things - dialogs, bottom
sheets, popup menus, notices, the floating action bars and readouts - and
answers its prompts (text, colour, font, link, measuring scale, page ranges,
signatures, ...). Each method defaults to the stock UI, so override only
what you want to change. Extend the class rather than implementing it: new
methods arrive with defaults.

```dart
class MyPresenter extends PdfEditorPresenter {
  const MyPresenter();

  @override
  bool notice(BuildContext context, PdfEditorNotice notice) {
    showMyToast(notice.message, onUndo: notice.onUndo);
    return true;
  }

  @override
  Future<String?> text(BuildContext context, PdfTextRequest request) =>
      showMyTextSheet(context, request.title, initial: request.initial);

  @override
  Widget actionBar(BuildContext context, PdfActionBarRequest request) =>
      MyChipRow(actions: request.actions); // or request.stock
}

PdfEditorView(bytes: bytes, presenter: const MyPresenter());
```

`PdfViewer` and `PdfReader` take `presenter:` too, or put a
`PdfEditorScope(presenter: ..., child: ...)` above several editors. The
stock dialogs carry the scope into their routes, so a prompt opened from
inside one (the stamp editor's colour picker, say) uses your presenter as
well. Call `super.method(...)` to fall back to the stock UI for a case you
don't handle.

**Signature pad.** `PdfSignaturePad` is the signature dialog's drawing
surface on its own - pointer and stylus with pressure, the predicted lead,
trackpad drawing - over a `PdfSignaturePadController` (strokes, ink, pen,
`toSignature()`). Put it in your own sheet or page; a presenter's
`signature` prompt can return what it draws.

**Cupertino presenter.** `package:dart_pdf_editor/cupertino.dart` adds
`PdfCupertinoPresenter`, an iOS-style presenter built on `cupertino_ui`:

```dart
import 'package:dart_pdf_editor/cupertino.dart';

CupertinoApp(
  home: CupertinoPageScaffold(
    child: PdfEditorView(
      bytes: bytes,
      presenter: const PdfCupertinoPresenter(),
    ),
  ),
)
```

| Method | Shows |
|---|---|
| `dialog` | every stock dialog on a `CupertinoDialogRoute` (Enter-to-submit kept) |
| `confirm`, `text`, `styledText`, `link` | a `CupertinoAlertDialog` with `CupertinoTextField`s (plus a slider, Bold/Italic toggles and swatches for `styledText`, a segmented control for `link`) |
| `pageRange`, `splitRanges`, `measurementScale`, `measurementInput` | a `CupertinoAlertDialog` form; units open as action sheets |
| `menu` | a `CupertinoActionSheet` with Cancel |
| `formChoice` | a `CupertinoPicker` (single-select) or a checklist (multi-select) under Cancel / Done |
| `sheet` | a modal popup sliding up from the bottom |
| `notice` | a toast in the root overlay, with Undo |
| `actionBar`, `readout` | dark iOS edit-menu style capsules |
| `color`, `font`, `signature` | the stock pickers, on the Cupertino dialog route |

Its text fields use `pdfCupertinoTextContextMenu` (the system menu where
the platform has one, else `CupertinoAdaptiveTextSelectionToolbar`), and its
prompts keep the stock prompts' `pdf-*` keys. It runs under a `CupertinoApp`
with no `MaterialApp`: `PdfMaterialHost` supplies what the stock pickers
need. It draws no `CupertinoIcons`, so it needs no `cupertino_icons`
dependency; its few glyphs come from Material Icons, which the chrome needs
anyway. `package:dart_pdf_editor/dart_pdf_editor.dart` does not import it,
so a Material app does not compile it. Extend it to change one method.

### 4. Commands and tool groups

Everything the stock toolbar does goes through `PdfEditorCommands`, which
`PdfEditorView` provides to its subtree (and the viewer's tool shortcuts use).
A host's own toolbar, menu or command palette runs the same commands, so a
measure tool still asks for its scale first:

```dart
final commands = PdfEditorCommands.of(context);
await commands.armTool(context, PdfEditTool.measureDistance);
commands.applyColor(const Color(0xFFE53935));

// Everything the editor offers, for a palette or menu: tools, panels, view
// modes, save.
for (final command in commands.catalog(context)) {
  print('${command.id}: ${command.label(context)}');
}
```

To reach them from above the editor (an app-level palette), create them
yourself and pass `PdfEditorView(commands: ...)`. `toolbarBuilder` replaces
the toolbar with one you build from the catalog.

**Keyboard.** The viewer's keys map to intents - `PdfCopyIntent`,
`PdfSelectAllIntent`, `PdfUndoIntent`, `PdfRedoIntent`,
`PdfDeleteSelectionIntent`, `PdfNudgeSelectionIntent`, `PdfArmToolIntent` and
the rest. Rebind keys by passing a copy of `pdfViewerDefaultShortcuts`
(`PdfViewer.shortcuts`, or `viewerShortcuts` on `PdfEditorView` and
`PdfReader`); add keys with a `Shortcuts` above the editor; change what a
command does with an `Actions` above it:

```dart
Actions(
  actions: {
    PdfDeleteSelectionIntent: CallbackAction<PdfDeleteSelectionIntent>(
      onInvoke: (_) => confirmThenDelete(),
    ),
  },
  child: PdfEditorView(
    bytes: bytes,
    viewerShortcuts: {
      ...pdfViewerDefaultShortcuts,
      const SingleActivator(LogicalKeyboardKey.backspace):
          const DoNothingAndStopPropagationIntent(),
    },
  ),
)
```

`toolGroups` orders the dock and takes groups of your own; an entry can be a
stock tool, a markup kind or a `PdfCommand`:

```dart
PdfEditorView(
  bytes: bytes,
  toolGroups: [
    pdfToolGroups.firstWhere((g) => g.id == 'select'),
    pdfToolGroups.firstWhere((g) => g.id == 'markup'),
    PdfToolGroup(
      'review',
      Icons.rate_review_outlined,
      [
        const PdfToolEntry.tool(PdfEditTool.note, Icons.sticky_note_2_outlined),
        PdfToolEntry.command(PdfCommand(
          id: 'approve',
          icon: Icons.verified_outlined,
          label: (context) => 'Approve',
          invoke: (context) async => approve(),
        )),
      ],
      labelBuilder: (context) => 'Review',
    ),
  ],
)
```

### Any host: MaterialApp (material_ui or legacy), CupertinoApp or WidgetsApp

The editor does not need a material_ui `MaterialApp`. `PdfViewer`,
`PdfReader`, `PdfEditorView` and `PdfComparisonView` run under a legacy
`package:flutter/material.dart` `MaterialApp`, a `CupertinoApp` or a plain
`WidgetsApp` too:

```dart
CupertinoApp(
  home: CupertinoPageScaffold(child: PdfEditorView(bytes: bytes)),
)
```

Each wraps its content in `PdfMaterialHost`, which supplies whatever the
stock chrome needs and the host lacks: material_ui and cupertino_ui
localizations, a theme, and a surface for ink and text fields. The theme
comes from `PdfEditorThemeData.primary`/`brightness` when set, else the
host's material_ui `Theme`, else a legacy `MaterialApp`'s theme (its colour
scheme, text and icon themes, platform and density, carried over by a small
bridge that also shows notices on the legacy `ScaffoldMessenger`), else the
host's `CupertinoTheme`, else its platform brightness and
`DefaultSelectionStyle`. Under a material_ui `MaterialApp` it adds nothing.
Legacy component themes and `ThemeExtension`s do not cross over; build with
`--dart-define=PDF_LEGACY_MATERIAL_BRIDGE=false` to drop the bridge (about
12 KB of web JS) when no host uses the legacy library. The editor's dialogs, menus, sheets, notices
and text-field context menus build under the root navigator, outside that
wrapper, so they re-inject the same things; without a `ScaffoldMessenger`,
notices appear as a toast in the root overlay. Wrap any stock widget you
mount on its own (a `PdfEditingToolbar` next to your own viewer) in
`PdfMaterialHost`, give text fields in your own dialogs
`contextMenuBuilder: pdfTextContextMenu`, and use `PdfDropdown` rather than
`DropdownButton`. The chrome still draws Material Icons, so
`uses-material-design: true` is still needed.

[`example/lib/cupertino_host.dart`](example/lib/cupertino_host.dart) puts the
layers together: a `CupertinoApp` whose nav bar is built from the header
parts, whose toolbar is built from the command catalog, and whose presenter
is `PdfCupertinoPresenter`. The example switches to it at runtime (app menu >
"Switch to Cupertino design", and back from the Cupertino Settings page);
the open documents and their unsaved edits carry over because the edit
sessions live above the app root, in
[`example/lib/workspace.dart`](example/lib/workspace.dart).
`flutter run -t lib/cupertino_host.dart` in `example/` starts it in
Cupertino.

### 5. Headless

Below all of that, the editor is a controller and a viewer you can wire into
any layout yourself - see [Composing your own UI](#composing-your-own-ui).
The preferences can live outside the device's shared_preferences too:
`PdfEditingPreferences(store: ...)` takes any `PdfPreferencesStore` (a
settings database, a per-user profile, or `PdfMemoryPreferencesStore`).

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

### Vector snapshot interchange

The Snapshot tool shares detached vectors between editing controllers by
default through `PdfSnapshotClipboard.instance`. A captured `PdfSnapshot`
provides `pngBytes` for image consumers and `pdfBytes` for PDF clipboard
consumers. `PdfVectorSnapshot.toPdfBytes()` exports one page sized to the
capture; `fromPdfBytes()` imports the first page of an interchange PDF.

Desktop hosts can provide `PdfViewer.systemPdfPasteProvider` (also available
on `PdfEditorView`) to read a PDF for keyboard or context-menu Paste:

```dart
systemPdfPasteProvider: (context) async {
  final data = await myClipboard.readPdf();
  return data == null ? null : PdfClipboardPdf(
    data.bytes,
    changeToken: data.clipboardRevision,
  );
},
```

Return null for snapshots written by your own process so local paste retains
its shared resources and position cascade. The optional `changeToken` should
change whenever the OS clipboard is replaced: once an external revision is
pasted, subsequent local annotation copies take precedence until it changes.
The app includes native PDF/PNG transport on macOS, Windows, and Linux;
mobile and web use the PNG fallback. Direct imports can use
`editing.pasteSnapshotBytes(pdfBytes, pageIndex, at: (x, y))`.

## Optional printing

Add [`dart_pdf_printing`](../dart_pdf_printing) for the DartPDF print preview,
page ranges, paper/layout settings, n-up, markup controls and native system
printing on Android, iOS, macOS, Windows, Linux and web. It registers as a
Flutter plugin; applications that omit it keep the viewer's dependency graph
unchanged. Call `printPdfWithPreview(context, document: document, title: title)`
from your Print button. See the companion package's setup and example,
including the macOS sandbox printing entitlement.
