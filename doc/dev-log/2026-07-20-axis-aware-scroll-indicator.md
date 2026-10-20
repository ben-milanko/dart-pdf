# Axis-aware scroll-indicator / page-scrubber API (issue #428)

The public scroll-indicator API (`PdfViewer.scrollIndicatorBuilder`,
`PdfScrollMetrics`, `PdfViewerController.jumpToNormalized`, from #326) was
vertical-only: it hard-wired the vertical scroll axis, so a host that switched
the viewer to `PdfPageLayout.horizontalContinuous` lost its custom bottom
scrubber and fell back to the stock bar. This makes the whole API describe the
viewer's **main layout axis** instead, so the same custom indicator works in
both continuous layouts.

All in `pdf_viewer.dart` (whole file is re-exported).

## What changed

- **`PdfScrollMetrics.scrollAxis`** - a new `Axis` field naming the main axis
  (`Axis.vertical` for vertical continuous, `Axis.horizontal` for horizontal).
  It defaults to `Axis.vertical` in the constructor, so existing const
  construction stays source-compatible. Every other field (`position`,
  `extent`, `pixels`, `maxPixels`, `viewportPixels`) is now documented as
  main-axis rather than vertical; the numbers were already computed off the
  main-axis scroll controller.
- **`_verticalScrollExtents` → `_mainScrollExtents`.** The only genuinely
  axis-bound line was the zoom-window unprojection: it read the transform's
  **Y** translation (`storage[13]`) unconditionally. It now reads
  `storage[_mainTranslate]` (13 for vertical, 12 for horizontal), reusing the
  same main/cross axis plumbing the rest of the geometry/gesture code already
  runs on (`_mainTranslate`, `_mainView`, `_pageMain`, …). Everything else -
  `position.pixels`, `maxScrollExtent`, `viewportDimension` - already tracks
  the scroll axis because the `ListView` scrolls along
  `widget.pageLayout.scrollAxis`.
- **The builder now fires in both layouts.** `build()` previously gated the
  indicator on `pageLayout.scrollAxis == Axis.vertical` and otherwise showed
  the stock main bar. That gate is gone: when `scrollIndicatorBuilder != null`
  it replaces the main bar (right edge vertical, bottom edge horizontal) via
  the same `Positioned.fill(child: _buildScrollIndicator())`. The cross-axis
  (zoom-window) bar is untouched.

## Why it was almost a one-liner

The viewer was already written in main/cross-axis terms (see the block comment
above `_horizontal` in `pdf_viewer.dart`): vertical is the identity case
(main = Y, cross = X), horizontal swaps them. `jumpToNormalized` routes through
`_scrollbarScrollBy`, which already uses `_mainTranslate` for the zoom-window
spillover, so normalized scrolling worked on the horizontal axis the moment
the extents did. The metrics snapshot was the last place still hard-coding Y.

## Host contract

`scrollIndicatorBuilder` fills the viewer (`Positioned.fill`) in either
layout, so the host positions/orients its own widget. It reads
`metrics.scrollAxis` to decide: an `Alignment.centerRight` vertical track vs.
an `Alignment.bottomCenter` horizontal one, and a vertical- vs.
horizontal-drag recognizer. The drag recognizer must match the scroll axis
(and be opaque) to win the gesture arena over the scroll view underneath - a
`PanGestureRecognizer` would fight the scrollable ambiguously, so the demo
uses `onVerticalDrag*`/`onHorizontalDrag*` picked by axis.

## Tests

- `test/scroll_indicator_test.dart` - value equality now covers `scrollAxis`
  (and its vertical default); a new `horizontal layout` group asserts
  `scrollAxis == Axis.horizontal`, main-axis position/extent tracking under a
  horizontal scroll, `jumpToNormalized` along X (top/mid/bottom), and the
  builder replacing the stock bar with horizontal metrics. The existing
  vertical test now also pins `scrollAxis == Axis.vertical`. (Pumping two
  viewers with different layouts in one test leaves the second's metrics null
  for a frame - the axis assertions pump a single viewer each.)
- `example/test/scroll_indicator_demo_test.dart` - a new case flips the demo
  into horizontal via the app-bar toggle, checks the readout reports
  `axis: horizontal`, and drags the now-bottom scrubber to scroll.

## Example app demo

`example/lib/scroll_indicator_demo.dart` gained a layout toggle in the app bar
and an axis-aware `_PageScrubber` that re-orients from `metrics.scrollAxis`
(right-edge track + vertical drag vs. bottom-edge track + horizontal drag),
with the readout showing the live `axis`. It exercises the whole API in both
layouts from one screen.
