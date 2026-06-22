# PAdES B-B/B-T/B-LT/B-LTA, RFC 3161 timestamps, LTV /DSS, Certify/DocMDP

PAdES + RFC 3161 timestamps + LTV (/DSS) + Certify/DocMDP (enterprise
signature tier). The crypto primitives are pure-Dart in `pdf_cos/src/crypto/`
and KAT-validated against OpenSSL (`pdf_cos/tool/gen_pkix_fixtures.sh` builds
a CA, leaf, revoked leaf, TSA cert, CRL, OCSP responses and an RFC 3161
token; `pdf_cos/test/pkix_test.dart` parses/verifies them, and compares our
`buildOcspRequest` CertID and `buildTimeStampRequest` imprint byte-for-byte
with OpenSSL's). Layout:
- `tsp.dart` — `buildTimeStampRequest` (TimeStampReq over a digest),
  `timeStampTokenFromResponse` (unwraps a TimeStampResp), `TimeStampToken`
  (parses the CMS + TSTInfo) and `verifyTimeStampToken` (imprint match +
  TSA CMS signature). A timestamp token is just a CMS whose eContent is a
  TSTInfo, so it reuses `CmsSignedData.parse`/`cmsVerify` (encapsulated
  mode). RFC 5652 §5.1 bit me here: a SignedData whose eContentType isn't
  id-data must be **version 3** — emitting v1 made asn1crypto/pyHanko parse
  the TSTInfo as a raw OctetString (`'OctetString' object is not
  subscriptable`); `cmsAssembleSignedData` now picks v3 for non-data
  content. `cmsSignEncapsulated` is the inverse of the parser (used by the
  test TSA in `pdf_test_fixtures/test_tsa.dart`).
- `ocsp.dart` / `crl.dart` — `buildOcspRequest`, `OcspResponse.parse`
  (BasicOCSPResponse → per-serial good/revoked/unknown, `signatureValid`
  against the issuer or a delegated responder by ResponderID), and
  `CertificateRevocationList.parse` (revoked serials + `signatureValid`).
  Both keep the original DER (`.der`) for verbatim embedding in a /DSS.
- `cms.dart` additions: `essSigningCertificateV2Attribute` (the ESS
  signing-certificate-v2 that lifts a CMS to a CAdES/PAdES baseline — issuer
  hash omits the AlgorithmIdentifier for the sha256 DEFAULT),
  `cmsSignedAttributes`/`cmsAssembleSignedData` (composable so a signature
  timestamp, computed over the signature value *after* signing, can be added
  as an unsigned attr before assembly), `cmsSignatureTimeStampAttribute`, and
  X.509 extension parsing for the AIA OCSP URL + CRL distribution points
  (`X509Certificate.ocspResponderUrl`/`crlDistributionUrls`) so a revocation
  client can find the endpoints. `CmsSignerInfo` now exposes
  `hasSigningCertificate` and `signatureTimeStampToken`.

PDF-structure layer (`pdf_document`): `signature_editor.dart` was refactored
so the byte-range/placeholder machinery (`_emitSignatureRevision`,
`_writeContents`) is shared by the classic `saveSigned` and the new
`PdfPadesSigning.saveSignedPades` (`pades_editor.dart`). saveSignedPades is
**async** (the TSA/OCSP/CRL transports are injected — `PdfTimestampClient`,
`PdfRevocationClient` in `pades.dart`, no `dart:io` in lib/, mirroring the
OCR seam) and drives the level ladder: B-B writes an ETSI.CAdES.detached CMS
with the ESS attribute; B-T fetches a token over sha256(signature value) and
embeds it as the signature-time-stamp unsigned attr in the *same* CMS; B-LT
reopens the signed bytes and appends a /DSS as a fresh incremental update;
B-LTA reopens again and appends a DocTimeStamp (SubFilter ETSI.RFC3161, the
/Contents is a bare token over the byte ranges). Each higher level is its own
revision on top of the last — the signature's ByteRange legitimately stops
before the /DSS, and pyHanko reports those tail updates as "signature
maintenance".

/DSS layout (`_writeDss`): every cert/OCSP/CRL DER becomes its own stream
object (`/Length` set by hand — the serializer writes `rawBytes` verbatim);
the catalog /DSS holds `/Certs`/`/OCSPs`/`/CRLs` arrays of those refs, and
`/VRI << <KEY> <vriRef> >>` where KEY is the **uppercase base-16 SHA-1 of the
signature's /Contents bytes** (the CMS) and the per-signature VRI dict
repeats the relevant `/Cert`/`/OCSP`/`/CRL` refs. `_writeDss` merges into an
existing /DSS so multiple signatures accumulate. The signer chain is always
embedded (so the signature resolves offline) plus the signature-timestamp
TSA chain pulled from the token, on top of whatever the revocation client
returns.

Certify/DocMDP: `saveSignedPades(certify: true, docMdpPermissions: 1/2/3)`
adds a `/Reference [ << /TransformMethod /DocMDP /TransformParams << /V /1.2
/P n >> /DigestMethod /SHA256 >> ]` to the sig dict and points the catalog
`/Perms /DocMDP` at it (`_applyDocMdp`).

Validation (`signature.dart`): `_validateCms` now reports `padesLevel`
(B-B…B-LTA, from the CAdES markers + a valid signature timestamp + a present
/DSS + a valid DocTimeStamp), `timestamp` (`PdfTimestampInfo` via
`verifyTimeStampToken` over the signature value), and `embeddedRevocation`
(`PdfRevocationStatus` resolved offline from `PdfDss.of(document)` — find the
issuer in the CMS/DSS cert pool, then an OCSP forSerial that verifies, else a
CRL from the issuer). DocTimeStamp signatures (SubFilter ETSI.RFC3161,
detected by `PdfSignature.isDocumentTimeStamp`) validate through
`_validateDocTimeStamp` (token over the byte ranges). `isLtvEnabled` =
padesLevel ≥ B-LT.

External verification: `pdf_document/tool/emit_pades_ltv.dart` writes a B-LTA
file (OpenSSL leaf signer, CA-issued TSA, full /DSS). With the OpenSSL CA as
the trust root and **allow_fetching=False** (purely offline), pyHanko 0.35.1
judges both the approval signature and the DocTimeStamp VALID and trusted,
reads the /DSS (3 certs, 1 OCSP, 1 CRL, VRI keyed by our SHA-1), confirms the
signature timestamp "is backed by a time stamping authority", and reports the
DSS/DocTimeStamp updates as compatible signature maintenance — i.e. the
signature is LTV-enabled. OpenSSL `cms -verify` also accepts our detached
PAdES CMS (the ESS signing-certificate-v2 is recognized as
`id-smime-aa-signingCertificateV2`). Our own `validate()` reports the same
offline (`pades_test.dart` covers B-B…B-LTA, the OCSP "good" consumption, and
the DocMDP wiring). Signing **encrypted** files is still refused: the PAdES
plumbing doesn't change that the /Contents and /ByteRange must stay
unencrypted and byte-patchable, so it remains a follow-up (would need the
updater to exempt the sig dict from `_encryptedCopy`).
