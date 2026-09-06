# Perf result envelope — schema v1

Every perf suite in this repo emits **one JSON envelope per run**. History
files (`tool/perf/history/*.ndjson`, and `history/<suite>.ndjson` on the
`perf-data` branch) hold one envelope per line. The envelope **extends** the
original `benchmark/` schema: the legacy top-level fields (`tool`, `scale`,
`maxPages`, `engine`) and the `results` array keep their exact old meaning,
so `benchmark/compare.py` consumes enveloped files unchanged (it ignores
unknown keys).

```jsonc
{
  "schema": 1,
  "suite": "vm-sweep",         // vm-sweep | vm-interpret | flutter-render |
                               // chrome-scroll | chrome-open | chrome-search |
                               // chrome-edit | web-renderer | pdfium |
                               // chrome-pdfium-parity | gate-counters
  "scenario": "ghent-suite-open", // named workload from scenarios.json, or null
  "tool": "dart-pdf-sweep",    // legacy field, unchanged semantics
  "engine": "dart-pdf (VM, NullDevice interpret)",
  "scale": 2,                  // legacy, when the suite rasterizes
  "maxPages": 10,              // legacy
  "params": {},                // suite-specific knobs (repeat, timeoutS, ...)
  "rev":  { "sha": "...", "branch": "main", "dirty": false, "date": "..." },
  "env":  { "os": "macos-arm64", "osVersion": "...", "cpus": 10,
            "dart": "3.9.0", "ci": false, "runner": "local" },
  "ts": "2026-07-18T09:00:00.000Z",
  "metrics": {                 // run-level aggregates; dashboards read ONLY
                               // this - never re-derive from results
    "files": 25, "errors": 0,
    "p50OpenMs": 1.2, "p95OpenMs": 9.8, "maxOpenMs": 14.0,
    "p50InterpretMsPerPage": 30.1, "...": "suite-specific"
  },
  "results": [                 // one row per file; every timing OPTIONAL -
                               // each suite fills what it measures
    { "file": "x.pdf", "pages": 10, "pagesRendered": 10,
      "openMs": 1.2,           // best-of-N (matches legacy tools)
      "firstPageMs": 8.0, "interpretMs": 30.1, "renderMs": 45.6,
      "extractMs": 4.0, "saveMs": 2.1, "peakRssBytes": 91234304,
      "decodeMs": 210.4,       // only with the `decodeImages` measure
      "imagesDecoded": 32,     // images the pages drew, alongside decodeMs
      "error": null,
      "perf": { "phases": {}, "counts": {}, "events": {} } // PdfPerf
                               // snapshot when the run passed --phases
    }
  ]
}
```

Rules:

- All times are milliseconds, **best-of-N** within a run (N = `params.repeat`).
- Per-file result fields are optional; consumers must skip rows lacking the
  metric they want (and rows with `error != null`).
- `metrics` percentile keys are `p50<Metric>` / `p95<Metric>` / `max<Metric>`
  with the metric capitalized (`p50OpenMs`); per-page rates use the
  `...MsPerPage` suffix.
- Comparisons (`tool/perf/diff.dart`) pair rows by `file` and judge each
  metric by the **median ratio** across files with 3-MAD outlier exclusion.
- `tool/perf/targets.json` holds aspirational per-scenario budgets checked
  against `metrics` — informational only, never a gate.

Producers: `packages/pdf_graphics/tool/perf_sweep.dart` (vm-sweep),
`packages/pdf_graphics/tool/benchmark_interpret.dart` (vm-interpret),
`benchmark/pdfium_benchmark.py` (pdfium),
`app/tool/perf/driver.mjs` (chrome-scroll),
`packages/dart_pdf_editor/test/benchmark_render_test.dart` (flutter-render),
`packages/pdf_graphics/tool/perf_count_gate.dart` (gate-counters).

## `chrome-pdfium-parity` records

The competitive Puppeteer suite stores one envelope containing `runs.dartPdf`
and `runs.pdfium` raw samples, per-engine `aggregates`, and budget entries in
`parity`. Its `params` must include the common page/zoom/scroll/query journey,
transport, viewport, `visualCaptureMode`, and `webBackend`. Visual capture is
part of the experiment identity: CDP `screencast` and full-compositor
`screenshot` runs must not be pooled, nor may JS/CanvasKit and SkWasm runs.
`params.webDirectory` records the bundle directory actually served; the
competitive runner uses `PERF_WEB_DIR`, then `PERF_BUILD_OUTPUT`, then the
default build directory in that order.
`visualCaptureMode: none` is diagnostics-only: its visual values are invalid,
its `parity` list is empty, its parity ratios are omitted, and the runner
refuses to use it with `--gate`. `env.graphics` records the Chrome GPU device,
display/Skia backend, and feature-status map so a hardware Metal/Vulkan run
cannot be silently compared with a software renderer.

Cold open reports logical-ready, engine-ready, first stable visual, and final
stable visual times. Page and zoom stages retain engine-ready, first-change,
and final-stable raw samples; budgets use the final-stable p50/p95 values.
Whole-browser RSS is the Chrome process-tree aggregate, not only the renderer
process or Dart heap. Engine-specific Flutter timings live under
`runs.dartPdf[].diagnostics` and never substitute for common visual metrics.
`flutterFramesByAction` retains raw `{s,b,r,t}` frame timings (vsync start,
build, raster, and total milliseconds) for cold open and
for each page, zoom, and wheel action, so a visual tail can be attributed to
Flutter build/raster work without pooling unrelated idle or later frames.

Long-document samples may additionally contain:

- `warmOpenFirstVisualMs` / `warmOpenVisualStableMs` for a same-process reopen;
- `scrubFirstVisualSamplesMs`, `scrubSamplesMs`, and
  `scrubRafIntervalsMs` for normalized scrollbar-thumb jumps;
- `browserOpenRssBytes`, `browserPeakRssBytes`, and
  `browserSettledRssBytes`, with the peak sampled continuously through the
  journey rather than inferred from its final point.

Range-backed samples keep both application and document clocks:

- `documentRequestOffsetMs` is navigation to the first `/perf.pdf` request;
- `documentFirstVisualMs` / `documentVisualStableMs` begin at that request;
- `navigationFullyLoadedMs` is the raw navigation-relative completion, while
  `fullyLoadedMs` is first-request-relative;
- `openNetwork` and `network` contain `{bytes, requests}` at stable first paint
  and complete handoff. Their aggregates are `openNetworkBytes`,
  `totalNetworkBytes`, `openNetworkRequests`, and `totalNetworkRequests`.

Request-count ratios are not percentages: a value of `6` means six DartPDF
requests for every one PDFium request. Byte and request amplification have
independent budgets. For range scenarios, `open*` remains a reported cold-app
diagnostic while `document*` is the matched transport/document gate.

`tool/perf.sh pdfium-gate` runs the four representative content shapes plus the
long-CAD and progressive-CAD scenarios with one shared build and fails if any
`parity` entry is false. It currently pins the default-off SkWasm
`domSurface=1` experiment, so it is that experiment's regression gate—not
evidence that the default viewer or every platform has reached PDFium parity.
