# 2026-07-25 — pointer-event costs: the overlay cursor repaint layer (#403 part 1)

#403's headline, and the last of its three parts. Part 2 (one `_pagePointAt`
per pointer event instead of four, plus the heavy-page hover-extraction gate)
landed in **#442**; part 3 (per-build search/selection rescans) in **#479**,
whose note left this one as a scoped follow-up. See
[2026-07-22-pointer-event-costs-403.md](2026-07-22-pointer-event-costs-403.md).

## The problem

With ink, the eraser, count, stamp or the signature tool armed - or the
eyedropper picking - the editing overlay paints its own cursor, and the
cursor's position was a *snapshot argument* of `_EditingPreviewPainter`. Moving
it therefore meant `setState`: every `PointerHoverEvent` rebuilt
`_EditingPageOverlayState`'s whole subtree (annotation widgets, selection
chrome, the ~7000-line overlay's build method, and a fresh
`_EditingPreviewPainter` with ~50 recomputed arguments) to move a dot a few
pixels. Continuous build-phase cost through exactly the moment the user is
about to draw.

## The fix (editing_overlay.dart)

A sibling of the pattern the file already had for the in-progress stroke
(`_ActiveStrokePainter` + `_activeStrokeRepaint`):

- **`_cursorRepaint`** — a `ValueNotifier<int>`, bumped by `_bumpCursor()`.
- **`_HoverCursorPainter`** — a new `CustomPainter` on its own
  `RepaintBoundary`, `super(repaint: _state._cursorRepaint)`, reading the live
  `_penCursor` / `_eraserCursor` / `_countCursor` / `_stampPreview` /
  `_rotateCursor` / `_signaturePreview` fields straight off the state. It sits
  above the active-stroke layer, so the cursors are topmost among the painted
  layers (they used to be the tail of the preview painter, below the stroke).
- `_onHover` (and the signature drag, and `_extendActiveStroke`) now assign the
  field and `_bumpCursor()` instead of `setState`. The one hover outcome that
  still rebuilds is a *change of system cursor kind*, which lives on the
  `MouseRegion` and only changes at tool/zone boundaries, not per event.
- The eyedropper's swatch is a widget, so it can't join the painter: it
  subscribes to the same notifier through a `ValueListenableBuilder`, rebuilding
  the chip alone.
- `_EditingPreviewPainter` lost `eraserCursor`/`eraserRadius`/`penCursor`/
  `penOpacity`/`countPreview`/`stampPreview`/`rotateCursor` (fields, paint code
  and `shouldRepaint` terms), and the signature preview left its `extraInk`.
  `_paintStampAfterimage` and the three stamp-template helpers became top-level
  functions taking the view `scale`, so both painters draw the identical mark.

### Two details worth keeping in mind

- **`shouldRepaint` is `true` here**, unlike `_ActiveStrokePainter`'s `false`.
  The stroke layer's notifier ticks on every mutation of its buffers, so it can
  own its repainting outright. The cursor layer also depends on inputs it does
  *not* observe - the armed tool, pen colour/width, zoom (`_geometry`),
  `_chromeScale` - and those change through ordinary rebuilds. A fresh painter
  instance means the overlay rebuilt for one of them; repainting a few circles
  and an arc then is cheaper than tracking which input moved.
- **The paint gates are the debug getters.** `_state._eraserCursor` outlives
  the eraser (nothing clears it when the tool is put away); `eraserCursor` -
  the getter `paint()` reads - is what is actually drawn. Tests assert on the
  getters for that reason.

## Measuring it

Two independent checks, because they answer different questions.

**Structural, in widget tests.** `_EditingPreviewPainter`'s *identity* is the
tell: a rebuild constructs a fresh one from new arguments, so the same instance
still being mounted after a pointer move means no rebuild ran.
`editing_cursor_test.dart` asserts exactly that for ink / eraser / count /
stamp / signature, and - so the assertion can't quietly become vacuous - that a
change the overlay really does rebuild for (setting the controller colour) does
swap the painter out.

**Wall-clock, in real Chrome.** The web harness gained a **`hover` kind**
(`app/tool/perf/perf_harness.dart` + `hover-ink` / `hover-eraser` in
`scenarios.json`): it arms a tool and dispatches N synthetic
`PointerHoverEvent`s at frame cadence over a dense vector sheet, reporting
`hoverBuildMs*` from the `FrameTiming`s captured across the sweep. Build-phase
ms *is* the rebuild cost, so the metric names the thing the fix removes.

`tool/perf.sh webdiff HEAD hover-ink`, 3 iterations per side (240 events over
`plan-set-16p.pdf`), medians:

| metric | baseline | this branch | Δ |
|---|---|---|---|
| `hoverBuildMsP50` | 1.46 | 1.10 | **−24.6%** |
| `hoverBuildMsTotal` | 527 | 493 | −6.5% |
| `hoverBuildMsPerEvent` | 2.20 | 2.05 | −6.5% |
| `hoverBuildMsP95` | 4.96 | 5.08 | +2.5% |

**Read these carefully.**

- `hoverBuildMsP50` is the one clean result: every working-tree run measured
  1.1 ms and every baseline run 1.4–1.7 ms, so the ranges don't overlap. A
  quarter off the *typical* build frame during an armed hover.
- The totals overlap between runs (WT 468/493/524 vs baseline 525/527/620);
  −6.5% is the right sign but n=3 can't tighten it. It is diluted by design:
  240 frames over a 16-page plan set contain plenty of build work the overlay
  has nothing to do with (page views, prerender, scroll), and the harness can't
  attribute build time per widget. The widget tests are what prove the overlay's
  own share went to zero.
- **`hoverBuildMsMax` (33.35 → 7.67, "−77%") is not a result.** Both sides threw
  a ~40 ms outlier in one of three runs (WT 7.7/7.6/40.9, baseline 33.4/40.8/7.4);
  the medians only separate because the outliers landed differently. Don't quote
  it without more iterations.
- The reported `buildMax` "regression" (71.3 → 78.5) is the *whole-run* max, and
  the run has only ~8 frames outside the hover window - it is a cold-open first-
  paint frame, which this change cannot touch. The in-window max is
  `hoverBuildMsMax` above.

## Not done here

- The async/off-thread hover text extraction (part 2's remaining half) is still
  gated behind #396. Nothing here touches `pdf_viewer.dart`.
- `_polyHover` (the polygon/cloud rubber band) deliberately stays on `setState`:
  it feeds `dragPath` on the preview painter, i.e. it changes what the *page*
  preview draws, not just a cursor. Same for the erase-drag preview, whose
  sliced/faded stroke sets the preview painter owns.
