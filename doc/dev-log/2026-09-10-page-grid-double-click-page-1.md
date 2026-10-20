# Double-clicking a page in the grid landed on page 1

A double-click on a tile in the full-area page grid (`PdfThumbnailView`,
View options → page grid) closed the grid but showed page 1 instead of the
page that was clicked.

The grid's own wiring was fine. `_PageTile._onTap` detects the second click,
`_openPage` calls `viewerController.jumpToPage(index)` and then fires
`onOpenPage`, which the shell wires to `prefs.showThumbnailView = false`. The
jump really did happen - instrumenting `_scroll` showed the viewer sitting on
the right page while the grid was still up, and no later `jumpTo` at all. The
scroll offset was simply 0 again on the first frame after the grid closed.

The cause was one frame further out, in `PdfShellPanelLayout.build`. It
wrapped its result in `PdfPanelDragScope` / `PdfToolbarDragScope` only when
the host had wired `onPanelDock` / `onToolbarDock`:

```dart
if (widget.onToolbarDock != null) {
  result = PdfToolbarDragScope(..., child: result);
}
```

Opening the grid sets `altView`, which hides the editing toolbar, which makes
`PdfEditorView` pass `onToolbarDock: null`. So the wrapper vanished on open
and came back on close. A wrapper that comes and goes changes the depth of
everything below it, so Flutter cannot match the old elements to the new
ones: `_PdfViewerState` was discarded and rebuilt from scratch each time (a
`print` in `initState` fired three times for one open/close round trip), and
its `ScrollController` re-attached to a fresh `ScrollPosition` at
`initialScrollOffset` - page 1. The viewer *was* still mounted the whole
time, as the existing test asserts, just not the same State.

Fix: both scopes now always sit in the tree and carry an `enabled` flag
instead. `maybeOf` returns null when disabled, so `PdfToolbarMoveHandle` and
a panel's move handle still hide exactly as before (that null check is the
whole public contract of these scopes), and `updateShouldNotify` now fires on
an `enabled` flip so a handle appears or disappears when docking is turned on
or off. The tree shape no longer depends on whether the toolbar is showing.

The same wrapper churn would have rewound the viewer for any other reason the
toolbar came and went, so this is not only a grid bug - it was just most
visible there, because the grid is the one place where a click is *supposed*
to move the viewer before the toolbar returns.

Regression test: `pdf_shell_test.dart`, "a page grid double-click lands the
viewer on that page" - double-click Page 6 of an 8-page document in the grid
and assert `viewerController.currentPage == 5` after it closes.
