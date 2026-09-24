# Signing encrypted (password-protected) PDFs (#935)

Every signing path used to refuse an encrypted document
(`UnsupportedEncryptionException` in `_emitSignatureRevision`). They now sign
it in place, and the output keeps the file's original protection.

## The one exempt string

ISO 32000 §7.6.1 exempts a signature dictionary's /Contents from string
encryption. `StandardSecurityHandler.isSignatureContents(dict, key)` is that
rule. It matches key `Contents` in a dictionary with `/Type /Sig` or
`/DocTimeStamp`, or, because /Type is optional on a signature dictionary, in
one that has a /ByteRange. It applies in both directions:

- `encryptObjectGraph` copies the /Contents string through unchanged. The
  zero-filled hex placeholder therefore reaches the file verbatim, and
  `_emitSignatureRevision` finds and patches it exactly as it does for an
  unencrypted file. /ByteRange holds integers, which are never encrypted.
  /M, /Name, /Reason, /Location and /ContactInfo are encrypted like any other
  string. The test asserts that their plaintext is absent from the output.
- `decryptObjectGraph` leaves it alone on load, so `PdfSignature.contents`
  and `validate()` read the raw CMS. This also fixes validation of encrypted
  files signed by other tools. Before this change the loader "decrypted"
  their plain /Contents into garbage.

No offset arithmetic changed. `_updater.save()` encrypts first, then the
placeholder and /ByteRange are located in the bytes as written, so AES
padding and IVs have already settled every other string's length before
anything is measured. The signed ranges are the encrypted bytes.

Objects inside an object stream are encrypted with the stream as a whole
(§7.6.3), never one string at a time, so the exemption does not reach them.
The updater never writes a signature dictionary into an object stream.

## PAdES follow-on revisions: `openAppended`

B-LT/B-LTA write the /DSS and the document timestamp as further incremental
updates. Before each one they reopened the intermediate bytes with
`PdfDocument.open(bytes)`, which has no password, so an encrypted file threw
`CosPasswordException`. The new `CosDocument.openAppended(bytes)` and
`PdfDocument.openAppended(bytes)` reopen this document's bytes plus appended
updates and reuse the already-authenticated `StandardSecurityHandler`, as long
as the trailer still points at the same /Encrypt object. The password is never
stored. `_addValidationData` and `_addDocumentTimestamp` use it, and
`addDocumentTimestamp` on a signed encrypted file works too. The
`PdfEditingController` signing paths already reopen with the session's
`_password`. No app or editor UI blocked signing an encrypted document.

## Tests

- `pdf_document/test/encrypted_signing_test.dart`:
  - `saveSigned` under RC4-40, RC4-128, AES-128 and AES-256 (R6), reopened with
    the password. Checks that the result is intact and covers the whole
    document, that the /ByteRange gap hex equals the reported CMS, and that the
    page and /Info still decrypt.
  - Opening with the owner password, and owner-password-only files (empty user
    password).
  - A second signature on top (RC4-40, AES-128, AES-256). The first signature
    stays intact and no longer covers the whole file.
  - `saveSelfSigned`/`saveSignedEcdsa`, `saveSignedExternal`, a visible box,
    `saveSignedPades` at every level, `saveSelfSignedPades` B-T,
    `addDocumentTimestamp`, and certify (DocMDP P=2) followed by an approval
    signature.
- `pdf_cos/test/standard_security_handler_test.dart`: tests for the exemption
  predicate, the encrypt and decrypt round-trip of a signature dictionary, and
  `openAppended` reopening an R6 revision that `open` without a password
  rejects.
- The refusal test in `editor_test.dart` is gone.

## External validation

`pdf_document/tool/emit_pades_ltv.dart` takes `--encrypted=N` (2/3/4/6, where
a bare flag means 6). It signs a password-protected source (user password
`user`, owner password `owner`) at B-LTA. pyHanko 0.37.0 (CLI 0.5.0) was run
from an ephemeral `pipx run` venv, offline (`allow_fetching=False`, hard-fail
revocation fed from the /DSS OCSP and CRL, the test CA as the only trust root).
It decrypted each file with the user password (and with the owner password for
R6) and judged the approval signature cryptographically sound and trusted,
with its TSA trusted, and the DocTimeStamp `INTACT:TRUSTED`. That held for all
four schemes. The pyHanko CLI (`sign validate --password user
--no-revocation-check`) also reports the /DSS and timestamp updates as
compatible signature maintenance and gives the verdict VALID. The CLI in 0.37
no longer has an LTV mode, so a plain CLI run with revocation checking reports
"no revocation information" on unencrypted output too. That result comes from
the CLI, not from the file.
