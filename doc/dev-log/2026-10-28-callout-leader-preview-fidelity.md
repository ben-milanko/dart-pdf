# Callout leader previews match the commit

The callout previews drew each leader as a straight terminus-to-base line:
the placement drag ran it to the pointer (the box's top-left corner), a box
move shifted the base by the drag delta, and a base-handle drag followed the
raw pointer. The commit seats the leader differently - `attach` on the edge
facing the target (2pt in from the corners), clamped onto the perimeter when
pinned, plus a knee stub out of that edge - so on release the arrow jumped.

The geometry now lives in one public function, `pdfCalloutLeaderLine(box,
leader)` (pdf_document `annotation.dart`, moved out of the editor extension's
private `_calloutLine`/`_calloutAttach`/`_calloutKnee`/`_clampToBoxPerimeter`).
The editor builds /CL with it and the overlay previews with it
(`_calloutLeaderPath` / `_calloutLeaderPaths` in `editing_overlay.dart`):
placement (box = `_calloutPlacementRect`, shared with the release), the open
box editor, terminus/base handle drags, box moves, and the after-commit hold.
`_EditingPreviewPainter.calloutLeaders` now carries polylines.

A rotated callout's box isn't in page space, so its preview keeps the old
straight lines. Tests: `editing_callout_test.dart` "...previews the leader(s)
the commit draws" compare the mid-drag polyline to the committed leaders.
