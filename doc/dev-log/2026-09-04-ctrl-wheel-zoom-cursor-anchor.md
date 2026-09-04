# Ctrl/Cmd+wheel zoom lands off the cursor

Reported as "ctrl zoom does not accurately zoom on the cursor position,
it's not aligned". Reproduced in `pdf_viewer.dart` `_zoomTo` - the shared
focal-point path behind wheel zoom, touch pinch, trackpad pinch and
`PdfViewerController.setZoom`.

## Why it drifts

The viewer splits zoom at the fit-width seam: at or below it the pages
**lay out** smaller (and re-centre on the cross axis), above it they ride
the InteractiveViewer transform. A notch that crosses the seam therefore
moves the content under the pointer twice - once by the relayout, once by
the transform - and `_zoomTo` only ever accounted for the second.

Three concrete bugs fell out of that:

- **The layout relayout was applied to a stale focal point.** Crossing up
  through the seam calls `_setLayoutZoom(1, ...)` and *then* built the
  transform around the same list-space focal point, which by then pointed
  at different content. On the cross axis the pages had re-centred under
  the pointer, so the anchor was off by the whole re-centring.
- **Crossing down through the seam pinned the wrong thing.**
  `_setLayoutZoom(focalMain:)` anchors in list space, and the caller passed
  the gesture's list-space position - but the transform is dropped to
  identity in the same breath, so the point had to be pinned where the
  pointer is *in the viewport*, not where it maps to while still zoomed.
  Off by the whole zoom-window translation (94 px in the regression test).
- **`pageSpacing` does not scale with the layout zoom**, but the scroll
  compensation was a flat `(pixels + anchor) * ratio`, so it drifted by one
  gap per page ahead of the pointer - 37 px by page 4 of the test document,
  and a whole page deep into a real one.

`PdfViewerController.setZoom` had the same class of bug: it passed the raw
viewport centre as a list-space focal point, so a zoomed, panned viewer
zoomed around whatever happened to sit at the untransformed centre.

## The shape of the fix

`_zoomTo` now resolves the focal point into three values before touching
anything: where the pointer is in the **viewport** (`viewFocal`), which
**content** sits under it (`contentMain`, a list coordinate at the current
layout zoom), and - after any relayout - where that content **ended up**
(`scene`, via the new `_remapMain`/`_remapCross`). The transform is then
built from scratch to put `scene` back under `viewFocal`:
`T(viewFocal) · S(zoom) · T(-scene)`. With no layout change that is
algebraically identical to the old post-multiply, so the pure-transform
path is unchanged.

`_remapMain` walks the pages so the constant `pageSpacing` gaps are carried
across a layout-zoom change instead of being scaled with them;
`_remapCross` is the closed form of the centring (every page is centred on
the cross axis, so the whole axis scales about the viewport centre).
`_setLayoutZoom` takes the content coordinate to pin as well as the
viewport anchor to pin it at.

## Deliberately still not anchored

The cross axis at the seam. Zooming in one notch from `PdfViewerFit.page`
wants to hold a point that would need the page pushed off its own left
edge, and `_clampedTransform` refuses to show canvas beside the page once
zoom lives in the transform (below the seam it is the layout that centres
the page, with no offset to give). So that first notch grows the page about
the viewport's cross centre - which is what Chrome's viewer does too - and
every notch after it anchors exactly. The scroll axis anchors in all cases.

`test/ctrl_wheel_zoom_focus_test.dart` covers both regimes and both seam
crossings; two of its six cases fail on the old code.

## Test gotcha (not a product bug)

`await controller.jumpToPage(3)` deadlocks a widget test: the jump is close
enough to animate, and nothing pumps frames while the test awaits it. Use
`unawaited(...)` and `pumpAndSettle()`. `jumpToPage(4)` in the same fixture
snaps instead (past the `max(_mainView * 2, 2400)` distance) and so looks
fine - which is what makes it confusing.
