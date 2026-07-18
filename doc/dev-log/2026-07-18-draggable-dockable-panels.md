# Draggable, dockable side panels (left/right/top/bottom) with saved layout

The editor's side panels (Pages/thumbnails, Search results, Bookmarks,
Annotations, Properties) could only sit left or right, and only implicitly -
placement was decided by which hard-coded list (`leadingPanels` /
`trailingPanels`) `pdf_editor_view.dart` dropped each panel into. This session
made the panels **draggable to any of the four edges** and **persists the
layout** per panel.

## Model

- `PdfPanelDock { left, right, top, bottom }` (`editing/editing_panel.dart`) is
  the new placement concept, with `isHorizontal` (left/right = fixed-width
  columns; top/bottom = fixed-height strips) and `gripSide` (maps a horizontal
  dock to the existing `PdfSidebarSide` the resize grip speaks). `PdfSidebarSide
  { left, right }` stays - it's still the grip's / comparison navigator's
  horizontal-only orientation.
- `PdfDockablePanel { thumbnails, search, bookmarks, annotations, properties }`
  is both the drag payload and the identity a shell maps to a persisted dock.
  Each value carries a `label` + `icon` for the drag feedback chip.

## The shared frame did the heavy lifting

All five panels already funnel through one `PdfSidebarPanelFrame`
(`editing/editing_panel.dart`), so most of the work landed there:

- Its `side` param became `dock`. Horizontal docks render as before
  (fixed-width column + `PdfSidebarResizeGrip` on the inner edge). Vertical
  docks render as a fixed-height strip with a new internal
  `_PdfSidebarVerticalResizeGrip` on the inner edge. **`width/minWidth/maxWidth`
  now mean the cross-axis extent** - the column width for left/right, the strip
  height for top/bottom - and the existing per-panel `...Width` prefs are reused
  as that extent (a left panel dragged to top carries its width over as height).
- `PdfSidebarPanelGeometry.moveHandle()` is the new counterpart to
  `closeButton()`: a `PdfSidebarMoveHandle` (a `Draggable<PdfDockablePanel>`)
  that each panel renders next to its close button. It renders **nothing** when
  no `PdfPanelDragScope` is in scope, so the same panels stay non-draggable in
  contexts that don't wire redocking (standalone use, the reader shell).

## Shell wiring

- `PdfShellPanelLayout` (`shell_chrome.dart`) is now stateful and gained
  `topPanels` / `bottomPanels` (full-width strips above/below the viewer row)
  and an `onPanelDock` callback. When `onPanelDock` is wired it provides a
  `PdfPanelDragScope` around the tree and, **only while a drag is underway**,
  overlays four edge `DragTarget` drop zones (`_PanelDropZones` /`_DropTarget`,
  keys `pdf-shell-dropzone-{left,right,top,bottom}`). Top/bottom bands are inset
  horizontally so they never overlap the left/right bands at the corners.
- `pdf_editor_view.dart` reads each panel's persisted dock, pairs every visible
  docked panel with its dock, and `dockedPanels(dock)` filters them into the
  four groups (canonical order = thumbnails, search, bookmarks, annotations,
  properties, so the default left/right layout is byte-identical to before).
  `_setPanelDock` writes the pref on drop; the pref notifies and the panel
  re-routes to its new edge on the next build.

## Persistence

Five `PdfPanelDock` prefs in `editing_preferences.dart`
(`thumbnailSidebarDock`, `searchPanelDock`, `bookmarkSidebarDock`,
`annotationSidebarDock`, `propertiesPanelDock`), persisted by enum `.name`
(`_readDock`/`_setDock`), defaults reproducing the built-in layout
(thumbnails/search/bookmarks left, annotations/properties right).

## Notes / gotchas

- ValueKey-ed panels moving between the leading/trailing/top/bottom lists
  **remount** (ValueKeys only match within one parent), which is the safe path -
  the same reason the docked/sheet variants already carry distinct keys (the
  thumbnail tiles' Tooltip `OverlayPortal` must not reactivate mid-layout).
- The reader shell (`pdf_reader.dart`) is left as-is: it passes no
  `onPanelDock`, so its thumbnail/bookmark panels keep their default docks and
  show no move handle. Wiring it would be a small follow-up.
- Tests: `test/panel_dock_test.dart` covers dock defaults + persistence,
  `PdfPanelDock.isHorizontal`, the vertical-strip frame layout, and an
  end-to-end drag of the annotation panel's handle onto the top drop zone
  (asserting the pref flips to `top`). Existing `editing_panel_frame_test.dart`
  / `editing_panels_test.dart` / `benchmark_panel_frame_test.dart` were updated
  for the `side` -> `dock` rename.
