# 2026-07-22 — explicit revision token, replacing document-identity checks (#414)

~20 sites across `dart_pdf_editor` used `PdfDocument` object identity as the
"a new revision landed" signal:

```dart
final before = _controller.document;
commit();
if (identical(before, _controller.document)) return; // "nothing committed"
```

This worked only by an undocumented invariant: every commit replaced `_document`
with a fresh wrapper. Nothing stated it, and it fails silently and plausibly -
an afterimage that stops painting, a preview that clears a frame early. It also
baked in a constraint: #395 had to keep allocating `withIncrementalUpdate` purely
to preserve the identity signal, blocking any future in-place revision apply.

## Change

`PdfEditingController` gained `int get revisionId` - a plain monotonic counter
bumped wherever `_document` moves to a new revision (`_reloadDocument`, the
incremental `withIncrementalUpdate` path, and the redaction-burn reopen). Plain,
not derived from `_cursor`, because undo-then-redo returns to the same cursor
while the document genuinely changed.

Every "did a revision land / is my snapshot stale" check switched from
`identical(document, ...)` to a `revisionId` comparison:

- Local `before = document; if identical(...)` sites (editing_overlay,
  editing_form_layer) → `before = revisionId; if before == revisionId`.
- Captured-snapshot fields whose whole job was staleness: `_afterDocument`,
  `_samplerDocument`, `_syncedDocument`, `_builtFor`, and the `_committedInk` /
  `_flash` record `document` members → `int?` revision ids.
- Async-capture-before-await staleness (`_ensureSampler`, resize-clean render,
  the content-image render) → capture `revisionId` before the await, compare
  after.
- `_finishInteraction` and `_captureLastStampAfterimage` took a `PdfDocument`
  only to run the staleness check → now take an `int` revision id.

**Left as genuine object identity (NOT converted):**

- `identical(widget.page.document, editing.document)` (does this page belong to
  the editing document), `pdf_reflow_view` / `shell_session` widget/worker
  identity.
- The viewer's own `identical(_loadedDocument, _document)` new-document-vs-
  incremental-revision detection - object identity there is correct, and under a
  future in-place apply it would simply `setState` instead of swapping (the
  optimisation this ticket unblocks).
- Genuine document *uses* kept their `document` local where the object is
  actually needed (rendering a pre-commit clean source, `document.pageCount`) -
  only the identity *check* moved to `revisionId`.

Relaxed `PdfDocument.withIncrementalUpdate`'s doc: the fresh wrapper is now a
convenience (skips the re-parse), not a contract; applying in place is a valid
drop-in once no caller depends on identity.

## Testing

- `revision_id_test.dart` pins the contract: `revisionId` bumps on commit, undo,
  and redo (including undo→redo back to the same cursor), and does NOT bump on a
  guarded no-op.
- The full `dart_pdf_editor` widget suite is the real gate - the afterimage,
  drag-preview, eraser-slice, and form-layer tests (the 17 that #395 broke) cover
  every converted site. `dart analyze` clean across the package.
