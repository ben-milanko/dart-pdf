# Signature validation: trust lists and live revocation (#936)

## What landed

- **Revocation** (`pdf_document/lib/src/revocation.dart`, `signature.dart`).
  `PdfSignature.validateOnline({trustStore, revocationClient, now})` is async
  because the injected `PdfRevocationClient` is. It sits next to `validate()`
  rather than being a `validate(revocationClient:)` parameter, so the sync
  API and its many callers stay unchanged. Both methods build a revocation
  path: the trust chain when one reached an anchor, otherwise
  `verifyCertificateChain` with no anchors over the CMS + /DSS certificates.
  Every certificate with an issuer is checked, and a self-signed root is
  skipped. `checkCertificateRevocation` does the checking: OCSP first, then CRL.
  `combineRevocation` merges embedded and live (a revocation from either
  source wins, then live good, then embedded good), and
  `applyRevocationPolicy` sets `affectsSignature`.
- **Policy.** A revoked certificate forces `chainTrusted = false` (even with
  no trust store) unless a *verified signature timestamp* predates the
  revocation time. Unknown status soft-fails. The claimed /M or signingTime is
  never trusted for this.
- **OCSP hardening in pdf_cos**: `OcspSingleResponse.matches` checks the full
  CertID (serial + issuer name hash + issuer key hash). Before this,
  `forSerial` alone let one CA's answer apply to another CA's certificate with
  the same serial. `responderFor` now requires a delegated responder to be
  issued *and signed* by the issuer and to carry id-kp-OCSPSigning. The
  existing `/DSS` path (`embeddedRevocation`) was switched onto the same
  checker. The nonce extension is parsed (`OcspResponse.nonce`,
  `echoesNonce`, `ocspNonceValue`) and so is the revocation reason.
  `X509Certificate` gained `extendedKeyUsages`, `isCa`, `hasOcspNoCheck` and
  `isValidAt`, and now exposes the RSA key of an **id-RSASSA-PSS** SPKI (the
  German TL signer uses one; before this its `publicKey` was null).
- `issueCertificate` gained AIA OCSP, CRLDP, EKU, ocsp-nocheck and `isCa`
  options. `pdf_test_fixtures/test_revocation.dart` builds on them: an
  in-process root, intermediate, signer and (rogue) delegated responder, plus
  `buildTestOcspResponse` / `buildTestCrl`. The OpenSSL fixtures in
  `pkix_ltv.dart` have no CA key, so they can't mint new revocation states.
  That is why this is a new generator rather than a `gen_pkix_fixtures.sh`
  regeneration.
- **Nonces** live in the client (`pdfOnlineRevocationClient`). A
  `PdfRevocationMaterial` carries no request context, so the validator can't
  match one. The client drops a response echoing a *different* nonce and
  accepts one with no nonce, because most public responders serve cached
  responses and ignore it. Freshness then does the anti-replay work.
- **Trust lists** (`package:pdf_document/trust_lists.dart`, a separate
  entrypoint, not exported from `pdf_document.dart`). `xml_lite.dart` is a
  strict XML reader plus inclusive/exclusive C14N 1.0. It is our own rather
  than package:xml because xml 6 and 7 differ on namespaces and we need exact
  control of attribute normalization and escaping. `xml_dsig.dart` verifies an
  enveloped XMLDSig (RSA, RSA-PSS `sha*-rsa-MGF1`, ECDSA raw r||s) and
  requires a reference that covers the whole document.
  `eu_trusted_list.dart` holds the pinned LOTL signers, the pointer parsing,
  the CA/QC + NationalRootCA-QC filter (granted and legacy active statuses) and
  the PEM snapshot. `aatl.dart` is a loader for a host-supplied
  `.acrobatsecuritysettings`: signature pinned to Adobe Root CA G2,
  ImportAction 1/2 with `<Root>1</Root>` (3 means remove).
- **Real-world check**: on 2026-09-23 the refresh tool verified LOTL #394
  and all 29 national lists it points to (1,007 CA/QC certificates, about
  2.2 MB PEM). That covered exclusive C14N, RSA-PKCS#1 and RSA-PSS signers,
  and the DE list at 5 MB (about 1.9 s to parse and verify on an M-series
  Mac). The AATL loader read the live file (167 root anchors, signed
  2026-09-10). Portugal's host resets connections from Dart's default
  User-Agent, so both the tool and the app send their own.
- **Editor**: `PdfEditingController.revocationClient` (setting it, or
  `trustStore`, bumps a generation so an in-flight validation from the old
  settings is discarded). The sidebar shows the Revoked pill, self-signed, the
  untrusted issuer by name, revoked-after-timestamp, and good online / good
  from embedded / unknown.
- **App**: `app/lib/signature_trust.dart` `SignatureTrust.platformDefault`
  is null on web and under `FLUTTER_TEST`. `DocumentTab` attaches every
  session. The EU list loads lazily, only once an attached document has a
  signature, and is cached in `<support>/signature_trust/eutl.pem` for 7 days.
  Fetching and verifying run in `Isolate.run`, and a failed refresh falls back
  to the stale cache.

## Licensing finding

The AATL has no redistribution grant we could find (Adobe publishes it for
Acrobat, and the member agreement is private), so it is neither bundled nor
fetched by the app. The LOTL is Commission content (reusable under Decision
2011/833/EU and CC BY 4.0), but national lists are Member State content with
their own terms. So no snapshot is committed, and the app fetches from the
official sources instead. The details and update cadence are in
doc/signing-identities.md.

## Gotchas

- TL `MimeType` sits in the additionaltypes namespace and some pointers carry
  none. We pick XML pointers by MIME type, or by `.xml`/`.xtsl` when the MIME
  type is empty, and skip the PDF renditions.
- Some territories are listed twice; the first XML pointer per territory is
  used.
- The TSA certificate's own revocation is not checked; only the signer chain
  is.
- CRL checks are direct CRLs only. Indirect CRLs, delta CRLs, and critical
  CRL-extension enforcement are not handled.
