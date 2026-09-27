# ECDSA: Jacobian coordinates, Shamir's trick, the P-521 order, one verify per chain link

**Symptom.** Validating an ECDSA signature was slow on every platform and
very slow on the web. A small document signed with the app's own
self-signed identity took ~36 ms to `validate()` natively (AOT) and ~206 ms
under dart2js, nearly all of it ECDSA. The signature panel runs that on the
UI isolate, and before the signature-validation memo it re-ran after every
edit. Fulcio, org-CA and many EU CA chains are P-256/P-384, so the same cost
repeats per certificate.

**Causes.**

- `ecdsa.dart` did affine point arithmetic: every point addition and doubling
  paid a BigInt `modInverse` (the profile showed `_binaryGcd` dominating on
  dart2js). `ecdsaVerify` ran two separate scalar multiplications and added
  the results.
- `EcCurve.p/a/b/n/g` were getters that `BigInt.parse` the hex constants on
  every read, and the affine add read `curve.p` once per operation.
- `verifyCertificateChain` verified each (certificate, issuer) pair twice:
  `_findIssuer` already called `isSignedBy` to pick the issuer, then the loop
  called it again. Self-signed validate = 3 ECDSA verifies instead of 2;
  an org-CA member without a trust store = 5 instead of 3.
- **Bug:** the P-521 order constant was 154 hex digits (609 bits) instead of
  the 521-bit NIST n. Every P-521 signature was rejected - OpenSSL's and our
  own - and RFC 6979 signing on P-521 produced signatures nobody accepts. No
  test covered P-521.

**Fix.**

- `_EcParams` (ecdsa.dart) holds each curve's parsed constants, one instance
  per OID built on first use. `EcCurve` is a const class and can't cache in
  late fields, so its getters read through it.
- Jacobian arithmetic for a = -3 (all three NIST curves; the constructor
  refuses anything else): doubling is dbl-2001-b, mixed addition madd-2007-bl.
  `addAffine` handles the cases the formula can't: an infinite accumulator,
  P + P (doubling) and P + (-P) (infinity). A scalar multiplication now pays
  one inversion, when it converts back.
- `shamir(u1, u2, Q)`: one doubling chain over both scalars' bits, adding G, Q
  or the precomputed G + Q. Q = ±G is taken by `addAffine` (G + Q becomes 2G
  or infinity). A zero u1 (the digest is 0 mod n) just contributes no
  additions; u2 is never zero, since r is in [1, n-1] and w is invertible.
  The public key's coordinates are reduced mod p first.
- The final check skips the last inversion: x = X/Z², and x < p < 2n, so
  `x mod n == r` exactly when X == r·Z² or (r + n < p and X == (r + n)·Z²).
- `_multiply` (key generation, `publicKey`, RFC 6979 signing) uses the same
  Jacobian double-and-add. It reaches the same point, so signatures are
  byte-identical on P-256 and P-384.
- The P-521 order is now `01ff…fa51868783bf2f966b7fcc0148f709a5d03bb5c9b8899c47aebb6fb71e91386409`
  (132 hex digits, 521 bits; also checked against FIPS 186-4's decimal).
- cms.dart: `_findIssuer` returns `(issuer, verified)` and
  `verifyCertificateChain` reads the flag instead of verifying again. The
  output is the same: the name-only fallback is reached only after that
  candidate already failed the first loop, and `isSignedBy` is pure.
- No verify memo. The optional LRU inside `ecdsaVerify` was not landed: after
  the dedup a single `validate()` never verifies the same tuple twice, so
  there is nothing to hit on a first validation. It could still skip the
  1-2 chain verifies a later re-validation repeats - left as a follow-up.

**Evidence** (Dart 3.13.3, AOT, thread-CPU medians, 5 interleaved rounds per
variant, base = origin/main at cc144ae7).

| | base | new | |
|---|---|---|---|
| P-256 verify | 11.27 ms | 1.33 ms | 8.5x |
| P-384 verify | 28.88 ms | 3.09 ms | 9.3x |
| P-256 sign (RFC 6979) | 5.81 ms | 1.14 ms | 5.1x |
| P-384 sign | 14.70 ms | 2.64 ms | 5.6x |
| validate, small doc, self-signed | 35.6 ms | 2.7 ms | 13.0x |
| validate, small doc, org-CA member, no store | 59.7 ms | 4.1 ms | 14.5x |
| validate, small doc, org-CA member, CA trusted | 36.2 ms | 2.8 ms | 13.1x |
| validate, 12 MB self-signed | 141.8 ms | 113.2 ms | 1.25x (SHA-256 dominates) |

dart2js -O4 under node (wall, 5 rounds): P-256 verify 68 → 21 ms (3.2x),
P-384 204 → 60 ms (3.4x), small self-signed validate 206 → 42 ms (4.9x).

ecdsaVerify calls per `validate()` (counted with a temporary instrumented
build): self-signed 3 → 2; org-CA member 5 → 3 without a store, 3 → 2 with
the CA as anchor.

Correctness:

- Project Wycheproof `ecdsa_secp{256r1_sha256,384r1_sha384,521r1_sha512}`
  (1,530 vectors), new vs base: 0 disagreements on P-256/P-384. Both miss
  the same 27 per curve, all encoding cases (BER, trailing bytes) that the
  lenient DER parser accepts - unchanged here. On P-521, 254 flips, every
  one from rejected to accepted and every one a mathematically valid (r, s):
  the 228 valid vectors the old order broke, plus 26 valid pairs in non-DER
  encodings the parser accepts on the other curves too.
- A randomized sweep against the base code (1,080 cases over 24 keys: valid,
  flipped digest bit, r+1, s+1, (r, n-s), r = 0, s = n, wrong digest,
  malformed DER): 0 flips on P-256/P-384; on P-521 exactly the 80 valid ones
  (signatures and their (r, n-s) twins) flip to accepted. RFC 6979 signatures
  byte-identical for all 80 P-256/P-384 cases; public keys identical 24/24.
- Validation fingerprints (digest, signature, coverage, trust, chain,
  problems, PAdES level, revocation, signer serial) identical base vs new for
  self-signed and org-CA documents, with and without a trust store.

New `pdf_cos/test/ecdsa_kat_test.dart`, green on the VM and under
`dart test -p node` (dart2js has its own BigInt):

- 60 Wycheproof vectors chosen for the arithmetic (point duplication, the
  Shamir edge case, extreme intermediate values, small r/s, modular inverse,
  special public keys, range checks);
- RFC 6979 A.2.6/A.2.7 P-384 and P-521 signing KATs, including the public
  keys;
- an OpenSSL secp521r1 signature;
- Q = G, Q = -G, Q = 2G and a zero digest (u1 = 0) on every curve;
- (n-1)·G = -G on every curve, and `EcCurve.p521.n.bitLength == 521`;
- a seeded sweep against a textbook affine verifier kept in the test.

`pkix_test.dart` gains the first test of the chain's "does not verify against
its issuer" branch: an impostor CA with the same subject name but another key.

**Follow-up.** Add `ecdsa_kat_test.dart` to CI's node step (the dart2js
KATs ran locally only).
