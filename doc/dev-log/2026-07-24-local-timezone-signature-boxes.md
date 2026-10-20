# Local timezone for digital signature boxes

## Problem

The visible signature box (and the `/M` signing-date entry) rendered the
signing time in UTC, so a signer in Melbourne saw `05:40:17 +00'00'`
instead of their wall-clock `15:40:17 +10'00'`. The Acrobat-style date the
box draws preserves whatever offset the `DateTime` carries
(`_displaySignDate` / `_pdfDate` in `signature_editor.dart`), but the entry
points forced the time to UTC before handing it to the appearance builder.

`saveSignedExternal` already did the right thing - keep the signer's own
offset for the box + `/M`, encode the CMS `signingTime` attribute in UTC (as
RFC 5652 requires; `derUtcTime` normalises to UTC internally anyway). The
other paths didn't.

## Change

- `PdfEditor.saveSigned` and `saveSignedEcdsa`
  (`packages/pdf_document/lib/src/signature_editor.dart`): stop calling
  `.toUtc()` on the display time; pass the local `time` to the appearance /
  `/M`, and `time.toUtc()` to the CMS. `saveSelfSigned` flows through
  `saveSignedEcdsa`, so one-tap self-signed signing picks this up too.
- `PdfEditor._saveSignedPades`
  (`packages/pdf_document/lib/src/pades_editor.dart`): same split - local
  time for the box, `time.toUtc()` for `cmsSignedAttributes`. Covers B-B
  through B-LTA and the keyless (Fulcio) B-T path.
- App live preview `_acrobatSignDate` (`app/lib/digital_signature.dart`):
  was hard-coded to UTC and documented as "matching" the signed box - now
  mirrors `_displaySignDate`, preserving the local offset so the preview and
  the rendered box agree.

The editor controller methods (`addSelfSignedSignature`,
`addKeylessSignature`, `addDigitalSignature`) already default `signingTime`
to `null` → `DateTime.now()` (local), so the fix reaches the UI without any
call-site change.

## Notes

- The CMS `signingTime` signed attribute is still UTC everywhere - only the
  human-facing box and `/M` gained the local offset. `PdfSignature.signingTime`
  (parsed back from the CMS) therefore stays UTC.
- A UTC `DateTime` input still renders `+00'00'`, so tests that sign with
  `DateTime.utc(...)` are unaffected.
- New coverage: `signature_test.dart` "the box shows the signing time in the
  local offset, not UTC" signs with a local `DateTime` and asserts the box,
  the `/M` entry, and the UTC-normalised CMS `signingTime`. The existing
  `external_signing_test.dart` already pinned the offset-preserving behaviour
  for the external path.
