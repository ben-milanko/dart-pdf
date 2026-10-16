# Auto-hiding chrome on phones

On a compact layout (`pdfCompactWidthOf`), `PdfEditorView` and `PdfReader`
now get their chrome out of the way the way mobile PDF apps do: the header
(the app's whole app bar, since the app draws it through `headerBuilder`)
and the editor's docked toolbar slide off while the user scrolls on through
the document, and come back on a scroll back or a single tap on the page.
On by default; `PdfEditorFeatures.autoHideChrome` /
`PdfReaderFeatures.autoHideChrome` turn it off. Wide layouts never hide.

## Pieces

- `design/auto_hide_chrome.dart` (widgets-only):
  - `PdfChromeAutoHide` - the shown/hidden state. Fed the viewer's
    `ScrollNotification`s through a `NotificationListener` around the
    viewer slot. Only **user** scrolls count (`UserScrollNotification`
    direction non-idle brackets them), so a jump from the page field,
    a search hit, a bookmark or the thumbnail strip never moves the
    chrome. A run of 24 px (`pdfChromeAutoHideTravel`) in one direction is
    needed, and a direction change resets the count.
  - `pinned` holds the chrome up. The shells set it in their build (no
    notify; the bars read it in the same build): not compact, a panel sheet
    open, the page grid, an armed tool / markup tool, an annotation or
    content-element selection. Pinning also forgets the hidden state, so
    arming a tool brings hidden chrome straight back.
  - `PdfAutoHideBar` - collapses its child with `ClipRect` + `Align
    (heightFactor)` toward its edge. It **collapses rather than floats**, so
    the viewer grows into the freed space and nothing is ever under the bar
    (the viewer re-reads only `_viewHeight` on a resize - no refit, no
    relayout of pages). A top bar keeps `MediaQuery.paddingOf(context).top`
    as it goes so the page doesn't run under the status bar. The tree shape
    is constant at every animation value - a wrapper that came and went
    would remount the header and drop the search field's text/focus. Focus
    inside the bar (search, page-number typing) also pins it.
- **Select is reading, not a tool.** The app and the example open the
  editor with `PdfEditTool.select` armed, so the first cut (which pinned on
  any `tool != null` and listened only for `UserScrollNotification`) never
  hid anything on a real phone. Three fixes: Select does not pin; with a
  tool armed the viewer scrolls by its own touch pan/fling
  (`_touchGrabPanBy` -> `position.jumpTo`, no user-scroll notifications), so
  `PdfChromeAutoHideListener` also tracks pointers and counts scroll updates
  while one finger is down or within 900 ms of lift-off (wheel ticks too;
  two fingers = pinch, ignored; a >half-viewport single update = a jump,
  ignored); and the select overlay owns empty-page taps, so it reports them
  through `PdfEditingInteractionHost.plainTap`. A tap that cleared a
  selection unpins the chrome - the toggle within 600 ms of an unpin is
  swallowed so that tap doesn't also hide it.
- `PdfViewer.onPlainTap` - a touch/stylus tap the viewer had no other use
  for: not on an annotation/link, not dismissing a text selection, no tool
  armed (Select aside), nothing selected for editing. Double-tap zoom never
  reaches it (the double-tap recognizer wins the arena). The shells pass
  `_chrome.toggle` only while auto-hide is live.

## Notes

- The reflow view has no `onPlainTap`; scrolling back reveals the chrome
  there.
- The web perf harness scenarios run at desktop widths, where nothing
  hides, so they cannot see this change; the cost is one viewer relayout
  per frame for the 200 ms of the slide (height only).
- Tests: `packages/dart_pdf_editor/test/auto_hide_chrome_test.dart`.
