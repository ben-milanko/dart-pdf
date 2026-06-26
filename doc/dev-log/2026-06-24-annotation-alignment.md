# Annotation alignment & distribution

Added an alignment system for multi-selected annotations: line edges or
centres up, and distribute spacing evenly. It rides entirely on the
existing multi-select model and `moveAnnotation` — no new geometry in the
PDF write path.

## Pieces

- **`pdf_document/src/annotation_align.dart`** (pure, VM-testable): the
  `PdfAlignment` enum (left / horizontalCenter / right / top /
  verticalCenter / bottom / distributeHorizontal / distributeVertical) and
  `alignmentOffsets(List<PdfRect>, PdfAlignment)`, which returns a per-rect
  `(dx, dy)` parallel to the input. All maths is in PDF user space (y up),
  so `top` is the visually-highest edge. Exported from `pdf_document.dart`.
  - Edge/centre alignment references the group's overall bounding box.
  - Distribution holds the two extreme edges and equalises the *gaps*
    between consecutive rects (gap-based, not centre-based — predictable
    with differently-sized boxes). Free space = span − Σ widths, split
    across `n-1` gaps; rects placed left-to-right (or bottom-to-top).
  - Returns all-zero offsets below `alignment.minimumCount` (2 to align,
    3 to distribute — the extremes anchor, so distribution only moves what
    sits between them).

- **`PdfEditingController.alignSelected(PdfAlignment)`** plus
  `canAlignSelected` / `canDistributeSelected` getters
  (`editing_controller.dart`, next to `moveSelected`). `_alignmentTargets()`
  takes the selected annotations that share `selectedPage` — cross-page
  alignment is meaningless, so the primary page wins and other pages'
  selections are left alone. It computes offsets, drops the zero ones, and
  applies the rest in **one** `apply(...)` revision via `moveAnnotation`
  (so coordinate arrays — QuadPoints/L/Vertices/InkList — shift with the
  /Rect, and one undo restores everything). Already-aligned selections move
  nothing, so they add no revision.

- **Toolbar** (`editing_toolbar.dart`): `_selectionStrip` grows an
  `_alignmentCluster` when `canAlignSelected` — three edge buttons, a
  divider, three more, a divider, two distribute buttons (disabled, but
  still rendered for stable layout, until three are selected). Buttons key
  off `pdf-align-<enum name>`. The strip card already scrolls horizontally,
  so the extra width is free. `PdfAlignment` added to the toolbar's `show`
  import.

## Tests

- `pdf_document/test/annotation_align_test.dart` — pure geometry (edges,
  centres, gap equality, anchors held, too-few no-op, already-aligned →
  zero offsets).
- `dart_pdf_editor/test/editing_align_test.dart` — controller (can-flags,
  single revision + undo, primary-page-only, no-op when aligned) and
  toolbar (buttons appear only on multi-select, tap aligns, distribute
  disables below three).

## Notes / gotchas

- `controller.bytes` is the raw incremental-save **buffer**, not a list of
  revisions — its length grows by the appended revision's size, not by 1.
  Assert `greaterThan`, and use `undo()` to prove single-revision grouping.
- Mobile (`_mobileTrailing`) wasn't given the cluster — eight buttons don't
  fit the dock row. The controller API works regardless; a mobile surface
  (e.g. the tools sheet) can be wired later.
- Distribution is gap-based and single-axis. Centre-based distribution and
  smart drag-snapping guides are natural follow-ups but out of scope here.
