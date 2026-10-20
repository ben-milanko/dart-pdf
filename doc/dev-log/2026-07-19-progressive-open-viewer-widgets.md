# Expose progressive open on the reusable viewer widgets (#378)

Progressive open (#359, #328) already worked inside the standalone app, but the
capability wasn't reachable through the published `dart_pdf_editor` public API:
the reusable widgets only took `bytes: Uint8List`, `PdfDocument`/`openSource`
weren't exported, and the background full-read helper (`readSourceFully`) lived
in `app/lib/file_io.dart`. A `dart_pdf_editor`-only host (Trax's PDF viewer) had
to re-implement ~150 lines of app orchestration against undocumented internals
(`doc.cos.bytes` as a renderable sparse buffer).

## What landed

- **`readSourceFully` moved into the library.** Lifted verbatim from
  `app/lib/file_io.dart` into `src/progressive_source.dart` (same signature:
  `{onProgress, chunk = 8<<20, cancelToken}`) and exported. The app now imports
  the library copy via the barrel; the app's own source tests are unchanged.
- **`PdfProgressiveSourceBuilder`** (new, exported): the reusable orchestration.
  It opens a sparse first-paint document from the source's ranges
  (`PdfDocument.openSource(..., firstPaintPages: 1)`, reading `.cos.bytes`),
  hands those bytes to a `builder(context, bytes, complete)` so page one paints
  immediately, reads the rest with `readSourceFully` in the background (progress
  + cancellation), then calls the builder again with the full buffer so it
  swaps in place. Owns an internal `PdfCancelToken` cancelled on dispose; never
  closes the host-owned source. Falls back to a plain full read when the first
  paint can't be assembled (`openSource` throws) - a `loadingBuilder` shows
  until bytes exist, `errorBuilder` only when nothing could be produced.
- **`PdfReader.source(...)` / `PdfEditorView.source(...)`** (new named
  constructors). Both are thin composition over `PdfProgressiveSourceBuilder`:
  the builder returns the existing **byte-based** widget at the same tree
  position, so the first-paint→full swap reopens in place (the inner widget owns
  the shell/session/worker) and, with a stable `documentId`, keeps its scroll
  position across the swap. API matches the issue: `source`, `options`,
  `documentId`, `onProgress`, `onFirstPaint`, plus `loadingBuilder`/
  `errorBuilder`.
  - `PdfEditorView.source` **gates editing until the full file lands**: while
    `!complete` it projects `features` through `_gatedFeatures` (toolbar, page
    editing, markup, undo/redo, annotation/properties panels off) and suppresses
    `onSave`/`onSaveAs`/`onDocumentChanged`/insert/export - the first-paint
    buffer is deliberately incomplete and must not be edited or saved.
- **`PdfDocument` exported** from `dart_pdf_editor` (added to the `pdf_document`
  `show` list; `openSource` is a static on it). A host can now open a source
  into a document with no direct `pdf_document` dependency.

## Gotchas

- Exporting `PdfDocument` from the barrel turned ~55 `import
  'package:pdf_document/...'` lines across the package/app tests + examples into
  `unnecessary_import` infos (CI runs `dart analyze --fatal-infos`). Removed each
  flagged line - safe because the barrel re-exports the same symbols. One was an
  `src/render_worker.dart` import surfaced by the same barrel change.
- The widget's "fall back to a plain full read" branch (`preview == null`) is
  defensive: `PdfDocument.openSource` already falls back to a full sequential
  download *internally* for an unknown-length / non-ranged source and still
  returns a renderable doc, so first paint fires there too. `preview` is only
  null when `openSource` throws outright.
- Source-mode widgets never build their `_shell`; `initState`/`didUpdateWidget`/
  `dispose` early-return in source mode and the inner byte-mode widget the
  builder mounts owns the shell. A widget instance is one mode for its lifetime.

Not in scope (per the issue): host-specific sources (`dart:io` file source,
Firebase Storage source) stay in the host; the app's multi-tab
`DocumentTab.preview` orchestration is untouched. Bare `PdfViewer` (which takes
a `PdfDocument`, not bytes, and has no shell/worker lifecycle) is left as-is - a
host wraps it with `PdfProgressiveSourceBuilder` + `PdfDocument.open` directly.

Test: `test/progressive_source_test.dart` covers `readSourceFully` (known/
unknown length, cancellation), source → first-paint (ordering proves it beats
the full-read completion) → full-read swap, the loader gate, dispose
cancellation, the sequential fallback, and `PdfEditorView.source`.
