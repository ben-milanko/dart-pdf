# 2026-07-18 — Tile pyramid: budget-vs-demand guard (fix #314/#360 eviction thrash)

## Symptom

On web release and **macOS release (the default-on platform)**, the deep-zoom
tile grid flickered "everywhere, even when the viewport wasn't moving" — the
green `pdfDebugPaintDetailBounds` overlay churned across the page. On-device
devtools traces:

- web: `scheduled 3897 / landed 3897 / discarded 0`, only **96 tiles retained**
  (cache pegged at the 96 MB budget), `batches` still climbing on a static view.
- macOS: tiles cache pegged at 100/100 MB on a 198-page CAD book, `jankFrames
  120/120`.

`discarded 0` with a huge scheduled/retained gap = **pure LRU eviction thrash**,
not invalidation. `PdfBudgetedCache` protects only the single most-recently-used
entry (`_protectedKey = _entries.keys.last`), so `viewFor`'s "MRU-protection
contract" is far weaker than its comment implied: last frame's `take`-promoted
tiles drift back toward LRU as new slab `put`s arrive and get evicted, then the
`repaint: Listenable.merge([store])` → `viewFor` loop re-requests them → re-raster
→ evict others → never settles.

## Root cause

The working set exceeded the shared 96 MB / 96-tile budget. Two compounding
reasons, both unmasked off the validated desktop-single-page path:

1. **The tile path inherited the patch's 50%-per-side inflation.**
   `_detailGeometryAt` defaults `inflation: 0.5`, quadrupling the requested tile
   area purely for pan-ahead headroom — but the pyramid already has a prefetch
   ring for that. On a 1440×900 HiDPI viewport at deep zoom the inflated visible
   set is ~77 tiles and +ring ~117 > 96 → thrash.
2. **No budget-vs-demand guard.** The code *assumed* "a viewport's worth stays
   above the eviction line" (tile_store.dart) but never enforced it. Big
   viewports / many-tile CAD pages blew past it.

(#314's "validated on 198-page scan books, pyramid pinned at its 96 MB budget
with healthy RSS" read the *saturation* signature as healthy utilization.)

## Fix (default stays ON, fix in place)

`PdfTileStore` (`tile_store.dart`):
- `budgetTileCapacity` = `maxBytes ~/ (tilePixels²·4)` — how many tiles the
  budget holds.
- `viewFitsBudget(...)` — true only when the visible exact-bucket tile count is
  ≤ `_budgetFitFraction` (0.75) of capacity; the remainder is headroom for
  coarser-fallback tiles + eviction margin. Shares a new `_tileGrid` helper with
  `viewFor` so the fit test and the scheduler count identical tiles.
- `viewFor` caps the **prefetch ring to the budget headroom** left after the
  visible set (labelled `break ring`), so a pass never schedules more than the
  LRU can hold.

`PdfPageView` (`pdf_page_view.dart`):
- Tile slice now uses `_tileInflation = 0.0` (rely on the ring, not the patch's
  guard band) — the primary thrash cut, ~4× smaller working set, keeps tiles
  enabled on normal displays.
- `_refreshTileGeometry()` returns a bool; when the view is over budget
  (`_tilesFitBudget` → `viewFitsBudget`) it leaves `_tileFraction` null and
  `_updateDetail` **falls through to the single detail patch** (pre-#314, well
  tested) — which covers an arbitrarily large region in one raster without
  evicting the pyramid. The `build` composition already prefers the patch when
  `tileLayer == null`, so no wiring change there.

Tiers: fits → tile with ring; visible fills budget → tile, ring dropped; visible
> 0.75·capacity → patch fallback.

## Tests

- `tile_store_test.dart` — `budgetTileCapacity`; `viewFitsBudget` accept/reject;
  `viewFor` drops the ring under pressure; **a budget-tight static view
  converges** (repeated identical passes schedule nothing further, `discarded 0`
  — the regression guard for the flicker).
- `tile_store_page_view_test.dart` — an over-budget deep-zoom view renders the
  single patch (`pdf-page-detail-image`), no tile layer, `tileCount == 0`.

## Follow-ups / notes

- Diagnostic blind spot fixed separately in PR #365 (devtools read the effective
  store, not just the override) — re-capture a macOS trace with that + this to
  confirm `scheduled`/`batches` stop climbing on a static view.
- Multi-page sharing: at deep zoom a page boundary shows a slice of each page
  (~one viewport combined), so the per-page 0.75 margin holds; two simultaneous
  full-viewport pages at deep zoom isn't reachable.
