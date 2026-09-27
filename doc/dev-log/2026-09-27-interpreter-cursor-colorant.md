# Interpreter: numeric content cursor

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
