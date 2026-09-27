# Interpreter cursor and colorant buffer costs

## Numeric content cursor with int opcodes

The cursor walk (`drawPageContent`, `beginPageContent`/`advance`) is what the
render worker records with on native and web, what retained scenes replay
from, and what a fresh `PdfTextExtractor.extract` runs. Every operator used to
cost a `ContentOperation`, a growable `List<num>`, a boxed double per real
operand (boxed once in the lexer's token, again in the list) and an ordered
String switch in `_execOp`, plus a `CosReal` per operand for any operator
outside `_execOp`'s seven-case numeric branch (`w`, `Td`, `rg`...). A
vector-dense CAD page is almost nothing but those operators.

### What changed

- **`CosTokenBuffer`** (`pdf_cos/src/token.dart`) stores a real unboxed
  (`setReal`) and carries the keyword's packed bytes as a read-only
  `keywordCode` (`re` is `0x6572`). The lexer sets it in `_internKeyword` for
  keywords of at most three bytes; `setToken` resets it to -1, so it is -1
  for every other token, for longer keywords and for the `{` / `}` tokens.
- **`ContentOperationCursor`** splits `nextOperation()` into `nextOperator()`
  (scan to the operator, operands pending) and `takeOperation()`
  (materialize). Number operands live in a cursor-owned `Float64List` with a
  `Uint8List` of kinds (real, int a double holds exactly, int past 2^53 kept
  in a side map cleared per operator), so a materialized `numberOperands` /
  `operands` list is exactly what it was. `nextOperation()` and `parse()`
  keep their contract, so the editor, serializer, compressor and every
  `parse()` consumer are untouched.
- **`PdfInterpreter._execNumeric`** runs the pending operator straight from
  the buffer when all its operands are numbers, switching on the int code:
  `m l c v y h re`, the painting operators `S s f F f* B B* b b* n W W*`,
  `q Q cm w`, and `Td TD Tm TL Tc Tw Tz Ts`. An operator with too few operands
  (or any other operator) returns false and goes through `_execOp` as before,
  so the general path's defaults still apply. Both cursor loops are
  `if (cursor.pendingIsNumeric && _execNumeric(cursor)) continue;
  _execOp(cursor.takeOperation(), ...)`.
- **One implementation per operator.** `q`/`Q` are `_saveState`/
  `_restoreState`, and `re`, `cm`, `w`, `TD`, `Tm`, `TL`, `Tc`, `Tw`, `Tz`,
  `Ts` are small helpers that `_execNumeric`, `_execOp`'s `numberOperands`
  branch and its String switch all call.

### The brace hazard

The first prototype kept the code on the lexer (`lastKeywordCode`) and set it
only in `_internKeyword`. `{` and `}` are emitted as keyword tokens without
going through it, so a stray brace reported the *previous* operator's code
and `_execNumeric` ran that operator again: `10 10 m 20 20 l 30 30 { S`
drew an extra segment where the String path ignores the brace. No real file
has braces in a content stream, which is why a 295-file identity sweep missed
it; a random-stream fuzz diverged on about 10% of streams. Carrying the code
on the token and resetting it in `setToken` makes a stale code impossible.
`streaming_interpreter_test` now checks in that fuzz: 4000 seeded streams
(braces, junk keywords, arrays, dictionaries, `true`/`false`/`null`, ints
past 2^53, `-0`/`-0.0`, `.5`/`5.`, arity mismatches, inline images,
malformed numbers, text shown with each text-state operator) recorded
through the cursor walk (sync, and resumable in 7-operation chunks) must
serialize byte-identically to `parse()` + `drawPageOperations`. With the
code left stale it fails 409/4000; perturbing `Tz` in the fast path fails
183/4000.

### Measurements

AOT (Dart 3.13.3, `dart compile exe`), origin/main vs this change as separate
executables, 7 interleaved A/B rounds, main-thread CPU
(`CLOCK_THREAD_CPUTIME_ID`), medians. The workload is the worker record:
`collectCharOffsets`, `beginPageContent` + `advance(65536)`,
`PdfRecordedText.capture`, `drawAnnotations`, `serializeCommands` with
placeholders and compact state scopes. "walk" is the content walk alone
(content inflated outside it); "pipeline" adds the inflate, text capture,
annotations and serialize.

| document | walk | pipeline | process CPU | peak RSS |
|---|---|---|---|---|
| cad-wide (8 pages) | 0.748 | 0.814 | 0.860 | 1.01 |
| diagram-dense-3p | 0.663 | 0.724 | 0.721 | 0.82 |
| plan-set-16p (8 pages) | 0.702 | 0.706 | 0.756 | 1.00 |
| private CAD set A (8 pages) | 0.699 | 0.757 | 0.766 | 1.02 |
| private CAD sheet B (1 page) | 0.742 | 0.796 | 0.837 | 1.00 |
| text-report-40p (8 pages) | 1.003 | 1.000 | 1.016 | 1.00 |
| type3-text-6p | 0.978 | 0.995 | 1.027 | noisy |

Every pair on the five dense documents is below 0.85 (walk). Text and Type3
pages are flat: their walk is text showing, not number-only operators.

- Fresh `PdfTextExtractor.extract`: diagram 0.771, plan-set 0.686,
  text-report 0.977.
- `parse()` plus touching every operation's operands (the materializing
  path): diagram 0.983, plan-set 0.997, cad-wide 0.960 - within +-5%.
- dart2js `-O3` (the shipped worker level) under node, main-thread CPU
  (`process.threadCpuUsage()`), same record shape: walk / pipeline -
  diagram 0.761 / 0.785, plan-set 0.714 / 0.722, cad-138 0.731 / 0.774,
  private CAD set A (8 pages) 0.759 / 0.794, private CAD sheet B 0.811 /
  0.857, text-report 0.928 / 0.946.
- Peak RSS in extract mode rose on the small documents (diagram 48 -> 64 MB,
  plan-set 1.08x) while worker-mode peaks fell or held. It is new-space
  sizing, not retention: with `--new_gen_semi_max_size=1` both builds peak at
  31.6 / 33.1 MB, and `--verbose_gc` shows about 13 scavenges where the old
  build ran about 143, i.e. the VM kept a larger nursery for the new
  allocation pattern.
- `contentOps` and every other counter in `tool/perf.sh gate` are exactly
  unchanged (a throwaway `--update-baseline` produced no diff).

### Identity

- Per page (first 8 of 295 files: the private corpus, test_corpora dartpdf,
  pdfjs and ghent; 602 pages, 12 files fail to open on both builds): the
  worker record bytes, the extracted text, the `parse()` +
  `drawPageOperations` record, and every parsed operation's operand types and
  values - 0 differences between origin/main and this change.
- The streaming test's generator run through both builds (4000 streams;
  sync walk, 7-operation chunked walk, `parse()` path and parsed operand
  types): 0 differences.

### Not covered

`renderPictureWithPlan` and every other `parse()` + `drawPageOperations`
path (forms, patterns, Type3, soft masks, the editor) still dispatch
materialized operations; `parse()` itself measured flat. An int code on
`ContentOperation` would extend the int dispatch to them; not done here.
Colour operators (`g rg k`...) are not in the fast path either (they need the
`_type3ColorLocked` guard and allocate colours anyway).

## Colorant buffer counters

Nothing in `PdfPerf` saw the overprint colorant buffer, which is how #755's
growth of it (glyph outlines, group surfaces) landed without a counter
moving. Five `PdfPerfCount` entries now cover it, each bumped once per page,
draw, read or group - never per span or cell:

- `colorantBufferPages` - `_beginOverprint` opened a buffer;
- `colorantDraws` - every draw the compositor takes (the `_draws` cap count);
- `colorantRasterized` - draws whose geometry was actually rasterized (equal
  to `colorantDraws` today; the changes below make it smaller);
- `colorantBackdropReads` - an effective overprint or group blend, a shading,
  an overprinting image or stencil, `uniformBackdrop`;
- `colorantGroups` - `beginTransparencyGroup`.

`perf_count_gate` tracks all five and gains
`1-CMYK/GWG162_Transp_Basic_BM_DeviceCMYK_Isolate_X4.pdf`: a DeviceCMYK
blending group opens the buffer with no `/OP`, which none of the existing
Ghent inputs covered. The re-baseline only adds keys and that input (GWG162:
269 draws, 124 reads, 50 groups on one page).

## Overprint glyph runs: unknown-backdrop probe

On a page with a colorant buffer every embedded-font run is resolved through
its real outlines (#755). On overprinting text with no OutputIntent most of
those runs are effective overprints of black onto a backdrop the buffer
cannot read: `_resolve` rasterized the run, found every cell under it
unknown, painted unknown over unknown and returned null - pure no-op work.
On the worst private document that was 5,596 of 8,532 rasterized draws.

- `PdfOverprintCompositor.fill` takes an optional `unknownProbe`, a thunk for
  a page-space box around the fill. For an effective overprint (overprint,
  opaque, not isolated, ink with a colorant reading) with no group open,
  after counting the draw, the compositor checks the box's
  `coveringBoxSpans` with the new `PdfColorantRaster.clippedCellsAll`, which
  applies exactly `paintFlat`'s clip box and mask. If there is a covering
  cell and every one the clip lets through is unknown, the draw returns null
  without rasterizing. It is exact: the run's centre-sampled cells lie in its
  control points' covering box, the eager path would read only unknown (or
  nothing) under the clip and paint unknown over it, and a probe that fails
  falls through to the unchanged path. A box that is not finite before or
  after the page mapping (where `coveringBoxSpans` would throw) falls through
  too.
- `subCellBounds` is now a thunk as well, asked only on the
  `spans.isEmpty` branch. The interpreter passes one memoized
  `_pathBounds` for both, so a run computes its bounds at most once and
  usually never (#811 computed them eagerly for every single-glyph run).
- `_pathBounds` walks `path.cursor()` instead of a `sync*` generator over
  `path.segments`, which also stops it materializing the packed paths the
  shading-clip and group-bounds callers pass. `_segmentPoints` stays for
  `_fillWithPattern`.

`glyphOutlinePaths` does not move: the run's path is still built before the
compositor sees it.

Measured against the previous commit (buffer on/off interleaved in one AOT
process, 5 interleaved process rounds, thread CPU, first 10 pages, record
path = `RecordingPdfDevice` walk + `serializeCommands`): the worst text
overprint document 0.691x on-mode record (pairs 0.66-0.70; buffer overhead
0.632x), another text-heavy one 0.831x (bounds laziness alone: nothing
there is skipped), the eight vector-only or tiny /OP documents 0.960-1.024x.
Whole set 0.963x on-mode, buffer overhead 0.850x. Record bytes with
`decodeImages: true` are identical on the 10 /OP documents, all 54 Ghent
files and the 53-document private corpus (first 10 pages each).

## Transparency groups: banded merges

Each transparency group on a buffer page copied the whole cell array three
times at its start (`external`, `initial`, and `accumulated` inside a
knockout parent) and walked every cell of the page at its end - several
times per group on the GWG16x pages, which open 16 to 50 groups on an
82k-cell buffer while each touches about a seventh of it.

- `_GroupCoverage {mask, lo, hi}` replaces the bare `touched` mask. Its only
  writers are `mark(raster, spans)`, which wraps `markCovered` and widens the
  flat row band `[lo, hi)` to the spans' rows (a superset of what the clip
  lets `markCovered` write), and `absorb(child)`. A debug assert at group end
  checks no marked cell lies outside the band.
- `endTransparencyGroup` merges the isolated and accumulated results, and ORs
  into the parent's coverage, over `[lo, hi)` only, reading the live cells
  instead of copying them first. The isolated/accumulated result still
  replaces the whole buffer (`setAll`), so cells outside the band come back
  from the snapshot exactly as before - including the unknown marks and
  images a group records without painting.
- `externalCells` is kept only for an isolated group and `initialCells` only
  for a knockout group; nothing else reads them.

A temporary verify build ran the old full merge on copies at every group
end and compared cells and the parent's coverage cell by cell: 357 groups on
the Ghent suite and 113 on the private corpus (first 10 pages of every
document), 0 failures, 0 band violations. Record bytes (`decodeImages:
true`) are identical on Ghent, the /OP set and the private corpus. A new
`colorant_buffer_test` case nests two isolated children on disjoint row
bands (plus an empty one) in a knockout group, isolated and not, and checks
the cells against the same shapes painted with no groups.

Measured against the previous commit (same harness, 7 rounds x 7 reps):
GWG161 knockout 0.503x on-mode record, GWG162 isolate 0.636x, GWG160
0.833x, GWG164 0.788x, GWG161 ICCBasedRGB 0.847x, the two GWG161x soft-mask
text files 0.86x. Pages without groups on a buffer do not run this code.

## Colorant buffer: lazy start

The 2026-07-25 buffer note named "defer the recording" as the next cut; it
was never built. Most pages that open a buffer never read it back: their
overprint-flagged paint is translucent or has no colorant reading (RGB/ICC
ink), or `/op` is set defensively and never painted with. Every draw on them
was still rasterized into cells nothing looked at - on the private /OP set,
six of ten documents never read the buffer on any page.

`PdfOverprintCompositor` now starts lazy. Until the first read, a mutation
that only writes the buffer is queued in a `List<Object>` - closures, plus
two int sentinels for clip save and restore (a restore right after a save
pops it, so the empty brackets forms and patterns put around their content
cost nothing):

- non-effective `_resolve` draws: knockout, translucent, isolated or
  colorant-less fills, strokes and glyph runs;
- `clipPath`, `markUnknownPath`, `markUnknownBox`;
- images and stencils that do not read the backdrop.

The first read replays the queue in order and the rest of the page runs
eagerly (re-queuing after a flush measured as not worth the state in the
prototype). Reads that go live first: an effective overprint, any
`gradient()` (it hands each cell's backdrop to its sampler and interns per
cell), an overprinting image with a colorant reading, a reading stencil,
`uniformBackdrop`, `spotEquivalents`, `debugCells`, and `begin`/
`endTransparencyGroup` - so no group is ever open while entries are queued.
The C3 probe runs after that flush, since it reads cells. What is still
queued at page end is dropped with the compositor (`_beginOverprint`
replaces it, `drawAnnotations` nulls it).

What keeps it exact:

- `_draws++` and the `_exhausted` / `_muted` checks run when the draw is
  queued, so the 20,000-draw cap trips at the same draw; the isolation depth
  (`_suspended`) is captured then too, as the recorded ink or unknown.
- **Interning happens at replay, not at enqueue** (a deliberate deviation
  from the plan). The eager path interns a palette entry and learns spot
  equivalents only for a draw that covers at least one cell; interning at
  enqueue would also intern off-page and sub-cell draws, and a spot learned
  that way could win `putIfAbsent` over the alternate a later draw would
  have set. Replay runs in call order and nothing interns in between (every
  interning reader goes live first), so the palette comes out identical.
- An effective overprint whose ink writes no colorant (Separation /None)
  neither reads nor writes and returns without going live - exactly what
  the eager path did after rasterizing it.

The interpreter no longer builds a run's page-space outlines up front:
`fillLazily` takes a memoized builder, and the probe's bounds and the
sub-cell fallback derive from the same built path. `_hasOutline` answers
"would `_glyphOutlinePath` return a path" without building one. A run that
stays queued, or that the compositor drops (draw cap, soft-mask content),
never builds it. That moves `glyphOutlinePaths` on three gate inputs
(GWG050 51 -> 50, GWG020 77 -> 75, GWG206 84 -> 82: soft-mask text), so
`counters.json` is re-baselined deliberately; every other counter is
unchanged there, because every gate page reads its buffer early.

`interpreter_test`'s "a page with a colorant buffer builds one per run" now
expects 0 for that page (it declares `/OP` but never reads the buffer) and 1
for a variant that overprints the same run onto a cyan box.

### Measurements

Deterministic (`colorantRasterized`, first 10 pages): the six no-read /OP
documents go from 31,077 / 20,000 / 10,777 / 34,520 / 25,671 / 20,000
rasterized draws to 0 each; the four that read are unchanged (every one of
their pages reads).

Record path (same harness as above, 5 interleaved process rounds), this
commit vs the counters commit (so C3 + C4 + C5 together, against main's
overprint code):

- /OP set: buffer overhead (on - off) 416 -> 191 ms, 0.459x; on-mode record
  total 0.876x.
- No-read multi-page documents, on-mode: 0.871x (4 pages; buffer-off floor
  0.852x), 0.726x (10 pages), 0.696x (6 pages). Single-page 20,000-draw
  sheets: 0.94-0.96x.
- Worst text-overprint document 0.668x; the other text-heavy ones 0.809x
  and 0.963x.
- GWG161 0.492x, GWG162 0.631x (7 rounds); Ghent suite total on-mode
  0.836x.
- Documents with no buffer: 0.990-1.025x (total 1.008x).

Deferral alone (vs the banded-groups commit): /OP set overhead 0.525x and
on-mode 0.908x; the documents that read are flat within noise (0.985-1.04).

Identity: record bytes with `decodeImages: true` are identical to the
previous commit on all 54 Ghent files, the 10 /OP documents and the
53-document private corpus (first 10 pages each).
