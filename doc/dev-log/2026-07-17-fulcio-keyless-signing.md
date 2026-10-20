# 2026-07-17 — Sigstore/Fulcio keyless signing (Tier 3 of #322)

Branch `claude/ticket-322-continuation-xgs6ru`, continuing #322 after #337
(Tier 1 self-signed identities + Tier 2 default TSA) and the follow-up that
landed the Flutter storage/UI and org-CA mode. This session adds **Tier 3
keyless signing** and documents **Tier 4** (Actalis import), the two remaining
follow-ups the issue lists.

## What Fulcio keyless signing is

Fulcio (OpenSSF/Sigstore) issues a short-lived (~10 min) X.509 certificate
bound to an OIDC-verified email. The user signs in with Google/GitHub/Microsoft;
Fulcio certifies that identity. Unlike a self-signed identity, the email is
independently verifiable. Because the certificate expires in minutes, a trusted
timestamp (PAdES B-T — which we already had) is mandatory, not optional.

## Architecture — same injected-transport rule as the TSA

The library performs no network I/O (no `dart:io` in `lib/`). The two
network/browser-bound steps are the host's job and are injected:

- the **OAuth PKCE flow** → the host hands us the resulting OIDC id_token (a
  JWT) as a plain string;
- the **HTTPS POST to Fulcio** → injected `PdfFulcioTransport` (request bytes →
  response bytes), mirroring `PdfTimestampClient`.

Everything else — request building, the proof-of-possession crypto, response
parsing — is pure Dart in the library.

## What landed

### pdf_cos — two small reusable primitives

- `ecSubjectPublicKeyInfo(EcPublicKey)` (`x509_builder.dart`): the DER
  SubjectPublicKeyInfo for an EC key. `_assembleCertificate` was refactored to
  use it (byte-identical, so the cert KATs/round-trips are untouched); the
  Fulcio request PEM-wraps its output.
- `pemEncode(label, der)` (`rsa.dart`, next to `pemBytes`): RFC 7468 PEM
  armor with a 64-column body. `PdfSigningIdentity.toPem` was switched onto it
  (its private `_pemBlock` is gone), and the fake-Fulcio fixture reuses it.

### pdf_document — the keyless client (`src/fulcio.dart`)

- `PdfFulcioAuthority` — the production + staging `signingCert` endpoints
  (transport-only constants).
- `PdfFulcioTransport` — the injected POST typedef.
- `oidcTokenSubject(jwt)` — decodes (does **not** verify) the JWT payload and
  returns the identity Fulcio will certify: `email` when present, else `sub`.
  This is the exact string the proof-of-possession signs.
- `fulcioProofOfPossession(key, subject)` — `ecdsaSign(key, sha256(subject))`,
  DER `SEQUENCE {r,s}`. Fulcio verifies this against the submitted public key
  to bind the OIDC identity to the ephemeral key.
- `buildFulcioSigningRequest(...)` — the Fulcio v2
  `CreateSigningCertificateRequest` JSON: the token as the credential, the
  public key as a PKIX `PUBLIC KEY` PEM, the base64 proof.
- `parseFulcioCertificateChain(response)` — pulls the DER chain (leaf first)
  out of either the `signedCertificateEmbeddedSct` or
  `signedCertificateDetachedSct` shape.
- `fulcioSigningIdentity({oidcToken, transport, random})` — orchestrates the
  four steps into a `PdfSigningIdentity` whose key is ephemeral and whose chain
  is Fulcio-issued. The host then signs with `saveSelfSignedPades(level: bT,
  timestampClient: ...)` — no new editor entry point needed; a keyless identity
  is just a `PdfSigningIdentity`.

### pdf_test_fixtures — an in-process fake Fulcio (`src/test_fulcio.dart`)

Mirrors `test_tsa.dart`: `TestFulcioCa.generate()` is a throwaway EC CA, and
`buildTestFulcioResponse(request, ca: ...)` parses the request, **verifies the
proof-of-possession** (so a wrong proof fails exactly as Fulcio would — the
`ecdsaVerify` over `sha256(subject)`), issues a 10-minute leaf with the email
in a subjectAltName via `issueCertificate`, and returns the real JSON response
shape. Uses pdf_cos only (the fixtures package doesn't depend on pdf_document),
so the CA is built straight from `buildCaCertificate`/`issueCertificate`.

## The trust caveat (unchanged, stated plainly)

Sigstore roots aren't Adobe-trusted, so a keyless signature still reads as
"signed, validity unknown" in Acrobat — but the certified email is real. To
validate it in our own viewer, seed a `PdfTrustStore` with the Sigstore root
(the host fetches it from the Sigstore TUF trust root; we ship no roots, per
`PdfTrustStore`'s existing contract). The end-to-end test proves this against
the fake CA as the anchor.

## Tests

- `pdf_document/test/fulcio_test.dart`: subject extraction (email > sub, and
  the reject cases); proof-of-possession verifies for the right subject and
  fails for a wrong one; request JSON carries the token/PKIX key/base64 proof;
  chain parsing for both SCT shapes + the empty-chain reject; and the full
  end-to-end keyless flow (fake token → `fulcioSigningIdentity` with the fake
  transport → `saveSelfSignedPades` B-T with the in-process TSA → `validate`
  reports `intact`, `signatureValid`, a `timestamp`, and `chainTrusted` against
  the fake CA). Plus: a tampered proof is rejected by the fake CA.
- `pdf_cos/test/ec_identity_test.dart`: `ecSubjectPublicKeyInfo` matches the
  cert's embedded SPKI byte-for-byte and parses back to the same point.

## Not in this session

Tier 4 (Actalis) is documentation only — manual, browser-based enrollment, so
there's nothing to integrate; `doc/signing-identities.md` writes up the import
path (PKCS#12 → PEM → `PdfSigningIdentity.fromPem`) alongside all the other
tiers. Shipping a hardcoded Sigstore/Actalis root in-tree was deliberately
avoided: `PdfTrustStore` ships no roots by design (they rotate), so the host
supplies them.
