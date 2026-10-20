# 2026-07-18 — Keyless signing in the DartPDF app (#322 Tier 3, UI)

Branch `claude/ticket-322-continuation-xgs6ru`. Follow-up to the Fulcio keyless
library work (`2026-07-17-fulcio-keyless-signing.md`): surface it in the app's
**Digitally sign** dialog, so a user can sign with an OIDC-verified email
instead of bringing their own PKI.

## The one thing the app can't ship: an OAuth client

Fulcio needs an OIDC id_token, which means an OAuth flow, which means a
registered client (provider + client ID + redirect) — deployment-specific, not
something DartPDF can bundle. So, exactly as #337 did for platform key storage,
the OAuth step is an **injected seam** and everything else is built and tested:

- `EditorScreen.oidcTokenProvider` (`OidcTokenProvider`, in
  `app/lib/keyless_signing.dart`) is the switch. Null (default) → the keyless
  option is hidden and nothing changes. Set → the dialog lights up.

## What landed

### app/lib/keyless_signing.dart — the transports

- `fulcioHttpTransport` — POSTs the `signingCert` request to
  `PdfFulcioAuthority.sigstore` over `package:http` (endpoint + client
  injectable for tests).
- `defaultTimestampClient` — a `PdfTimestampClient` backed by DigiCert
  (`application/timestamp-query` → `timeStampTokenFromResponse`). Keyless
  **requires** a timestamp because the Fulcio cert lives ~10 min.
- `keylessSigningIdentity(context, tokenProvider, transport)` — runs the token
  provider, then `fulcioSigningIdentity` through the transport (production HTTPS
  by default). Returns null on cancel.

Needed a direct `pdf_cos` dependency in `app/pubspec.yaml` for
`timeStampTokenFromResponse` (the only pdf_cos symbol the app touches directly).

### app/lib/digital_signature.dart — the dialog

- `KeylessIdentityCreator` seam + `DigitalSignatureOptions.keylessIdentity` /
  `timestampClient` (asserted together) and a `signingTime` field (tests set it
  for determinism; production leaves it null → sign-at-now).
- A third path in the dialog behind `createKeylessIdentity != null`: a
  "Sign in with your email (keyless)…" button (busy spinner during sign-in), a
  result card, and the caveat text. A keyless pick supersedes file/self-signed
  and vice-versa. Submit pops the keyless identity + timestamp client.

### dart_pdf_editor — the editor path

- `PdfEditingController.addKeylessSignature(identity, {timestampClient, ...})` —
  `saveSelfSignedPades(level: bT, ...)` through the same `_adoptDigitalSignature`
  validation/undo as the other signature kinds. B-T is a single incremental
  update, so it still `coversWholeDocument`.

### editor_screen apply-site

`_digitallySign` gained a keyless branch (before self-signed), and the default
dialog call now passes `createKeylessIdentity`/`timestampClient` built from
`oidcTokenProvider` (production Fulcio + DigiCert). `signingTime` is threaded
through all three branches.

## Tests

- `dart_pdf_editor/test/editing_digital_signature_test.dart`: controller mints
  a keyless identity through the in-process Fulcio and `addKeylessSignature` →
  B-T signature that is intact, timestamped, `chainTrusted` against the fake
  Sigstore CA, and undoable.
- `app/test/digital_signature_test.dart`: the dialog keyless path (sign-in →
  card → returns identity + timestamp client); the option is hidden without a
  token provider and shown with one; and the full menu → keyless B-T → save →
  validate (intact + timestamped + trusted). **Gotcha:** the keyless button
  lives below the dialog's scroll fold — `tester.ensureVisible` before tapping,
  or the tap lands on empty space and silently no-ops.

## Not shipped (still, by design)

No OAuth client and no built-in Sigstore/Actalis root — a deployment supplies
both. The app is fully wired; flipping `oidcTokenProvider` on turns it live.
