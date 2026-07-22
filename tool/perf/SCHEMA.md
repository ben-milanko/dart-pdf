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
                               // gate-counters
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
