# content-delete region slicing: snap to the glyph the box covers

Historical implementation notes. The current implementation and validation
are described in [the September refresh](2026-09-06-content-delete.md).

PR #112 (`codex/add-content-delete-tool-like-bluebeam-1l9dr0`) adds the
Bluebeam-style content-erase tool: drag a rectangle and
`PdfEditor.deleteElementsInRect` (`content_editor.dart`) removes the
bounded page-content elements under it, slicing text runs to character
boundaries so a partial hit leaves the rest of the run in place (a
compensating TJ gap holds the following glyphs at their original x).

## Bug

`_textSlice` mapped the drag box onto the run's glyphs and erased every
glyph that *overlapped* the box at all:

```dart
if (next > eraseUnits0 && cursor < eraseUnits1) { ... }
```

Because the run's per-glyph advances are measured with the same
`measureHelvetica` used to lay out `eraseUnits0/1`, a box drawn flush to
a glyph edge lands its boundary exactly on the neighbouring glyph's
`cursor`/`next`, and floating-point ties make `<`/`>` true. So a box
covering `"first "` erased `"first l"` (left `"ine"`), and a box covering
`"ne"` erased `"ine"` (left `"first l"`) — one glyph too many at every box
edge. That's what "not slicing content correctly at the drag box" was.

## Fix

Erase a glyph when its **centre** falls inside the box, not when it
merely overlaps an edge:

```dart
final center = (cursor + next) / 2;
if (center > eraseUnits0 && center < eraseUnits1) { ... }
```

Centres are strictly monotonic, so the erased indices stay contiguous
(the `first`/`last` capture still holds), the kept/removed split lands
where the box actually crosses each glyph, and a box flush to an edge no
longer ties on a neighbour. This matches the intuitive "slice where I
dragged" and is the standard rounding rule for hit-slicing.

## Notes / not touched

- Bounds for simple fonts are themselves Helvetica-approximated in
  `content_elements.dart`, so the slice is only as accurate as those
  bounds — internally consistent for the base-14 metric fonts, still
  approximate for embedded fonts whose real advances differ. Out of
  scope here.
- Type0/composite runs still drop whole (byte length != char length
  guard in `deleteElementsInRect`).
- `eraseElementsInRect` (the clip-outside-the-box variant) remains in
  the file with its own tests but is not wired to any tool; the overlay
  uses `deleteElementsInRect`.

Regression test: `content_edit_test.dart` → "a region flush to a glyph
edge does not swallow the neighbour".
