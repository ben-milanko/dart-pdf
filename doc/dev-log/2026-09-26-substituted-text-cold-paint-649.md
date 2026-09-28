# Substituted text: recovering #649's cold-paint cost

Follow-up to #649 (exact placement of substituted glyphs, see
2026-08-06-substituted-glyph-placement-649.md). That change draws every word
piece of an unembedded-font run at the PDF's own pen offset. It shapes each
multi-character piece with a fresh `TextPainter`, and the run cache keys on the
whole run text plus a hash of its offsets, so every new line misses. On a page
of unique labels (coordinates, dimensions, grid refs) that meant one paragraph
per piece of every label. Cold replay of `test_corpora/dartpdf/cad-labels-6p`
went from about 30 ms per 3 pages before #649 to about 150 ms (flutter_tester),
and prose set one line per `Tj` got 6-7x slower cold. Warm replay was fine,
and neither the VM sweeps (no UI isolate) nor the best-of-2 render bench can
see it, so nobody noticed.

All the changes are in `CanvasPdfDevice` (`canvas_device.dart`). Output is
unchanged on every document page checked: pixel-identical in both font
configurations. The one exception is a subpixel rounding flip that a
randomized label sweep turns up about once in 1,400 synthetic label renders
(below).

## What changed

1. **Typed run-layout key.** `_measureLayout` and `_placedLayout` used a string
   key that formatted six doubles on every drawn run, hit or miss. On a page
   of ~1,700 short substituted runs, formatting, hashing and comparing that
   string profiled at about a fifth of a warm replay. `_RunLayoutKey` holds
   text, font, the exact colour and fill alpha, Tc/Tw, and the offsets hash.
   Its hash is computed once, cheap fields are compared before the text, and
   NaN compares equal to NaN. (A key unequal to itself can never be found
   again to evict. On dart2js a record key with a NaN double makes
   `PdfBudgetedCache`'s trim loop spin forever; a record key is also slower
   than the string there.)
   Colours are compared exactly, not quantized to 8 bits, because the painter
   bakes the exact colour in.
2. **`_toFloat64` fills a fresh `Float64List(16)` directly** instead of a list
   literal plus `Float64List.fromList`. It stays fresh per call, not a shared
   scratch buffer, because gradients hand the same matrix to `ui.Gradient`.
3. **Glyph layouts are resolved once per placed run.** `_buildPlacedLayout`
   looked each character up in the glyph cache two or three times (measure,
   cut, emit), and each lookup formatted the font name and four doubles into
   the key. Now the key suffix is built once per run, and the layouts go into a
   local list that the cut and emit passes share. A resolved layout is
   borrowed, not owned, so a run with more distinct characters than the
   4,096-entry glyph cache could see an early one evicted and disposed by a
   later insert in the same run. `glyphAt` looks a disposed one up again
   (`per_glyph_text_test` pins this with 4,200 ideographs).
4. **Kern-free pieces are composed, not shaped.** A piece that passes #454's
   gate (`_composableSpan`: digits, capitals next to digits or spaces, plain
   punctuation) is laid out from its cached glyph layouts, placed end to end
   from the piece's own offset. That is the piece, provided the face kerns
   none of those pairs. So it is gated on the face (`_kernFreeFace`):
   - Only runs whose substitute is TeX Gyre Heros, Termes or Cursor qualify.
     Adventor kerns `7.` / `.1` / `1.` by up to 0.135 em and Carlito kerns
     `.-`. Composing them measured 264-371 differing pixels on a single 40 pt
     label.
   - A host that leaves `dart_pdf_editor_assets` out draws Helvetica/Arial in
     a system face that kerns `11`. Whether the bundled face is registered
     can't be asked of the engine, so it is measured: `_kernProbe` holds
     every pair the gate admits, once each. It is shaped as the renderer
     shapes it and again with `FontFeature.disable('kern')`, and a width
     difference means the face kerns. This runs once per substitute, weight
     and slant per process (and again after `clearTextLayoutCache`), at the
     cost of two paragraph builds.
5. **Word pieces are shared across runs** (`_pieceCache`). A piece is laid out
   without Tc/Tw, so it depends only on its text and what the glyph key
   covers, and prose repeats its words line after line. The cache holds 1,024
   entries, is bounded by entry count only, and clears under memory pressure.
   It has no weigher on purpose: a weighted `getOrAdd` calls
   `PdfCacheRegistry.enforceBudget()`, whose hard trim does not protect the
   newest entry, so it could dispose the piece just inserted before the
   caller `retain()`s it. Pieces are retained like glyphs, so either the run
   cache or the piece cache can drop them first
   (`text_cache_test` "shared pieces outlive whichever cache lets go first").

Not done: a per-run `Expando` memo of the resolved layout. It was a net loss on
fresh worker transcripts (every record makes new `PdfTextRun`s), it can hand
out an LRU-disposed layout, and it goes stale when the placement flags flip.
The piece cache also admits every piece on first sight, not on the second:
unique pieces mostly live inside run layouts the run cache still holds, so
caching them costs little (see Memory).

## Numbers

All in flutter_tester (JIT, asserts on, Skia CPU raster), because this is
UI-isolate code: pages are recorded the worker's way (interpret, serialize,
deserialize) off the clock, then `PdfPageRenderer.pictureFromCommands` is
timed. `clearTextLayoutCache` runs before each cold pass. The base
(origin/main) and patched trees ran as separate processes, alternated ABAB
for 7 rounds. Each figure below is a median over the rounds, and each ratio
is the median of the per-round patched/base ratios.
The bundled faces are registered the way the app registers them. "Raster" is
`toImage` of the recorded picture at DPR 2. Wall clock on a loaded machine,
so only large ratios and the build counts mean anything.

| workload | TextPainter builds (cold pass) | cold replay | warm replay | raster | cold replay + raster |
|---|---|---|---|---|---|
| cad-labels-6p, 3 pages | 3973 → 15 | 155 → 28 ms (0.18x) | 1.10x | 2.0x | 172 → 60 ms (0.35x) |
| real-vocabulary prose, 20 pages | 11623 → 5402 (0.46x) | 387 → 204 ms (0.53x) | 0.88x | 1.0x | 0.59x |
| same prose, first 3 pages | 1815 → 977 (0.54x) | 0.68x | 0.79x | 1.06x | 0.71x |
| text-report/letterhead/annotated/styled-booklet, 5 pages each | 16719 → 234 | 0.16x | 0.55x | 0.97x | 0.33x |
| private real-world corpus, 5 docs × 3 pages | 1887 → 1446 | 0.82x | 0.74x | 1.17x | 0.92x |
| cad-labels, system faces only | 3973 → 3975 | 0.86x | 0.89x | 1.0x | 0.88x |
| prose (3 pages), system faces only | 1815 → 997 | 0.65x | 0.71x | 0.94x | 0.68x |

The real-vocabulary prose is a scratch fixture, not committed: dev-log
English set one `Tj` per 88-character line in unembedded Helvetica. The
synthetic `test_corpora` documents draw every word from the same 26-word
list, so they flatter any word cache. Treat that row as a ceiling, not as
evidence. The web harness's text scenarios use the same generator.

A repeat of the first two rows later the same day, with the same method and
7 rounds on a machine at a load average near 80, agreed on everything except
the cad-labels warm replay. That row came out at 0.87x, so treat its 1.10x
as noise around 1.0. The other figures: cad-labels cold 175 → 31 ms (0.18x),
raster 1.88x, cold replay + raster 0.36x; prose cold 374 → 200 ms (0.53x),
warm 0.90x, raster 1.02x, cold replay + raster 0.59x.

By commit:
- The typed key and matrix fill alone: warm replay 0.81x on the real-world
  set and 0.78x on cad-labels (7 rounds each), with cold within noise.
- Composition takes cad-labels from 3973 builds to 15.
- The piece cache, on top of composition, takes the 20-page prose from 11184
  builds to 5402 (cold replay 0.61x).

Memory: `/usr/bin/heap -s` on the tester process after one pass over the
pages, and again after `clearTextLayoutCache`. The difference is what the
text caches hold natively. It was identical across two runs of each.

| pass | base | patched |
|---|---|---|
| real-vocabulary prose, 40 pages | 313 MB | 169 MB |
| text-report-40p, 40 pages | 235 MB | 3.7 MB |
| cad-labels-6p, 6 pages | 66 MB | 0.2 MB |
| private real-world corpus, 5 docs × 8 pages | 34 MB | 25 MB |

Pixels: DPR-2 rasters of base and patched compared byte for byte on 21
pages: cad-labels, text-report, annotated, letterhead, styled-booklet (3
pages each), pdf.js `standard_fonts` and the prose fixture. Each page was
rendered once from empty caches and once from caches warmed by the other
pages. All 42 rasters were identical with the bundled faces, and all 42 were
identical again with the system Helvetica, Times New Roman and Courier New
standing in for them. A repeat at DPR 1, 2 and 3 matched on all 126
rasters in each font configuration. The same check on the private corpus
(bundled faces, DPR 2): 30/30 identical on 15 pages, and 86/86 on a second
pass over 43 pages of its unembedded-font documents.

Composition is not bit-exact in general, though. A randomized sweep drew
1,800 synthetic gate-shaped labels one at a time, at DPR 1, 2, 3 and 4. The
labels used a random substitute and style, sizes of 3-33 pt, one in six
rotated, one in three with jittered offsets so pieces get cut, and some
Tc/Tw. With the bundled faces, 5 of the 7,200 renders differed from base;
with the system faces, 2 of 7,200. Each difference is one glyph of one label
(27-452 pixels, max channel delta 46-79), and it shows up in monospaced
Courier too, which cannot kern. What differs is float rounding. A composed
glyph's origin reaches the canvas as one summed offset, while the shaped
piece adds each glyph's position inside the paragraph to the piece's origin
separately. Once in a while that tips a glyph into the neighbouring subpixel
position: the differing glyph's ink centroid moves about a quarter of a
device pixel sideways (0.24 px at DPR 2) and not at all vertically. The same
sweep over mixed text (lowercase words, kerning pairs, Adventor, Carlito,
Tc/Tw, the odd gate-shaped word) was identical on all 7,200 renders. Making
composition bit-exact would mean reproducing the engine's own order of float
operations from Dart, which it does not expose. #454's per-glyph
composition places its glyphs the same way.

## Gotchas

- **flutter_tester answers any unregistered font family with its kern-free
  test font**, including the *first* name in a `fontFamily` + fallback list.
  So a test can't reach a later fallback name, and the render suites
  (Ghent, pdf.js) draw substituted text in the test font, which has no
  kerning for composition to lose. To test a kerning face, register it under
  the substitute's own package family (`substituted_piece_compose_test`), and
  do the same with the system faces to measure a "no bundled assets" host.
- **The composed pieces add draw calls.** Composition brings back #454's
  per-glyph draw pattern for gate-shaped pieces: on cad-labels the software
  rasterizer in flutter_tester takes about 2x longer per raster of the
  recorded picture. First paint is still 2.8x faster, but a picture that gets
  rasterized many times (zoom settles) gives some of that back: roughly +6
  ms per page per raster here, and 1.17x raster on the private CAD sets. GPU
  backends (Impeller, SkWasm) weren't measured, and neither was the real-Chrome
  harness. No web gain is claimed.
- `debugTextPainterBuilds` counts the kern probe's two builds per face.

## Files

- `packages/dart_pdf_editor/lib/src/canvas_device.dart`: `_RunLayoutKey`,
  `_toFloat64`, `_glyphKeySuffix`, `_buildPlacedLayout`, `_composableSpan`,
  `_kernFreeFace` / `_probeKernFree` / `_kernProbe`, `_pieceCache`,
  `debugPieceLayoutCacheLength`.
- Tests: `per_glyph_text_test` (unique multi-character labels compose, glyph
  cache overflow inside one run), `text_cache_test` (exact/NaN keys, shared
  pieces and their lifetimes), `substituted_piece_compose_test` (real Heros
  composes pixel-identically, Adventor and a kerning stand-in never compose).
- `app/tool/perf_harness/lib/harness.dart` reports `pieceLayoutCacheEntries`.
