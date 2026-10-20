# Page ops, form reads and page loops: linear on flat page trees

`PdfDocument.page(i)` finds a page by walking the tree and trusting each
intermediate node's /Count to skip subtrees. On a flat tree, where every page
is a direct kid of the root /Pages node, that walk is a linear scan of /Kids.
So a `for (i < pageCount) page(i)` loop costs O(n²) whenever the wrapper's page
cache is cold. Flat trees are common: every page op DartPDF performs rewrites
the tree as one flat node, and many producers write one too.

The cache is cold on the wrapper the editing controller holds after any
non-structural revision (annotation, form fill, content edit, rotate, redo).
`withIncrementalUpdate` hands back a fresh wrapper, and
`_tryReconcileIncrementalRevision` never walks it. After open and after a
structural revision, the viewer walks `document.pages` itself, so the first page
op after opening and back-to-back page ops were already linear. Only the first
one after a markup edit paid the cost.

Callers that paid it:

- `_materializedLeaves` (every move, reorder, remove, insert blank, and
  append/insert-from-bytes);
- `_PageImporter.importPages` (insert pages from bytes, duplicate, extract);
- `PdfAcroForm._pages`. `fields` always reconciles orphan widgets through it,
  and the controller drops its form on every revision, so each form fill after
  an edit paid it;
- `PdfAttachments.of`, `PdfTakeoffSummary.of`, `nameAnnotations`, and the
  compressor's resource prune and final validation;
- every caller-side `page(i)` loop in the editor (annotation sidebar,
  redaction-mark checks, count tally, scale adoption).

At 3000 pages one cold `movePage` took ~0.72 s of CPU time. The `pages`
getter's own doc comment already warned that the loop "becomes quadratic".

## A live data-loss bug under the same loop

If an intermediate /Count is too small, the /Count-trusting lookup repeats and
skips pages. With an inner node claiming 1 of its 2 leaves, a cold loop over
leaves 4, 5, 6 returns 4, 6, 6. `_materializedLeaves` fed that into
`_rebuildPageTree`, so a cold `removePage(0)` saved only page 6 and dropped
page 5. `movePage`, `insertBlankPage` and `appendPagesFrom` (from such a
source) lost pages the same way. `pages` collects the true leaf order, so moving
the callers onto it also fixes the bug. `page_ops_test.dart` "an intermediate
/Count that is too small" pins all four operations. Every one of those tests
fails on the old code.

## What changed

1. **Whole-document callers iterate `document.pages`.** That covers
   `page_editor.dart` (`_materializedLeaves`, `_PageImporter.importPages`),
   `form.dart` `_pages`, `attachment.dart`, `takeoff.dart` (whole-document
   path only; an explicit `pages:` subset still looks up its indices),
   `annotation_editor.dart` `nameAnnotations`, and `compressor.dart` /
   `compressor_resources.dart`. Each of these already paid O(n) for
   `pageCount`, so the walk adds only a constant factor.
2. **`page(i)` caches the leaf siblings after a page it finds**
   (`PdfDocument._seedFollowingLeaves`), so forward loops that are not worth
   rewriting stay linear. This covers the editor's sidebar, redaction and
   tally loops, `adoptDocumentScale`, `font_embedder`, and `document_ai`.
   - Seeding runs only on the /Count fast walk, only when the found page is a
     direct kid, and it stops at the first intermediate node. It uses the same
     visited set, so a repeated kid takes no index, and it is capped by
     `_sourcePageCountHint`.
   - **It is exact.** Every seeded entry is the page `page(k)` would have
     returned. A first cut without the bound below was not exact. When the walk enters a subtree
     because of its /Count, a later index follows the same path only while it
     still falls inside that /Count. `_Counter.seedBudget` shrinks to the
     smallest such slack. Without that bound, an overstated /Count before leaf
     siblings, or leaf siblings inside an understated subtree, would seed a
     different page than a fresh lookup returns. `page_cache_test.dart` checks
     every (earlier lookup, later lookup) pair against a fresh single lookup
     on those trees. Removing the bound fails two of those tests.
   - **Its size is limited to the target index.** `page(0)` seeds nothing. A
     lone `page(k)` seeds at most k siblings, so the seed never costs more than
     the scan that found the page. A forward loop misses only at indices
     2^j - 1. An uncapped seed would make a single `page(1)` resolve every
     sibling on a 3000-page tree.
   - `_findPage` now computes `inherited.mergedWith` only for intermediate
     nodes. On a leaf the result was unused, and it cost four resolves plus an
     allocation per kid scanned. Dropping it offsets most of the seed's cost
     on a single mid-document lookup (see below).

## Numbers

Flat `buildMultiPagePdf(n)`, measured on the cold wrapper the app holds:
open, `pages` (as the viewer does), a `rotatePages` revision, then
`withIncrementalUpdate` and `pageCount`. The timed span is the op plus
`saveTail`. All numbers are thread-CPU medians from AOT executables, 5 rounds
interleaved base / fix-1 / fix-1+2, each round a median of 5 reps.

| op | n | base ms | callers only | callers + seed | speedup |
|---|---|---|---|---|---|
| movePage | 300 | 8.56 | 0.26 | 0.25 | 34x |
| movePage | 1000 | 83.0 | 0.77 | 0.72 | 115x |
| movePage | 3000 | 720 | 2.39 | 2.38 | 303x |
| removePage | 3000 | 723 | 2.30 | 2.31 | 312x |
| page(i) loop + annotations | 300 | 7.93 | 7.83 | 0.11 | 72x |
| page(i) loop + annotations | 1000 | 80.7 | 80.3 | 0.28 | 290x |
| page(i) loop + annotations | 3000 | 718 | 714 | 1.04 | 689x |
| form fill after a fill | 1000 | 79.6 | 0.22 | 0.22 | 367x |
| form fill after a fill | 3000 | 718 | 0.77 | 0.77 | 936x |
| append all pages of a fresh source | 1000 | 98.8 | 17.5 | 18.7 | 5.3x |
| append all pages of a fresh source | 3000 | 821 | 95.9 | 99.1 | 8.3x |
| single page(1) | 3000 | 0.003 | 0.002 | 0.002 | ~1x |
| single page(n/2) | 1000 | 0.084 | 0.086 | 0.119 | 0.71x |
| single page(n/2) | 3000 | 0.358 | 0.353 | 0.449 | 0.80x |

The last two rows are what the seed costs. A lone mid-document lookup on a
cold wrapper now also caches up to n/2 siblings. Without the `mergedWith` trim
the same lookup measured 0.15 ms at 1000 pages and 0.57 ms at 3000, about 1.8x
base. With the trim it adds 0.04-0.09 ms, and in exchange every forward loop
is linear. The 1.07x gap between the two append columns is within run-to-run
noise, since the seed plays no part there: the importer now walks `pages`.

The investigation behind this change found the same effect on a private
real-world corpus of flat 291-344-page documents: 9-16 ms per cold page op or
form re-read dropped to about 0.5-1 ms. On dart2js a cold move at 1000 pages
dropped from about 200 ms to about 3 ms.

A second, independent 5-round interleaved run of the same benchmark
reproduced the table within noise (movePage 728.9 -> 2.58 ms at 3000 pages,
page(i) loop 82.1 -> 0.28 ms at 1000, form fill 83.4 -> 0.23 ms at 1000,
append-all 103.6 -> 19.1 ms at 1000, single page(n/2) 0.096 -> 0.127 ms at
1000).

## Identity

Outputs are unchanged on well-formed trees. A scratch harness digested, on
both a fresh wrapper and the cold after-rotate wrapper, every output this
change can reach: `page(i)` in forward and mid-first order (object number,
rotation, media/crop box, resources), a fresh single lookup per index as the
oracle, `pages`, the saved tails of movePage (both directions), removePage,
insertBlankPage, appendPagesFrom (all pages and a reversed subset) and
extractPages, form field names with their widget pages, attachments, the
takeoff summary, nameAnnotations and PdfCompressor output. Over 236 inputs
(the synthetic fixtures, a private real-world corpus and the pdf.js test
suite) base and patched agreed on every digest, except the ones that already
differ between two runs of base (random /NM UUIDs and other per-run values in
a handful of saves). `tool/perf.sh gate` rewrites a byte-identical
`counters.json` with `--update-baseline`, and the Ghent and overprint render
tests pass with no baseline change.

## Gotchas

- "Seed every leaf the scan passes" does nothing for a forward loop. Each new
  index lies just past the previous scan's frontier, so the passed leaves are
  already cached. Only seeding *forward* works.
- The seed must track /Count slack (above). With lying /Count values, the fast
  walk is not even monotonic: with an overstated inner /Count, page(2) and
  page(3) are the same leaf. The seed has to reproduce that exactly, not fix
  it. `pages` is the true order.
- Append-all at 3000 pages is still superlinear (18.9 ms at 1000 pages, 98 ms
  at 3000). The page lookups are gone, so the rest has another cause. Not
  investigated here.
- Reverse-order or random `page(i)` loops over a flat tree are still O(n²).
  Callers that need the whole document should use `pages`.
- `tool/perf.sh gate` counters are byte-identical. The gate calls `pageCount`
  first, which already loads every leaf, so the seed resolves nothing new.

## Tests

- `pdf_document/test/page_ops_test.dart`: cold remove, move, insert-blank and
  append on an understated /Count keep every page.
- `pdf_document/test/page_cache_test.dart` "page(i) caching the leaves that
  follow it":
  - seeded lookups match fresh ones on well-formed, understated, overstated
    and repeated/non-dict-kid trees;
  - with the /Kids reversed in place, lookups show which indices a `page(2)`
    cached and that `page(0)` caches nothing.
- `pdf_document/test/perf_gate_test.dart`: a coarse tripwire keeps a cold
  `movePage` and a `page(i)` loop at 3000 pages under 150 ms. They take about
  4 and 2 ms under JIT; the old code took about 700 ms.
