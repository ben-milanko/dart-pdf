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
