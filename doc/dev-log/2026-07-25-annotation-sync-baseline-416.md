# Annotation sync diffs a cached baseline, not a re-opened document (#416)

## Problem

With an annotation-sync listener attached, every commit paid a **second full
`PdfDocument.open`**. `_emitAnnotationChanges` reconstructed the pre-edit state
by re-parsing the byte prefix `[0, beforeLength)`:

```dart
final before = PdfDocument.open(Uint8List.sublistView(_bytes, 0, beforeLength), ...);
final changes = pdfDiffAnnotations(before, _document, pages: annotationPages);
```

The re-open was there for a real reason (documented in the old comment): the
editor mutates the in-memory COS of the document it ran on, so the live pre-edit
`PdfDocument` object is already contaminated with the edit. Re-parsing a clean
byte range was the easy way to get an uncontaminated "before". After #415 this
got *more* necessary — `withIncrementalUpdate` shares the underlying
`CosDocument`, so the previous wrapper isn't an independent snapshot either.

But the re-open walks the whole `/Prev` chain per revision, so a live sync
session degraded O(N²) over the session — the very thing #415 fixed for the
*primary* open, still paid on this second one.

## Fix

Keep a cached **baseline** of the document's annotation states and diff against
it instead of re-opening. The baseline sidesteps the contamination problem by
being captured from the *clean* document rather than reconstructed after the
mutation:

- `pdf_document` gains a small state-snapshot API on top of the existing diff:
  `PdfAnnotationStates` (opaque, identity-keyed, proportional to annotation
  count), `pdfCollectAnnotationStates(doc, {pages})`, and
  `pdfDiffAnnotationStates(before, after)`. `pdfDiffAnnotations` is now a thin
  wrapper (`collect` + `collect` + `diffStates`), so its API and tests are
  unchanged.
- The controller seeds `_annotationBaseline` from the clean current document
  the instant a listener attaches (the broadcast feed's `onListen`), and clears
  it on `onCancel`. Nothing is captured while nobody listens — same gate as
  before.
- Each `_emitAnnotationChanges` recollects only the touched pages
  (`impact.annotationPages`; null for structural edits), diffs them against the
  baseline restricted to those pages, then advances the baseline by replacing
  those pages' entries. This reproduces the old page-limited diff exactly, minus
  the open.

The `beforeLength` argument is gone — nothing reconstructs from bytes anymore.

### Remote applies

`applyRemoteChange` still advances the baseline (so the remote edit isn't
re-announced as a local change on the next commit) but emits nothing — the same
echo-free contract as before. Previously the re-open naturally included the
remote revision's bytes; now the baseline advance does the same job. Covered by
`editing_sync_test.dart`'s "never echoes" and "two devices converge" cases.

## Result

Micro-benchmark (200 commits, 30-revision-deep session, 8 annotations, listener
attached):

| | µs/commit |
|---|---|
| main (per-commit re-open) | ~739 |
| this change (cached baseline) | ~405 |

~45% per commit, and the gap widens with session length because the re-open's
`/Prev` walk was O(N²) while the baseline stays flat. No change with sync off
(single-user editing never touched the re-open path).

## Files

- `packages/pdf_document/lib/src/annotation_sync.dart` — `PdfAnnotationStates` +
  `pdfCollectAnnotationStates` / `pdfDiffAnnotationStates`; `pdfDiffAnnotations`
  reduced to a wrapper.
- `packages/dart_pdf_editor/lib/src/editing/editing_controller.dart` — baseline
  field, feed `onListen`/`onCancel` seeding, rewritten `_emitAnnotationChanges`.
- `packages/dart_pdf_editor/test/editing_sync_test.dart` — added the
  mid-session-attach multi-annotation guard.
