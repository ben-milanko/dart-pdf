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
  costs more than the id). Without /ID the opened revision's fields are
  walked through the per-revision `acroForm` cache, which the form layer
  reuses, and only a withheld field pays the hash and the read.
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
- A no-/ID file with a form now walks its fields at construction, where
  base hashed the file. No such file exists in the corpora we have (none of
  the no-/ID files carries an /AcroForm), and the walk is cached for the
  form layer.

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
  strings by bytes, the /CF crypt filters included). The object number alone
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

AES-128 and RC4 reopens were already well under a millisecond; the saving
is the R6 key derivation, which on the web is dominated by package:crypto's
emulated 64-bit SHA-384/512.

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

Prevalence: in the private real-world corpus 8 of 53 files have no /ID, all
at most 1.7 MB (1-20 ms each); none of the no-/ID files in either corpus
has an /AcroForm. DartPDF's own writer always emits /ID. The large-file case
needs a big third-party file without /ID (some scanner output), which the
corpora don't contain. None of the 53 private files is encrypted; R6
appears in the checked-in pdf.js suite.

## Files

- `packages/dart_pdf_editor/lib/src/editing/editing_controller.dart`:
  constructor gate (`_mayHoldFormSecrets`, `_holdsWithheldValue`),
  `_resolveFormSecretId`, `debugFormSecretIdResolved`, `_openRevision`.
- `packages/pdf_document/lib/src/document_identity.dart`:
  `pdfFallbackDocumentId`.
- `packages/pdf_cos/lib/src/document.dart`: `openAppended(password:)`,
  `_sameEncryptDictionary`/`_sameCos`; `packages/pdf_document/lib/src/document.dart`:
  `PdfDocument.openAppended` forwards the password.
- Tests: `form_secret_store_test.dart` (no hash or `readAll` without a
  withheld field, a withheld field in a no-/ID file still restoring, the
  first fill after another edit filing under the opened hash),
  `editing_incremental_reload_test.dart` (R6 undo keeps the handler and
  matches a cold open, with and without a user password),
  `standard_security_handler_test.dart` (an earlier revision reuses the
  keys; a re-keyed /Encrypt under the same number re-authenticates; one that
  keeps the key material but swaps a crypt filter is not donated the old
  handler).
