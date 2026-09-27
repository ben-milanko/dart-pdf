# Editable open without the whole-file hash; undo keeps the AES-256 keys

Two UI-isolate costs on `PdfEditingController`, both paid on paths every
user takes and neither doing useful work.

## 1. The form-secret id no longer hashes the file at open

The password-field secret store (#931/#943) files withheld values under the
document's permanent identity: trailer /ID[0], or for a file without /ID the
SHA-256 of the bytes as opened (the first withheld fill then writes that
hash as /ID, so a saved copy answers to the same key). The constructor
computed it eagerly whenever a store was attached, and the app attaches one
to every tab: fresh open, deferred materialise, progressive swap, window
handoff, native and web. For a file without /ID that is an O(file) hash
before the first paint (about 8 ms per MB native, 6-8 ms per MB under
dart2js), even when the document has no form at all. #438 had just removed
the same class of cost from the recents key.

Now:

- The constructor takes `pdfTrailerPermanentId` only (a trailer lookup).
- The store read at open (`_loadFormSecrets`, a keychain `readAll` on
  native) runs only when it could restore something. It only ever kept
  values for fields the opened file shows as withheld and unfilled
  (`_holdsWithheldValue`: password flag, no /V,
  `/DartPdfPasswordWithheld true`), so skipping it otherwise changes nothing.
  No /AcroForm skips it in O(1). With /ID it runs as before (the field walk
  costs more than the id). Without /ID `_fieldTreeHoldsWithheldMarker`
  walks the /Fields tree (descending /Kids, never the pages) for a node
  carrying the marker, and only a hit pays the hash and the read. The walk
  is budgeted (`debugFormSecretGateBudget`: one node per 4 KB of the opened
  file, at least 128); past the budget it answers "may hold secrets", which
  is the eager open exactly (see the gate gotchas below).
- The fallback id is resolved lazily by `_resolveFormSecretId`, on first
  need: a withheld fill, `forgetFormSecrets`, an undo/redo that moves a
  stored value, or `formSecretDocumentId`.

Gotchas:

- **Hash the opened prefix, never the current revision.** The lazy getter
  hashes `sublistView(_bytes, 0, _revisions[0])`. Every revision appends to
  that prefix, so the key is byte-identical to the eager one. The fill must
  pass that id explicitly as `documentId:`. Passing null makes
  `setPasswordValue` hash `document.cos.bytes`, the *current* revision; after
  any earlier edit the /ID it writes would then differ from the store key,
  and the value would be lost on reopen. There is a test for exactly that
  (a first withheld fill after an unrelated edit).
- `_resetTo` (redaction burn) replaces the buffer, so it resolves the id
  first when a store is attached. The burn is O(file) anyway.
- `pdfFallbackDocumentId` (pdf_document `document_identity.dart`) is the
  hash on its own, so the controller does not have to open a document to
  get it. The first prototype re-opened the prefix inside the getter, which
  on an AES-256 file would have re-run the password check.
- **The gate reads /Fields, never `PdfAcroForm.fields`.** Base did no form
  work at open: it paid the hash, and the viewer's form layer only computes
  `fields` for a page that shows a Widget (`formWidgetsOn` skips other
  annotations first). `fields` always runs the orphan-widget reconcile,
  which maps every page and parses every annotation on it to find widgets
  missing from /Fields. So a gate built on `fields` adds work at open
  instead of moving it. Review caught this twice:
  - Round 1: `PdfAcroForm._pages` still looked each page up with
    `page(i)`, which is quadratic on a flat /Kids tree before the viewer
    has warmed the page cache (1.36 s at 4000 pages, against 12 ms for the
    hash). #969 fixed `_pages` on main.
  - Round 2: even as one page walk, the reconcile parses every annotation.
    A no-/ID file with an empty /AcroForm stub and dense link annotations
    (a TOC or an index) went from 68 ms (the hash) to 800 ms in the
    constructor at 40k links (`buildMultiPagePdf(2000)`, 20 /Link each).

  The gate over-approximates from the /Fields tree alone. It checks the
  marker on every node reachable through /Kids (widget kids included), with
  an identity-keyed visited set and an explicit stack, and ignores /Ff and
  /V. A false positive only costs the hash and the store read, and
  `_loadFormSecrets` still filters exactly.
- **The walk is budgeted, because a field node costs more than the bytes it
  occupies.** Round 3 of review found that the unbudgeted /Fields walk still
  cost more than the hash on a field-dense form: every node is an object
  load, and a field dictionary is only ~180-200 bytes of file. A no-/ID file
  with 5000 fields constructed 4-7x slower than base (JIT 11 -> 48-79 ms), and
  none of the earlier gate inputs had a non-empty /Fields. Measured costs
  (thread CPU): an object load in the walk is ~1.5-3.5 us AOT (the higher
  end with /AP dictionaries) and ~3.5-7.5 us under dart2js; SHA-256 is
  ~8.2 ns a byte AOT and ~6.5 under dart2js. So one node costs as much as
  hashing 200-420 bytes native, 640-1250 on the web, and in an object-stream
  file a field node can occupy as little as ~25 bytes.

  The budget is `max(128, openedLength >> 12)` nodes, and the walk counts
  **pushes**: every node pushed is later popped and resolved, so repeated
  references and wide /Kids fan-outs are charged, and a /Kids array (or the
  /Fields root) that would overshoot ends the walk before anything is
  pushed. Past the budget the gate answers true, and `_loadFormSecrets`
  pays exactly what base paid (the hash of the opened bytes and the
  `readAll`), so the budget cannot hide a secret. What it bounds is the
  extra: a walk that runs out adds at most ~10% (native) or ~30% (web) to
  the hash it then pays, and under 512 KB the 128-node floor adds at most
  ~0.5 ms native, ~1 ms web. The floor exists so a small form with a few
  dozen fields still skips the store read and the hash. A flat /Fields wider
  than the budget (the usual shape of a big form) costs one array parse.
  The budget counts nodes, not bytes: a form built from very large field
  dictionaries (inline option lists many KB long) walks slower per node.
  `form_secret_store_test` pins the budget: a 310-node tree loads at most
  128 + 16 objects in the constructor and falls back to the eager load (one
  `readAll`, the fallback id resolved); a withheld field the walk never
  reached still restores; a flat 1000-field /Fields loads fewer than 16
  objects; a 110-node form is still ruled out without the hash. Without the
  budget those loads are 311, 1001 and 311.

  The exact alternative the review offered, deferring the no-/ID decision
  to the form layer's first `fields` computation, would also close the
  orphan-widget residual below, but it moves the store read into the form
  layer's timing and needs a hook there. The budget keeps the change in the
  constructor.

  The other `form_secret_store_test` pins: no `pageTreeWalk` in the
  constructor, the same constructor `objectsLoaded` with 0 or 4000 link
  annotations (the `fields` gate loaded 202 vs 4202 objects), and a withheld
  field nested under /Kids that still restores.

  What the /Fields walk cannot see is a field synthesized from an orphan
  page widget (no /Fields entry by that name) that carries the marker.
  Getting there takes several steps: a withheld fill on such a field, which
  writes /ID; another tool later stripping /ID while keeping the private
  marker; then a store entry filed under the hash of exactly the stripped
  bytes by an earlier session that never saved over them - one that was
  discarded, or one saved to a new path with Save As, after which the
  original is reopened. Even then only the inline editor's prefill is lost.
  The store keeps the value, and the field still shows its mask. This case
  is accepted. Keeping it exact would mean starting the load from the form
  layer's first `fields` computation.

## 2. Undo reopens with the authenticated keys

Undo is not an append, so `_reloadDocument(grew: false)` reopened the
revision with `PdfDocument.open(bytes, password: _password)`. On an AES-256
(R6) file that re-runs Algorithm 2.B on the UI isolate for every undo (about
10 ms native after #973's AES rewrite, about 75 ms under dart2js, where the
emulated 64-bit SHA-384/512 dominates). It now goes through `_openRevision`,
i.e. `_document.openAppended(bytes, password: _password)`, which donates the
current document's security handler. The burn/reset reopen in `_resetTo`
uses the same helper. A compacted (burned) file is never encrypted, since
the compaction refuses encrypted input, so there the donation only applies
when nothing burned and the editor saved an ordinary incremental update.

`CosDocument.openAppended` changes to support this:

- It now accepts a shorter prefix (an earlier revision), not only an append.
  Nothing in the parse depended on the direction.
- It takes a `password` for the non-donated path (it used to be hard-wired
  to the empty password).
- It donates only while the revision's /Encrypt has the same object number
  **and** the same entries (`_sameEncryptDictionary`: a structural compare,
  strings by bytes, the /CF crypt filters included). The compare is against
  `_authenticatedEncrypt`, a copy (indirect entries inlined) of the
  dictionary the donor's handler was derived from, which donated documents
  inherit. It is not compared against the donor's current trailer
  /Encrypt: `applyIncrementalUpdate` keeps the handler while a folded
  revision may redefine that object, and then the donor would vouch for a
  dictionary it never authenticated. The editor cannot reach that state,
  because `CosIncrementalUpdater` copies the /Encrypt reference and never
  rewrites the object. A test folds a re-keyed /Encrypt into the donor
  anyway. The object number alone
  does not prove the handler is unchanged: a revision can rewrite that
  object under the same number. The handler is a function of the /Encrypt
  entries, /ID[0] and the password, so comparing the whole dictionary (a
  dozen entries) is exact where comparing only /O, /U, /OE and /UE is not:
  a rewrite that keeps the key material but swaps a crypt filter (say
  /StmF to /Identity) would otherwise keep AES-decrypting streams the file
  now declares plain. A mismatch authenticates the password like a fresh
  open. /ID[0] is not compared: an editor keeps it across revisions, an undo
  target's trailer is one the session already had open, and the forward
  (append) path has always donated across it.
- **The snapshot is taken before the handler is installed.** Once
  `_encryption` is set, any object that loads for the first time has its
  strings decrypted. An indirect sub-object of /Encrypt that
  `fromEncrypt` did not read would then be snapshotted decrypted, while the
  next revision's compare (which runs before its own handler exists) sees
  the raw bytes, so the donation would never match: undo would pay the key
  derivation again and `openAppended()` with '' would throw on a
  user-password file. The standard handler reads all of its own strings
  first, so only an extra indirect entry hits this; a test adds one.

The render worker's own reopen on shrink (render_worker_isolate.dart) and
the web worker's per-revision restart still derive keys from scratch; that is
a separate change (it would mean sending key material over the port).
`_loadFormSecrets` also still reopens the as-opened prefix with the password
to see which fields take a stored value; on an R6 file that is one more key
derivation, but only after the store has actually returned values for the
document, so it was left alone.

Noticed on the way, not changed: `decryptObjectGraph` decrypts strings
inside dictionaries, arrays and stream dictionaries in place, so an indirect
object that is itself a bare string (`8 0 obj (...) endobj`) is never
decrypted. Base and branch behave the same way.

## Numbers

Base is origin/main at 51b30ecd (#969-#973 included); patched is this
branch. Every A/B ran 6 rounds ABAB with the order flipped each round (7 for
dart2js), one process per side per round. The clock is thread CPU
(`clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)` through `dart:ffi`), not
wall time, because the machine was shared (load average 7-13). Figures are
medians of the per-round medians, and the median of the per-round
base/patched ratios; above 1 means patched is faster.

Harnesses (scratch, not committed):

- JIT: the real `PdfEditingController` with an `InMemoryFormSecretStore`
  under `flutter test`, 5 reps per round after a warm-up. "+ attach" adds
  the viewer's `document.pages` and `formWidgetsOn(0)`.
- AOT: a `dart compile exe` bench built from each worktree that mirrors the
  constructor's library calls (base: `pdfPermanentDocumentId`; patched: the
  trailer id, the budgeted walk copied verbatim, and the hash when the gate
  answers true), 8 reps per round. "+ pages" adds `document.pages`.
- dart2js: `dart compile js -O2` of the R6 undo reopen, run under node.

Inputs, generated in scratch (none has a trailer /ID except the control):

- `noid-20mb`: 21.5 MB, 101 pages: pdf.js `calrgb.pdf` (no /ID) with 14
  copies of `photo-jpeg-6p.pdf` merged in (`PdfMerger` keeps the first
  file's trailer). `withid-20mb`: 23.2 MB, the same built on
  `plan-set-16p.pdf`, which has an /ID.
- `annotform-2000x20`: the round-2 class, an empty /AcroForm and 40k
  /Link annotations.
- The round-3 class, a field-dense /AcroForm, all fields merged text
  field/widgets added by one incremental update: `manyfields-PxF` (F fields
  on each of P pages; 200x25 is 5000 fields in 0.89 MB), `apform-200x25`
  (the same with /AP streams, 1.88 MB), `-cover` variants with no widget on
  page 0, `objstm-manyfields-200x25` (rewritten with object streams, 0.12
  MB), `treeform-40x25` (50 parents x 20 fields, each with its own widget:
  2050 nodes, 0.27 MB).
- Budget edges: `edge-40x25` (1000 flat fields padded to 4.3 MB with an
  unreferenced stream: budget 1055, the walk finishes); `edgetree-20x25`
  (1025 tree nodes padded to 4.1 MB: budget 1000, the walk runs almost to
  the end, gives up and hashes, which is the most a give-up can add past the
  floor); `small-1x120` (120 fields, 20 KB) and `objstm-small-1x120` (the
  same with object streams, 4 KB): under the 128-node floor, so the walk
  finishes and nothing is hashed.
- `noid-20mb-form2000`: `noid-20mb` with 2020 fields added.

| input | gate | JIT ctor | JIT ctor + attach | AOT open + decision |
| --- | --- | ---: | ---: | ---: |
| noid-20mb | no form: no hash | 197.2 -> 0.24 ms (833x) | 197.6 -> 0.77 ms (257x) | 177.9 -> 0.058 ms (~3000x) |
| withid-20mb (control) | /ID: read | 0.18 -> 0.19 ms (0.98x) | 0.81 -> 0.84 ms (0.99x) | 0.047 -> 0.048 ms (1.00x) |
| noid-20mb-form2000 | walk finishes | 200.4 -> 7.97 ms (25x) | 207.7 -> 10.1 ms (21x) | 182.0 -> 4.54 ms (40x) |
| edge-40x25 | walk finishes | 40.0 -> 3.08 ms (13x) | 43.2 -> 4.94 ms (8.8x) | 36.1 -> 1.92 ms (19x) |
| annotform-2000x20 | empty /Fields | 62.5 -> 16.3 ms (3.8x) | 77.3 -> 33.7 ms (2.3x) | 52.2 -> 10.2 ms (5.1x) |
| manyfields-200x25 | gives up at the root | 10.65 -> 10.83 ms (0.98x) | 32.6 -> 34.6 ms (0.96x) | 8.86 -> 8.87 ms (1.00x) |
| manyfields-40x25 | gives up at the root | 2.18 -> 2.10 ms (1.02x) | 6.05 -> 5.57 ms (1.07x) | 1.74 -> 1.77 ms (0.98x) |
| manyfields-cover-200x25 | gives up at the root | 10.06 -> 10.17 ms (0.98x) | 11.31 -> 11.52 ms (0.98x) | 8.82 -> 8.79 ms (1.00x) |
| apform-200x25 | gives up at the root | 21.5 -> 22.0 ms (0.99x) | 48.0 -> 48.3 ms (0.97x) | 17.86 -> 18.01 ms (0.99x) |
| apform-cover-200x25 | gives up at the root | 20.5 -> 21.1 ms (0.98x) | 21.9 -> 23.1 ms (0.94x) | 18.07 -> 18.14 ms (1.01x) |
| objstm-manyfields-200x25 | gives up at the root | 4.64 -> 4.97 ms (0.95x) | 27.5 -> 29.2 ms (0.92x) | 2.40 -> 2.39 ms (1.00x) |
| treeform-40x25 | gives up (budget 128) | 3.18 -> 3.48 ms (0.92x) | 8.59 -> 8.85 ms (0.99x) | 2.63 -> 2.72 ms (0.97x) |
| edgetree-20x25 | gives up near the end | 37.9 -> 40.2 ms (0.94x) | 40.5 -> 41.3 ms (0.98x) | 34.5 -> 35.4 ms (0.97x) |
| small-1x120 | walk finishes (floor) | 0.28 -> 0.42 ms (0.68x) | 0.78 -> 0.66 ms (1.19x) | 0.20 -> 0.23 ms (0.86x) |
| objstm-small-1x120 | walk finishes (floor) | 0.17 -> 0.46 ms (0.38x) | 0.65 -> 0.69 ms (0.97x) | 0.085 -> 0.24 ms (0.35x) |

AOT with `+ pages`: noid-20mb 178.4 -> 0.28 ms (641x), withid-20mb 0.261 ->
0.262 ms (1.01x), noid-20mb-form2000 182.5 -> 5.10 ms (36x), edge-40x25
36.3 -> 2.18 ms (17x), annotform-2000x20 63.4 -> 20.9 ms (3.0x); the
field-dense rows stay at 0.98-1.00x, treeform and edgetree at 0.97x.

For the round-3 class the review had measured, with the unbudgeted walk,
JIT constructors of 11 -> 48-79 ms (manyfields-200x25), 2.3 -> 5.0 ms
(manyfields-40x25) and 22.9 -> 35.0 ms (apform-200x25), and AOT 10.0 ->
40.9 ms for 5000 bare fields. Those rows are now at parity: their flat
/Fields is wider than the budget, so the gate costs one array parse and then
pays base's hash. What is slower than base, and by how much:

- a walk that runs almost to the end of its budget and gives up:
  edgetree-20x25 +0.9 ms AOT (0.97x) and +2.3 ms JIT (0.94x) on a 35 ms
  hash; treeform-40x25 +0.09 ms AOT, +0.3 ms JIT;
- tiny files under the floor, where walking 120 nodes costs more than
  hashing the whole file: objstm-small-1x120, a 4 KB file, 0.085 -> 0.24 ms
  AOT (+0.16 ms) and 0.17 -> 0.46 ms JIT (+0.28 ms); small-1x120 +0.03 ms
  AOT. With the viewer's attach included they are 0.97x and 1.19x.

On every patched open the gate's answer matched the table's "gate" column:
where it rules the form out, `debugFormSecretIdResolved` stays false (no
hash) and a counting store sees no `readAll`; where it gives up, the id is
resolved and there is one `readAll`, as on base. The /ID control reads the
store on both sides.

The per-node figures behind the budget come from a separate micro (thread
CPU for AOT; node wall time over 30-rep loops for dart2js -O4): walk cost
per pushed node 1.6-1.8 us (bare fields), 3.4-3.6 us (/AP fields), 1.8-2.1
us (object streams) AOT, and 3.4-7.4 us under dart2js; SHA-256 8.2-8.6 ns a
byte AOT, 5.4-8.1 ns under dart2js.

Undo on an R6 fixture (`buildEncryptedPdf(revision: 6)`, 12 rectangles then
12 undos; #973's AES rewrite cut the native base from about 26 ms in the
earlier rounds to about 7.4 ms, while under dart2js it is still about 75 ms,
dominated by the emulated 64-bit SHA-384/512):

| path | user password | base | patched | ratio |
| --- | --- | ---: | ---: | ---: |
| `controller.undo()`, JIT | empty (owner-only) | 7.32 ms | 0.30 ms | 25x |
| `controller.undo()`, JIT | set | 7.41 ms | 0.077 ms | 96x |
| the reopen + page 0 decrypt, AOT | empty | 9.73 ms | 0.030 ms | 326x |
| the reopen + page 0 decrypt, AOT | set | 10.22 ms | 0.030 ms | 350x |
| the reopen + page 0 decrypt, dart2js -O2 on node | empty | 72.0 ms | < 0.2 ms | > 400x |
| the reopen + page 0 decrypt, dart2js -O2 on node | set | 77.2 ms | < 0.1 ms | > 900x |

(The node figures for the patched side sit at the timer's resolution.) R4
(AES-128) `controller.undo()`: 0.51 -> 0.062 ms (8.3x), because donating the
handler also skips the R2-R4 MD5/RC4 key derivation.

App end to end, measured in the first round against the base of that time
(the hash it removes does not depend on anything merged since): a desktop
open through `EditorScreen` (flutter test, the app's incoming-file channel,
`PdfPerfLog` timestamps), open trigger to the editable view's page 0 ready,
on the 21.5 MB no-/ID file, 5 rounds of 3 reps per process, rep 0 dropped as
warm-up, wall clock:

| mode | base | patched | patched/base | pair ratio |
| --- | ---: | ---: | ---: | ---: |
| direct (bytes handed to the tab) | 379 ms | 172 ms | 0.45 | 2.22x |
| progressive (sparse preview, then swap) | 460 ms | 262 ms | 0.57 | 1.79x |

A second run on a busier machine (load average about 25-30) saved about
the same time, but the ratios were smaller because everything else ran
slower: direct 402 -> 207 ms (0.51, pair ratio 2.01x), progressive
498 -> 320 ms (0.64, 1.44x). The deterministic counters (main-isolate
`cos open`s, worker generations, page 0 interprets and ready events) were
the same on both sides; only the hash was gone. (Progressive's counts vary
run to run on both sides - two or three `cos open`s, occasionally page 0
interpreted twice - a swap timing race that predates this change.)

Earlier rounds, for the record (their base predates #971-#973):

- Round 1's gate went through `PdfAcroForm.fields`; with #969 it made the
  constructor of a flat-tree no-/ID form slower than base by about one page
  walk (flatform-4000: 13.96 -> 19.82 ms JIT), and before #969 it was
  quadratic (1347 ms AOT at 4000 pages).
- Round 2's gate read /Fields without a budget. It fixed the annotation
  class (annotform-2000x20: 68.4 -> 16.1 ms JIT, where the `fields` gate took
  735 ms AOT) but claimed "no workload is slower than base", which was false
  for field-dense forms: none of its inputs had a non-empty /Fields. Round 3
  (above) measured that class and added the budget.

Prevalence: in the private real-world corpus 8 of 53 files have no /ID, all
at most 1.7 MB (1-20 ms each); none of the no-/ID files in either corpus
has an /AcroForm. DartPDF's own writer always emits /ID. The large-file case
needs a big third-party file without /ID (some scanner output), which the
corpora don't contain. None of the 53 private files is encrypted; R6
appears in the checked-in pdf.js suite.

## Files

- `packages/dart_pdf_editor/lib/src/editing/editing_controller.dart`:
  constructor gate (`_mayHoldFormSecrets`, `_fieldTreeHoldsWithheldMarker`,
  `debugFormSecretGateBudget`, `_holdsWithheldValue`),
  `_resolveFormSecretId`, `debugFormSecretIdResolved`, `_openRevision`.
- `packages/pdf_document/lib/src/document_identity.dart`:
  `pdfFallbackDocumentId`.
- `packages/pdf_cos/lib/src/document.dart`: `openAppended(password:)`,
  `_sameEncryptDictionary`/`_sameCos`, `_authenticatedEncrypt`/
  `_inlineEncrypt`; `packages/pdf_document/lib/src/document.dart`:
  `PdfDocument.openAppended` forwards the password.
- Tests: `form_secret_store_test.dart` (no hash or `readAll` without a
  withheld field, a withheld field in a no-/ID file still restoring, the
  first fill after another edit filing under the opened hash, a 3000-page
  flat-tree no-/ID form whose constructor walks no page tree (the viewer's
  `document.pages` is the only walk), the constructor's `objectsLoaded`
  independent of the annotation count, a withheld field nested under /Kids
  still found, a no-/ID file keeping its opened identity across a redaction
  burn, and the gate budget: its size, a tree past it falling back to the
  eager load within 128 + 16 loads, a withheld field past it still
  restoring, a wide flat /Fields costing one array, a form within it still
  ruled out),
  `editing_incremental_reload_test.dart` (R6 undo keeps the handler and
  matches a cold open, with and without a user password),
  `standard_security_handler_test.dart` (an earlier revision reuses the
  keys; a re-keyed /Encrypt under the same number re-authenticates; one that
  keeps the key material but swaps a crypt filter is not donated the old
  handler; a donor that folded in a re-keyed /Encrypt does not vouch for
  it; an indirect /Encrypt entry the handler never read still donates).
