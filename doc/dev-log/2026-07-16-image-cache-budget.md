# Tuning the decoded-image cache budget (issue #281)

`PdfImageCache.instance` was a flat `256 * 1024 * 1024` on every platform, a
number nobody had ever measured. This session measured it on native and web,
then replaced the constant with a platform-aware default and wired the
memory-pressure signal the class doc had been claiming for months.

## The mental model the numbers argue for

**The budget is a ceiling, not a reservation.** A document whose images decode
to 40 MB costs 40 MB under any budget. Raising the budget only changes
behaviour for documents that *exceed* it - and for those, the cache only pays
off when it can hold the *whole* working set. LRU under a linear scan is the
pathological case: each pass evicts exactly what the next pass wants. So a
budget that lands *between* "fits the document" and "small" is the worst place
to be - it costs RSS proportional to itself and buys almost nothing.

That reframes the whole question. Don't ask "how much memory can we afford?";
ask "how big is a document we want to hold outright?"

## What was measured

Harness: `packages/dart_pdf_editor/test/benchmark_image_cache_budget_test.dart`
(two tests, both skipped unless their env var is set - not CI).

### Corpus footprint - the number that picks the budget

`PDF_FOOTPRINT_DIR=../../corpus`, 49 real-world PDFs, decoded footprint of the
first 40 pages of each:

| budget | documents held whole |
|--------|----------------------|
| 16 MB  | 33/49 (67%) |
| 32 MB  | 37/49 (76%) |
| 64 MB  | 43/49 (88%) |
| 128 MB | 46/49 (94%) |
| 256 MB | 47/49 (96%) |
| 512 MB | 47/49 (96%) |

The curve is flat past 128 MB: 256 MB buys exactly one more document, and past
that the only documents left are `Combined Design Pack.pdf` (1881 MB of RGBA)
and `ly9-far-cad.pdf` (1183 MB), which no sane budget holds.

### Budget sweep on the ticket's document

The reader-reported file (`8100_Time_Without_Tide_Quickstart.pdf`, 62 pages,
24 MB, **436 MB** of decoded RGBA across 314 unique images) - so every budget
below is pegged and evicting. `PDF_BENCHMARK_PDF=...`, rendered at 1x:

Reading straight through (one pass):

| budget | hit rate | decodes | render | RSS after |
|--------|----------|---------|--------|-----------|
| 16 MB  | 0.0%  | 742 | 249 ms/pg | 493 MB |
| 64 MB  | 34.1% | 489 | 180 ms/pg | 512 MB |
| 128 MB | 51.6% | 359 | 147 ms/pg | 581 MB |
| 256 MB | 57.4% | 316 | 145 ms/pg | 679 MB |
| 512 MB | 57.7% | 314 | 156 ms/pg | 658 MB |

**128 → 256 MB buys 2 ms/page and costs ~100 MB of RSS.** (The ticket's
"282 MB / 247 images" differs from 436 MB / 314 because that figure came from
the app, where the worker caps images to display resolution; this sweep decodes
at full resolution.)

Re-reading (3 passes - where a fitting cache should pay):

| budget | hit rate | decodes | render | RSS after |
|--------|----------|---------|--------|-----------|
| 64 MB  | 34.5% | 1459 | 205 ms/pg | 500 MB |
| 128 MB | 52.2% | 1065 | 164 ms/pg | 490 MB |
| 256 MB | 58.8% | 916  | 149 ms/pg | 654 MB |
| 512 MB | 85.9% | 314  | 113 ms/pg | 891 MB |

512 MB holds the document whole: **314 decodes across 3 passes - zero
re-decodes**. That is the cliff. 256 MB, stuck mid-cliff, gets a fifth of the
benefit for a quarter of the memory.

### Web: the ticket's hypothesis was wrong

The ticket suspected the budget was sharper on web ("a tab OOM under this
budget is plausible but unmeasured"). Measured, it is not the cache.

Driver: `app/tool/perf/driver.mjs` now probes
`performance.measureUserAgentSpecificMemory()` (the only API that counts
CanvasKit's wasm heap, not just the JS heap - it needs cross-origin isolation,
which the server already sends) and Chrome runs with `--expose-gc` so the
figures are retained memory, not uncollected garbage. `PERF_IMAGE_CACHE_MB`
sweeps the budget via a URL param.

62-page scroll of the same document, tab memory by budget:

| budget | agent memory | image cache |
|--------|--------------|-------------|
| 32 MB  | 2136 MB | 25 MB |
| 64 MB  | 2136 MB | 62 MB |
| 128 MB | 2138 MB | 122 MB |
| 256 MB | 2328 MB | 191 MB |
| 512 MB | 2238 MB | 184 MB |

The budget barely moves the total. What does move it is **pages scrolled** -
at a fixed 64 MB budget: 10 pages → 1122 MB, 20 → 1465 MB, 40 → 1972 MB,
62 → 2286 MB, while the cache stays pinned at ~60 MB. Controls: a 1-page
render of the same document is 370 MB, and a tiny PDF is 128 MB, so the probe
does respond.

So a tab does approach its ceiling (2.3 GB against a ~4.2 GB
`jsHeapSizeLimit`), but the image cache is ~3% of it. **Filed as #283** -
~20 MB/page of per-page retention on web. The budget is not the lever there.

## What shipped

`pdfDefaultImageCacheBytes()` in `performance_policy.dart` (next to the
platform detection that was already there; `PdfPerformanceEnvironment.detect`
now shares the new `detectedPdfPerformancePlatform` instead of a second copy of
the same switch):

- **desktop 256 MB** - unchanged, but now defended: holds 96% of the corpus
  whole, and ~700 MB RSS is affordable where a machine has tens of GB.
- **mobile 128 MB** - still holds 94% outright; on documents it cannot hold,
  the ~100 MB it returns matters under an iOS jetsam limit far more than
  2 ms/page does.
- **web 128 MB**, dropping to **64 MB** when `navigator.deviceMemory` <= 2 GB.
- **other 128 MB**.

`maxBytes` is now settable (trims immediately) so a host that has profiled its
own documents can override at startup; `bytes` is public occupancy (it pairs
with the public budget, and the perf harness needs it from another package).

### Two `navigator.deviceMemory` traps, both verified in Chrome 141

Read defensively in `performance_memory_web.dart`:

- It only exists in a **secure context**, and only in Chromium - Firefox and
  Safari have never shipped it. `package:web` types it as a non-nullable
  `double`, so reading it blind on a plain-http page hands back a bogus value
  instead of null. The code probes for the property first.
- **The widely-cited "clamped to 8" is out of date**: a 16 GB host reports
  `16`. Don't read 8 as the maximum.

There is no total-RAM API on the VM side (`dart:io` gives you your own RSS,
not the machine's), so native falls back to the platform tier - which is the
distinction that matters anyway.

### Memory pressure

`_PdfViewerState` is now a `WidgetsBindingObserver` and implements
`didHaveMemoryPressure` (iOS/Android only; the web never sends it): it clears
`PdfImageCache.instance` and its own `_previews`. Every cache here hands out
clones, so dropping masters cannot pull pixels from a painting picture, and
on-screen pages keep their retained scenes. Several viewers mounted at once
each clear the process-wide cache - the second call is a no-op. The observer is
removed in `dispose`, and there is a test for exactly that (an unmounted viewer
that still answered pressure would be a leak).

Left alone deliberately: `PdfThumbnailCache` (256 entries, no byte budget) -
its tiles are on screen, so clearing them under pressure is churn, not relief.

## Gotchas for next time

- `ui.decodeImageFromPixels` never completes inside `testWidgets`' fake-async
  zone. Any cache test that builds a real `ui.Image` under `testWidgets` must
  wrap it in `tester.runAsync` or the test hangs with no output at all.
- Under `flutter_test` the platform reports as **mobile** (android), so the
  default budget in tests is 128 MB, not the desktop 256 MB.
- The budget benchmark warms every lazy structure with an unbounded pass before
  measuring, so the sweeps differ only in their budget - without it the first
  budget measured wears the font/xref warm-up cost.
