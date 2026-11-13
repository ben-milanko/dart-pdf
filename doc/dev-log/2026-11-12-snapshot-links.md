# 2026-11-12 - Snapshots preserve links

A vector snapshot used to carry only drawing: the page content plus the
appearances of live annotations. A /Link has no drawing of its own (or only
a border), so a snapped region of a document full of web links pasted as a
dead picture of them.

- **Capture** (`captureVectorSnapshot` -> `_snapshotLinks`): every visible
  /Link with a *portable* action over the region becomes a
  `PdfSnapshotLink` (`PdfVectorSnapshot.links`) - its area mapped through
  the same page -> display-box matrix the content uses (so /Rotate is baked
  in), clipped to the box. One entry per /QuadPoints quad, so a link that
  wraps lines does not turn into one big box over unrelated text. A traced
  (polygon) capture keeps a link only if it reaches into the polygon.
  Captured regardless of `annotations:` - a link is behaviour, not drawing.
- **Portable = /URI only** (`_portableLinkActions`). /GoTo, bare /Dest and
  named destinations point at the *source* document's pages, which a
  detached snapshot does not have; pasting one into another file would jump
  somewhere arbitrary, so they are dropped. /Next chains are stripped.
  Widening this set (e.g. internal jumps when pasting back into the same
  document) needs a source-document identity the snapshot deliberately
  doesn't hold.
- **Paste** (`pasteVectorSnapshot`): links become real /Link annotations
  inserted *before* the stamp in /Annots (the controller selects the last
  annotation after a paste). Each carries `/DartPdfSnapshotLinkOf` (the
  stamp ref) and `/DartPdfSnapshotLinkBox` (its area in the captured box);
  the stamp carries `/DartPdfSnapshotCapMatrix`, the captured-box ->
  appearance-form-space mapping the appearance draws under (scale + the
  destination page's counter-rotation). Only written when there are links.
- **Following the stamp**: `_markAnnotationChanged` calls
  `_layoutSnapshotLinks` for any dict with the cap-matrix key, so every
  geometry edit (move, resize, flip, rotate, group transforms, crop) re-lays
  the links: box -> cap matrix -> clip to the appearance BBox -> the form's
  /Matrix + BBox->Rect fit (`_bakedFormMatrix`) -> /Rect + /QuadPoints.
  `cropVectorSnapshot` rewrites the cap matrix for its new appearance; a link
  cropped away entirely gets /F Hidden (not removed) so un-cropping restores
  it. `_removeAnnotations` removes a stamp's owned links with it.
- **PDF clipboard**: `toPdfBytes` writes the links as /Annots on its page,
  and `fromPdfBytes` captures them back, so the system-clipboard round trip
  keeps them too.

Gotcha for tests: `PdfAnnotation` parses /Rect and /F once and
`page.annotations` is cached by /Annots identity + length, so a link
re-laid in place reads stale within the same editor session - save and
reopen before asserting (as the editor does with every revision).

Not done: a stamp copied through the *annotation* clipboard (copy/paste of
the placed stamp) does not bring its links - the annotation clipboard skips
/Link by design.

Tests: `pdf_document/test/vector_snapshot_test.dart` (group
"PdfVectorSnapshot links"), `dart_pdf_editor/test/editing_snapshot_test.dart`.
