# Inactive overprint and region replay

A locally supplied 42-page engineering PDF has a 14,400 × 842 pt opening
sheet. Its visible drawing sits in annotation appearance streams and records
216,886 commands. Ten commands explicitly disable both fill and stroke
overprint, split between OPM 0 and OPM 1. The region index rejected every
overprint command, so even a small detail region replayed the entire sheet.

The safety scan now permits a reset when both flags are false. OPM has no
effect in that state. A command enabling either flag still declines the whole
index, including inside soft-mask lists and tiled cells. The unit builder
can omit the inactive reset because region replay starts with a fresh device
whose overprint flags are already off. No index/wire-format change is needed.

## Local measurements

Flutter 3.47.8 on Linux, headless software rasterization, 2 px/pt. Each region
is 256 × 192 page-view points at y=300. Medians cover three samples after a
discarded warmup pair; full/selective order alternates. Each timed sample
includes Canvas replay, rasterization and RGBA readback. Both routes use the
same retained scene and decoded images. Every sampled image is byte-identical.

| Region x | Full commands | Selected paint commands | Full median | Selective median |
| --- | ---: | ---: | ---: | ---: |
| 100 | 216,886 | 1 | 244.499 ms | 8.350 ms |
| 1,300 | 216,886 | 6,575 | 176.003 ms | 49.486 ms |
| 2,500 | 216,886 | 261 | 195.592 ms | 2.968 ms |
| 3,800 | 216,886 | 459 | 199.570 ms | 7.401 ms |
| 6,000 (blank) | 216,886 | 0 | 178.591 ms | 0.768 ms |

The one-time index build took 268.857 ms and its estimated retained size was
12,721,676 bytes. Those costs are reported separately, outside the per-region
times. Dense worker transcripts cache this index for subsequent detail requests.
These are retained-region measurements, not whole-app latency or initial-open
measurements. The editor's separate live annotation-appearance layer is unchanged.
The supplied PDF and its rendered drawings remain local and are not test assets.

## Reproduction and checks

From `packages/dart_pdf_editor`, use a local PDF path:

```sh
PDF_PATH=/path/to/file.pdf PDF_PAGE=0 PDF_REGION_REPEAT=3 \
PDF_REGIONS='100,300,256,192;1300,300,256,192;2500,300,256,192;3800,300,256,192;6000,300,256,192' \
PDF_REGION_OUT=/tmp/region-replay.json \
  fvm flutter test test/benchmark_region_replay_test.dart
```

`atomic_region_replay_test.dart` covers inactive resets in both OPM modes,
linear/grid/wire culling, nested masks and tiled cells, exact high-zoom pixels,
and conservative fallback for active fill/stroke overprint even if later reset.
The worker-index, grid, spatial-corpus and wide-CAD suites exercise the shared
index across the render seam. All selected PDF.js spatial-corpus pages can now
cull; their old minimum-fallback assertion depended on inactive resets being
incorrectly treated as unsafe.
