# Signature validation: per-revision memo, crypto core reused across revisions, hashing off the UI isolate

**Symptom.** With the annotations sidebar showing a signed field, every
validation hashed the whole signed span again on the UI isolate:

- when the panel opened;
- after every edit, undo and redo (`_dropStaleValidations` cleared the cache
  per revision);
- whenever a trust store or revocation client was set
  (`_invalidateValidations`) - the app does that when a signed document
  attaches and again when the EU list or AATL lands;
- and right after signing, although `_adoptDigitalSignature` had just
  validated the same bytes.

On a PAdES B-LTA document each approval-signature validation also ran a full
nested `validate()` of the document timestamp (`_padesLevel` ->
`_documentHasValidTimeStamp`), and the timestamp's own row hashed again: a
panel pass cost 3 whole-file hashes. `validationFor`'s `Future(() async {..})`
body ran synchronously on the UI isolate, so each of those was one frozen
task: ~0.15 s at 12 MB, ~0.6 s at 58 MB, over 1 s for a 58 MB B-LTA pass
(numbers below).

**Fix.**

- pdf_document `signature.dart`:
  - `_validateSignature` (the signature half of `validate`, no chain or
    revocation verdicts) is memoised per signature dictionary in a static
    `Expando`. A hit needs the same byte buffer object and length (one
    revision: `applyIncrementalUpdate` swaps in a new buffer, a reopen builds
    new dictionaries) and the same /ByteRange, /Contents, /SubFilter and
    /Cert, so an in-place edit of the dictionary is noticed. It is bypassed
    over a sparse buffer (`populatedRanges != null`). The buffer is held by a
    `WeakReference`: the COS layer keeps dictionaries alive across revisions,
    and the memo must not keep an outgrown session buffer alive with them.
  - `_documentHasValidTimeStamp` uses the timestamp's `_validateSignature()`
    rather than a full `validate()`. `signatureValid` passes through the
    chain and revocation steps unchanged, so the result is the same; the
    timestamp's own row then hits the memo.
  - The expensive part is split out as `PdfSignatureCryptoCore`: the digest,
    the CMS / PKCS#1 / RFC 3161 verification, the certificates, the signing
    time and the signature timestamp. It depends only on the covered bytes and
    those dictionary values, is plain data (sendable between isolates) and
    copies what it keeps, so it never pins the file buffer. Coverage and the
    "updated after this signature" problem, the PAdES level (/DSS plus
    document timestamps) and the embedded revocation status are derived on top
    of it for every revision. Problem order is unchanged.
  - `validate` / `validateOnline` take `PdfSignatureCoreResolver? cores`,
    consulted for the signature and for each document timestamp the PAdES
    level depends on. A resolved core that does not `describes()` the current
    dictionary is ignored and recomputed. `cryptoCore()` computes one
    directly; `PdfSignature.debugHashedBytes` counts bytes fed to range
    digests, for tests.
  - `problems` (and `certificates`) of a validation are now unmodifiable,
    since memoised results are shared. Nothing in the repo mutated them.
- dart_pdf_editor `PdfEditingController`:
  - `_signatureCores` keeps cores by field name across revisions (the
    resolver passed to `validate`). Revisions append to one buffer, so signed
    bytes only change where a revision rewrites them, and cores are dropped
    exactly there: past `beforeLength` in `_finishRevision` (a new edit over
    an undone tail), past the new length when an undo reopens a shorter
    prefix, all of them in `_resetTo` (redaction burn) and before the
    color-processing worker's whole-buffer commit (no prefix check there). The
    map starts empty for each controller. The whole verdict is never cached:
    the chain, live revocation and every per-revision part are redone.
  - `_adoptDigitalSignature` keeps the cores its own full `validate()`
    computed on the candidate - exactly the committed bytes - and adds them
    after the commit, so the panel does not hash a fresh signature again. It
    stays synchronous, and its prefix check compares 32-bit words when both
    views are aligned.
  - Native: `validationFor` first awaits `_ensureSignatureCores()`. When the
    current revision's signatures lack cores covering at least
    `signatureCoreOffloadBytes` (512 KB), one `Isolate.run`
    (`signature_validation_worker.dart`, native/stub by conditional import)
    gets one `TransferableTypedData` copy of the revision, the password and
    the missing field names, reopens the document and returns the cores by
    ownership transfer. A job over bytes a later revision rewrote is
    discarded. Chain building, revocation and `validateOnline`'s network
    step stay on the main isolate: a trust store is large to send and a host
    revocation client may not be sendable.
  - Each revision is settled once (`_signatureCoresRevision`): the first row
    to get there checks every kept core against its signature, drops the ones
    that no longer `describes()` it, and starts at most one job; every other
    row waits on whichever job is running (re-reading the slot after each
    wait, so jobs never run side by side) and then returns. Only signatures
    whose /ByteRange can be hashed at this revision count
    (`PdfSignature.hasSignableByteRange`, the same test validation applies),
    and a signature a job could not fill is remembered with its range
    (`_signatureCoresUnavailable`, dropped with the cores) and never sent
    again: validation computes that one inline. While the revision is
    settled, `_resolveSignatureCore` hands out kept cores without comparing
    them a second time (PdfSignature still checks the one it is given).
  - Web computes cores inline, as before, but they are still reused across
    revisions and trust-store changes.
  - The validation body also treats a disposed controller as stale, since
    the helper isolate may answer after the tab closed.

**Evidence** (base = origin/main at cc144ae7; documents built programmatically
from random-byte padding, signed self-signed ECDSA or RSA PAdES B-LTA with the
in-process test TSA and OCSP/CRL fixtures).

Bytes hashed (deterministic; multiples of the file size), pdf_document level,
all signatures per phase:

| document | panel open | trust store arrives | after an annotation edit |
|---|---|---|---|
| B-LTA | 3.0 -> 2.0 | 3.0 -> 0 | 3.0 -> 0 |
| self-signed | 1.0 -> 1.0 | 1.0 -> 0 | 1.0 -> 0 |

The same phases, thread-CPU medians (AOT, 5 interleaved rounds; "open"
includes the Jacobian ECDSA change):

| document | open | trust | edit |
|---|---|---|---|
| B-LTA 12 MB | 322.5 -> 214.0 ms | 321.2 -> 1.3 | 320.9 -> 2.7 |
| B-LTA 58 MB | 1515.5 -> 1014.0 | 1514.0 -> 1.3 | 1520.2 -> 2.8 |
| self-signed 12 MB | 142.3 -> 109.0 | 140.2 -> 1.5 | 139.7 -> 1.9 |
| self-signed 58 MB | 542.0 -> 509.5 | 542.9 -> 1.5 | 543.6 -> 1.9 |

Longest UI-isolate event-loop gap (1 ms periodic timer):

- AOT, the controller's steps (helper-isolate cores, then `validate(cores:)`),
  5 rounds, median: panel open 139 / 211 / 538 / 1015 ms -> 1.8 / 2.5 / 6.5 /
  6.4 ms for self 12 MB / B-LTA 12 MB / self 58 MB / B-LTA 58 MB (worst new
  round 8.6 ms); trust arrival -> 1.3-1.9 ms.
- The real `PdfEditingController` under `flutter test` (debug JIT), 3 rounds,
  median:
  - panel open: 196 / 256 / 594 / 1142 -> 9.9 / 12.4 / 11.5 / 12.4 ms (worst
    14.1 ms, inside the 20 ms budget);
  - one annotation edit with the panel open: 165-1136 -> 3.9-4.9 ms gap, and
    the re-validation's wall time 165-1699 -> 4-8 ms;
  - trust store arrives: 153-1128 -> 1.4-3.7 ms.
  Wall time to the first verdict stays about the same (the hash still runs,
  plus a copy and a reopen on the helper isolate).

Post-sign prefix check, 58 MB: 41.3 -> 14.7 ms (12 MB: 8.7 -> 3.2 ms).

Identity: validation fingerprints (digest, signature, coverage, chain,
problems, PAdES level, timestamp, embedded and live revocation, signer and
certificates) identical base vs new for 120 validations over 23 documents -
RSA, ECDSA self-signed and org-CA, PAdES B-B to B-LTA and B-LTA edited, a
document timestamp, certify, RC4/AES-128/AES-256 encrypted, a flipped byte, a
tampered CMS, a broken /ByteRange, two signed documents from a private
real-world corpus - each with no store, a store, a repeat and
`validateOnline`. The panel-bench fingerprints match too.

Tests: signature_test (same-revision reuse hashes nothing; unmodifiable
problems; an in-place /Contents edit is noticed; an incremental revision
applied in place re-derives coverage; a redaction burn reports the signature
broken; a resolver is consulted and a foreign core ignored), pades_test (a
document timestamp applied in place lifts B-LT to B-LTA; the timestamp is
hashed once for both rows), editing_digital_signature_test (an edit reuses the
core and a burn drops it; undo below a signature, edit, re-sign gives a fresh
verdict; a document above the threshold hashes on the helper isolate - zero
bytes on the test isolate, trust arrival too), editing_sidebar_test (an edit
with the panel open re-validates with zero bytes hashed). Removing the reset
drop, the offload or the resolver each fails one of them.

**Review round: signatures that never get a core.** The first cut counted a
signature as missing whenever it had no kept core. A signature whose
/ByteRange fails the range check has none to get - typically one that came
in with `insertPagesFrom`/`appendPagesFrom`, whose copied /V keeps the source
file's offsets, or a real-world file with a broken range. Every row then
started its own job (a row resumed from its wait, rescanned, and never
re-read the job slot), on every revision: one helper isolate and one full
copy of the file per signature row per edit. Base paid nothing for such a
signature (its range check fails before any hashing). Fixed by the settling
above. Measured with the real controller under `flutter test` (debug JIT, a
1 ms timer probe, default 512 KB threshold): a signed file padded to 12 or 58
MB appended into a one-page host, plus 5 local signatures (6 rows), panel
open then 3 annotation edits each followed by a full panel pass:

| | before | after |
|---|---|---|
| helper jobs, panel open / per edit | 6 / 6 | 1 / 0 |
| bytes copied per edit, 12 MB / 58 MB | 76 MB / 365 MB | 0 / 0 |
| longest gap, 58 MB, open (3 rounds, median) | 36.5 ms | 12.0 ms |
| longest gap, 58 MB, per edit (9 edits, median; range) | 26.5 ms (22.1-34.3) | 7.7 ms (7.1-8.1) |
| longest gap, 12 MB (1 round): open; edits | 16.2; 9.5-12.5 ms | 7.7; 7.2-7.6 ms |

The job counts are deterministic and pinned by two tests in
editing_digital_signature_test (threshold 0): a merged document with a
foreign signature and two local ones (one job for the first pass, none for
three edits; previously 3 on the first pass), and a signature whose core
computation throws (sent once, then never again; previously once per edit).
Reverting to the first cut fails both; dropping only the negative entry fails
the second. signature_test covers `hasSignableByteRange` on a merged
signature (false, no core, `validate()` hashes nothing).

**Not done.** No `ecdsaVerify` memo: after the chain dedup a first validation
repeats no ECDSA verify, so it cannot reach the 1.15x bar there; it would only
trim the 1-2 chain verifies a re-validation repeats (~1.3 ms each AOT, ~20 ms
on the web). Web hashing stays on the main thread (chunked hashing or the
render worker would need a browser to verify).
