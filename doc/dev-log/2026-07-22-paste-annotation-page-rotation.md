# Paste annotation onto a rotated page — counter-rotate the appearance

## Symptom

Copy the FreeText box from page 17 of a real-world sample and paste it onto
page 19: the pasted box renders rotated 90°. Page 17 is `/Rotate 0`; page 19
is `/Rotate 90`. It reproduces for *any* annotation copied between two pages
whose `/Rotate` differs — nothing specific to that file.

## Cause

The renderer maps an annotation's appearance stream through the page's display
rotation along with the rest of the page (this is why `addFreeText` &co. bake a
counter-rotation via `_orientedCounterRotation` when authoring oriented artwork
on a rotated page). An appearance authored on an unrotated page carries no such
counter-rotation, so when it lands on a `/Rotate 90` page the renderer spins it
90°.

`PdfEditor.pasteAnnotation` (`annotation_clipboard.dart`) copied the appearance
verbatim and only translated `/Rect` by the paste offset — it never looked at
the destination page's rotation, nor recorded the source page's. So the
source→destination rotation delta was silently dropped.

## Fix

Record the source rotation on the snapshot and fold the delta into the pasted
appearance:

- `PdfAnnotationSnapshot` gains `sourceRotation` (the captured page's
  `/Rotate`, normalized to 0/90/180/270). `capture(..., sourcePageRotation:)`
  sets it; `toJson` emits `'rot'` only when non-zero (payloads from unrotated
  pages — the common case — stay byte-identical to pre-field ones, and the
  schema version stays `v: 1`); `fromJson` defaults it to 0 for old payloads.
- `pasteAnnotation` computes `delta = dstPageRotation − snapshot.sourceRotation`
  and, when non-zero, counter-rotates the (still-inline) `/N` appearance by
  `delta` degrees about the `/Rect` centre before hoisting streams.
- The centre-preserving rotate/rect/point-array math is now shared:
  `rotateAnnotation`'s body is extracted to `_foldRotationInto(dict, form,
  rect, degrees)`, which both `rotateAnnotation` and the paste path call. A
  quarter turn flips the `/Rect` aspect (wide ↔ tall) about the same centre, so
  the box occupies the region that, once the page's display rotation is
  applied, reads upright.

Only single-stream `/N` appearances re-orient (widgets/multi-state `/N` never
paste — `capture` refuses them). Degenerate/missing BBox or Rect ⇒ no-op,
falling back to the old verbatim behaviour.

### Why source rotation, not just destination

Sync (`pdfDiffAnnotations` / `annotationBaseline` / `upsertAnnotation`) replays
snapshots onto same-structured pages: recording the true source rotation keeps
the delta 0 there, so replay stays a verbatim no-op even for annotations that
live on rotated pages — no double-rotation. `moveSelectedToPage` and
`applySelectedAnnotationsToPages` (both capture→paste) get the correct
re-orientation for free.

## Call sites threading `sourcePageRotation`

All read `PdfPage.rotation` (which already resolves inheritance + normalizes):
`copySelectedAnnotations`, `applySelectedAnnotationsToPages`,
`moveSelectedToPage`, both `annotationBaseline`s, and `_collectAnnotations`
(the sync diff).

## Tests

`annotation_clipboard_test.dart` → group *pasting across a page-rotation
difference*: the upright-on-90°-page case (aspect flip + centre held +
quarter-turn `/Matrix`), the same-rotation no-op (appearance byte-identical),
the JSON round-trip of `sourceRotation`, and the compact-payload check
(unrotated capture omits `rot`). Existing `rotateAnnotation` tests cover the
extracted `_foldRotationInto`.
