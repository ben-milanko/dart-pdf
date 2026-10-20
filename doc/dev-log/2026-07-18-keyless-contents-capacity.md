# Keyless signing: "signature blob exceeded its reserved space"

## Symptom

Signing keyless (Sigstore/Fulcio) in the app failed with:

> Could not digitally sign: Bad state: signature blob exceeded its reserved space

## Cause

Keyless signs at **PAdES B-T** with a **public TSA** (DigiCert by default -
`app/lib/keyless_signing.dart`). The B-T flow in `_saveSignedPades`
(`pades_editor.dart`) reserves the /Contents placeholder *before* fetching the
timestamp, sizing it with `PdfSigning._cmsCapacity(certificates)` =
`6144 + signer chain`. But the assembled CMS then embeds the RFC 3161 token as
an unsigned attribute (`cmsSignatureTimeStampAttribute`), and that token is a
whole CMS SignedData carrying the **TSA's own certificate chain**. Nothing in
the fixed 6144 slack budgeted for it.

The in-process test TSA (`test_tsa.dart`) signs with a single ~740-byte cert,
so its token fit the 6144 slack and the existing B-T tests never hit the
ceiling. A real public TSA ships several KB of certs and overflows it. The
sibling standalone DocTimeStamp path already reserved `16384` for exactly this
kind of token - the B-T CAdES path just didn't.

## Fix

`signature_editor.dart`: named the token budget
`PdfSigning._timestampTokenReserve = 16384` (reused by the DocTimeStamp path,
replacing its magic 16384) and gave `_cmsCapacity` a `withTimestamp` flag that
adds it. `pades_editor.dart` passes `withTimestamp: level >= PdfPadesLevel.bT`
so every timestamped PAdES level reserves room for the token.

## Regression test

`fulcio_test.dart`: a B-T keyless sign driven by the test TSA with a chain
padded to >8 KB (16 copies of the signer cert). Overflows the old 6144 budget
(verified: throws the exact error with the fix reverted), fits and validates
with the fix.
