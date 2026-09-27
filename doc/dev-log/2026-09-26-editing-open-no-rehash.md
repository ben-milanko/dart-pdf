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
before the first paint (about 10 ms per MB native, 8 ms per MB under
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
  carrying the marker, and only a hit pays the hash and the read. That is
  O(field nodes + their widgets), whatever the page or annotation count
  (see the gate gotcha below).
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

  The gate now over-approximates from the /Fields tree alone. It checks the
  marker on every node reachable through /Kids (widget kids included), with
  an identity-keyed visited set and an explicit stack, and ignores /Ff and
  /V. A false positive only costs the hash and the store read, and
  `_loadFormSecrets` still filters exactly. `form_secret_store_test` pins
  three things: no `pageTreeWalk` in the constructor, the same constructor
  `objectsLoaded` with 0 or 4000 link annotations (the `fields` gate loaded
  202 vs 4202 objects), and a withheld field nested under /Kids that still
  restores.

  What the /Fields walk cannot see is a field synthesized from an orphan
  page widget (no /Fields entry by that name) that carries the marker.
  Getting there takes several steps: a withheld fill on such a field, which
  writes /ID; another tool later stripping /ID while keeping the private
  marker; then a store entry filed under the hash of exactly the stripped
  bytes by an earlier session that was discarded unsaved. Even then only
  the inline editor's prefill is lost. The store keeps the value, and the
  field still shows its mask. This case is accepted. Keeping it exact would
  mean starting the load from the form layer's first `fields` computation.

## 2. Undo reopens with the authenticated keys

Undo is not an append, so `_reloadDocument(grew: false)` reopened the
revision with `PdfDocument.open(bytes, password: _password)`. On an AES-256
(R6) file that re-runs Algorithm 2.B on the UI isolate for every undo. It now
goes through `_openRevision`, i.e. `_document.openAppended(bytes, password:
_password)`, which donates the current document's security handler. The
burn/reset reopen in `_resetTo` uses the same helper. A compacted (burned)
file is never encrypted, since the compaction refuses encrypted input, so
there the donation only applies when nothing burned and the editor saved an
ordinary incremental update.

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

The render worker's own reopen on shrink (render_worker_isolate.dart) and
the web worker's per-revision restart still derive keys from scratch; that is
a separate change (it would mean sending key material over the port).
`_loadFormSecrets` also still reopens the as-opened prefix with the password
to see which fields take a stored value; on an R6 file that is one more key
derivation, but only after the store has actually returned values for the
document, so it was left alone.

## Numbers

All A/Bs are base (origin/main) vs patched worktrees, alternated ABAB with
the order flipped each round; medians of the per-round medians and of the
per-round base/patched ratios.

Constructor, `PdfEditingController(bytes, formSecretStore:
InMemoryFormSecretStore())`, flutter test (JIT), 7 rounds x 5 reps:

| file | base | patched | ratio |
| --- | ---: | ---: | ---: |
| 21.5 MB, 101 pages, no /ID (synthetic, see below) | 201.2 ms | 1.27 ms | 161x |
| 23.2 MB, 100 pages, with /ID (control) | 0.83 ms | 0.72 ms | 1.13x (noise) |
| 1.7 MB real-world file without /ID (private corpus) | 16.0 ms | 0.74 ms | 22x |

The synthetic files are a checked-in fixture (pdf.js `calrgb.pdf`, no /ID;
`plan-set-16p.pdf`, with /ID for the control) with 14 copies of
`photo-jpeg-6p.pdf` merged in - `PdfMerger` keeps the first file's trailer.

The same work in AOT (open + the form-secret id + the /AcroForm lookup, 6
rounds of 8 reps) on the 21.5 MB file: 179.2 ms -> 0.07 ms per open
(process CPU for the whole run 1.62 s -> 0.00 s).
`debugFormSecretIdResolved` stays false after such an open on every round
(no hash), and a counting store sees no `readAll`.

Undo on an R6 fixture (`buildEncryptedPdf(revision: 6)`, 12 rectangles then
12 undos):

| path | user password | base | patched | ratio |
| --- | --- | ---: | ---: | ---: |
| `controller.undo()`, flutter test, 7 rounds | empty (owner-only) | 26.2 ms | 0.36 ms | 72x |
| `controller.undo()`, flutter test, 7 rounds | set | 26.8 ms | 0.16 ms | 178x |
| the reopen + page 0 decrypt, AOT, 6 rounds | empty | 28.9 ms | 0.03 ms | 910x |
| the reopen + page 0 decrypt, AOT, 6 rounds | set | 30.0 ms | 0.03 ms | 934x |
| the reopen + page 0 decrypt, dart2js -O2 on node, 7 rounds | empty | 87.1 ms | < 0.2 ms | > 400x |
| the reopen + page 0 decrypt, dart2js -O2 on node, 7 rounds | set | 93.6 ms | < 0.2 ms | > 400x |

(The node figures for the patched side sit at the timer's resolution.)

AES-128 and RC4 reopens were already well under a millisecond. They are
now about 5x faster (R4 `controller.undo()`: 0.45 -> 0.08 ms, pair ratio
5.7x), because donating the handler also skips the R2-R4 MD5/RC4 key
derivation. The absolute saving that matters is the R6 key derivation,
which on the web is dominated by package:crypto's emulated 64-bit
SHA-384/512.

App end to end: a desktop open through `EditorScreen` (flutter test, the
app's incoming-file channel, `PdfPerfLog` timestamps), open trigger to the
editable view's page 0 ready, on the 21.5 MB no-/ID file. 5 rounds of 3 reps
per process, rep 0 dropped as warm-up:

| mode | base | patched | patched/base | pair ratio |
| --- | ---: | ---: | ---: | ---: |
| direct (bytes handed to the tab) | 379 ms | 172 ms | 0.45 | 2.22x |
| progressive (sparse preview, then swap) | 460 ms | 262 ms | 0.57 | 1.79x |

A second run on a busier machine (load average about 25-30) saved about
the same time, but the ratios were smaller because everything else ran
slower: direct 402 -> 207 ms (0.51, pair ratio 2.01x), progressive
498 -> 320 ms (0.64, 1.44x). The same re-run reproduced the constructor
(209 -> 1.36 ms), AOT open (188 -> 0.07 ms) and R6 undo (27.7 -> 0.39 ms,
28.3 -> 0.17 ms) figures within noise.

The deterministic counters (main-isolate `cos open`s, worker generations,
page 0 interprets and ready events) are the same on both sides; only the
hash is gone. The hash was about half of time-to-editable in direct mode
and over a third in progressive mode, where the sparse preview's own open
and worker generation stay. (Progressive's counts vary run to run on both
sides - two or three `cos open`s, occasionally page 0 interpreted twice -
a swap timing race that predates this change.)

### Re-run after review round 1, rebased onto #969 (superseded)

These rows measure the round-1 gate, which still went through
`PdfAcroForm.fields`. The round-2 re-run below replaces them. Base is
origin/main with #969 and #970. Both arms ran 6 rounds, ABAB, with
the order flipped each round. "+ pages" adds the viewer's attach-time
`document.pages` walk to the open. `flatform-n` is the review's
counter-example class: flat-tree `buildMultiPagePdf(n)` with no /ID and an
empty /AcroForm added by an incremental update.

| workload | base | patched | pair ratio |
| --- | ---: | ---: | ---: |
| JIT constructor, 21.5 MB no /ID | 212.9 ms | 0.58 ms | 369x |
| JIT constructor + pages, 21.5 MB no /ID | 215.0 ms | 2.04 ms | 105x |
| JIT constructor + pages, 23.2 MB with /ID (control) | 1.52 ms | 1.33 ms | 1.11x (noise) |
| JIT constructor, flatform-500 / 2000 / 4000 | 1.85 / 6.69 / 13.96 ms | 3.08 / 9.23 / 19.82 ms | 0.61 / 0.73 / 0.72x |
| JIT constructor + pages, flatform-500 / 2000 / 4000 | 4.21 / 13.58 / 29.54 ms | 3.10 / 9.24 / 19.83 ms | 1.38 / 1.49 / 1.51x |
| JIT `controller.undo()`, R6 owner-only / user password | 27.5 / 28.5 ms | 0.35 / 0.14 ms | 78x / 200x |
| JIT `controller.undo()`, R4 | 0.45 ms | 0.08 ms | 5.7x |
| AOT open + id decision + pages, 21.5 MB no /ID | 191.1 ms | 0.35 ms | 549x (process CPU 1.72 -> 0.01 s) |
| AOT the same, 23.2 MB with /ID (control) | 0.32 ms | 0.32 ms | 1.02x |
| AOT the same, flatform-500 / 2000 / 4000 | 2.49 / 10.85 / 23.21 ms | 1.35 / 5.79 / 12.99 ms | 1.85 / 1.86 / 1.80x |
| AOT R6 undo reopen + page 0 decrypt, owner-only / user password | 30.6 / 31.8 ms | 0.034 / 0.035 ms | 921x / 911x |

With that gate, a flat-tree form without /ID made the constructor alone
slower than base by about one page-tree walk, which the viewer then
reused. That description missed the annotation parse, which the viewer
does not reuse (round 2). The same AOT bench built from the pre-rebase
branch, where `_pages` still used `page(i)`, took 26 / 344 / 1347 ms on
flatform-500 / 2000 / 4000.

### Re-run after review round 2 (/Fields-only gate)

Base is origin/main (with #969 and #970). Both arms ran 6 rounds, ABAB,
with the order flipped each round. `annotform-PxL` is `buildMultiPagePdf(P)`
with no /ID, an empty /AcroForm and L indirect /Link annotations per page,
all added by an incremental update: the round-2 counter-example. JIT is the
real `PdfEditingController` with an `InMemoryFormSecretStore`, 5 reps per
round. "+ attach" adds the viewer's `document.pages` and `formWidgetsOn(0)`.
AOT is a `dart compile exe` bench, built from each worktree, that mirrors
the constructor's calls, 8 reps per round. Its "+ pages" adds
`document.pages`. Process CPU comes from `/usr/bin/time`.

| workload | base | patched | pair ratio |
| --- | ---: | ---: | ---: |
| JIT constructor, 21.5 MB no /ID | 202.5 ms | 0.47 ms | 430x |
| JIT constructor + attach, 21.5 MB no /ID | 204.3 ms | 1.89 ms | 109x |
| JIT constructor + attach, 23.2 MB with /ID (control) | 1.51 ms | 1.41 ms | 1.03x (noise) |
| JIT constructor, flatform-4000 | 13.7 ms | 2.07 ms | 6.5x |
| JIT constructor + attach, flatform-4000 | 29.0 ms | 17.7 ms | 1.65x |
| JIT constructor, annotform-2000x20 (40k links) | 68.4 ms | 16.1 ms | 4.3x |
| JIT constructor + attach, annotform-2000x20 | 83.1 ms | 31.7 ms | 2.6x |
| JIT constructor, annotform-300x15 (4.5k links) | 7.55 ms | 1.27 ms | 5.8x |
| JIT constructor + attach, annotform-300x15 | 10.1 ms | 2.83 ms | 3.4x |
| JIT `controller.undo()`, R6 owner-only / user password | 26.1 / 26.8 ms | 0.33 / 0.13 ms | 80x / 206x |
| JIT `controller.undo()`, R4 | 0.44 ms | 0.08 ms | 5.9x |
| AOT open + id decision, 21.5 MB no /ID | 183.2 ms | 0.059 ms | ~3000x (process CPU 1.67 -> 0.00 s) |
| AOT the same + pages, 21.5 MB no /ID | 183.4 ms | 0.32 ms | 584x |
| AOT the same + pages, 23.2 MB with /ID (control) | 0.31 ms | 0.30 ms | 1.02x |
| AOT open + id decision (+ pages), flatform-4000 | 10.4 (21.4) ms | 1.12 (11.5) ms | 9.4x (1.89x) |
| AOT open + id decision (+ pages), annotform-2000x20 | 59.6 (70.7) ms | 11.4 (22.2) ms | 5.2x (3.2x), process CPU 0.66 -> 0.22 s |
| AOT open + id decision (+ pages), annotform-300x15 | 6.72 (8.15) ms | 1.01 (2.45) ms | 6.7x (3.3x) |
| AOT R6 undo reopen + page 0 decrypt, owner-only / user password | 29.0 / 30.2 ms | 0.032 / 0.032 ms | 912x / 944x |

The patched constructor on the annotform files is the xref parse of the
42k-entry update, which base pays too. As a reference, the round-1 gate
(`fields.any(...)`) mirrored in the same patched AOT bench took 735 ms on
annotform-2000x20 (process CPU 7.1 s), 27 ms on annotform-300x15 and
11.5 ms on flatform-4000. That matches the reviewer's 741 ms. No workload
is slower than base any more. The constructor no longer walks the page
tree, so flat-tree forms without /ID come out faster in the constructor
too, not only once the viewer has attached.

Prevalence: in the private real-world corpus 8 of 53 files have no /ID, all
at most 1.7 MB (1-20 ms each); none of the no-/ID files in either corpus
has an /AcroForm. DartPDF's own writer always emits /ID. The large-file case
needs a big third-party file without /ID (some scanner output), which the
corpora don't contain. None of the 53 private files is encrypted; R6
appears in the checked-in pdf.js suite.

## Files

- `packages/dart_pdf_editor/lib/src/editing/editing_controller.dart`:
  constructor gate (`_mayHoldFormSecrets`, `_fieldTreeHoldsWithheldMarker`,
  `_holdsWithheldValue`),
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
  still found, and a no-/ID file keeping its opened identity across a
  redaction burn),
  `editing_incremental_reload_test.dart` (R6 undo keeps the handler and
  matches a cold open, with and without a user password),
  `standard_security_handler_test.dart` (an earlier revision reuses the
  keys; a re-keyed /Encrypt under the same number re-authenticates; one that
  keeps the key material but swaps a crypt filter is not donated the old
  handler; a donor that folded in a re-keyed /Encrypt does not vouch for
  it).
