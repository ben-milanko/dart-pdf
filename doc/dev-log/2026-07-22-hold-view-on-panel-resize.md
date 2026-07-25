# Make the viewer invariant to the panels (panels overlay, don't squeeze)

The editor's side panels (Pages, Search, Bookmarks, Annotations, Properties,
Dev tools) were **push** panels: laid out beside the viewer as siblings in a
`Row`/`Column` (`PdfShellPanelLayout`, `shell_chrome.dart`), with the viewer in
the flex `Expanded` slot. So opening, closing, or resizing a panel resized the
viewer. And the viewer's render scale (`_fitScale = viewerWidth / pageWidth`)
and its page centering are both tied to that width, so any width change
rescaled *and* re-centered the page — the document visibly jumped/zoomed as
panels toggled (most obvious while zoomed in: closing a panel widened the
viewport, grew the fit scale, and zoomed the page from ~286% to ~690%).

## What didn't work: compensating in the viewer

The first attempts tried to *cancel* the width change inside `PdfViewer` —
counter-scaling `_layoutZoom` (at/below fit-width) and the `InteractiveViewer`
transform (zoomed in past fit-width), plus pinning the reading anchor. These
held the zoom in unit tests but not reliably in the app, and couldn't address
the horizontal re-centering. The core problem is architectural: with push
panels the viewport genuinely changes size, and both scale and centering are
functions of that size, so after-the-fact compensation is a losing game (the
transform tier also can't be corrected during build without a mid-build
notifier mutation, leaving a one-frame lag).

## The fix: overlay the panels

`PdfShellPanelLayout` now lays the **viewer full-size** (`Positioned.fill`) and
floats the docked panels *over* it at the edges, instead of squeezing it:

```dart
final panelsOverlay = Column([
  ...topPanels,
  Expanded(child: Row([
    ...leadingPanels,
    const Expanded(child: SizedBox.expand()),  // transparent gap: viewer shows through
    ...trailingPanels,
  ])),
  ...bottomPanels,
]);
Stack([
  Positioned.fill(child: viewer),        // always the whole content area
  Positioned.fill(child: panelsOverlay), // panels at the edges, middle transparent
  ...overlays, floatingToolbar, bottomSheets, dropZones,
]);
```

The panels keep their **exact original nesting** (top/bottom columns spanning
the width, a middle band of leading · gap · trailing), so their arrangement,
resize grips, drop zones, and tab groups are unchanged — only the viewer's old
flex slot becomes a transparent `Expanded(SizedBox.expand())` gap. An empty box
takes no pointer input, so taps in the gap fall through the `Stack` to the
viewer beneath; taps on a panel hit the panel. Result: the viewer always
receives the full content-area constraints, so a panel opening/closing/resizing
**never changes the viewer's size** — the document view is invariant to the
panels by construction (no zoom or position jump); the panel simply reveals or
covers a strip of the page beside it.

## Viewer revert

The viewer's `_preserveViewOnResize` experiments were reverted to the original
`_preserveReadingAnchor` — it now only pins the scroll reading position across a
*genuine* viewport resize (a window/pane resize), which no longer includes panel
toggles.

## Tests

- `panel_dock_test.dart` → group "viewer is invariant to the panels": asserts
  the viewer fills the whole area, and that opening a panel and resizing a panel
  both leave the viewer's measured size unchanged.
- `pdf_viewer_test.dart` keeps "resizing a side panel preserves the reading
  position" for the genuine-resize path; the three zoom-hold tests from the
  compensation attempts were removed with that code.
