# Canvas path cache: counted lookups without an LRU touch, keyed by the path

`PdfCanvasPathCache` (#900) keeps the native `ui.Path` built for each
`PdfPath` in a retained scene, so a zoom settle, detail patch or thumbnail
replay doesn't rebuild dense vector geometry. Every draw, clip and stroke asks
it for a path. On `main` each of those calls hashed a `(PdfPath, PdfFillRule)`
record and ran `PdfBudgetedCache.take`, and `take` unlinks the entry from the
recency list and re-appends it. A 13k-path diagram page makes about 12k of
these calls per replay.

The recency relink buys nothing here. The cache is admission-only: `pathFor`
stores a path only while it fits under the 32 MB / 65,536 bounds, so the
cache's own trim never evicts. Memory pressure clears everything. The one
eviction that does read recency order is the `PdfCacheRegistry` process
ceiling's hard trim (the app always sets `maxTotalWeight`), and every full
replay visits every path in paint order anyway, so after a replay LRU order
and insertion order are the same thing.

## What changed

`packages/dart_pdf_editor/lib/src/budgeted_cache.dart`:

- New `V? lookup(K key)`. It counts a hit or a miss exactly as `take` does,
  but it doesn't touch recency and doesn't run the `cloner`: it returns the
  stored master. The doc comment limits it to admission-only caches whose
  recency order is their insertion order. Nothing else in the file changed.
- `peek` was not an option. It counts nothing, and
  `benchmark_path_replay_test` reports the `canvas-paths` hit/miss counters.

`packages/dart_pdf_editor/lib/src/canvas_path_cache.dart`:

- `pathFor` uses `lookup` instead of `take`.
- The one budgeted cache is keyed by the `PdfPath` alone. `PdfPath` doesn't
  override `==`/`hashCode`, so that is an identity key, as the record's first
  field already was. The value is a two-slot `{nonZero, evenOdd, weight}`
  holder. A lookup hashes one object instead of building and hashing a record.
- A known path that misses its other fill rule (for example a `B*` fill and
  its stroke, when both commands carry the same `PdfPath` object) is admitted
  on weight alone, because it adds no entry. The combined value is re-put
  with the summed weight. There is no disposer, so the re-put leaves the
  first path live in the new holder.
- `maxEntries` now counts source paths rather than (path, rule) pairs.
  `debugLabel: 'canvas-paths'`, `rejectOversize`, `clearsUnderMemoryPressure`,
  the budgets and the admission rule are unchanged, so `snapshot()`,
  `clearLabel`, the process ceiling, adaptive memory's registry weight and
  memory pressure all see the cache exactly as before.

What was not done, on purpose:

- Raw `HashMap.identity()` maps outside the registry, which the original
  finding proposed. They would take up to 32 MB per live scene out of the
  process ceiling and adaptive-memory accounting.
- An identity front map over the budgeted cache. It measured 15-40% slower on
  the cold replay in the earlier study.
- Two budgeted caches, one per rule. That doubles the per-scene budget and the
  registry entries.
- Calling `enforceBudget` once per replay instead of once per `put`. The
  registry is left alone for a later worker-memory change.

## Numbers

### AOT microbench (the gate)

`pathFor` logic copied verbatim from each side, with `ui.Path` swapped for a
Dart stand-in so it AOT-compiles, over the real `PdfBudgetedCache`. The paths
are worker-style packed `PdfPath`s. The registry is app-like: a 384 MB ceiling
plus 20 other registered weight-bearing caches. Dart 3.13.3, `dart compile
exe`. Thread-CPU medians in ms for one full pass over every draw: cold is a
fresh cache (every draw misses and puts), warm is the next pass (every draw
hits).

Cross-build A/B. `origin/main`'s code and this branch's code were built as
separate executables and run one process each, interleaved ABAB for 6 rounds
of 21 reps each. 13,310 paths (the dense-diagram page), one rule per path:

| | main | branch | branch/main |
|---|---:|---:|---:|
| cold | 3.51 | 2.51 | **0.72x** |
| warm | 1.81 | 0.30 | **0.17x** |

Decomposition. One executable with the three shapes interleaved per rep,
ratios against `main` (ranges over rounds):

| Paths / draws | Record key + `lookup` (cold / warm) | PdfPath key + slots + `lookup` (cold / warm) |
|---|---|---|
| 13,310 / 13,310, one rule each (5 rounds) | 1.01-1.03x / 0.43-0.44x | 0.74-0.76x / 0.17x |
| 13,310 / 14,334, every 13th path `B*` + stroke (3 rounds) | 0.99-1.01x / 0.42-0.43x | 0.76-0.78x / 0.16-0.17x |
| 3,450 / 3,450 (plan-sheet size, 3 rounds) | 1.00-1.01x / 0.41-0.42x | 0.75x / 0.16x |
| 34,130 / 34,130 (3 rounds) | 0.94-0.97x / 0.44-0.46x | 0.73-0.81x / 0.15-0.16x |

- `lookup` alone halves the warm cost but leaves the cold pass flat. A cold
  pass is all puts, and a put still hashes the record key into the map. The
  path key is what moves the cold number, so both steps ship.
- The mixed-rule row exercises the re-put path. It stays well inside the gate.
- The 34k row is informational. Pages above
  `PdfPageView.retainedZoomReplayMaxCommands` (20,000) keep their scene only
  for tile region replays, so they never make one flat replay of that size.

Absolute savings at 13k paths are about 1 ms cold and 1.5 ms warm per replay
on the AOT VM. dart2js lookups measured about 4x costlier in the earlier study,
but no Chrome timing was taken for this change.

### End to end (informational)

flutter_tester (JIT), with `PdfRenderWorker` records turned into a
`PdfRetainedScene` and replayed through `CanvasPdfDevice` into a real
`ui.PictureRecorder`. Main's cache logic and the branch's alternate every rep,
21 reps, 384 MB ceiling set. Wall-clock medians, two separate runs. Cold is
the first replay at 1x on a fresh cache; warm is the replay at 2x that follows
it:

| Page | Cold main → branch | Warm main → branch |
|---|---|---|
| diagram-dense-3p p0 (13,310 commands) | 23.3 → 21.6 (0.93x), 22.5 → 21.8 (0.97x) | 12.2 → 10.6 (0.87x), 12.3 → 10.7 (0.87x) |
| diagram-dense-3p p1 | 22.0 → 20.8 (0.95x), 22.0 → 21.0 (0.95x) | 11.9 → 10.2 (0.85x), 12.1 → 10.5 (0.87x) |
| diagram-dense-3p p2 | 23.1 → 21.3 (0.92x), 21.8 → 21.1 (0.96x) | 11.9 → 10.6 (0.89x), 11.8 → 10.4 (0.88x) |
| plan-set-16p p0 (3,848 commands) | 5.9 → 5.4 (0.92x), 5.8 → 5.7 (0.97x) | 3.1 → 2.7 (0.88x), 3.0 → 2.6 (0.89x) |
| plan-set-16p p1 | 5.7 → 5.3 (0.93x), 5.7 → 5.4 (0.94x) | 3.0 → 2.6 (0.87x), 3.2 → 2.8 (0.88x) |

The direction is consistent, but every ratio is inside the 1.15x bar this perf
pass trusts for end-to-end claims. The gain is claimed from the microbench, not
from this table. Text, office and letterhead pages make no path lookups at all
and are unaffected.

## Correctness

- Pixels are identical by construction: a hit returns the same `ui.Path`
  object for the same (source, rule) pair, and a miss builds it the same way.
  `benchmark_path_replay_test` (cached vs uncached replay, RGBA byte compare
  at 2x, 4x and 8x) passes on all three pages of
  `test_corpora/dartpdf/diagram-dense-3p.pdf`.
- Its `canvas-paths` counters are identical on `main` and on the branch (for
  example p0: 11,961 entries, 5,191,520 bytes, 275,103 hits, 11,961 misses,
  0 evictions).
- A scratch sweep replayed every page cold then warm through both
  implementations and compared length, weight, hits, misses and evictions. It
  covered eight checked-in `test_corpora/dartpdf` files (46 pages) and the
  first 8 pages of every file in a private real-world corpus (234 pages).
  All 280 pages matched. None of them drew one `PdfPath` under both fill
  rules.
- Where a path is drawn under both rules, the counters shift in one way. The
  first other-rule use finds the source's entry, so it counts as a hit even
  though it builds its slot; on `main` it was a miss. Hits plus misses still
  equal lookups.

## Tests

- `budgeted_cache_test.dart`: `lookup` returns the master (no clone), counts
  hits and misses, and leaves `keys` in insertion order, so the next
  count-cap eviction drops the looked-up oldest entry. The counters test also
  covers `lookup`.
- `canvas_path_cache_test.dart`:
  - The entry-cap and pressure tests now fill the cap with a second source
    path. The other rule of the same path no longer takes a new entry.
  - New: both rules of one path share an entry and sum its weight (length 1,
    weight 1024). A known path's second rule is gated on weight alone.
  - New: the process ceiling trims in insertion order. A `pathFor` hit on the
    oldest path doesn't save it from the trim. With `take` this test fails.

## Gotchas

- `lookup` only suits caches that never evict through their own bounds. A
  cache that relies on LRU eviction under its budget must keep using `take`,
  or its hottest entries get evicted first.
- If `PdfBudgetedCache` ever moves its entry map to `LinkedHashMap.identity()`,
  keep record-keyed caches off it: `identical` on records is unspecified. This
  cache doesn't need that, because `PdfPath`'s default `==` is already
  identity.
- The key assumes `PdfPath` keeps default (identity) equality. A structural
  `==` would merge distinct sources that happen to share geometry
  (harmless for pixels, but it changes the counters and occupancy) and make
  every lookup hash the whole path.
