# Polyline placement: pan, edge scroll, undo a vertex, nodes-only chrome

Placing a polyline/polygon is many clicks long, so the viewport and undo have
to work *during* the placement, not only around it
(`editing_overlay.dart`, `editing_controller.dart`).

- **Middle-button pan mid-path.** The viewer already grabs a middle drag as a
  temporary hand (`_middleButtonDrag`), but a plain poly tool placed its
  vertex in the raw `_onPointerDown` for *any* button, so the press that began
  the pan dropped a node. A mouse now places only with the primary button
  (touch/stylus unchanged). While the hand pans, `_onPointerMove` re-derives
  the rubber band's `_polyHover` from the global position - a move event's
  `localPosition` is pinned to the transform at the press, so it drifts as
  the page slides.
- **Edge auto-scroll while hovering.** Between clicks no button is held, so
  the region-drag edge auto-scroll never ran. `_polyHoverScrolls` (a path in
  progress with a live hover and no rectangle drag) joins
  `_autoScrollDragActive`; `_onHover` feeds `_autoScrollGlobal` and starts the
  ticker, and `_applyDragPosition` keeps `_polyHover` on the content scrolled
  under the pointer. Leaving the page (`onExit` clears `_polyHover`), any
  press, a middle pan, or finishing/abandoning the path stops it.
- **Ctrl+Z pops the last vertex.** `PdfEditingController.setPlacementDraftUndo`
  registers the owning overlay's `_undoPolyPoint`; `undo()` asks it first and
  falls through to the document history once it returns false.
  `hasPlacementDraft` feeds `canUndo`. Every path that drops the draft goes
  through `_clearPolyDraft` (which unregisters); the tool-switch reset in
  `build` and `dispose` unregister without notifying.
- **Nodes-only selection.** A lone selected Line/PolyLine/Polygon
  (`_selectedNodesOnly`) paints just its vertex handles - no bounding box,
  no rotate knob, and `_hitsRotateHandle` refuses it (dragging a node already
  turns it). Multi-selections keep their boxes.

Tests: `test/editing_polyline_placement_test.dart`.
