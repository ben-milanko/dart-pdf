# Issue 256 render-session benchmark

This change moves only the page-render control plane: visual identity,
invalidation outcomes, full/detail generations, stale-result acceptance, and
hold/scheduler routing. Local rendering, native/web worker protocols, command
replay, retained scenes, strip plans, image decoding, transfer buffers, and
raster caches are unchanged.

## Control-plane updates

Run from `packages/dart_pdf_editor`:

```sh
PDF_BENCHMARK_SESSION=1 \
  fvm flutter test test/benchmark_render_session_test.dart --reporter expanded
```

Detached `c821f29` baseline versus this branch, 9 trials of 300 settled-view
updates after 30 warmups:

| revision | median | per update |
| --- | ---: | ---: |
| baseline | 238,452 us | 794.84 us |
| render session | 235,619 us | 785.40 us |

The 1.2% difference is below run-to-run noise and favors the branch.

## Representative cold/warm rendering

A four-file directory was assembled from the local corpus with one lightweight
vector page, one dense CAD page, one image-bearing page, and one scanned page.
Run from `packages/dart_pdf_editor`:

```sh
PDF_BENCHMARK_DIR=/path/to/four-file-matrix \
PDF_BENCHMARK_SCALE=1 PDF_BENCHMARK_MAX_PAGES=1 \
  fvm flutter test test/benchmark_warmcache_test.dart --reporter expanded
```

| revision | cold | warm |
| --- | ---: | ---: |
| baseline | 66.5 ms/page | 54.2 ms/page |
| render session | 67.6 ms/page | 52.9 ms/page |

Cold moved +1.7% and warm moved -2.4%, within single-run raster variance. The
measured rendering code is byte-for-byte unchanged by this patch.

## Adapter and output parity

The focused adapter suite covers local and isolate recording, scheduler hold,
preview progression, retained-scene replay, worker strip plans, speculative
zoom/pan detail, and web Slug fallback. Corpus/pixel suites and the complete
Flutter package suite remain the final gates.

Live browser transfer-volume, browser memory/allocation, and platform frame-jank
traces require the existing device/browser harnesses and are intentionally a
ready-for-review gate rather than inferred from VM widget timing. The draft PR
must not be marked ready if those downstream measurements expose a regression.
