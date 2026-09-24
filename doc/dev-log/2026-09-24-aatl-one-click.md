# One-click, opt-in Adobe Approved Trust List (#936 follow-up)

## What landed

- **pdf_document** (`trust_lists/aatl.dart`)
  - `fetchAatl({fetch, now, maxAge, rootFingerprint})` downloads
    `PdfAatl.url` through the host transport and runs
    `parseAatlSecuritySettings`: PDF signature intact, covering the whole
    file, and chaining to the pinned Adobe Root CA G2. The returned
    `PdfAatlSnapshot` is stamped with `fetchedAt`.
  - `PdfAatl.maxAge` is **365 days** from Adobe's signing time. The file has
    no expiry field. Adobe republishes it when membership changes, several
    times a year: the live file was signed 2026-09-10. A year never trips on
    a normal gap and still bounds how long a dropped root could stay trusted.
  - The snapshot PEM now carries `# signed:`, `# signer:` and
    `# fetched-at:` headers. It gained `fromPem` and `isCurrentAt`.
- **Provenance** (`signature.dart`)
  - `PdfTrustStore.addCertificate/addDer(…, source:)` and `sourceOf(anchor)`
    record where an anchor came from.
  - The EU and AATL snapshots tag their anchors
    (`PdfEuLotl.sourceName`, `PdfAatl.sourceName`).
  - `PdfTrustLists.combine` keeps the tags.
  - The sidebar's trusted line becomes "Trusted via {authority} ({list})"
    (new key `sidebarSignatureTrustedViaList`).
- **Editor hook** (dart_pdf_editor)
  - `PdfEditingController.signatureTrustAction` is a
    `PdfSignatureTrustAction` with a label and explanation (both
    context-aware, so the host localizes them) and an `onPressed`.
  - The panel shows it only under an **intact** signature whose signer is
    not trusted, not self-signed (no list can vouch for that) and not
    revoked.
  - The library carries no Adobe policy.
- **App** (`app/lib/signature_trust.dart`, `signature_trust_store_io.dart`,
  `settings_screen.dart`)
  - `AatlTrustSetting` persists the choice in SharedPreferences
    (`dart_pdf_editor_app.signatures.aatl`). It is off by default.
  - `SignatureTrust` now keeps the EU and AATL stores separately and hands
    every attached controller their union.
  - While the setting is off, attached controllers get the panel action,
    which calls `setAatlEnabled(true)`.
  - **Turning it on** saves the choice, clears the action and loads the list
    at once. **Turning it off** bumps a generation counter, drops the AATL
    roots, publishes, restores the action and deletes the cache. Because of
    the generation counter, a download still in flight when the user turns
    it off can't bring the roots back.
  - With a saved "on", the list loads lazily, the first time a signed
    document is attached, like the EU list.
  - `loadAatlTrustStore` uses the cache (`signature_trust/aatl.pem`) while
    it was fetched **under 7 days** ago and is within `maxAge`. Otherwise it
    downloads in an `Isolate.run`, verifies and caches.
  - After a failed download it falls back only to a cache within `maxAge`.
    `deleteAatlCache` removes the file.
  - Settings has a new "Signatures" section with the switch
    (`settings-aatl`). It shows only when `SignatureTrust.platformDefault`
    exists, so not on the web or under `flutter test`.

## UX

- **Settings > Signatures:** a "Trust Adobe Approved Trust List" switch.
  Underneath: "Downloads Adobe's list of trusted signing authorities from
  Adobe and checks for updates weekly. Nothing about your documents is
  sent."
- **Signature panel:** under an unknown signer, a "Trust Adobe Approved
  Trust List" button with a one-line explanation. One click switches the
  setting on. The row re-validates when the list lands and then reads
  "Valid — trusted" / "Trusted via X (Adobe Approved Trust List)".

## Gotchas

- `fetchAatl`'s `rootFingerprint` parameter exists for tests. The fixture
  signs a fake security-settings PDF under the test PKI root.
- The app strings live in the app ARB bundle, not the editor's, because the
  editor only renders what the host passes in.
