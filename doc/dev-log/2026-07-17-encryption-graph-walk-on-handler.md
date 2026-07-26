# Move the encryption object-graph walk behind the security handler

Issue #313. `StandardSecurityHandler`'s interface was per-primitive
(`encrypt/decryptString`, `encrypt/decryptStream` on raw bytes +
object/gen), so every caller re-implemented the object-graph traversal and
the exempt-stream policy. `document._decryptStringsDeep` and
`updater._encryptedCopy` were mirror-image tree walks maintained
separately, and the exempt policies had **diverged**:

- `document.dart`'s `_streamIsEncrypted` honoured cross-reference streams,
  unencrypted `/Metadata`, **and** a `/Crypt` filter naming `/Identity`.
- `updater.dart`'s `_encryptedCopy` exempted only `/Type /XRef` and
  `/Metadata`. It omitted the `/Crypt`-with-`/Identity` case, so
  encrypt-on-write would have wrongly re-encrypted a fresh Identity-crypt
  stream (the verified latent bug).

## What landed

Three graph-level operations now live on `StandardSecurityHandler`, each
owning the tree walk and/or the exempt policy once:

- `streamPayloadIsEncrypted(stream, resolve)` — the single exempt-stream
  policy (XRef / unencrypted Metadata / `/Crypt`-Identity, incl. the
  filter-array + parms-array slot alignment). Both the loader
  (`decodeStreamData`) and the writer (`encryptObjectGraph`) call it.
- `decryptObjectGraph(object, num, gen)` — decrypts every string in a
  loaded object's graph in place; stream payloads stay raw for lazy
  decoding. Replaces `document._decryptStringsDeep`.
- `encryptObjectGraph(object, num, gen, {resolve, keepsFileCiphertext})`
  — deep-copies with strings + non-exempt stream payloads encrypted,
  passing exempt streams and still-file-ciphertext payloads through
  verbatim. Replaces `updater._encryptedCopy`. Fixes the `/Crypt`
  divergence **by construction** (it routes through
  `streamPayloadIsEncrypted`).

The `keepsFileCiphertext` predicate is now an explicit parameter instead of
a document-held side map. The old `_streamOwners`
`Map<CosStream, CosReference>` (plus the `streamKeepsFileBytes` predicate
that leaked across the document→updater seam) is **deleted**. Its two jobs
— (1) supply the owning ref for lazy stream decryption, (2) mark a payload
as still file ciphertext — both move onto `CosStream.sourceRef`, a nullable
field the document sets when it parses a stream (null for in-memory
streams). `decodeStreamData` reads `stream.sourceRef` for the key; the
updater passes `keepsFileCiphertext: (s) => s.sourceRef != null`.
`applyIncrementalUpdate` no longer prunes a side map — dropping the cache
entry for a redefined object discards its stream (and its `sourceRef`)
already.

## Gotchas

- `/Crypt` is not a decode filter — the security handler consumes it, and
  `filters.dart` has no `Crypt` entry. So the end-to-end regression test
  (`encryption_test.dart`) asserts the fresh Identity-crypt payload appears
  **verbatim in the saved tail** rather than calling `decodeStreamData`
  (which would throw `UnsupportedFilterException('Crypt')` on the filter
  stage — a pre-existing, unrelated limitation).
- The bug only bites a stream whose payload is *not* still file ciphertext
  (a fresh/edited Identity-crypt stream). A *loaded* one short-circuits via
  `keepsFileCiphertext` and passes through regardless — which is why the
  divergence was latent.

## Tests

- New `test/standard_security_handler_test.dart` — the handler's first
  direct tests: the exempt policy across XRef / Metadata / Crypt-Identity /
  real-crypt-filter / bare-Crypt / filter-array cases, `decryptObjectGraph`
  round-trips, and `encryptObjectGraph` for ordinary/exempt/file-ciphertext
  streams.
- `encryption_test.dart` gains the end-to-end Identity-crypt regression.
