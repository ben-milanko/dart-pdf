# One page-set module for the viewer's revision swaps (#1201)

`_PdfViewerState` used to decide what a document swap invalidates in five
hand-written places: `_swapDocument`, `_tryReconcileIncrementalRevision`,
`_tryReconcileKeyedPageOrder`, `_onViewRotationChanged` and the paper-colour /
annotation-visibility branch of `didUpdateWidget`. They had drifted.

## Shape

- `lib/src/page_set.dart` (not exported; `PdfPageReconciliationMode` moved
  here and is re-exported from `pdf_viewer.dart`).
- `PdfPageSet` is an immutable value: document, page wrappers, stable refs,
  aspects, point widths, max sizes, content stamps, view rotation, slot
  `epoch` and `tileNamespace`. The viewer's `_pages`, `_pageRefs`,
  `_aspects`, `_pointWidths`, `_maxPoint*`, `_pageEpoch`,
  `_tileCacheNamespace` and `_loadedDocument` are now getters onto it.
- `reconcile(next, sameLineage:, impact:, contentStamp:)` picks incremental →
  keyed → full and returns a `PdfPageSetChange`; `rotated(r)` and
  `repainted()` return the same type for the two view-only changes.
- `PdfPageSetChange` = previous + next set, mode / fallback reason /
  diagnostics numbers, `newIndexForOld` for a reorder, `remapPage(old)`, and
  one `PdfPageInvalidation`: `textPages`, `annotationPages`, `rasterPages`,
  `warmPages` (old indices; null = re-arm every lane), `previews`
  (`bind`/`rebind`/`reorder`/`clear` + `previewChanged`),
  `retiredTileNamespace`, `viewport` (`keep`/`remap`/`reset`) and
  `placeViewportNow`.
- `_applyPageSetChange` in the viewer is the only consumer. Order matters:
  the viewport is captured against the *old* set before anything moves.

## Gotchas

- The incremental path must not touch `next.pages` (that walks the page
  tree; `page_set_test` asserts `PdfPerfPhase.pageTreeWalk` stays 0). It
  resolves the dirty pages by stable reference instead.
- Undo of an annotation edit opens a fresh COS graph, so it is a full reload
  (`different-cos`) that still rebinds previews (same geometry and order).
- `_rasteredPages` now follows one rule: cleared when `rasterPages` is null,
  otherwise permuted by `newIndexForOld` and pruned. The page item also drops
  its own readiness when its image inputs change, so clearing up front on a
  rotation/repaint only makes the viewer's view of it truthful sooner.

## Tests

`test/page_set_test.dart` covers annotation edit, page rotation, reorder (+
undo), insert, delete, undo to a fresh COS, content-stamp rebind, unrelated
swaps, view rotation and repaint without widgets. The controller hooks
`debugIncrementalPageReconciliations`, `debugKeyedPageReconciliations`,
`debugLastIncrementallyReconciledPages` and `debugTileCacheNamespace` are
gone; widget tests use `debugPageReconciliationDiagnostics` and the public
`tileCacheNamespaceIdentity`.
