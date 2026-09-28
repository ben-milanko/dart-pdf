# Glyph outline paths: built only where they are read

## What happened

`PdfInterpreter._showText` can bake a run's glyph outlines into one
page-space path (`_glyphOutlinePath`: a new `PdfMoveTo`/`PdfLineTo`/
`PdfCubicTo` per outline segment, plus a `PdfMatrix` per glyph). Two things
read that path:

- a tiling-pattern text fill (`fillText` and `/PatternType 1`), which clips
  the pattern cell through the outlines;
- the colorant buffer's resolve of plain-colour text (`_overprint != null`,
  no pattern, mode not 3/7), which only exists on a page that declares
  `/OP`/`/op` or a DeviceCMYK transparency group.

They never both apply to one run: one needs a tiling pattern, the other no
pattern at all. Before #755 the path was built inside the tiling branch.
#755 (overprint glyph resolve) moved it above both branches so the new
colorant-buffer branch could read it. After that, **every** run in an
embedded-outline font built the path, and almost all of them dropped it
straight away. Text extraction paid too. It runs with
`resolveOverprint: false`, so apart from tiling text it never reads the
path.

## Fix

Each reader builds the path itself, which is the pre-#755 shape
(`interpreter.dart`, `_showText`):

- `tilingFill = fillText && _isTilingPattern(pattern)` is evaluated once.
  The tiling branch builds the path only when `tilingFill && glyphs != null`.
  The substituted-font tiling-colour fallback reuses `tilingFill` instead of
  resolving `/PatternType` again (`doFill` implies `fillText`, so it is the
  same test).
- Inside `mode != 3 && mode != 7 && !paintedAsTiling`, the path is built
  only when `_overprint != null && pattern == null && glyphs != null`.
  Otherwise the run takes the existing em-box `_markTextUnknown` branch,
  which is exactly what a null path did before.

Building at the reader, rather than restating both readers' conditions in a
separate `needsGlyphPath` predicate, means a third reader can't drift out of
sync with the gate.

## Regression guard

The regression lasted a month because nothing watched it:

- the synthetic `test_corpora/dartpdf` documents use non-embedded fonts, so
  the web scenarios and the VM sweep are blind to embedded-outline text
  cost;
- the counter gate counted ops and bytes, not allocations.

Three guards now cover it:

- `PdfPerfCount.glyphOutlinePaths` (pdf_cos `perf.dart`) is bumped in
  `_glyphOutlinePath` (DCE-safe `PdfPerf.add`).
- `perf_count_gate.dart` tracks the counter, and `counters.json` was
  re-baselined deliberately. Only the new key was added; every existing
  counter is unchanged. A re-hoist would move 8 of the 12 gate inputs:

  | gate input | main (re-hoisted) | now |
  | --- | ---: | ---: |
  | fixture:embedded-font | 2 | 0 |
  | ghent GWG010 (OP) | 122 | 61 |
  | ghent GWG050 | 102 | 51 |
  | ghent GWG060 | 114 | 0 |
  | ghent GWG020 (OP) | 154 | 77 |
  | ghent GWG206 | 168 | 84 |
  | ghent GWG230 | 182 | 0 |
  | the other 5 | 0 | 0 |

  On pages with a colorant buffer, the count halves because extraction no
  longer builds the path.
- `interpreter_test.dart` "page-space glyph outline paths" covers three
  cases:
  - an embedded-TrueType page builds 0, for both render and extraction;
  - a tiling-pattern text fill builds 1;
  - the same page with an `/OP` ExtGState builds 1 when rendered and 0
    with `resolveOverprint: false`.

  With only the counter added to main, the first test and the extraction
  half of the third fail (1 instead of 0).

## Evidence

**Identity.** I hashed the render worker's record for up to 30 pages per
file: `drawPage` + `drawAnnotations` with `collectCharOffsets`, then
`serializeCommands` with `imagePlaceholders` and `compactStateScopes`. The
hash also covers the `PdfTextExtractor` output: text, run text, transforms,
start indices and MCIDs. The file set was all of `test_corpora/{ghent,pdfjs,dartpdf}`
plus a 53-file private real-world corpus. **283/283 comparable files are
identical**, and 12 pdf.js fixtures (encrypted/fuzzed) fail identically on
both sides. The pdf_graphics suite and dart_pdf_editor `ghent_render_test`
and `overprint_render_test` pass with no baseline change.

**Census** (same files, up to 30 pages, `glyphOutlinePaths`):

| | main | now |
| --- | ---: | ---: |
| render paths built | 230,478 | 40,269 |
| extraction paths built | 230,472 | 1 (pdf.js pattern text) |
| files building any | 148 | 46 |

In the private corpus, 38 of 53 documents built paths. Only 4 of them have
pages with a colorant buffer, and those pages keep building by design.

**Timing.** The bench is the worker record above on a warm document, first
20 pages. I used AOT builds of origin/main and the branch (Dart 3.13.3), 6
interleaved rounds (order alternates each round) of 5 reps plus 2 warm-up
reps. Each ratio is the median of the per-round paired fix/base ratios of
thread CPU. The machine was heavily loaded (load average 25-70), which is
why thread CPU is the metric and not wall time.

| input | record CPU main -> now | now/main | interpret | serialize |
| --- | ---: | ---: | ---: | ---: |
| pdf.js complex_ttf_font | 1.1 -> 0.7 ms | 0.71 | 0.49 | 1.04 |
| pdf.js bigboundingbox | 1.8 -> 0.9 ms | 0.50 | 0.35 | 1.03 |
| Ghent GWG051 | 0.4 -> 0.3 ms | 0.73 | 0.62 | 1.07 |
| Ghent GWG052 | 0.5 -> 0.3 ms | 0.70 | 0.59 | 1.01 |
| private A | 83.0 -> 47.7 ms | 0.58 | 0.43 | 0.87 |
| private B | 7.3 -> 4.5 ms | 0.62 | 0.47 | 0.98 |
| private C | 40.4 -> 28.9 ms | 0.71 | 0.63 | 0.95 |
| private D | 64.5 -> 46.5 ms | 0.73 | 0.66 | 0.94 |
| private E | 164.4 -> 143.4 ms | 0.88 | 0.85 | 0.96 |
| private F | 24.5 -> 17.7 ms | 0.73 | 0.66 | 0.92 |
| private G | 21.9 -> 12.9 ms | 0.60 | 0.49 | 0.89 |
| private H (few embedded runs) | 45.6 -> 44.9 ms | 0.99 | 0.99 | 0.97 |
| dartpdf styled-booklet-24p | 23.6 -> 23.1 ms | 0.97 | 0.97 | 0.98 |
| dartpdf text-report-40p | 10.6 -> 10.6 ms | 1.00 | 1.01 | 1.00 |
| dartpdf letterhead-report-40p | 9.4 -> 9.4 ms | 1.00 | 1.00 | 0.99 |

The web numbers use the same bench built with dart2js `-O2` (the worker's
level) and run under node, with `process.threadCpuUsage`:

| input | now/main |
| --- | ---: |
| complex_ttf_font (4.9 -> 2.9 ms) | 0.55 |
| bigboundingbox | 0.45 |
| private A (266.6 -> 154.7 ms) | 0.59 |
| private B | 0.59 |
| private D | 0.67 |
| private G | 0.59 |
| GWG051 | 0.87 |
| styled-booklet | 0.97 |
| text-report | 1.03, within the 0.94-1.12 range of its rounds |

Two other AOT kernels:

- Warm `PdfTextExtractor.extract` over 20 pages: complex_ttf_font 0.56,
  A 0.55, B 0.60, C 0.68, D 0.71, text-report 1.02.
- Cold open plus page-0 record, the worker half of first paint:
  complex_ttf_font 0.69, D 0.78, A 0.90. B and C land at 0.95-0.96, where
  opening the file dominates.

Only the record step gets faster. The UI isolate's deserialize, scene build
and raster are unchanged, so time-to-visible improves by the absolute saving
(0.4-35 ms per 20 pages, native, on these documents), not by the ratio.

## Gotchas

- Pages that open a colorant buffer still build the path for every run.
  That is correct, and #755's design; it also covers DeviceCMYK
  transparency-group pages without `/OP` (GWG161/164). A cheaper path for
  those would walk the em-space outlines through the run transform instead
  of materialising page-space segments. That is left for the overprint work,
  not this fix.
- The text-clip block for modes 4-7 still transforms outlines into
  `_textClipSegments` on its own. That is a separate, rare consumer and is
  unchanged here.
- If you add a new reader of the page-space outlines, build the path inside
  that reader and expect `glyphOutlinePaths` to move on the gate inputs it
  touches. Re-baseline on purpose and say why.

## Files

- `packages/pdf_graphics/lib/src/interpreter.dart`: `_showText` and
  `_glyphOutlinePath`
- `packages/pdf_cos/lib/src/perf/perf.dart`: `PdfPerfCount.glyphOutlinePaths`
- `packages/pdf_graphics/tool/perf_count_gate.dart` and
  `tool/perf/baselines/counters.json`
- `packages/pdf_graphics/test/interpreter_test.dart`: "page-space glyph
  outline paths"
