# 2026-07-22 — pointer-event costs: per-build search/selection rescans (#403 part 3)

#403 has three parts. Part 2 (resolve the hovered page once per pointer event
instead of up to four times) already landed in **#442**, including the
heavy-page gate that skips synchronous text extraction on hover. This is
**part 3** — the per-build rescans during an active search or text selection.

## Change (pdf_viewer.dart)

- **Search matches by page.** `_matchesOn(pageIndex)` filtered the whole
  `_matches` list per page per build — O(matches × visible-pages) every frame
  while a search is active. Now `_setMatches` builds a `Map<int, List>` index
  once when the matches change, and `_matchesOn` is an O(1) lookup. The three
  `_matches =` sites (search start/land, clearSearch) route through `_setMatches`.
- **Selection quads memoized.** `_selectionQuadsOn(pageIndex)` re-ran
  `quadsFor` on every call, and `_textSelectionOn`, the selection-rects helper,
  and the per-page build each asked for the same quads — several full
  `quadsFor` scans per selected page per build. Now cached in a
  `Map<int, List<PdfTextQuad>>` keyed on the selection range (`_selRange`, a
  value-equal record): a new anchor/focus rebuilds the cache, a stable
  selection computes each page once. Cleared explicitly in `_clearSelection`.

Both are pure hot-path memoization — no behavioural change. Search and
touch-selection widget suites pass unchanged.

## Not done here

- **Part 1 (overlay cursor repaint layer)** — the headline: the editing
  overlay `setState`s per mouse-move to move a pen dot / eraser ring / count
  mark, rebuilding its whole subtree. The file already has the right pattern
  (`_ActiveStrokePainter` reads live `_state` fields and repaints via
  `super(repaint: _state._activeStrokeRepaint)` on its own layer, no rebuild);
  the fix is to move hover-cursor rendering out of the snapshot-arg
  `_EditingPreviewPainter` onto a sibling repaint layer and have `_onHover`
  bump a `_cursorRepaint` notifier instead of `setState`. That is a delicate
  extraction in the render-critical overlay painter whose main failure mode
  (cursor flicker / wrong z-order / stale cursor) is *visual* and not reliably
  caught by widget tests — it wants eyes-on validation, so it is left as a
  scoped follow-up rather than shipped blind.
- The async/off-thread hover text extraction (part 2's remaining half) is
  gated behind #396.
