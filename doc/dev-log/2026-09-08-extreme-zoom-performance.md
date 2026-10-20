# Viewport rendering at 3000–10000%

Follow-up to the [dense-vector parsing and replay work](2026-09-08-dense-vector-pdf-performance.md).
The local engineering sheet is a single 421 × 269 pt page. Its compact worker
transcript contains 77,312 commands, including 24 transparency groups and 16
soft masks. Previously, any group disabled the region index for the entire
page, so a small zoomed viewport replayed all 77,312 commands and could not use
the cached tile path.

## Changes

- Balanced compositing groups are indivisible indexed ranges. Selection
  preserves every command inside a selected group, its entry clips and blend
  mode, and painter order. Bounds come from source paint coverage; a group's
  allocation hint or a soft mask's painted footprint cannot safely bound it.
  Mask transfer functions and backdrop values can reveal source elsewhere.
- A recursive safety check preserves full replay for malformed state stacks,
  overprint, seeded non-isolated groups, and cells whose clip or blend state
  escapes. Shared cells are checked in their incoming blend context. The
  worker index format carries exclusive range ends and rejects old versions.
- Dense pages start using the spatial grid at 32,768 commands. The viewer
  warms that index through its render worker, and worker detail requests reuse
  the same index and budget. The index is still released on memory pressure.
- Small groups can use existing cached tiles. Groups exceeding 1,024 command
  slots, including nested mask/cell commands, retain a single viewport patch
  to avoid repeating a large indivisible group for every tile. The separate
  banded-transcript path also keeps its group fallback.
- The default viewer reaches at least 10000% actual size independently of
  viewport width. Explicit host zoom caps retain their previous behavior.
  The shell adds 3000%, 5000%, and 10000% presets; the tile resolution ladder
  reaches 512 physical pixels per PDF point for high-DPI displays.

## Paired measurements

Native Flutter test engine, 1280 × 800 logical viewport, DPR 2, fixed
2560 × 1600 output. Each region has one warm-up pair and seven measured pairs,
alternating full and selective replay on the same retained scene and images.
These are renderer times, not end-to-end app or browser latency. Readback is
measured separately and excluded from replay + raster below.

| Drawing region | View zoom | Full replay + raster | Selective replay + raster | Speedup |
| --- | ---: | ---: | ---: | ---: |
| Centre | 3000% | 71.78 ms | 19.64 ms | 3.65× |
| Centre | 6000% | 64.77 ms | 10.87 ms | 5.96× |
| Centre | 10000% | 61.28 ms | 4.94 ms | 12.39× |
| Lower junction | 3000% | 69.73 ms | 19.13 ms | 3.65× |
| Lower junction | 6000% | 65.72 ms | 12.44 ms | 5.28× |
| Lower junction | 10000% | 64.05 ms | 10.76 ms | 5.95× |

At 10000%, the centre selects 405 commands and the lower junction 951.
The four mask-heavy regions select 28–107 commands: replay takes 0.30–0.40 ms,
but rasterization remains the larger cost. Their total times improve from
125–172 ms to 74–119 ms. Cached tiles avoid that cost when returning to a
previously visited viewport.

All 18 regions (six locations at three zooms) are genuinely selective and
byte-identical to full replay in every comparison. Grid and linear-index
outputs also match exactly. The grid retains 71,987 units, estimates 6.75 MB,
and took 99 ms to build locally; that one-time build belongs on the worker.
The private input, benchmark JSON and viewport PNGs remain local.

## Reproduction and regression coverage

From `packages/dart_pdf_editor`:

```sh
PDF_PATH=/absolute/path/to/drawing.pdf \
PDF_BENCHMARK_REQUIRE_SELECTIVE=1 \
PDF_BENCHMARK_OUT=/tmp/extreme-zoom.json \
  fvm flutter test --no-pub test/benchmark_extreme_zoom_test.dart
```

The benchmark self-skips without `PDF_PATH`. Its header documents viewport,
DPR, location, zoom and PNG-output overrides. It never allocates a whole-page
raster at extreme zoom.

Regression coverage includes exact pixels for nested masks, knockout, clip
and blend combinations at 3000% and 10000%, plus 13 PDF.js fixtures at ordinary
and extreme zoom. Worker codec and real-isolate tests cover range retention.
A real Canvas widget test uses a generated grouped PDF at 10000% on DPR 3:
one-column panning renders only missing edge tiles; returning to the original
viewport schedules zero new tiles and zero rasterizations. Raster slabs and
cache memory remain bounded.

## Remaining opportunities

The mask-heavy graphics are now raster-bound. Conservative layer bounds or
reusable mask surfaces are candidates for a separate measured change; group
allocation hints must not become clips, and mask backdrop/transfer semantics
must remain intact. The supplied sheet's drawing areas already benefit from
selective replay without that additional compositing work.

Text extraction still interprets the page separately from worker recording.
Sharing extraction-ready text runs could reduce initial preparation time,
provided character advances, bidi order, invisible text and appearance/mask
exclusion remain correct.
