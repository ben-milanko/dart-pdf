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
- The zoom sits in one of two tiers and **both** are compensated so the hold
  works wherever the user is:
  - at/below fit-width the pages lay out at `_layoutZoom` (transform ≈
    identity) — counter-scaled during build (same frame, no flicker).
  - **zoomed in past fit-width** the `_transform` scale carries the zoom
    (`_layoutZoom == 1`) — counter-scaled in the post-frame callback by
    rescaling the transform `oldCross / newCross` about the viewport centre.
    This is the common editing case, and the one that shipped broken first:
    reading at e.g. 286% and closing a panel widened the viewport, grew the fit
    scale, and — with the transform untouched — zoomed the page in to 400%+.
    (The transform is set post-frame, not during build, to avoid mutating its
    `ValueNotifier` mid-build; a discrete panel toggle self-corrects in one
    frame.)

The scale is held for **any** cross-axis change, whatever moves it (a resize
grip, a panel opening/closing, or a window resize).

> **Follow-up correction.** A first pass tried to scope the hold to a "pure
> cross-axis" resize by passing `holdScale: newMain == oldMain`, the idea being
> that a side panel leaves the main (scroll) axis untouched while a window
> resize moves both. In the real app that backfired: opening or closing a panel
> also nudges the viewer's main axis a hair (the surrounding toolbar/header
> chrome reflows), so `newMain == oldMain` was false and the zoom jumped on
> exactly the case the feature protects. The byte-exact gate was removed — the
> hold now fires on any cross-axis change. The only cost is that a window resize
> also holds the on-screen scale instead of re-fitting to width, which is
> consistent with "don't shift the view" anyway.

The call is also skipped while a `_pendingViewport` restore is in flight —
that explicit restore sets its own layout zoom and scroll and should win.

## Tests

`pdf_viewer_test.dart`: the existing "resizing a side panel preserves the
reading position" test uses `PdfViewerFit.width` (where `_layoutZoom` is pinned
at 1), so it exercises the unchanged path. "resizing a side panel below
fit-width holds the zoom" rests the viewer at fit-page (`_layoutZoom < 1`),
widens the panel, and asserts `controller.zoom` is unchanged (scale held) and
the reading anchor still holds. "closing a panel holds the zoom even when the
main axis also nudges" is the regression test for the byte-exact-gate
follow-up: it closes a panel (viewer widens) while a stand-in bottom chrome
also shifts the height, and asserts the zoom still holds. "closing a panel
holds the zoom while zoomed in past fit-width" is the regression test for the
transform tier: it zooms to 2.5 px/pt (well past fit-width, so the transform is
active), closes the panel, and asserts the zoom holds — this fails without the
transform counter-scale and passes now.
