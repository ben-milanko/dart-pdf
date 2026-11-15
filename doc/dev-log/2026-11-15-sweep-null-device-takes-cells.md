# 2026-11-15 - The sweep's null device takes tiled cells whole

The VM sweep interprets every page into a `NullDevice` and reports
`interpretMs`. For two scenarios most of that number was the harness.

## What it was

When the interpreter fills a tiling pattern (#524) or shows a Type3 glyph
(#535) it records the cell once and hands it to the device as one
`PdfDrawTiledCellCommand` - if the device is a `PdfTiledCellSink`. Otherwise
it replays the recorded cell once per tile through a `TranslatingPdfDevice`.

Every device the library points an interpreter at is a sink: the recorder,
the streaming writer, the canvas, the image collector, the text extractor.
The sweep's `NullDevice` was not, so it took the fallback - and since it
answers every call through `noSuchMethod`, each replayed command also built
an `Invocation`.

Profile of `hatch-sections-4p.pdf` into the old `NullDevice`: 87% of the
time in `replayCommands`, 44% in `NullDevice`'s own dispatch. Nothing in the
product does that work at interpretation time.

(The per-tile expansion itself is real - `replayCommands` does it for a
device that is not a sink, such as the browser canvas device or vector
print. But that is replay cost, paid from a recording, and the real-Chrome
harness's `scroll-hatch` is where it shows.)

## What changed

`NullDevice` in `perf_sweep.dart` implements `PdfTiledCellSink` with an empty
`drawTiledCell`. One class, one method.

| scenario | interpretMs before | after |
|---|---|---|
| hatch-sections-sweep | 158 - 165 ms | 27 ms |
| type3-text-sweep | 48 ms | 25 ms |
| dartpdf-corpus (18 files) | 697 ms | 623 ms |

`firstPageMs` moves with it (hatch 40 -> 7 ms). `extractMs`, `openMs` and
the image measures do not use this device.

## What this does to the trend

- **Nightly history** (`perf-data`): these scenarios step down on the night
  this lands. That step is the harness, not the code; the hatch scenario's
  note in `scenarios.json` says so.
- **Ratio checks and `perf.sh diff`**: unaffected as comparisons.
  `perf_diff.sh` grafts the *current* `perf_sweep.dart` onto the baseline
  commit, so both sides run the same device.
- **Sensitivity**: better. A change to pattern-cell recording used to be
  buried under 6x its weight in replay; a change to the replay loop used to
  show up as a win no reader would see.
- **Backfill**: `backfill.sh` grafts this file onto old commits, and one
  that predates `PdfTiledCellSink` (#524, July 2026) cannot compile it. The
  file already uses newer API than that (the `decodeImagesAtTarget` measure,
  September), and backfill reports such refs as "failed (API drift?); skip",
  so this adds no ref that worked before.

Left alone on purpose: `perf_count_gate.dart` has its own `NullDevice`, and
its counters are a checked-in baseline - changing the device there is a
re-baseline, which is a separate reviewed step. `_ImageCollectingDevice`
(the `decodeImages` measures) still receives a cell's images through the
expansion, which is what it wants.
