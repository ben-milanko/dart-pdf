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
- The store read (`_loadFormSecrets`, a keychain `readAll` on native) only
  ever kept values for fields the opened file shows as withheld and
  unfilled (`_holdsWithheldValue`: password flag, no /V,
  `/DartPdfPasswordWithheld true`), so it runs only when such a field
  exists (`_openFormSecrets`):
  - no /AcroForm: skipped, decided in O(1);
  - a trailer /ID: read at open, as before (the id is free, and the load
    parses the form only when the store returns something);
  - no /ID: the decision **waits for the first read of the form's fields**.
    The controller's `acroForm` hands `PdfAcroForm.of` an `onFields` hook
    (new, pdf_document) while the decision is pending, and the hook settles
    it with `fields.any(_holdsWithheldValue)` - the load's own test, so the
    answer is exact. The open itself reads no field.
- The fallback id is resolved lazily by `_resolveFormSecretId`, on first
  need: a withheld fill, `forgetFormSecrets`, an undo/redo that moves a
  stored value, a store read, or `formSecretDocumentId`.

Who reads the fields first: the viewer's form layer (`FormInteractionLayer`
in reading/select modes, `FormFieldLabelLayer` under the form tool) calls
`formWidgetsOn(page)` as a page attaches, and that reads `fields` as soon as
the page shows a Widget annotation. A password field can only be tapped on
such a page, so the prefill (`formFieldTextValue`) is never asked for before
the store read has started - the same async race base had, with the read
starting at the first widget page instead of at construction. A fill looks
its field up (`fieldNamed`), which reads the fields too.

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
  first when a store is attached. The burn is O(file) anyway. A decision
  still pending at the burn simply carries on: the burn starts a fresh
  history, so the burned file is revision 0, the only state the session can
  show again, and the bytes `_loadFormSecrets` filters against.
- `pdfFallbackDocumentId` (pdf_document `document_identity.dart`) is the
  hash on its own, so the controller does not have to open a document to
  get it. The first prototype re-opened the prefix inside the getter, which
  on an AES-256 file would have re-run the password check.
- **Exact only at revision 0.** The hook records whether its form is
  revision 0 (`_decideFormSecretsOn(opened: _cursor == 0)`). A form first
  read at a later revision may have lost a field revision 0 withheld - the
  toolbar's Flatten from a cover page removes every field without the
  controller's form ever being read - and an undo brings it back. So a
  first read after an edit falls back to the eager open's load (the hash
  and the store read), paid then instead of at open, never more than base.
- **Nothing may wait on a read that never comes.** `formSecretsLoaded` is
  now a getter over a completer. It completes when the decision settles
  (immediately when there is nothing to read). Asking for it reads the
  fields then and there if nothing has yet (`_settleFormSecretsNow`), so a
  host that awaits it before building the viewer cannot deadlock. The same
  happens when `formFieldTextValue` is given a field from some other
  `PdfAcroForm` instance, and `forgetFormSecrets` settles a pending decision
  without a read (the store is being cleared anyway).
- **Why not a cheaper look at open.** Three review rounds each found an
  open-time cost in a gate that tried to rule the store out at construction:
  - Round 1 went through `PdfAcroForm.fields`. Its orphan-widget reconcile
    maps every page and parses every annotation, and `PdfAcroForm._pages`
    looked pages up with `page(i)`, quadratic on a flat /Kids tree (1.36 s
    at 4000 pages against 12 ms for the hash; #969 fixed `_pages`).
  - Round 2 walked /Fields only, but that still costs more than the hash on
    a field-dense form: a node is an object load of about 1.5-3.5 us native,
    and a field dictionary occupies about 200 bytes of file (5000 fields:
    JIT 11 -> 48-79 ms).
  - Round 3 budgeted the walk by node count, but one node can cost far more
    than the bytes it occupies. A combo box parses its whole inline /Opt
    list on resolve (0.35-1.4 us per entry, against 0.1-0.25 us to hash the
    same bytes), and on the web each field in its own object stream pays a
    pure-Dart inflate. With no widget on page 0, base's attach never touched
    those objects: option-heavy forms ran at 0.27-0.68x of base AOT and
    0.14-0.15x under dart2js, object-stream-spread fields at 0.34x on the
    web.

  The base viewer reads the fields anyway once a widget page attaches, so
  deciding there costs one `.any` over a list already built, and it sees
  exactly what the load sees, including fields the form reconciles from
  orphan widgets (which the /Fields walks missed).
- `PdfAcroForm.of(onFields:)` calls the hook once, after caching the list,
  so the hook can read `form.fields` again without recursing.
  `form_test.dart` pins it: not called by `of`, called once by the first
  read (here through `fieldNamed`), never again.

`form_secret_store_test` pins the behaviour:

- A 3000-page no-/ID form's constructor makes no `pageTreeWalk`, and its
  `objectsLoaded` is the same with 0 or 4000 link annotations.
- Two-page no-/ID forms with a cover page and 20 or 1000 combo boxes (40
  option pairs each), flat or spread over object streams: from the
  constructor through the cover page attaching, 20 and 1000 dropdowns load
  the same objects (4 flat; 5 and one object stream spread) and no store
  read happens; the dropdown page attaching settles the decision without a
  hash. The round-3 code loads 24 and 25 on the 20-dropdown file.
- A withheld field: the store is read when the form layer reads the fields,
  not before, and the value comes back.
- An edit before the first read falls back to the load; a Flatten from the
  cover followed by undo still shows the stored value.
- A prefill of a field from another `PdfAcroForm`, `forgetFormSecrets`
  before any read, a redaction burn before any read, a withheld field
  nested under /Kids, and a withheld orphan widget (missing from /Fields,
  reconciled back) all behave.

Mutation checks: the round-3 controller fails nine of the new tests - the
two dropdown open costs and the orphan widget are what it got wrong, the
other six pin when the store read happens, which round 3 did at
construction. Dropping the revision-0 guard, the `formFieldTextValue`
settle or the `forgetFormSecrets` settle each fails its own test; a
`formSecretsLoaded` that does not read the fields hangs every test that
awaits it.

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

Base is origin/main at 4d46406d; patched is this branch. Every A/B ran 6
rounds ABAB with the order flipped each round, one process per side per
round. The clock is thread CPU (`clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)`
through `dart:ffi`; `process.threadCpuUsage()` under node), not wall time,
because the machine was shared (load average 11-20). Figures are medians of
the per-round medians, and the median of the per-round base/patched ratios;
above 1 means patched is faster.

Harnesses (scratch, not committed):

- JIT: the real `PdfEditingController` with an `InMemoryFormSecretStore`
  under `flutter test`, 5 reps per round. "+ attach" adds the viewer's
  `document.pages` and `formWidgetsOn(0)`; "+ fields" then attaches the
  first page that shows a widget (`formWidgetsOn(p)`), the first read of the
  fields - on base that is where the form layer's work lands, on the branch
  it also settles the no-/ID decision. The time is cumulative from the
  constructor.
- AOT: a `dart compile exe` bench built from each worktree that mirrors the
  constructor's library calls (base: `pdfPermanentDocumentId`; patched: the
  trailer id and `PdfAcroForm.of(onFields:)` with the controller's hook
  copied verbatim), 9 reps per round. "+ pages" adds `document.pages`,
  "+ fields" the first `fields` read.
- dart2js: the same mirror compiled with `dart compile js -O4`, run under
  node, inputs generated in JS, 9 reps per round.

Inputs, generated in scratch (none has a trailer /ID except the control):

- `noid-big`: 21.6 MB, 100 pages of random image streams. `withid-big`: the
  same file with an /ID.
- The round-4 class, forms whose fields cost more to resolve than their
  bytes, all with page 0 showing no widget: `optpairs-40x250` (40
  country-style combo boxes of 250 [export display] pairs, 314 KB),
  `opt-60x1500` (60 combos of 1500 options, 1.4 MB), `optpairs-60x750`
  (1.4 MB), `objstm-spread-400` (400 fields, each in its own object stream,
  3 MB). `optpairs-40x250-p0` puts the combos on page 0.
- Earlier classes: `flat5000` (5000 flat fields), `chain-edge` (a /Kids
  chain 1100 deep, padded to 4.3 MB: the round-3 budget's worst case),
  `small120` (120 fields on page 0, 20 KB), `bigv-100x8k` (100 text fields
  with 8 KB values), `r6-noid-form400` (an AES-256 user-password form, 2.2
  MB, widgets on page 0).

JIT, the real controller (ms, base -> patched, pair ratio):

| input | ctor | ctor + attach | + fields |
| --- | ---: | ---: | ---: |
| noid-big (no form) | 199.2 -> 0.147 (1364x) | 199.5 -> 0.478 (418x) | same |
| withid-big (control) | 0.145 -> 0.156 (0.92x) | 0.504 -> 0.521 (0.96x) | same |
| optpairs-40x250 | 3.26 -> 0.125 (26x) | 3.34 -> 0.184 (18x) | 13.7 -> 12.1 (1.13x) |
| optpairs-40x250-p0 | 3.25 -> 0.138 (23x) | 13.1 -> 10.2 (1.23x) | same |
| opt-60x1500 | 14.7 -> 0.174 (84x) | 14.8 -> 0.235 (64x) | 49.9 -> 39.8 (1.25x) |
| optpairs-60x750 | 13.7 -> 0.161 (85x) | 13.8 -> 0.224 (63x) | 58.5 -> 45.8 (1.29x) |
| objstm-spread-400 | 44.0 -> 11.9 (3.7x) | 44.2 -> 12.0 (3.7x) | 73.9 -> 43.7 (1.69x) |
| flat5000 | 11.3 -> 2.02 (5.4x) | 12.1 -> 2.90 (4.0x) | 35.5 -> 28.4 (1.24x) |
| chain-edge | 40.0 -> 0.53 (76x) | 40.1 -> 0.57 (70x) | 42.8 -> 4.41 (9.7x) |
| small120 | 0.313 -> 0.086 (3.6x) | 0.852 -> 0.639 (1.35x) | same |
| bigv-100x8k | 8.20 -> 0.31 (26x) | 8.29 -> 0.41 (21x) | 12.8 -> 4.24 (3.2x) |
| r6-noid-form400 | 28.8 -> 7.70 (3.7x) | 33.5 -> 12.3 (2.7x) | same |

"same" means the widget page is page 0 (or there is no form), so the attach
already read the fields. The control's range was wide (0.59-1.36x); a
focused 8-round rerun put it at 0.191 -> 0.185 ms (1.10x) and 0.593 ->
0.597 ms (1.01x), and small120's attach at 1.624 -> 1.659 ms (0.97x, range
0.74-1.13): parity. On every patched no-/ID open `debugFormSecretIdResolved`
stayed false after `formSecretsLoaded` (no hash, no store read); the
control resolved its free /ID.

AOT mirror (ms, base -> patched, pair ratio):

| input | open + decision | + pages | + fields |
| --- | ---: | ---: | ---: |
| noid-big | 183.7 -> 0.067 (2754x) | 184.0 -> 0.315 (584x) | same |
| withid-big (control) | 0.070 -> 0.068 (1.01x) | 0.339 -> 0.343 (0.99x) | 0.346 -> 0.322 (1.00x) |
| optpairs-40x250 | 2.61 -> 0.016 (164x) | 2.63 -> 0.028 (93x) | 9.54 -> 6.20 (1.56x) |
| opt-60x1500 | 11.2 -> 0.021 (527x) | 11.3 -> 0.036 (310x) | 42.7 -> 30.8 (1.40x) |
| optpairs-60x750 | 11.6 -> 0.022 (535x) | 11.8 -> 0.037 (318x) | 52.3 -> 38.9 (1.30x) |
| objstm-spread-400 | 34.1 -> 8.94 (3.8x) | 34.1 -> 9.12 (3.7x) | 58.2 -> 32.7 (1.79x) |
| flat5000 | 8.99 -> 1.40 (6.4x) | 9.55 -> 2.14 (4.4x) | 26.4 -> 19.3 (1.42x) |
| chain-edge | 35.6 -> 0.216 (164x) | 35.7 -> 0.224 (163x) | 38.5 -> 1.94 (20x) |
| small120 | 0.218 -> 0.036 (5.9x) | 0.240 -> 0.054 (4.4x) | 0.510 -> 0.314 (1.59x) |
| bigv-100x8k | 7.19 -> 0.038 (188x) | 7.17 -> 0.059 (122x) | 8.56 -> 1.42 (6.0x) |
| r6-noid-form400 | 28.0 -> 9.48 (3.0x) | 28.2 -> 9.75 (2.9x) | 31.3 -> 12.8 (2.5x) |

dart2js -O4 on node (ms, base -> patched, pair ratio):

| input | open + decision | + pages | + fields |
| --- | ---: | ---: | ---: |
| noid-big | 141.5 -> 0.46 (308x) | 140.6 -> 1.07 (133x) | 141.3 -> 0.81 (174x) |
| withid-big (control) | 0.108 -> 0.095 (1.12x) | 0.642 -> 0.646 (1.02x) | 0.582 -> 0.571 (1.01x) |
| optpairs-40x250 | 2.02 -> 0.039 (53x) | 2.07 -> 0.060 (35x) | 15.6 -> 12.8 (1.19x) |
| opt-60x1500 | 8.74 -> 0.027 (319x) | 8.77 -> 0.050 (174x) | 70.0 -> 58.7 (1.19x) |
| objstm-spread-400 | 30.9 -> 12.5 (2.5x) | 28.0 -> 12.1 (2.4x) | 114.0 -> 94.0 (1.21x) |
| flat5000 | 7.20 -> 1.51 (4.8x) | 7.89 -> 2.29 (3.4x) | 44.2 -> 39.1 (1.12x) |
| chain-edge | 27.5 -> 0.154 (183x) | 27.6 -> 0.169 (167x) | 30.4 -> 3.02 (10x) |
| small120 | 0.183 -> 0.044 (4.1x) | 0.208 -> 0.068 (3.0x) | 0.858 -> 0.734 (1.17x) |
| bigv-100x8k | 5.31 -> 0.066 (80x) | 5.29 -> 0.096 (56x) | 7.28 -> 2.06 (3.5x) |

No workload in any of the three harnesses is slower than base at any stage
beyond the control's noise. The patched open costs what opening the file
costs (objstm-spread-400's 9-12 ms is its 51k-object xref stream, which base
pays too). The first read of the fields costs base's read minus the hash:
the decision is one `.any` over the list the read just built. What remains
slower than base by construction is only a no-/ID form that does withhold a
value, or one whose fields are first read after an edit: those pay the hash
and the store read at that read instead of at open, the same work base did.

Undo on an R6 fixture (`buildEncryptedPdf(revision: 6)`, 12 rectangles then
12 undos, three revisions for the mirrors):

| path | base | patched | ratio |
| --- | ---: | ---: | ---: |
| `controller.undo()`, JIT, user password set | 6.97 ms | 0.102 ms | 68x |
| the reopen + page 0 decrypt, AOT | 9.54 ms | 0.020 ms | 479x |

Earlier rounds measured the owner-only case too (JIT 7.32 -> 0.30 ms, 25x;
AOT 9.73 -> 0.030 ms), dart2js -O2 on node (72-77 ms -> below 0.2 ms, the
timer's resolution; there the emulated 64-bit SHA-384/512 dominates) and R4
(AES-128) `controller.undo()` 0.51 -> 0.062 ms (8.3x), because donating the
handler also skips the MD5/RC4 key derivation.

App end to end, measured in the first round against the base of that time
(the hash it removes does not depend on anything merged since): a desktop
open through `EditorScreen` (flutter test, the app's incoming-file channel,
`PdfPerfLog` timestamps), open trigger to the editable view's page 0 ready,
on a 21.5 MB no-/ID file, 5 rounds of 3 reps per process, rep 0 dropped as
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

Earlier rounds' gates, for the record: round 1 (`PdfAcroForm.fields` at
open) was quadratic before #969 and one page walk slower after it; round 2
(an unbudgeted /Fields walk) fixed the link-annotation class
(annotform-2000x20: 68.4 -> 16.1 ms JIT, where the `fields` gate took 735 ms
AOT) but made 5000-field forms 4-7x slower; round 3 (a node budget) brought
those to parity but left the /Opt and object-stream class above at
0.14-0.36x. The deferred decision replaces all three.

Prevalence: in the private real-world corpus 8 of 53 files have no /ID, all
at most 1.7 MB (1-20 ms each); none of the no-/ID files in either corpus
has an /AcroForm. DartPDF's own writer always emits /ID. The large-file case
needs a big third-party file without /ID (some scanner output), which the
corpora don't contain. None of the 53 private files is encrypted; R6
appears in the checked-in pdf.js suite.

## Files

- `packages/dart_pdf_editor/lib/src/editing/editing_controller.dart`:
  `_openFormSecrets`, `_decideFormSecretsOn`, `_settleFormSecrets`,
  `_settleFormSecretsNow`, `formSecretsLoaded` (now a getter), the `acroForm`
  hook, `_holdsWithheldValue`, `_resolveFormSecretId`,
  `debugFormSecretIdResolved`, `_openRevision`.
- `packages/pdf_document/lib/src/form.dart`: `PdfAcroForm.of(onFields:)`.
- `packages/pdf_document/lib/src/document_identity.dart`:
  `pdfFallbackDocumentId`.
- `packages/pdf_cos/lib/src/document.dart`: `openAppended(password:)`,
  `_sameEncryptDictionary`/`_sameCos`, `_authenticatedEncrypt`/
  `_inlineEncrypt`; `packages/pdf_document/lib/src/document.dart`:
  `PdfDocument.openAppended` forwards the password.
- Tests: `form_secret_store_test.dart` (see section 1), `form_test.dart`
  (the `onFields` hook), `editing_incremental_reload_test.dart` (R6 undo
  keeps the handler and matches a cold open, with and without a user
  password), `standard_security_handler_test.dart` (an earlier revision
  reuses the keys; a re-keyed /Encrypt under the same number
  re-authenticates; one that keeps the key material but swaps a crypt
  filter is not donated the old handler; a donor that folded in a re-keyed
  /Encrypt does not vouch for it; an indirect /Encrypt entry the handler
  never read still donates).
