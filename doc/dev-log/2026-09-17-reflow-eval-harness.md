# A ruler for reading-view reflow, and the first thing it found

Reading-view reflow — `PdfTextExtractor.reflowPage` feeding `PdfReflowView` —
had no measurement. Every change to the line-banding, column-clustering and
paragraph-splitting heuristics in `text_extraction.dart` was judged by opening
a PDF and looking at it. That is fine for a first cut and useless for getting
to state of the art, because the failure modes are invisible one document at a
time: a column detector that is right on your test file and wrong on
three-column layouts looks identical from the armchair.

This session built the ruler, baselined it, and fixed the first bug it found.

## Why the corpus is generated, not annotated

The obvious ground truth for reading order is a tagged PDF: `/StructTreeRoot`
says what is a heading, what is a paragraph, what is an artifact, and in what
order to read it — and we already parse it (`PdfStructTree`, `PdfTaggedText`,
`PdfExtractedRun.mcid`).

So I scanned every checked-in corpus for one. **Three of 242 files** carry a
structure tree (`pdfjs/smaskdim.pdf`, `pdfjs/type4psfunc.pdf`, and
`pdfjs/bug816075.pdf`, whose tree is empty). That is not a measurement set.

So the corpus is synthesized instead, and the truth is recorded by the
generator rather than annotated afterwards: the same pass in
`tool/reflow/corpus.dart` that writes a block's content-stream operators
appends the `ReflowTruthBlock` describing it — role, text, bounds, reading
index. Truth and bytes are emitted together, so they cannot drift.

That is only worth anything if the generator is itself correct, so the gate
test checks the fixture before it scores anything: for every page, the truth's
words must equal the drawn words **as multisets** (a duplicated line cannot
hide behind a set comparison), nothing may be drawn outside the page box, and
no two text runs may overlap. All ten documents pass, which is what makes the
scores attributable to the pipeline rather than to a broken fixture.

Ten documents, each built to break one assumption: `simple-report` (running
head/foot and page numbers that must *not* be read), `two-column`,
`three-column-news`, `justified-kerned` and `justified-wordspaced`,
`nested-lists`, `table-ruled` and `table-borderless`, `figures-captions`
(raster *and* vector), `footnotes`.

## Seven metrics, not one

`tool/reflow/scoring.dart` reports `textAccuracy`, `readingOrder`,
`segmentationF1`, `artifactRejection`, `listF1`, `headingF1` and
`figureRecall` separately, plus split/merge rate as diagnostics. They are kept
apart because they fail apart: a pipeline can score 1.0 on words and 0.4 on
order — that is a column bug, and a single blended number would hide exactly
the thing worth knowing. The scorer takes neutral `ReflowPredictedBlock`s, not
`PdfReflowPage`, so a later structure-tree or layout-model path is scored on
the same ruler as today's geometry.

One detail worth recording: **scoring headings required restating a rule that
lives in the widget.** `PdfReflowBlock` has no role — the "this is a heading"
decision is a font-size ratio inside `_styleFor` in `pdf_reflow_view.dart`. The
eval reproduces it in `predictReflow`. That the model carries no semantics at
all is the finding, not an oversight in the harness.

## The bug: justification by kerning erased every space

`justified-kerned` scored **0.232 textAccuracy**. The page came back as
`Fontsareembeddedasprogramswhoseglyphdescriptions…`.

Plain extraction was fine — the fixture check compares against
`PdfTextExtractor.extract` and passed. The loss was in the reflow layer alone.

`_lineFrom` assembled a line by writing `piece.text.trim()` and then
re-deriving the spacing from geometry: insert a space when the gap between one
run's right edge and the next run's left edge exceeds `fontSize * 0.18`.

Text justified by spreading slack over per-gap `TJ` kerns — what LaTeX and
InDesign emit — arrives as one run per word with the space carried *inside*
the run:

```
x=72.0..98.3  "Fonts"
x=98.6..116.6 " are"
x=116.9..169.5 " embedded"
```

The boxes touch. The gap is 0.3pt against a 1.89pt threshold, so no space was
synthesized — and the space that *was* drawn had already been trimmed away.
Every justified-by-kerning document in the world read as one run-on word in
the reading view.

The fix is to stop throwing the information away: a space the page actually
drew settles the question, and geometry only gets asked when neither side drew
one. Ten lines in `_lineFrom` plus a `_drewSpaceBetween` helper.

`justified-kerned`: text 0.232 → 0.990, segmentationF1 0.083 → 0.833, overall
0.511 → 0.721. It now scores **identically to `justified-wordspaced`** on every
metric, which is the real confirmation — the two files are the same prose
justified two different ways, so any difference between them was always the
pipeline's fault, never the document's.

The fix also *moved a metric down*: `justified-kerned.readingOrder` 0.764 →
0.727. That is not a regression. With the text mangled, fewer blocks matched a
truth block at all, so fewer entered the ordering sequence and the ordering
errors that were already there went uncounted. The wordspaced twin scores
0.7273 too. This is the case the baseline workflow exists for — re-baseline
deliberately and review the diff.

## Where the pipeline actually stands

Pooled means after the fix:

| metric | score |
| --- | --- |
| textAccuracy | 0.786 |
| readingOrder | 0.780 |
| segmentationF1 | 0.746 |
| artifactRejection | 0.500 |
| listF1 | 0.878 |
| headingF1 | 0.420 |
| figureRecall | 0.967 |

The weak numbers say what the next phases are, and now they say it with
evidence:

* **artifactRejection 0.500** — there is no header/footer detection at all.
  Every document that has a running head reads it into the text, once per
  page, and scores 0.000. Cross-page repetition detection is the classic cheap
  fix.
* **headingF1 0.420** — no role model, plus headings are routinely merged into
  the paragraph beneath them (`_startsParagraph` compares leading and left
  edge, and a heading sitting on the body's left margin with normal leading
  looks like a continuation).
* **segmentationF1 0.746 with split 0.920 / merge 0.619** — blocks are both
  over-merged and over-split, which is the paragraph detector running on two
  thresholds and no notion of what a block *is*.
* **three-column-news text 0.237** — column clustering falls apart at three
  columns; lines are being merged across gutters. `_orderLines` bails to
  `_topDown` whenever it cannot find two confident columns, and top-down
  across three columns interleaves them.
* **table text 0.548** — table cells are read as prose. Unchanged between the
  ruled and borderless variants, which confirms nothing looks at the rules.
* **figureRecall 0.967** — only `figures-captions` loses anything, and it loses
  exactly the vector figure. `PdfReflowImage` wraps a `PdfImageRequest`, so
  artwork drawn as paths cannot be surfaced at all.

## Using it

```sh
cd packages/pdf_graphics
fvm dart run tool/reflow_eval.dart                      # table + gate
fvm dart run tool/reflow_eval.dart --only two-column
fvm dart run tool/reflow_eval.dart --json
fvm dart run tool/gen_reflow_corpus.dart                # regenerate corpus
fvm dart run tool/reflow_eval.dart --update-baseline    # re-baseline
```

`test/reflow_eval_test.dart` runs the fixture checks, the metric unit tests,
and the baseline comparison in CI.
