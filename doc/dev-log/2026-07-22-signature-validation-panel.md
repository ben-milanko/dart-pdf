# Signature validation in the annotations panel

Surfaced digital-signature validation status in the editor's annotation
sidebar, so a reader can see whether a signature is intact and whether its
signer chains to a trusted authority (the "validate against known CAs"
ask - Adobe/DocuSign/Bluebeam etc.).

## What landed

- **`PdfEditingController.trustStore`** (`editing_controller.dart`): a
  settable `PdfTrustStore?` (also a constructor param). The library ships
  no roots, so this is the seam a host uses to supply an AATL/EUTL or org
  bundle (`PdfTrustStore.trusting([...])`). Setting it drops the
  validation cache and notifies listeners, so a bundle loaded
  asynchronously lights up the panel when it arrives.
- **`PdfEditingController.validationFor(signature)`**: returns the cached
  `PdfSignature.validate(trustStore:)` result, or null while it computes.
  Validation walks CMS/cert crypto (a whole-file hash + chain build), so it
  never runs on the caller's frame - when the result isn't cached it's
  scheduled off the current event-loop turn and `notifyListeners` fires when
  it lands. The result is cached per `(revisionId, field name)`, so panel
  rebuilds are free. This is what keeps opening the panel instant on a
  heavily-signed document (an earlier synchronous version blocked the frame).
- **`PdfEditingController.signatureByFieldName`**: the current revision's
  signatures keyed by field name, computed once per revision. The sidebar's
  `_signatureFor` was calling `PdfSignature.of` (a full AcroForm walk) once
  per annotation row - quadratic on a form-heavy document; this makes the
  lookup O(1). The cache is dropped
  whenever the revision moves or the trust store changes.
- **`_signatureSection` in `editing_sidebar.dart`**: for a signed
  signature-field row, renders a status pill + detail lines under the tile
  (same nesting model as the comment-thread section, suppressed during
  multi-select):
  - Pill: **Checking…** (while validation runs off-frame), **Invalid**
    (red, `!intact`), **Valid — trusted** (green, `chainTrusted == true`),
    or **Valid — unverified** (orange, intact but not chained to an anchor).
  - Details: signer (cert CN, falling back to `/Name`), signing time,
    trust ("Trusted via <root CN>" / "not from a trusted authority" /
    "No trusted authorities are configured" when no store), a
    "changed after signing" note when `!coversWholeDocument`, a revoked
    note from embedded `/DSS` material, the trusted timestamp time, and
    the PAdES level. Cryptographic `problems` are listed only for an
    invalid verdict.

## Scope / follow-ups

- Trust is **pluggable, not bundled**. Out of the box a real Adobe or
  DocuSign signature reads as "Valid — unverified" because no roots are
  configured. Getting an out-of-box green check means shipping an AATL
  (and optionally EUTL) root bundle and loading it into the controller's
  trust store - deliberately left as a follow-up.
- Chain building (via `verifyCertificateChain`) still does no
  revocation/key-usage/name-constraint/policy processing; only offline
  `/DSS` revocation is reported (as `embeddedRevocation`). Fine for a
  "signed by a known CA" badge, worth remembering before claiming strict
  AATL parity.
- A dedicated Acrobat-style "Signatures" panel is the nicer long-term
  home; the annotation-panel badge was the smaller first slice.

## Tests

`editing_sidebar_test.dart`: an unverified self-signed signature shows the
orange pill + "No trusted authorities are configured"; trusting the
signer's own (self-signed) certificate flips it to "Valid — trusted" +
"Trusted via <CN>". l10n added to the abstract localizations, the `_en`
impl, and the `.arb`.
