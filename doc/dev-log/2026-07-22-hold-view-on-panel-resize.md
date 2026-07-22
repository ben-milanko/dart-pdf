# Hold the view put when a side panel is resized

Resizing a docked side panel changes the viewer's `Expanded` width, which is a
vertical layout's **cross axis**. On-screen scale is `_fitScale × _layoutZoom`
and `_fitScale = _crossView / _maxCrossPoint`, so a width change rescales every
page. The existing `_preserveReadingAnchor` pinned the scroll-axis reading
position but let the pages keep rescaling, so while the resize grip was dragged
the document still visibly **zoomed** under the reader.

## Change

`_preserveReadingAnchor` → `_preserveViewOnResize(oldCross, newCross)`
(`pdf_viewer.dart`). In addition to pinning the reading anchor (page + fraction
at the viewport top), it now **counter-scales `_layoutZoom`** so the on-screen
scale stays constant across the width change:

```dart
_layoutZoom = (_layoutZoom * oldCross / newCross).clamp(widget.minZoom, 1.0);
```

- `_layoutZoom` is assigned **directly during build** (a plain field write, no
  `setState`), so the same build lays the pages out at the held scale — no
  one-frame flicker while the grip is dragged. This mirrors the initial-fit
  branch a few lines below, which also writes `_layoutZoom` during build.
- Capped at fit-width (1.0): past that the page already fills the viewport and
  growing further would overflow the now-narrower width, so filling the width
  is the natural stopping point for a resize.
- Only the at-/below-fit tier is touched (`_transform` ~ identity). When zoomed
  in past fit-width the transform carries the zoom, so `_layoutZoom` is left at
  1 and only the reading anchor is preserved (unchanged from before — no
  regression, holding scale there would need to rescale the transform during
  build, which risks a mid-build notifier mutation).

The call is also now skipped while a `_pendingViewport` restore is in flight —
that explicit restore sets its own layout zoom and scroll and should win.

## Tests

`pdf_viewer_test.dart`: the existing "resizing a side panel preserves the
reading position" test uses `PdfViewerFit.width` (where `_layoutZoom` is pinned
at 1), so it exercises the unchanged path. A new test, "resizing a side panel
below fit-width holds the zoom", rests the viewer at fit-page (`_layoutZoom <
1`), widens the panel, and asserts `controller.zoom` is unchanged (scale held)
and the reading anchor still holds.
