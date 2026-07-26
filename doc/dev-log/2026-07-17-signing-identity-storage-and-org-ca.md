# 2026-07-17 — Signing-identity storage/UI + org-CA mode (#322)

Branch `claude/github-issue-322-3mztkz`. Follow-up in the same PR to the
Tier 1 crypto (see `2026-07-17-self-signed-signing-identity.md`): the two
remaining pieces the issue asked for and that are testable here - the
Flutter "Create signing identity" storage + UI, and the "org CA" mode from
the "Trust inside our own ecosystem" section. Tier 3 (Fulcio keyless,
network + OAuth) and Tier 4 (Actalis import docs) stay out of scope.

## Org-CA mode (pdf_cos + pdf_document, pure Dart)

`x509_builder.dart` was refactored so `buildSelfSignedCertificate` and two
new builders share one `_assembleCertificate` core:

- **`buildCaCertificate`** - a self-signed CA cert: basicConstraints cA=TRUE
  (critical, optional pathLenConstraint), keyUsage keyCertSign + cRLSign
  (`[1, 0x06]` - bits 5,6, one unused bit), subjectKeyIdentifier.
- **`issueCertificate`** - an end-entity cert for a given `EcPublicKey`,
  signed by the CA key, issuer Name copied from the CA cert's subject
  (`_subjectNameOf`, DER-sliced without needing `X509Certificate`, avoiding a
  cms.dart import cycle), plus an authorityKeyIdentifier linking leaf→CA.

The end-entity extension set is now shared (`_endEntityExtensions`) between
the self-signed and CA-issued paths; the self-signed path is byte-identical
to before (no AKI added), so the earlier KAT/round-trip tests are untouched.

`PdfSigningIdentity` gained:

- **`generateCa({name, organization, pathLength, validity})`** - a one-shot
  CA identity (default 10-year validity).
- **`ca.issue({name, email, ...})`** - mints a member identity: a fresh EC
  key + a CA-signed leaf, chain = `[leafCert, caCert]`, so it validates
  against a trust store holding just the CA. Default 2-year validity.

`PdfTrustStore.trusting([caDer])` is a small convenience factory. The whole
flow is proven end-to-end: generate CA → issue member → `saveSelfSigned` →
`validate(trustStore: PdfTrustStore.trusting([ca.certificate]))` reports
`chainTrusted: true`, and a member of a *different* CA is rejected
(`ec_signing_test.dart`, `ec_identity_test.dart`).

## Storage + "Create signing identity" UI (dart_pdf_editor)

- **`PdfIdentityStore`** (interface) with two implementations:
  - `InMemoryIdentityStore` - session-only, for tests / "don't remember me".
  - `SecureIdentityStore` - `flutter_secure_storage` (Keychain/Keystore), the
    only new dependency. Stores each identity's `toPem()` under a namespaced
    key and keeps a JSON id index so `ids()` can enumerate. The private key
    never touches `shared_preferences`.
- **`CreateSigningIdentityForm` / `showCreateSigningIdentityDialog`** - name
  (required) + optional email/organization → `PdfSigningIdentity.generate`,
  optional persist to a `PdfIdentityStore`, returns the identity. The dialog
  spells out the "signed, validity unknown" caveat inline (matching Acrobat's
  own self-signed ID), as the issue requires. The form takes an injected
  store, so it's driven by an in-memory store in the widget test - which
  also confirms the produced identity signs a document that validates.

### Why the store interface, not just flutter_secure_storage everywhere

The dialog depends on the `PdfIdentityStore` interface, not the plugin, so a
host can pick the backend (secure, in-memory, or its own) and widget tests
run headless without platform channels. `flutter_secure_storage` is the
default production backend, wired via `SecureIdentityStore`.

## Not in this PR

Tier 3 Fulcio keyless (network + OAuth, can't be exercised offline here) and
Tier 4 Actalis import docs remain follow-ups, as the issue lists them.
