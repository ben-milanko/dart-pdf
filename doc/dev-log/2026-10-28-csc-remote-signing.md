# CSC remote signing (phases 1-2: library + protocol client)

Goal: let a certificate on the AATL or an EU trusted list sign a PDF through
its provider's Cloud Signature Consortium API, so Acrobat shows a trusted
signature without dart-pdf becoming a CA. This session covers the library
hook and the protocol client. The editor UI and app wiring (provider
settings, OAuth sign-in, token storage) are phases 3-4 and not started.

## Signing hook (pdf_document)

- `PdfRemoteSigner` (pades.dart): `certificates`, `signatureAlgorithm` (the
  SignerInfo AlgorithmIdentifier) and `Future<Uint8List> signDigest(digest)`,
  where the digest is SHA-256 of the DER signed attributes.
- `PdfEditor.saveSignedPadesRemote` (pades_editor.dart) runs the existing
  B-B...B-LTA core. `_saveSignedPades`'s signer callback became async, which
  is the only structural change; the local RSA/EC paths wrap theirs in
  `async`. The remote path verifies the returned value against the signer
  certificate (`cmsSignatureValueVerifies`) before fetching the timestamp or
  writing anything, and throws `PdfRemoteSigningException` on a mismatch.
  The older `saveSignedExternal` (RSA, adbe.pkcs7.detached, hands over the
  attribute bytes) is untouched.

## Crypto additions (pdf_cos)

- `rsaSignPss` (rsa.dart). KAT: an empty salt reproduces the existing
  OpenSSL saltlen-0 vector byte for byte.
- `rsaPssSignatureAlgorithm` / `rsaPkcs1SignatureAlgorithm`
  (x509_builder.dart). The PSS identifier matches what
  `openssl cms -keyopt rsa_padding_mode:pss -keyopt rsa_pss_saltlen:32` emits
  (hash and MGF1 hash with explicit NULL params, saltLength 32).
- `ecdsaRawSignatureToDer` (ecdsa.dart) for services that return P1363
  `r || s`.
- `cmsSignatureValueVerifies` (cms.dart): the signature-value half of
  `cmsVerify`, now shared by both through `_verifySignatureValue`.

## Protocol client (csc.dart)

- Transport injected as `PdfCscTransport` (method + JSON + bearer in,
  status + body out, so the client reads the service's `error` and
  `error_description` itself). No I/O in lib.
- v1 and v2 field names are switched by `PdfCscClient.version`
  (`hash`/`hashAlgo`/`PIN`/`OTP` vs `hashes`/`hashAlgorithmOID`/`authData`;
  v2 lists inline `credentialInfos`, v1 needs `credentials/info` per id).
  Credential parsing is lenient about string-vs-bool `presence`, string
  `SCAL`, and v2's `auth.objects`.
- Authorization is a host callback (`PdfCscAuthorizer`) returning PIN/OTP
  secrets (exchanged for SAD bound to the hash), a ready SAD, or an OAuth2
  `credential`-scope token, which replaces the SAD and the service token on
  `signHash`. It runs after the revision is laid out, so SCAL2 hash binding
  works with one authorization per signature.
- Algorithm choice (`cscSigningAlgorithmFor`): PKCS#1 v1.5, then PSS, for
  RSA; ecdsa-with-SHA256 (or the bare ecPublicKey OID if that is all the key
  lists) for EC. SHA-256 only. `hashAlgo` is always sent. Some services
  require it for rsaEncryption and the spec allows it elsewhere.
- ECDSA values are kept as DER if they verify, otherwise re-encoded from raw
  and re-checked. A value that verifies neither way is left for the editor's
  check to reject.

## Testing

`TestCscService` (pdf_test_fixtures/test_csc.dart) is an in-process service
in the style of `test_fulcio.dart`: it requires the bearer token, rejects a
wrong PIN or OTP, requires `sendOTP` before an online OTP, binds a SCAL2 SAD
to its hashes and counts its uses, honours credential tokens, checks
`signAlgo` against the key's list, signs PSS from `signAlgoParams`, and can
answer ECDSA as raw `r || s`. `csc_test.dart` runs the flows on both API
versions, checks for a trusted chain, and covers B-T plus B-LT with the
OpenSSL OCSP/CRL fixtures. Removing the ECDSA normalisation or the
pre-write verification fails the tests, so both are actually exercised.

External check: `tool/emit_csc_signed.dart` writes PKCS#1 B-LTA, PSS B-T and
raw-ECDSA B-T files. pyHanko 0.38 (`--trust-replace --trust <ca>
--no-revocation-check`) judges all three VALID with trusted signer and TSA,
reports the PSS mechanism as `rsassa_pss`, and treats the /DSS + DocTimeStamp
updates as signature maintenance. That matches the locally-signed
`emit_pades_ltv.dart` reference under the same flags. With `--force-revinfo`
both the reference and the CSC file fail identically: the fixture TSA cert
has no revocation info. That is a property of the fixture, not of this code.

## Not done / next

- Phases 3-4: `PdfEditingController.addRemoteSignature`, credential picker
  and PIN/OTP/waiting UI, app provider settings with OAuth (reuse
  `oidc_pkce.dart`) and secure token storage. Native only at first, because
  provider CORS is unknown.
- Not yet tried against a real provider sandbox; the field names follow the
  spec and real deployments deviate. Do a sandbox smoke test before the app
  ships it.
- SHA-384/512 digests, signing several documents under one authorization,
  v2 `signatures/signDoc`, and `auth/login` (basic auth) are out of scope.
