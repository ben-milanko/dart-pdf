# Reflow evaluation corpus

Ten synthetic documents that measure the **reading-view reflow** pipeline
(`PdfTextExtractor.reflowPage` → `PdfReflowView`), plus the ground truth each
was generated with.

Everything here is produced by
`packages/pdf_graphics/tool/gen_reflow_corpus.dart`. The generator records a
block's role, text, bounds and reading position in the same pass that writes
the block's content-stream operators, so `<name>.truth.json` cannot drift from
`<name>.pdf` — and `test/reflow_eval_test.dart` asserts the two agree
word-for-word before it scores anything.

Only 3 of the 242 PDFs in the other checked-in corpora carry a
`/StructTreeRoot`, which is why the truth is generated rather than harvested:
there is no real-world tagged set here big enough to measure against. Tagged
files remain an opportunistic second source through `PdfTaggedText`.

## Contents

| Document | What it is for |
| --- | --- |
| `simple-report` | The easy case, plus a running head, running foot and page numbers that must **not** be read |
| `two-column` | A title and abstract spanning the page over two columns |
| `three-column-news` | Three narrow columns under a spanning masthead |
| `justified-kerned` | Justification as per-gap `TJ` kerns (LaTeX / InDesign) |
| `justified-wordspaced` | The same text justified with `Tw` (Word) |
| `nested-lists` | Bulleted and numbered lists at two depths |
| `table-ruled` | A bordered table, read row-major |
| `table-borderless` | The same table with no rules — the false-column trap |
| `figures-captions` | Raster **and** vector figures with captions |
| `footnotes` | Body text over a rule with small-type footnotes |

## Regenerating

The committed bytes are the measurement contract. Everything is deterministic
(fixed prose, fixed layout arithmetic, no timestamps), so regenerating without
a deliberate change produces no diff.

```sh
cd packages/pdf_graphics
fvm dart run tool/gen_reflow_corpus.dart
fvm dart run tool/reflow_eval.dart --update-baseline   # truth changed, so scores did
```

Review both diffs the way a perf baseline update is reviewed.

## Scoring

```sh
cd packages/pdf_graphics
fvm dart run tool/reflow_eval.dart              # table + check against baseline
fvm dart run tool/reflow_eval.dart --json       # machine readable
fvm dart run tool/reflow_eval.dart --only two-column
```

Metrics and what they mean are documented in `tool/reflow/scoring.dart`.
