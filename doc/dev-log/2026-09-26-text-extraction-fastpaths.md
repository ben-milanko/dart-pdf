# Text extraction fast paths: textless cells, LTR BiDi pre-scan, direct bounds, CJK scan

Three output-identical changes to `packages/pdf_graphics/lib/src/text_extraction.dart`,
one commit each. `_pageTextFrom` serves both fresh extraction
(`PdfTextExtractor.extract`: worker search on pages it has not recorded, the
UI-isolate hover/selection `_pageText` for pages up to 512 KB of content,
compare, text diff, struct text) and `fromRecordedText` (worker search and
selection on pages it has already recorded, via `PdfWorkerTextCache`). Nothing
here touches the render, record, scroll or save paths.

## 1. Textless tiling and Type3 cells are skipped

`_ExtractionDevice` was not a `PdfTiledCellSink`, so the interpreter's two
sink probes (tiling fills in `_fillWithTilingPattern`, cached glyphs in
`_drawType3Glyph`) took their non-sink branch: replay the recorded cell once
per tile through `TranslatingPdfDevice`, which rebuilds every translated path,
for a device whose `fillPath`/`strokePath` do nothing. On
`hatch-sections-4p` that is 298,568 tile replays and 1.25M device commands
over four pages, to find no text at all.

The device is now a sink with a `required bool collectImages` (false from
`extract()`, true from `reflowPage()`). A per-device
`Map<List<PdfRenderCommand>, bool>.identity()` answers "can this cell produce
anything I keep": a `PdfDrawTextCommand`, a `PdfDrawImageCommand` when
collecting images, or a nested `PdfDrawTiledCellCommand` (with origins) whose
cell can. It never descends into `PdfEndSoftMaskedCommand.maskCommands` -
`endSoftMasked` never runs `drawMask` - which is the same rule
`PdfRecordedText.capture` already applies. A needed cell replays with the
exact expansion `replayCommands` gives a non-sink device (origin (0, 0)
verbatim, the rest through `TranslatingPdfDevice`, in origin order), so runs,
order and floating-point translations are unchanged.

Gotchas:

- Being a sink also routes **Type3 glyph cells** here (one origin per glyph
  occurrence). Vector glyphs are skipped for both paths; bitmap (ImageMask)
  glyphs are skipped only by `extract()`, because `reflowPage()` keeps
  images. That is where real documents gain.
- With the base-tile check being `dx == 0 && dy == 0` rather than "first
  tile", a non-base tile could only replay untranslated if an invertible
  pattern matrix mapped a non-zero step to exactly zero; the interpreter
  refuses singular matrices and zero steps before it gets there.
- `drawImage` is now a no-op when `collectImages` is false, so the flag means
  the same thing whether an image arrives directly or from a cell.
- Recorded cells are complete before they are drawn, so a cell can't contain
  itself; the memo needs no cycle guard (the recorder builds the nesting).

## 2. Left-to-right lines skip the BiDi pass; bounds without a quad

`_bidiLine` built its per-glyph piece list (substrings, closures,
`glyphs.map(...).join()` per run) for every line just to return null on
left-to-right text. `_mayHaveRtl` now returns early when no code unit on the
line could be RTL. The exactness argument:

- `_bidiKind` yields RTL only for strong R/AL/RLE/RLO/RLI, for the
  supplementary RTL blocks, or for a nonspacing mark with no preceding class
  (`previous ?? rtl`).
- In bidi 2.0.13 every strong RTL class is at or above U+0590; surrogates are
  above it too, so astral RTL is caught.
- The only nonspacing marks below U+0590 are **U+0300-036F and U+0483-0489**.
  A pre-scan on `>= 0x0590` alone is *not* exact: a line starting with a
  combining mark (a macron drawn before its base, a unicode-math accent) is
  classed RTL at HEAD, splits into per-glyph runs and, on a short line,
  reverses its text (`U+0304 x` reads back as `x U+0304`). So those two
  ranges also take the full pass. Changing the `previous ?? rtl` quirk itself
  would be a behaviour fix for another day.
- `text_extraction_test.dart` enumerates `bidi.getCharacterType` for
  0..0x58F, so a bidi upgrade that moves a class breaks a test rather than
  output.

`_boundsOf` now folds the four transformed corners directly, in the same
order and with the same `math.min`/`math.max` as `PdfTextQuad.bounds` (whose
extra first-corner step is `min(a, a) == a`, also for -0.0 and NaN), instead
of allocating a quad, a corner list and records per run. Not extended to
`quadsFor`: its quads are output.

## 3. Closure-free CJK scan

#907's `line.any((item) => item.run.text.runes.any(_isCjkRune))` walked every
rune through a `RuneIterator` and two closures. `_lineHasCjk` walks code
units: every CJK range starts at U+2E80, so one compare rejects almost
everything; a surrogate pair is decoded only when both halves are present, and
a lone surrogate is tested as itself, as the rune iterator yields it (no
surrogate is in a CJK range). A 2M-string randomized comparison against
`runes.any` found no mismatch. After change 2 this scan was most of what was
left of `fromRecordedText` on text-dense pages. A per-run "has CJK" bit set in
the interpreter was rejected: it would move per-glyph work onto the render
path to save an extraction-only cost.

## Numbers

AOT executables built from an origin/main worktree and this branch, run as
alternating processes (ABAB, 7 rounds unless noted), thread-CPU time
(`clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)`), median of per-round
ratios. Wall-clock ratios agreed to within 0.015.

| workload | base | branch | ratio |
|---|---|---|---|
| extract, hatch-sections-4p (4 pages) | 65.5 ms | 2.3 ms | 0.034x |
| reflowPage, hatch-sections-4p | 66.5 ms | 3.1 ms | 0.046x |
| extract, type3-text-6p | 31.1 ms | 15.6 ms | 0.500x |
| reflowPage, type3-text-6p | 42.0 ms | 26.1 ms | 0.621x |
| extract, text-report-40p | 22.3 ms | 15.3 ms | 0.692x |
| extract, styled-booklet-24p | 26.1 ms | 19.4 ms | 0.755x |
| fromRecordedText, text-report-40p | 7.6 ms | 0.8 ms | 0.105x |
| fromRecordedText, 291-page private doc, first 60 pages | 29.7 ms | 11.1 ms | 0.374x |
| fromRecordedText, 344-page private doc, first 60 pages | 20.8 ms | 8.1 ms | 0.389x |
| extract, 291-page private doc, first 60 pages | 98.0 ms | 80.1 ms | 0.815x |
| extract + findAll, 291-page private doc, whole document | 366 ms | 303 ms | 0.831x |
| extract + findAll, 344-page private doc, whole document | 535 ms | 466 ms | 0.868x |
| extract, a real-world Type3 private doc | 6.25 ms | 4.78 ms | 0.772x |
| extract, cad-sheet-8p | 10.8 ms | 10.4 ms | 0.961x |
| extract, plan-set-16p | 86.3 ms | 83.1 ms | 0.961x |

Per commit (5 rounds each, same method):

- Cells (base to commit 1): hatch extract 0.036x, type3-text-6p 0.658x, the
  real-world Type3 doc 0.877x, text-report extract and fromRecordedText 1.00x.
- BiDi + bounds (commit 1 to 2): fromRecordedText 0.286x (text-report),
  0.415x / 0.432x (the two long documents); text-report extract 0.745x.
- CJK scan (commit 2 to 3): fromRecordedText 0.371x (text-report), 0.904x
  (291-page doc); text-report extract 0.921x.

dart2js (`dart compile js -O3`, the worker's level) under node, 7 alternating
rounds, wall time: hatch extract 141 to 8 ms (0.057x), type3-text-6p 0.696x,
fromRecordedText on text-report-40p 7.8 to 0.9 ms (0.122x), text-report
extract 0.679x.

Deterministic reach of change 1 (top-level cell draws the device now skips,
counted from a recording with the extractor's interpreter options):
hatch-sections-4p 298,568 replays / 1,248,811 commands; type3-text-6p 35,128
for extract and 17,704 for reflow (the bitmap glyphs still expand there).
Real-world reach is narrow: 2 Ghent files, 14 small pdf.js files, and 2 of 53
private-corpus documents (154 and 1,583 glyph cells) hit it at all. The hatch
class matters because such pages are tiny (about 3 KB of content), so they
pass the 512 KB hover gate and paid the full cost synchronously on the UI
isolate on first hover.

## Identity

`serializePageText` of `extract()`, `serializePageText` of `fromRecordedText`
(from a `RecordingPdfDevice` walk with `collectCharOffsets`) and a
`reflowPage()` signature (block text, bounds, font size, list flag; image
bounds and transform) were digested per page on both builds: identical on 240
openable test_corpora documents (561 pages; 12 encrypted files fail to open on
both) and 53 private-corpus documents (1,254 pages).

## Files

- `packages/pdf_graphics/lib/src/text_extraction.dart` - `_ExtractionDevice`
  (sink, `collectImages`, `_needsCell`/`_scanCell`, `drawTiledCell`),
  `_interpret(collectImages:)`, `_mayHaveRtl`, `_lineHasCjk`, `_boundsOf`.
- `packages/pdf_graphics/test/text_extraction_test.dart` - the
  `tiling-pattern and Type3 cells` group (extract and reflowPage against a
  plain non-sink collecting device), the `left-to-right fast path` group
  (bidi class enumeration, line-initial U+0304/U+0483, bounds vs quad), and
  the astral U+20000 / lone-surrogate CJK test.

Not done: a text-only interpreter mode (skip path construction and paint
work during extraction). Its measured ceiling on main is about 5% of
extraction on dense vector pages, and reusing the image-scan bounding-box
shortcut for tiling fills would widen tile ranges under rotated pattern
matrices, which extraction (it ignores clips) would turn into extra text.
