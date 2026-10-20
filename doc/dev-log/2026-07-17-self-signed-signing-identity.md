# 2026-07-17 — One-tap self-signed signing identity + default TSA (#322)

Branch `claude/github-issue-322-3mztkz`. Tier 1 + Tier 2 of #322: make
signing accessible without the user bringing their own PKI. Everything here
is pure Dart (VM + web, no `dart:io`), so the crypto lands in `pdf_cos` and
the editor plumbing in `pdf_document`; the Flutter secure-storage + dialog
UI is the remaining follow-up (see "Not in this PR").

## What landed

### pdf_cos — the crypto (the main piece)

- **EC key generation** (`ecdsa.dart`): `EcPrivateKey` (a scalar `d` on a
  curve) with `EcPrivateKey.generate(curve, {random})`. The scalar is drawn
  by sampling the order's byte-width from `Random.secure()` and rejecting
  anything outside `[1, n-1]`; P-256's order is just under `2^256` so
  rejection essentially never loops. No prime search (that's why we skip RSA
  keygen), no platform channels.
- **Deterministic ECDSA signing** (`ecdsa.dart`): `ecdsaSign` returns the
  DER `SEQUENCE { r, s }` the existing `ecdsaVerify`, CMS, and X.509 all
  expect. The per-signature nonce is RFC 6979 (HMAC-DRBG over the message
  digest), so signing needs no secure randomness *and* is reproducible —
  which is what lets the tests pin exact known answers. `bits2int` truncates
  the digest to the order's bit length exactly as `ecdsaVerify` already did,
  so signer and verifier agree on `e`. **No low-S normalization** — the
  RFC 6979 Appendix A.2.5 vectors are not low-S, and matching them byte-for-
  byte is the KAT.
- **Self-signed X.509 v3 builder** (`x509_builder.dart`):
  `buildSelfSignedCertificate(...)` assembles a `TBSCertificate` with the
  existing DER toolkit and signs it with `ecdsaSign`. Issuer == subject
  (CN, optional O); email goes in a subjectAltName rfc822Name, not the
  deprecated emailAddress RDN. Extensions: basicConstraints CA:FALSE
  (critical), keyUsage digitalSignature+contentCommitment (critical),
  subjectKeyIdentifier (SHA-1 of the SEC1 point). UTCTime before 2050,
  GeneralizedTime after, per RFC 5280. It round-trips through our own
  `X509Certificate.parse` and passes `isSignedBy(itself)` /
  `verifyCertificateChain(trustAnchors: [self])`.
- **CMS ECDSA path** (`cms.dart`): `cmsAssembleSignedData` grew a
  `signatureAlgorithm` parameter (defaulting to rsaEncryption so every
  existing caller is unchanged); `cmsSignDetachedEcdsa` mirrors
  `cmsSignDetached` but signs the attributes with ECDSA and stamps the
  SignerInfo with `ecdsa-with-SHA256`. `cmsVerify` already dispatched on the
  cert's key type, so verification needed nothing new.
- **Key persistence** (`ecdsa.dart`): `EcPrivateKey.sec1Der` /
  `EcPrivateKey.fromSec1` (RFC 5915 `ECPrivateKey`, also unwraps PKCS#8) so
  an identity can be stored and restored by any backend.

### pdf_document — editor plumbing

- **`PdfSigningIdentity`** (`signing_identity.dart`): bundles the EC key, the
  DER chain, and a display name. `PdfSigningIdentity.generate({name, email,
  organization, ...})` is the one-tap path — mints the key + self-signed cert
  offline, backdating notBefore 5 min for clock skew, 5-year validity by
  default. `toPem()` / `fromPem()` persist it (`EC PRIVATE KEY` +
  `CERTIFICATE` blocks) for a host to drop in a keychain.
- **Signing entry points** (`signature_editor.dart`): `saveSignedEcdsa`
  (EC analog of `saveSigned`) and `saveSelfSigned({identity})`.
- **PAdES** (`pades_editor.dart`): `saveSignedPades` was refactored to a
  shared `_saveSignedPades` core taking a sign callback + signature
  AlgorithmIdentifier; `saveSignedPadesEcdsa` and `saveSelfSignedPades` are
  the EC variants. This is how a self-signed identity earns a **trusted
  signature timestamp** (B-T) — CA-anchored signing time even though the
  signer cert isn't publicly trusted.
- **Default TSAs** (`pades.dart`): `PdfDefaultTimestampAuthority` lists
  DigiCert (default), Sectigo, Apple, freeTSA — transport endpoints a host
  wires into an injected `PdfTimestampClient` (the library still does no I/O).

## The trust caveat, stated plainly

A self-signed identity reads as "signed, validity unknown" in any validator
that only trusts AATL/EUTL roots (Acrobat's green check needs a paid CA).
This matches Acrobat's own built-in self-signed digital ID. Two mitigations
ship here: pair it with a default-TSA B-T signature for trusted time, and add
the identity cert to a `PdfTrustStore` so it validates cleanly in *our*
viewer (`validate(trustStore:)` already existed; the new test exercises it).

## Tests

- `pdf_cos/test/ec_identity_test.dart`: RFC 6979 P-256/SHA-256 KATs for
  "sample" and "test" (exact r, s), keygen point-on-curve, self-signed cert
  round-trip + anchor trust, CMS ECDSA verify, SEC1 DER round-trip.
- `pdf_document/test/ec_signing_test.dart`: generate → `saveSelfSigned` →
  reopen → `validate().intact`; trust-store validation; incremental-update
  byte-prefix; PEM round-trip re-sign; EC PAdES B-T with the in-process test
  TSA carrying a timestamp.

## Not in this PR (follow-ups from #322)

- Flutter `flutter_secure_storage` + "Create signing identity" dialog in
  `dart_pdf_editor` (needs platform channels; can't be exercised in headless
  CI here — the persistence primitives above are the seam it plugs into).
- Tier 3 Sigstore/Fulcio keyless, Tier 4 Actalis docs.
