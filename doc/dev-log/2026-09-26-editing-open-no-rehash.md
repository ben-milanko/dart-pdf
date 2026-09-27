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
    answer is exact. `_holdsWithheldValue` asks the field's own withheld
    marker first (see the gotcha below). The open itself reads no field.
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
  hashes `_openedBytes` (`sublistView(_bytes, 0, _revisions[0])`). Every
  revision appends to that prefix, so the key is byte-identical to the
  eager one. The fill must pass that id explicitly as `documentId:`.
  Passing null makes `setPasswordValue` hash `document.cos.bytes`, the
  *current* revision; after any earlier edit the /ID it writes would then
  differ from the store key, and the value would be lost on reopen. There
  is a test for exactly that (a first withheld fill after an unrelated
  edit).
- `_resetTo` (redaction burn) replaces the buffer, so it resolves the id
  first when a store is attached. The burn is O(file) anyway. A decision
  still pending at the burn simply carries on: the burn starts a fresh
  history, so the burned file is revision 0, the only state the session can
  show again, and the bytes `_loadFormSecrets` filters against.
- `pdfFallbackDocumentId` (pdf_document `document_identity.dart`) is the
  hash on its own, so the controller does not have to open a document to
  get it. The first prototype re-opened the prefix inside the getter, which
  on an AES-256 file would have re-run the password check.
- **Test the field's own marker first.** `_holdsWithheldValue` is
  `dict[DartPdfPasswordWithheld] == true && isPassword && value == null`.
  The marker is one lookup in the field's own dictionary (the filler writes
  it there and nowhere else). `isPassword` and `value` resolve inheritable
  /Ff and /V up the /Parent chain, with a fresh visited set per call. The
  first cut asked `isPassword` first, for every terminal field, and on a
  deep hierarchy (/FT on a root hundreds of levels up) that is O(fields x
  depth): the round-6 review measured the first `fields` read of a
  depth-1000 x 2000-leaf form at 13.6 -> 163.5 ms AOT against base, and a
  0.74 MB depth-3000 x 3000-leaf file at 31 -> 797 ms. Base never computes
  an inherited attribute for every field at that read; the form layer only
  does so for the widgets on the page that attached. With the marker first,
  only a marked field climbs /Parent. A crafted file that puts the marker
  on every leaf of a deep tree still costs O(fields x depth) (not
  memoised; our filler only marks password fields, and base's
  `formWidgetsOn` is already super-linear on crafted files).
- **Exact only at revision 0.** The hook records whether its form is
  revision 0 (`_decideFormSecretsOn(opened: _cursor == 0)`). A form first
  read at a later revision may have lost a field revision 0 withheld - the
  toolbar's Flatten from a cover page removes every field without the
  controller's form ever being read - and an undo brings it back. So a
  first read after an edit falls back to the eager open's load (the hash
  and the store read), paid then instead of at open. Over the session that
  is the same CPU as base, but the hash now runs inside `formWidgetsOn`,
  i.e. in the build of the first widget page, which can land in a scroll:
  about 180 ms AOT for a 22 MB file (edit-first numbers below).
- **Why not ask revision 0 after an edit.** The round-6 review suggested
  deciding exactly against revision 0 instead: reopen the prefix with
  `_document.openAppended` (keys donated, xref lazy) and run the same test
  over its fields, hashing only when it really withholds something. That
  was built and measured. It takes the hash out of the scroll on a big
  file (22 MB with a 50-field form behind a cover page: 182 -> 0.64 ms over
  open plus the attach), but the extra `fields` read costs three times the
  hash it saves or more on a small file whose bytes are mostly form, so
  those sessions ended up slower than base: 0.62-0.66x over open plus the
  attach for a 5000-field spread form, a depth-50 x 3000-leaf form and 60
  option-heavy combo boxes (0.85x for 2000 fields in object streams). The
  fallback stays at parity for every class, so it stays (edit-first
  numbers below).
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
  deciding there costs one pass over a list already built: one map lookup
  per field, plus the inherited lookups of any marked field. It sees
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
- A deep hierarchy (a chain of 300 named field nodes, /FT and an indirect
  /Ff on the root only, 1000 leaves behind a cover page): after the first
  `fields` read has settled the decision, the root's /Ff object is still
  unloaded - one inherited-flag lookup afterwards loads exactly that one
  object - so no unmarked field climbed /Parent. With the password flag on
  the root and the marker on the last leaf, the decision still finds it and
  the stored value comes back.
- A prefill of a field from another `PdfAcroForm`, `forgetFormSecrets`
  before any read, a redaction burn before any read, a withheld field
  nested under /Kids, and a withheld orphan widget (missing from /Fields,
  reconciled back) all behave.

Mutation checks: the round-3 controller fails nine of the new tests - the
two dropdown open costs and the orphan widget are what it got wrong, the
other six pin when the store read happens, which round 3 did at
construction. Dropping the `formFieldTextValue` settle or the
`forgetFormSecrets` settle each fails its own test; a `formSecretsLoaded`
that does not read the fields hangs every test that awaits it. Asking
`isPassword` before the marker fails the deep-hierarchy probe, and
dropping the revision-0 guard (trusting the later revision's fields) fails
the Flatten-then-undo test.

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
`_loadFormSecrets` reopens revision 0 through the same `_openRevision` to see
which fields take a stored value, so on an R6 file it no longer re-runs the
key derivation either.

Noticed on the way, not changed: `decryptObjectGraph` decrypts strings
inside dictionaries, arrays and stream dictionaries in place, so an indirect
object that is itself a bare string (`8 0 obj (...) endobj`) is never
decrypted. Base and branch behave the same way.

## Numbers

### Round 7: the marker first (the code as committed)

Base is origin/main at 4d46406d; patched is this branch. Every A/B ran 6
rounds ABAB with the order flipped each round, one process per side per
round, 7 reps per process after 2 warm-ups. The clock is thread CPU
(`clock_gettime(CLOCK_THREAD_CPUTIME_ID)` through `dart:ffi`); load average
3-5. Figures are medians of the per-round medians, and the median of the
per-round base/patched ratios; above 1 means patched is faster.

The AOT mirror (`dart compile exe` from each worktree, scratch only) runs
the constructor's library calls - base: `pdfPermanentDocumentId`; patched:
the trailer id plus `PdfAcroForm.of(onFields:)` with the controller's hook
and `_holdsWithheldValue` copied verbatim - then the viewer's first steps.
Stages are cumulative from the open, so base's figures include the hash it
pays at open:

- A: open plus the constructor's decision;
- B: plus `document.pages` and attaching page 0 (`formWidgetsOn(0)`);
- D: plus the first `fields` read (where the no-/ID decision now runs);
- C: plus attaching page 1 (the first widget page of the `-cover` and
  `spread` inputs).

Inputs, generated in scratch with the round-6 reviewer's generator (none
has a trailer /ID except the control):

- `noid-big`: 22.1 MB, 100 pages of random image streams, no form.
  `noidform-big`: the same plus 50 text fields on page 1. `withid-big`:
  the no-form file with an /ID (control).
- Realistic forms: `flat5000-cover` / `-p0` (5000 flat text fields on page
  1 behind a cover page, or on page 0; 0.79 MB), `objstm2000-cover` (2000
  fields in object streams, 42 KB), `opt-60x1500-cover` (60 combo boxes of
  1500 [export display] pairs, 2.76 MB), `annots-2000x20` (an empty
  /AcroForm and 2000 pages x 20 link annotations, 4.45 MB),
  `spread-d6x5000` (5000 leaves six levels deep over 50 widget pages).
- Deep hierarchies, /FT on the root only and no /Ff: `deep-DxN-cover` puts
  N leaves under a chain of D named field nodes on page 1; `deep-8x2000-p0`
  on page 0; `spread-dDxN` spreads them round-robin over the widget pages
  after a cover page (d50x3000 and d3000x3000 over 30 pages, d1000x2000
  over 20). `spread-d3000x3000` (0.74 MB) is the review's adversarial file.

AOT mirror (ms, base -> patched, pair ratio):

| input | A open | B + attach 0 | D + fields | C + widget page |
| --- | ---: | ---: | ---: | ---: |
| noid-big | 184.8 -> 0.048 (3848x) | 185.1 -> 0.265 (697x) | same | same |
| noidform-big | 182.8 -> 0.061 (3015x) | 183.1 -> 0.284 (647x) | 183.2 -> 0.388 (473x) | 183.2 -> 0.430 (427x) |
| withid-big (control) | 0.049 -> 0.050 (0.97x) | 0.265 -> 0.265 (1.00x) | same | same |
| flat5000-cover | 7.94 -> 1.42 (5.60x) | 8.58 -> 2.06 (4.18x) | 23.6 -> 16.8 (1.41x) | 234.3 -> 240.0 (0.98x) |
| flat5000-p0 | 7.90 -> 1.43 (5.57x) | 274.1 -> 277.1 (0.98x) | same | same |
| objstm2000-cover | 0.891 -> 0.557 (1.61x) | 1.19 -> 0.857 (1.39x) | 5.46 -> 5.20 (1.05x) | 47.3 -> 48.8 (0.97x) |
| opt-60x1500-cover | 23.5 -> 0.029 (820x) | 23.5 -> 0.044 (537x) | 100.1 -> 77.2 (1.29x) | 100.2 -> 77.3 (1.29x) |
| annots-2000x20 | 47.7 -> 11.3 (4.26x) | 56.3 -> 19.9 (2.87x) | 116.0 -> 79.6 (1.45x) | same |
| spread-d6x5000 | 7.55 -> 0.887 (8.40x) | 8.30 -> 1.67 (5.01x) | 24.6 -> 18.2 (1.37x) | 29.7 -> 24.2 (1.26x) |
| deep-8x2000-p0 | 2.90 -> 0.288 (10x) | 52.5 -> 51.5 (1.02x) | same | same |
| deep-30x5000-cover | 7.40 -> 0.786 (9.44x) | 8.04 -> 1.42 (5.64x) | 23.8 -> 17.1 (1.39x) | 269.2 -> 268.3 (1.01x) |
| deep-200x3000-cover | 4.58 -> 0.475 (9.70x) | 4.97 -> 0.858 (5.83x) | 13.7 -> 9.61 (1.45x) | 328.5 -> 323.7 (1.02x) |
| deep-1000x2000-cover | 3.82 -> 0.452 (8.41x) | 4.07 -> 0.711 (5.72x) | 11.6 -> 8.03 (1.44x) | 2254 -> 2202 (1.02x) |
| spread-d50x3000 | 4.46 -> 0.445 (10x) | 4.89 -> 0.871 (5.62x) | 14.2 -> 10.1 (1.41x) | 18.0 -> 14.1 (1.28x) |
| spread-d1000x2000 | 3.81 -> 0.448 (8.54x) | 4.10 -> 0.739 (5.56x) | 13.0 -> 9.78 (1.34x) | 127.2 -> 121.7 (1.05x) |
| spread-d3000x3000 | 7.02 -> 0.893 (7.86x) | 7.45 -> 1.32 (5.62x) | 32.8 -> 25.9 (1.28x) | 1111 -> 1082 (1.03x) |

"same" means nothing new runs at that stage (no form, or the widgets are
on page 0 so attaching it already read the fields).

What this shows, and what it does not:

- Every input is at parity with base or faster at every stage. The lowest
  medians are 0.97x (range 0.95-1.01) for objstm2000-cover at the widget
  page, 0.98x for flat5000-cover at the widget page and flat5000-p0 at its
  attach (0.95-1.00), and 0.97x for the control's open. At those stages
  both sides run the same code: the widget matching in `formWidgetsOn`
  (O(annotations x fields)) dominates.
- The first `fields` read on its own (D minus B, per round) now costs the
  same on both sides within noise: 8.92 vs 9.04 ms for spread-d1000x2000,
  25.4 vs 24.6 ms for spread-d3000x3000, 15.0 vs 14.7 ms for
  flat5000-cover, 76.8 vs 77.1 ms for opt-60x1500-cover. So the decision
  adds nothing measurable to that read. The advantage at D and C is the
  hash base paid at open, carried in the cumulative figures.
- Before the reorder the review measured spread-d1000x2000 at D 13.6 ->
  163.5 ms (0.08x) and C 130.7 -> 278.3 ms (0.47x), spread-d50x3000 at
  0.75x / 0.78x, and the depth-3000 file at 31 -> 797 ms for the first
  fields read. Those rows are now 1.34x / 1.05x, 1.41x / 1.28x and 1.28x /
  1.03x.
- The per-field cost is O(1) only for unmarked fields. A crafted file that
  marks every leaf of a deep tree still pays O(fields x depth) (not
  measured; see the gotcha above).

The edit-first path, which no earlier table covered: A is the open; then an
edit on the cover page (untimed, the same work on both sides); E is the
first widget page attaching at that later revision, where the shipped code
falls back to the hash and the store read. Same method and inputs:

| input | A open | E widget page after an edit | A + E |
| --- | ---: | ---: | ---: |
| noidform-big | 181.9 -> 0.082 (2217x) | 0.160 -> 181.9 (the hash) | 182.1 -> 182.0 (1.00x) |
| flat5000-cover | 7.92 -> 1.42 (5.58x) | 267.5 -> 269.2 (0.99x) | 275.4 -> 270.6 (1.01x) |
| objstm2000-cover | 0.905 -> 0.534 (1.66x) | 46.0 -> 45.0 (1.02x) | 46.9 -> 45.5 (1.03x) |
| opt-60x1500-cover | 23.1 -> 0.031 (744x) | 74.2 -> 98.3 (0.75x) | 97.5 -> 98.4 (0.99x) |
| deep-30x5000-cover | 7.37 -> 0.791 (9.30x) | 300.8 -> 307.4 (0.98x) | 308.2 -> 308.2 (1.00x) |
| spread-d6x5000 | 7.42 -> 0.777 (9.55x) | 21.6 -> 27.7 (0.77x) | 29.1 -> 28.4 (1.01x) |
| spread-d50x3000 | 4.45 -> 0.448 (9.93x) | 12.7 -> 16.8 (0.76x) | 17.2 -> 17.2 (1.00x) |
| spread-d1000x2000 | 3.81 -> 0.448 (8.52x) | 118.1 -> 121.7 (0.97x) | 121.9 -> 122.1 (1.00x) |

Over open plus that attach every input is at parity (0.99-1.03x), but the
hash has moved out of the open and into the attach: 0.16 -> 182 ms on the
22 MB form. The rejected revision-0 variant (see the gotcha above),
measured the same way:

| input | E widget page after an edit | A + E |
| --- | ---: | ---: |
| noidform-big | 0.161 -> 0.572 (0.28x) | 182.4 -> 0.637 (287x) |
| flat5000-cover | 264.4 -> 251.6 (1.05x) | 272.5 -> 253.0 (1.07x) |
| objstm2000-cover | 44.9 -> 53.0 (0.85x) | 45.8 -> 53.5 (0.85x) |
| opt-60x1500-cover | 76.4 -> 153.2 (0.50x) | 99.3 -> 153.2 (0.65x) |
| deep-30x5000-cover | 301.5 -> 285.3 (1.06x) | 308.8 -> 286.1 (1.08x) |
| spread-d6x5000 | 21.7 -> 43.2 (0.50x) | 29.1 -> 44.0 (0.66x) |
| spread-d50x3000 | 12.7 -> 27.4 (0.46x) | 17.2 -> 27.9 (0.62x) |
| spread-d1000x2000 | 119.6 -> 129.6 (0.92x) | 123.5 -> 130.1 (0.95x) |

The real `PdfEditingController` with an `InMemoryFormSecretStore` under
`flutter test` (JIT), the round-6 reviewer's harness, 5 interleaved rounds
of 5 reps: the constructor, then plus `document.pages` and
`formWidgetsOn(0)`, then plus `formWidgetsOn(1)` (ms, base -> patched, pair
ratio):

| input | ctor | + attach 0 | + widget page |
| --- | ---: | ---: | ---: |
| noid-big | 202.7 -> 0.315 (643x) | 204.4 -> 1.51 (136x) | same |
| withid-big (control) | 0.281 -> 0.281 (1.02x) | 0.823 -> 0.812 (1.01x) | same |
| flat5000-cover | 9.60 -> 2.24 (4.28x) | 12.7 -> 2.96 (4.11x) | 139.2 -> 145.2 (0.96x) |
| opt-60x1500-cover | 25.7 -> 0.182 (142x) | 25.8 -> 0.229 (115x) | 117.1 -> 91.5 (1.25x) |
| annots-2000x20 | 53.7 -> 13.0 (4.25x) | 68.4 -> 24.5 (2.79x) | same |
| spread-d6x5000 | 8.91 -> 1.25 (7.07x) | 9.90 -> 2.02 (4.78x) | 35.3 -> 27.9 (1.32x) |
| spread-d50x3000 | 5.28 -> 0.798 (6.87x) | 5.74 -> 1.29 (4.65x) | 20.9 -> 16.0 (1.29x) |
| spread-d1000x2000 | 4.63 -> 0.758 (6.13x) | 4.95 -> 1.07 (4.61x) | 177.8 -> 174.6 (1.02x) |
| spread-d3000x3000 | 8.42 -> 1.44 (5.94x) | 10.5 -> 1.99 (4.48x) | 1571 -> 1559 (1.01x) |

The round-6 review had the old order at 0.69x (d50) and 0.54x (d1000) at
the widget page on this harness.

flat5000-cover at the widget page is the weakest cell in either harness:
0.96x here (range 0.91-0.98) and 0.95x over a focused 8-round rerun;
0.98x in the AOT table (0.97-1.00, and 0.98x with 0.96-1.04 over a focused
10-round rerun), where flat5000-p0 and objstm2000-cover sit at 0.97-0.98x. That stage is
`formWidgetsOn`'s widget matching - 5000 annotations x 5000 fields, the
same code on both sides - and the extra 2-5% is not the decision:
probing with the AOT mirror, a patched mirror with no hook at all was as
slow as the real one, and base's mirror compiled against this branch's
libraries was as fast as base. It follows the heap state the open leaves
behind (it goes away when the open hashes), not work the branch adds. A
field-by-widget map would remove the O(annotations x fields) matching
itself; that is a separate change.

Undo on the R6 user-password fixture this round: the AOT reopen plus a
page 0 decrypt 9.50 -> 0.011 ms (887x); `controller.undo()` plus reading
page 0's annotations under JIT 7.59 -> 0.681 ms (11x).

### Round 4 (before the marker went first)

These were measured on the previous revision of this branch, which asked
`isPassword` before the marker. The reorder only removes work from the
decision, and none of these runs makes an edit, so the revision-0
fallback does not run in them.

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

Within these inputs no stage was slower than base beyond the control's
noise. That claim was too broad as first written: none of these inputs had
a deep field hierarchy, and the round-6 review found the old decision order
at 0.08-0.78x on those (see round 7 above). The patched open costs what
opening the file costs (objstm-spread-400's 9-12 ms is its 51k-object xref
stream, which base pays too). A no-/ID form that does withhold a value, or
one whose fields are first read after an edit, pays the hash and the store
read at that read instead of at open, the same work base did at open.

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
  `_openFormSecrets`, `_decideFormSecretsOn`, `_openedBytes`,
  `_settleFormSecrets`, `_settleFormSecretsNow`,
  `formSecretsLoaded` (now a getter), the `acroForm` hook,
  `_holdsWithheldValue` (marker first), `_resolveFormSecretId`,
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
