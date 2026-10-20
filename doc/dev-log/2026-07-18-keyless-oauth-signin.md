# 2026-07-18 — Keyless sign-in via Sigstore's public OAuth broker (#322)

Branch `claude/ticket-322-continuation-xgs6ru`. Second app-side follow-up: the
keyless option was wired but gated behind an unconfigured
`EditorScreen.oidcTokenProvider`, so the button never appeared. This session
makes it **appear and work by default** on desktop/mobile.

## The unlock: Sigstore ships a public OAuth client

The blocker was "the app can't bundle an OAuth client (registration is
deployment-specific)". That's true for a *first-party* client, but Sigstore
runs a **public interactive broker** — a Dex instance at
`https://oauth2.sigstore.dev/auth`, client_id `sigstore`, **no secret**, PKCE +
loopback redirect. It brokers Google/GitHub/Microsoft and issues an OIDC token
Fulcio's production CA accepts. This is exactly what `cosign` uses for keyless
signing, so DartPDF can too, with zero registration.

## What landed (app)

- `oidc_pkce.dart` — pure, testable OAuth/PKCE helpers: `SigstoreOidc`
  (endpoints/client), `PkceSession.generate` (verifier + S256 challenge +
  state + nonce), `buildAuthorizationUrl`, `buildTokenRequestBody`,
  `idTokenFromResponse`.
- `oidc_signin_io.dart` — `runSigstoreSignIn`: binds a throwaway loopback
  `HttpServer`, opens the system browser (`url_launcher`), waits for the
  redirect, checks `state` (CSRF), and exchanges the code for an `id_token`.
  `client`/`launch` are injectable for tests.
- `oidc_signin_stub.dart` + a conditional import in `oidc_signin.dart` — web
  gets a stub returning null (a browser tab can't host the loopback), so the
  web build still compiles (no `dart:io`).
- `app.dart` — `oidcTokenProvider: kIsWeb ? null : sigstoreOidcTokenProvider`,
  so the keyless button is live on desktop/mobile and hidden on web.

## Tests

- `oidc_signin_test.dart` — the PKCE helpers (challenge = unpadded base64url
  S256), the authorization URL and token-request bodies, `idTokenFromResponse`,
  and — the good part — the **whole loopback flow** end-to-end against a real
  localhost socket: the injected `launch` fires the browser redirect back at the
  callback (unawaited, or it would deadlock the server it's driving) and a
  MockClient stands in for the token endpoint. Covers the happy path, cancel,
  CSRF `state` mismatch, and an OAuth `error` redirect.
- `keyless_signing_test.dart` — the previously-uncovered HTTP transports:
  `fulcioHttpTransport` (body passthrough + non-200 throws), `defaultTimestampClient`
  (posts `application/timestamp-query`, unwraps the token, non-200 throws), and
  `keylessSigningIdentity` (mints from token+transport; null on cancel). Uses
  `MockClient` + the in-process fake Fulcio/TSA, so no network.

## Honesty notes

- The interactive browser leg (real sign-in against the live broker) can't run
  in CI; everything around it is covered by driving the loopback locally with a
  mock token endpoint. The one genuinely un-CI-able bit is `url_launcher`
  opening the browser, which is injected out in tests.
- Still no hardcoded Sigstore/Actalis trust root — a keyless signature reads as
  "validity unknown" in Acrobat (the certified email is real); to trust it in
  this library's viewer, seed a `PdfTrustStore` with the Sigstore root.
