# JBIG2 scanned-book perf scenario, and the #532 headline number (#557)

`#532` (globals dictionary cache) landed justified *by construction* - a map
copy replacing per-page symbol arithmetic-decode, plus a byte-identical
cache-equivalence test - because nothing in the corpus could exhibit it. Every
in-repo JBIG2 file inlines its globals into a single image stream (the pdfjs
`bitmap-*`/`jbig2_*` samples) or is one image on one page (ghent GWG173), and
the saving only exists when **many** page images share **one** `/JBIG2Globals`
stream. This session built that workload and measured it.

## A pure-Dart JBIG2 encoder instead of jbig2enc

The issue assumed a pre-generated doc committed under `tool/perf/cache/`,
because producing this shape normally needs `jbig2enc` (absent from CI, and
JBIG2 arithmetic *encoding* was out of scope for our writers). It turned out
cheaper to just write the encoder: the decoder already defines every context
model, so the encoder is its mirror, and the only genuinely new algorithm is
the MQ *coder* (T.88 Annex E.3 - CODEMPS/CODELPS, RENORME, BYTEOUT with carry
propagation into the byte already written, and the SETBITS flush).

`packages/pdf_test_fixtures/lib/src/jbig2_encoder.dart`, ~200 lines of profile:

- MQ encoder + the Annex A.2 integer coder (IADH/IADW/IAEX/IADT/IAFS/IADS) and
  IAID, each written directly against the decoder's `decodeInt`/`decodeId` so
  the bit order and `prev` context walk match by inspection;
- generic region encoding, template 0 with the nominal AT pixels, TPGDON off -
  it re-uses the decoder's "sort the combined template by row then column"
  rule, which is the only thing the two sides have to agree on;
- one symbol dictionary segment (SDHUFF=0, REFAGG=0) for the globals stream,
  symbols in height classes, export flags as `(skip 0, export all)`;
- page-info + immediate text region segments (SBHUFF=0, SBSTRIPS=1, TOPLEFT)
  per page image.

Gotcha worth writing down: the text region's **last strip must not emit a
closing OOB**. The decoder breaks out of the strip loop the moment `decoded`
reaches `SBNUMINSTANCES`, before reading another IADS, so an encoder that
symmetrically closes every strip desynchronises the final bytes.

Validated by round-trip against the shipping decoder in
`packages/pdf_cos/test/jbig2_roundtrip_test.dart` (place symbols, decode,
compare to the bitmap composed directly). That is circular by nature - the
encoder is checked against our own decoder - which is fine for a perf fixture
and is *not* claimed as decoder validation; the decoder's own KATs against
jbig2enc/jbig2dec output are unchanged and still the source of truth there.

## The document

`packages/pdf_test_fixtures/tool/gen_jbig2_scanned_pdf.dart` - 32 pages,
1700x2200 px images (~200 dpi Letter), one shared 900-symbol globals stream
(4.5 KB), ~2.7k symbol instances per page, 125 KB total, deterministic from a
seed. Glyphs are stroke-built (stem + bar/bowl/diagonal/descender) rather than
noise, so the arithmetic contexts adapt the way they do on real scanned text;
ink coverage lands at 7.5%. Each page draws from a sliding third of the
dictionary - the scanned-book property that makes the saving real: before
#532 every page re-decoded the *whole* book-wide dictionary while only ever
drawing a slice of it.

Wired into `gen_perf_docs.sh` (it *is* generated in CI, unlike the
cjpeg/opj_compress-dependent docs), `nightly.sh`, and pre-seeded by
`backfill.sh`.

## The vm-sweep had no window on image decode

First run of the new scenario reported `interpretMs` 4.7 ms for 32 pages -
because `perf_sweep`'s `NullDevice` swallows `drawImage`, and the interpreter
hands the device an undecoded `PdfImageRequest`. The VM sweep never decoded an
image; the "exercises image decode" note on `image-heavy` was only ever true of
its `image-render` companion.

So `perf_sweep` gained a `decodeImages` measure: interpret with a device that
*keeps* the image requests, then time `decodePdfImagePixels` over them - the
same pure-Dart path the render worker runs, no Flutter engine needed. It is
opt-in via the scenario's existing `measures` key (it is the one measure that
costs real time on image-heavy corpora, and every other scenario exists to
track parse/interpret). New `decodeMs`/`imagesDecoded` result fields,
`p50/p95/maxDecodeMsPerPage` in the summary, `decodeMs` added to `diff.dart`'s
default metric list and the dashboard's curated order. Missing metrics are
skipped per-metric by `diff.dart`, so old history stays comparable.

`perf_diff.sh` needed two fixes to A/B a scenario that did not exist at the
ref: the harness files (perf_sweep, perf_run_context, gen_cad_pdf,
scenarios.json) are now **always** grafted into the ref worktree rather than
only when absent - both sides must run the same apparatus, and a measure or
scenario added after the ref exists only here - and `tool/perf/cache/` is
pre-seeded into the worktree (`cp -Rn`, so the reused-worktree path stays
cheap). The PdfPerf facade under `lib/` keeps the copy-only-if-absent rule:
that is library code the ref must keep measuring for itself. This also
unblocks `tool/perf.sh diff <ref> image-heavy`, which had the same problem.

## The number

`tool/perf.sh diff` between `d41fb18^` and `d41fb18` (the #532 commit
isolated, harness and corpus grafted identically onto both), 3 interleaved
runs, `jbig2-scanned-sweep`:

| metric | before | after | ratio |
|---|---|---|---|
| decodeMs (32 pages) | 2769 ms | 1825 ms | **0.659x** |
| openMs | 2.17 | 2.04 | 0.94x |
| interpretMs | 4.32 | 3.71 | 0.86x |

**1.52x faster image decode** on the scanned book. Isolating just the JBIG2
decoder (decode each page with `debugResetGlobalsCache()` before it vs. not,
excluding the 1bpp->RGBA expansion `decodePdfImagePixels` adds) puts the
codec-level ratio at **1.92x** - 1967 ms vs 1026 ms over the same 32 pages.
Both scale with symbols x pages, as predicted.

The `jbig2-scanned-render` companion (flutter-render, 4 pages) is in for the
raster trend but is *not* where the #532 number comes from: across the same
two commits its `renderMs` ratios were 0.82x and 1.08x - noise. Expected, and
worth not over-reading. Rasterization there is dominated by painting a
1700x2200 image, the decoded-image cache means each page decodes once, and 4
pages leaves only three saved globals decodes (~90 ms) inside an ~800 ms
render on a 4-core box.

So: #532's justification-by-construction was right, and the harness now shows
it. `jbig2-scanned-sweep` is the regression guard for the JBIG2 symbol path
from here.
