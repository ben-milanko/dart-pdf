# Signing identities

`PdfEditor.saveSigned` / `saveSignedPades` can sign with any private key and
certificate chain you bring. But most users can't produce those, so dart-pdf
also ships **automated signing identities** — ways to obtain a usable signing
credential with little or no setup. This document covers them and, plainly,
what each one is worth in a validator.

## The trust reality

There is **no free path to Adobe Acrobat's green checkmark.** That check
requires the signer certificate to chain to an AATL/EUTL root, i.e. a paid,
publicly-trusted CA/QTSP. Every free option below lands at **"signed, validity
unknown"** in Acrobat — which is exactly what Acrobat's own built-in
self-signed digital ID produces. That is the industry-standard baseline, not a
shortcoming of this library.

Two things you can always add on top of any identity:

- **A trusted timestamp** (PAdES **B-T**). Even when the signer certificate
  isn't publicly trusted, the RFC 3161 timestamp chains to a public TSA, so the
  *signing time* is CA-anchored and the timestamp itself often validates in
  Acrobat. Wire a default TSA via `PdfDefaultTimestampAuthority` (DigiCert by
  default) into a `PdfTimestampClient`.
- **Your own trust store.** `validate(trustStore:)` validates a chain against
  anchors you choose. Add the identity (or its CA, or the Sigstore root) to a
  `PdfTrustStore` and the signature validates cleanly **inside this library's
  own viewer** — the right answer for a first-party ecosystem.

The library ships **no built-in roots**: you always decide what to trust.
The opt-in public lists (the EU trusted lists, an AATL file you supply) and
live revocation checking are covered in
[Validating: trust lists and revocation](#validating-trust-lists-and-revocation).

## Tier 1 — one-tap self-signed identity

The default, fully-offline path. Mints a fresh P-256 key and a self-signed
X.509 certificate; nothing but a name is required.

```dart
final identity = PdfSigningIdentity.generate(
  name: 'Ada Lovelace',
  email: 'ada@example.com',      // optional; goes in a subjectAltName
  organization: 'dart-pdf',      // optional
);
final signed = PdfEditor(document).saveSelfSigned(identity: identity);

// persist it in a keychain/keystore between sessions
final pem = identity.toPem();
final restored = PdfSigningIdentity.fromPem(pem);
```

Reads as "signed, validity unknown" everywhere except a trust store that holds
its certificate. Pair with a timestamp for trusted signing time
(`saveSelfSignedPades(level: PdfPadesLevel.bT, timestampClient: ...)`).

## Org-CA mode — real chain validation within a deployment

Generate a CA once, share its certificate as a trust anchor across your
deployment, and issue member identities from it. Member signatures then chain
to the CA and validate for real (not just "validity unknown") for anyone
holding the CA certificate.

```dart
final ca = PdfSigningIdentity.generateCa(name: 'Acme Org CA', organization: 'Acme');
final alice = ca.issue(name: 'Alice', email: 'alice@acme.example');

final result = signature.validate(
  trustStore: PdfTrustStore.trusting([ca.certificate]),
);
// result.chainTrusted == true
```

## Tier 2 — free RFC 3161 timestamps

Any signature can carry a trusted timestamp from a free public TSA, with no
account. This is the single biggest trust upgrade available for free.

```dart
await PdfEditor(document).saveSelfSignedPades(
  identity: identity,
  level: PdfPadesLevel.bT,
  timestampClient: (req) async {
    final res = await http.post(
      Uri.parse(PdfDefaultTimestampAuthority.digicert),
      headers: {'Content-Type': 'application/timestamp-query'},
      body: req,
    );
    return timeStampTokenFromResponse(res.bodyBytes);
  },
);
```

`PdfDefaultTimestampAuthority` lists DigiCert (default), Sectigo, Apple and
freeTSA. The library performs no I/O — you supply the transport.

There's also an **identity-free** option: a bare document timestamp
(`addDocumentTimestamp`, SubFilter `ETSI.RFC3161`) that proves a document's
integrity and existence-at-a-time without any signer identity at all.

## Tier 3 — Sigstore/Fulcio keyless signing

[Fulcio](https://docs.sigstore.dev/) (OpenSSF/Sigstore) issues a short-lived
(~10 minute) X.509 certificate bound to an **OIDC-verified email** — the user
signs in with Google, GitHub or Microsoft, and Fulcio certifies that identity.
No PKI to manage, and unlike a self-signed identity the email is independently
verifiable. Nobody else in the PDF space does this.

The flow the library assembles (`fulcio.dart`):

1. mint an ephemeral P-256 key,
2. read the identity out of your OIDC token and sign it — the *proof of
   possession* Fulcio requires,
3. POST the public key + proof + token to Fulcio, receive a certificate chain,
4. wrap the ephemeral key and chain in a `PdfSigningIdentity`.

```dart
// 1. Your app runs the OAuth 2.0 PKCE flow and gets an OIDC id_token (a JWT).
final idToken = await myOAuthFlow(); // Google / GitHub / Microsoft sign-in

// 2. Exchange it for a keyless identity (you inject the HTTPS POST).
final identity = await fulcioSigningIdentity(
  oidcToken: idToken,
  transport: (body) async {
    final res = await http.post(
      Uri.parse(PdfFulcioAuthority.sigstore),
      headers: {'Content-Type': 'application/json'},
      body: body,
    );
    return res.bodyBytes;
  },
);

// 3. Sign IMMEDIATELY with a timestamp — the certificate expires in minutes,
//    so PAdES B-T is mandatory (the timestamp preserves the signing time).
final signed = await PdfEditor(document).saveSelfSignedPades(
  identity: identity,
  level: PdfPadesLevel.bT,
  timestampClient: myTimestampClient,
);
```

Caveats, stated plainly:

- The Sigstore roots are **not** Adobe-trusted, so this still reads as "signed,
  validity unknown" in Acrobat — but the certified email is real. To validate
  keyless signatures in this library's viewer, seed a `PdfTrustStore` with the
  Sigstore root (fetch it from the [Sigstore TUF trust
  root](https://github.com/sigstore/root-signing); the library ships no roots).
- Fulcio certificates carry a code-signing EKU that some strict document
  validators may flag.
- The flow needs network access and an OIDC client registration for your app.

The library performs no network I/O: your app runs the OAuth flow and the
HTTPS POST; `fulcio.dart` builds the request, parses the response, and does the
crypto. See `fulcioSigningIdentity`, `buildFulcioSigningRequest`,
`fulcioProofOfPossession`, `parseFulcioCertificateChain`, and `oidcTokenSubject`.

### In the DartPDF app

The app wires keyless signing into the **Digitally sign** dialog, and it is
**on by default on desktop/mobile** — no configuration. The trick is that
Sigstore runs a *public* interactive OAuth broker (`oauth2.sigstore.dev`, a Dex
instance), so DartPDF needs no OAuth client of its own: `oidc_signin.dart` uses
the public `sigstore` client with PKCE and a loopback redirect — exactly how
`cosign` signs — brokering Google/GitHub/Microsoft sign-in. `keyless_signing.dart`
ships the network transports (`fulcioHttpTransport`, DigiCert
`defaultTimestampClient`) and `PdfEditingController.addKeylessSignature` is the
PAdES B-T editor path.

So the flow is: **DartPDF menu → Digitally sign → "Sign in with your email
(keyless)…"** → the system browser opens, you sign in, and DartPDF mints a
short-lived certificate and signs B-T with a DigiCert timestamp.

Two knobs:

- **Web:** keyless is native-only. A browser tab can't host the loopback
  redirect, and — the harder wall — Sigstore's OAuth broker
  (`oauth2.sigstore.dev`) sends **no CORS headers**, so a browser is blocked
  from the token exchange in *any* flow (loopback, redirect, or device-code);
  Fulcio itself does allow cross-origin (`Access-Control-Allow-Origin: *`), but
  the sign-in step can't complete. So `app.dart` wires `oidcTokenProvider`
  off-web only, and the dialog shows a short note pointing web users to the
  desktop/mobile app. (A deployment with its own CORS-enabled IdP can still wire
  a custom `oidcTokenProvider` for web.)
- **Custom identity provider:** to use your own OAuth/OIDC instead of the
  Sigstore broker, pass your own `EditorScreen.oidcTokenProvider` returning an
  `id_token`. Passing `null` hides the option entirely; the file/self-signed
  paths are unchanged either way.

## Tier 4 — importing a free CA-issued certificate (Actalis)

If you want a certificate that chains to a **publicly-trusted** root without
paying, [Actalis](https://www.actalis.com/) issues **free S/MIME certificates**
validated against your email address, chaining to a public Actalis root that is
in many trust stores (though **not** Adobe's AATL — so, again, not the Acrobat
green check on its own). Enrollment is manual and browser-based, so this is an
import affordance rather than an in-app integration:

1. Enroll at Actalis' free S/MIME page and complete the email challenge.
2. Download the issued certificate and private key (usually a password-protected
   PKCS#12 / `.p12` bundle).
3. Export it to PEM with a standard tool, e.g. OpenSSL:

   ```sh
   openssl pkcs12 -in actalis.p12 -nodes -out actalis.pem
   ```

   The result is an `EC`/`RSA PRIVATE KEY` block plus one or more `CERTIFICATE`
   blocks (leaf first, then intermediates).
4. Load it as a signing identity and sign:

   ```dart
   final identity = PdfSigningIdentity.fromPem(actalisPem, name: 'Ada Lovelace');
   final signed = PdfEditor(document).saveSelfSigned(identity: identity);
   ```

   > `PdfSigningIdentity.fromPem` currently restores **EC** keys
   > (`EcPrivateKey.fromSec1`). For an RSA Actalis certificate, sign directly
   > with `saveSigned(privateKey: RsaPrivateKey.fromPem(...), certificates: [...])`.

Because the Actalis chain includes real intermediates, embed them and add a
trusted timestamp (B-T) so the signature validates offline; add long-term
validation material (B-LT/B-LTA) for archival signatures.

## Summary

| Option | Setup | Acrobat | This library's viewer |
| --- | --- | --- | --- |
| Tier 1 self-signed | none, offline | validity unknown | trusted if in trust store |
| Org-CA member | one-time CA | validity unknown | **trusted** (holds the CA) |
| Tier 2 timestamp | none (free TSA) | trusted *time* | trusted time |
| Tier 3 Fulcio keyless | OAuth sign-in | validity unknown, real email | trusted if Sigstore root added |
| Tier 4 Actalis import | manual enrollment | not AATL | trusted (public root) |

## Validating: trust lists and revocation

Signing is half the story; the other half is what a *verifier* concludes.
`PdfSignature.validate(trustStore:)` checks the chain against anchors you
supply. Two opt-in additions close the gap with desktop viewers.

### Revocation

`validate()` checks the signer and every intermediate against the revocation
data embedded in the document's `/DSS` (offline LTV).
`validateOnline(revocationClient:)` adds a live check through the same
injected `PdfRevocationClient` PAdES B-LT uses to gather material:

```dart
final result = await signature.validateOnline(
  trustStore: store,
  revocationClient: pdfOnlineRevocationClient(fetch: (request) async {
    // POST request.body (application/ocsp-request) or GET request.url
    return responseBytes;
  }),
);
for (final r in result.revocation) {
  print('${r.certificate.subjectCommonName}: ${r.status} via ${r.source}');
}
```

`pdfOnlineRevocationClient` asks each certificate's OCSP responder (from its
Authority Information Access) with a random nonce, drops an answer that
echoes a different nonce, and falls back to the CRL distribution points.
The validator accepts an OCSP answer only when its CertID matches the
certificate *and* issuer, it is signed by the issuer or by a delegated
responder the issuer authorized (id-kp-OCSPSigning), and it is current
(thisUpdate not in the future, nextUpdate not passed, or no older than seven
days without one). A CRL must be issued and signed by the certificate's
issuer and be current the same way.

**Policy.** A revoked certificate makes `chainTrusted` false, unless a
verified RFC 3161 signature timestamp is dated *before* the revocation time;
then the signature provably predates the revocation and stays valid (the
entry reports `affectsSignature: false`). The claimed signing time is not used
for this, because the signer controls it. When a status can't be established
(no responder, network failure, stale or unverifiable answer) it is reported
as `PdfRevocationStatus.unknown` and does not by itself untrust the chain,
which is how desktop viewers soft-fail. Each certificate's verdict carries its
`source`: `embedded` (/DSS) or `live`.

### Trust lists

`package:pdf_document/trust_lists.dart` is the opt-in trust-anchor library.
It contains code, not certificates:

- **EU trusted lists (EUTL).** `fetchEuTrustedLists(fetch:)` downloads the
  Commission's List of Trusted Lists, verifies its XML signature against the
  pinned LOTL signing certificates (`PdfEuLotl.signerFingerprints`), then
  downloads each Member State list and verifies it against the certificates
  the LOTL names for that country. It keeps the active qualified CA services
  (`CA/QC` and `NationalRootCA-QC` with a granted status). A list past its
  NextUpdate (with 12 hours of grace) is expired and may still hold
  withdrawn anchors. An expired LOTL is refused outright, and an expired
  national list is skipped. The result serializes to a PEM snapshot that
  records when the earliest of its lists expires (`toPem`, `expires`), and
  `PdfTrustLists.eutl(pem)` refuses a snapshot past that date.
- **Adobe Approved Trust List (AATL).** `parseAatlSecuritySettings(bytes)`
  reads a `.acrobatsecuritysettings` file you already have. It checks that the
  file's PDF signature chains to Adobe Root CA G2 (pinned by fingerprint) and
  keeps the identities marked as trusted roots. The file has no expiry
  field, only Adobe's signing date, so an age limit is opt-in (`maxAge:`).

**Why no data is committed.** The AATL is distributed by Adobe for Acrobat
under its member agreements, and we found no terms that allow a third party to
redistribute it, so dart-pdf neither bundles nor downloads it; the loader is
for deployments whose own arrangement with Adobe covers it. The EU lists are
public, and the LOTL itself is Commission content reusable under Decision
2011/833/EU, but the national lists are published by each Member State under
its own terms. Rather than commit a snapshot whose reuse terms we couldn't
confirm for every country, the library fetches the lists from their official
sources at run time.

**Refreshing.** `packages/pdf_document/tool/refresh_trust_lists.dart --eutl
eutl.pem [--aatl aatl.pem]` writes verified PEM snapshots for a host to ship or
cache. Cadence:

- The DartPDF app refreshes its cached EU snapshot when it is older than
  **7 days** or any list in it has expired, and only after a signed
  document is opened. If the refresh fails, it keeps a cache that is still
  current and drops an expired one. Member States
  reissue their lists when a service changes, so weekly keeps them current
  without re-downloading about 25 MB on every launch.
- A host that ships a snapshot should refresh it at least **monthly** and
  before each release.
- The pinned LOTL signers change only when the Commission publishes new ones
  in the Official Journal (the most recent change was the TL v6 transition in
  April 2026). The current set is the six digests in OJ C/2026/1944
  (https://eur-lex.europa.eu/eli/C/2026/1944/oj), checked digest for digest
  on 2026-09-24. When a new notice appears, cross-check it against the
  LOTL's pointer to itself and update `PdfEuLotl.signerFingerprints`. Until
  then the refresh tool accepts `--lotl-signer <sha256>` overrides.

### In the editor and app

`PdfEditingController.trustStore` and `.revocationClient` feed the signature
panel. It shows whether the signer is trusted, self-signed, or issued by an
authority you don't trust. It also shows whether the certificate was revoked
(and whether that was before or after a trusted timestamp), confirmed not
revoked (online or from embedded data), or couldn't be checked. Outside the
browser, the DartPDF app wires both by default (`app/lib/signature_trust.dart`):
an HTTP revocation client, and the EU trusted list fetched and cached as above.
The web build keeps to embedded data, since browsers block cross-origin
OCSP/CRL requests.
