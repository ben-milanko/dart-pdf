# Colorant raster: typed edge tables and cursor path reads

The overprint colorant buffer (2026-07-25-overprint-colorant-buffer.md) is
rasterized for every draw on a page that declares `/OP` or `/op`. Two costs in
it had nothing to do with the feature itself: the scanline rasterizer's
tables, and how it read paths. Both are fixed here without changing a single
span.

## What changed

- **Typed edge and crossing tables** (`raster/colorant_raster.dart`,
  `PdfColorantRaster._spansOf`). The edge table (`xTop`, `slope`, `yTop`,
  `yBottom`, `winding`) and the per-scanline crossings are `Float64List` /
  `Int32List` fields with explicit counts, grown by doubling and never
  shrunk. The scan itself is untouched: every edge on every row, gathered in
  index order.
- **Cursor path reads** (`raster/flatten.dart`, `_axisAlignedRect`).
  `flattenPath` walks `path.cursor()` and switches on `PdfPathVerb` with the
  same arithmetic. `_axisAlignedRect` checks `segmentCount` is 4..6 before
  reading anything, requires a leading moveTo, and collects corners into a
  static `Float64List(5)` pair instead of two growable lists. The
  coincident-control cubic rule (`m/v/v/v/v/h` boxes) is unchanged.
- `raster/strip_generator.dart` asks `segmentCount` instead of
  `segments.length` for its size gates.

## Why

- **`List.clear()` does not keep capacity on the VM.** The 2026-07-25 note
  says the rasterizer's edge and crossing lists "are reused across draws".
  They were not: `_GrowableList.clear()` sets `length = 0`, which takes the
  shrink-to-fit path and drops the backing store. So the five edge lists
  regrew from nothing on every draw and the two crossing lists on every
  scanline, boxing each double on the way. In a profile of the render
  worker's record path on real /OP documents, `_GrowableList.add`, `_grow`
  and `_allocateData` were about half of `_spansOf`.
- **`_axisAlignedRect` materialized every path.** It read `path.segments`
  before checking the length, so every fill and clip that reached the buffer,
  of any size, was turned from the interpreter's packed form into segment
  objects plus an entry in `PdfPath`'s global `Expando`; `flattenPath` then
  read that list again. #659 introduced packed paths and said rendering
  should use `cursor()`; the colorant raster predates it and was never
  moved over. On a worker record of the Ghent suite plus the 10 /OP
  documents below this was 257,068 materializations; it is now 0.

## What was tried and dropped

- **Active-edge bucketing** (bucket edges by first row, keep an active list).
  Slower than typed arrays alone in every path-size group on both AOT and
  dart2js: paths span few rows of the 384-cell grid, so the per-edge bucketing
  work costs more than the compares it saves. It also needs integer row
  indices, and those break for far-off-page geometry: the VM saturates
  `ceil()` near 9.2e18, `±1` slack then wraps, and `Int32List` storage
  truncates past 2^31 rows. A differential fuzz found fills silently dropped
  and an uncaught `RangeError` (which fails the whole page render) for
  coordinates from about 3e9. Broken generators print FLT_MAX with `%f` and
  pdf_cos parses it, so those inputs are reachable. The typed-only scan keeps
  no row indices, so it has nothing to overflow.
- **A typed clip stack.** `PdfColorantRaster._clipStack` is a `List<int>` of
  Smis, so nothing is boxed, and a typed version measured as noise.
- **A bounding-box pre-cull against the clip.** Not exact: an empty span list
  is what sends a sub-cell mark to `coveringBoxSpans`, so culling would change
  results. Only a cull against the grid bounds would be safe.
- **Deferred recording** stays the bigger lever (the 2026-07-25 note's "next
  cut"): most declaring pages never read a backdrop.

## Measurements

The workload is the render worker's record path: `RecordingPdfDevice` with
`collectCharOffsets`, the resumable walk, text capture, annotations, then
`serializeCommands` with the worker's flags. It ran over 10 real-world
documents from a private corpus whose pages declare overprint, first 10 pages
each. `PdfInterpreter.debugResolveOverprint` switched the buffer on and off,
interleaved inside each process with 3 reps per mode, so "overhead" (on minus
off) is the buffer's own cost. Timing is mutator-thread CPU from AOT
executables. There were 6 rounds with the variant order rotated per round, on
a machine at load average 30-90; the table shows medians of per-round totals.

| | base | typed tables | + cursor reads |
|---|---|---|---|
| buffer off (control) | 2461 ms | 2459 ms (0.999) | 2451 ms (0.996) |
| buffer on | 3195 ms | 3053 ms (0.956) | 2802 ms (0.877) |
| buffer overhead | 733 ms | 585 ms (0.797) | 370 ms (0.505) |

- Paired within a round, overhead is 0.825 (range 0.66-0.83) for the typed
  tables alone and 0.507 (0.41-0.60) for both; the on-mode record is 0.888
  (0.80-0.91).
- Per document, the on-mode record is 0.76-0.94x and overhead 0.34-0.84x.
  The document with the most overhead left (0.73x) is dominated by the scan
  itself on large strokes, which neither change touches.
- An earlier run of the same code with separately built executables gave
  0.516 (overhead) and 0.890 (on-mode).
- Re-measured after each of three rebases onto a newer main (base and branch
  only, alternating which runs first, 6 rounds each). In every repeat the
  per-round on-mode ranges of base and branch do not overlap:

| repeat | buffer overhead | on-mode record | buffer off |
|---|---|---|---|
| 1 | 696 -> 387 ms (0.557x) | 2722 -> 2408 ms (0.884x) | 1.001x |
| 2 | 667 -> 384 ms (0.576x) | 2661 -> 2363 ms (0.888x) | 0.998x |
| 3 | 683 -> 411 ms (0.602x) | 2796 -> 2497 ms (0.893x) | 0.987x |

dart2js (-O2) under node, process CPU, 6 alternating processes per variant, on
the two smallest of those documents (medians; the last two columns are
repeats after rebases):

| | base on | final on | ratio | repeat 1 | repeat 2 |
|---|---|---|---|---|---|
| document A | 885 ms | 544 ms | 0.615 | 0.655 | 0.646 (840 -> 543 ms) |
| document B | 628 ms | 401 ms | 0.640 | 0.645 | 0.620 (600 -> 372 ms) |

The on-mode ranges never overlap. Overhead drops to 0.25-0.36x of base, while
buffer-off time stays inside the per-process spread (0.97-1.08x). Two larger
documents from the same set gave 0.832 (1480 -> 1232 ms) and 0.806 (674 ->
543 ms) on-mode in the last repeat. The web gain is larger because dart2js pays
more for both the `Expando` and the growable-list churn.

Reach: only pages that declare `/OP` or `/op` (or a DeviceCMYK blending
group) build the buffer. That is about a fifth of the documents in the private
corpus, so this is not a general speed-up. On those pages it helps every
interpretation: the worker record on native and web, in-process renders,
thumbnails and print. `flattenPath` is shared with `StripGenerator` and the
flutter_gpu backend, which stop materializing packed paths too; that effect
was not measured.

## Identity

- **Worker wire bytes**: an FNV-1a hash of `serializeCommands` output per page,
  worker flags, over the 54 Ghent files plus the 10 overprint documents (at
  most 40 pages each). All 251 pages are identical to base, with no errors,
  before and after each rebase.
- **Materializations**: a scratch build with a counter in `PdfPath.segments`
  counted 257,068 materializations on base over that same run and 0 with this
  change (same counts after each rebase).
- **Differential fuzz**: base's `fillSpans`/`strokeSpans`/`flattenPath` and
  the rect verdict against the new ones. The same path object goes to both,
  as segment objects, a builder-packed path or a float32 decoder path. The
  inputs include cell-centre ties, cubics, open and closed subpaths, both fill
  rules, caps, joins, dashes and pathological coordinates (NaN, ±inf, ±1e12,
  3e9, 2^32 rows, ±1e19, ±1e300, FLT_MAX). 200,000 cases on the VM (8 seeds,
  repeated after rebases) and 80,000 under dart2js gave 0 span, rect-verdict
  or flatten mismatches.
  The ~6% of cases that throw (NaN reaching `ceil()`) throw the same error
  type on both sides; that is a pre-existing robustness gap, left alone.
- `ghent_render_test` and `overprint_render_test` pass with no baseline
  change, and the counter gate is unmoved.

## Gotchas

- **The gathering order is part of the result.** A non-finite vertex (an
  infinite x maps to a NaN cell y through a shear-free page matrix) gives NaN
  crossings, and the insertion sort leaves a NaN wherever it was gathered.
  With edges gathered in path order the NaNs trail the finite crossings and
  no run reads them; gathered earlier, one would open or close a run. Any
  future reordering of the scan (bucketing, sorting edges) has to keep
  non-finite edges in index order. The test "a vertex at infinite x drops out
  without disturbing the rest" pins this.
- **`continue` inside a `switch` in a `while` loop** continues the loop, as it
  did in the old `for`-in; `flattenPath`'s "no current point" cases rely on
  it.
- The rectangle scratch is static. `_axisAlignedRect` is synchronous and never
  re-enters, and each isolate (render worker, web worker) has its own.

## Pointers

- `packages/pdf_graphics/lib/src/raster/colorant_raster.dart` -
  `_spansOf`, `_growEdges`, `_axisAlignedRect`, `debugIsAxisAlignedRect`.
- `packages/pdf_graphics/lib/src/raster/flatten.dart` - `flattenPath`.
- Tests: `test/colorant_buffer_test.dart` ("the colorant rasterizer" group:
  edges at 1e12 / 3e9 / 2^32 rows / 1e19 / FLT_MAX, an infinite-x vertex, a
  packed coincident-cubic rectangle and a float32-decoded one), and
  `test/raster/flatten_test.dart` ("a packed path flattens exactly like its
  segment objects").
- `packages/pdf_graphics/tool/bench_overprint_buffer.dart` is the in-repo
  on/off bench; the numbers above used a worker-faithful variant timed in
  thread CPU.
