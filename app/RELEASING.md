# Releasing DartPDF

The standalone app ships from the `app/` workspace package. Versioning,
artifact builds, and packaging are automated; **code signing and store upload
are manual** because they need credentials only the maintainer holds.

## Version

`app/pubspec.yaml` `version:` is the single source of truth (`X.Y.Z+build`).
CI passes `--build-name`/`--build-number` derived from the tag and run number,
so platform build files don't hardcode versions.

## Cutting a release

1. Bump `version:` in `app/pubspec.yaml`.
2. Tag and push: `git tag app-v0.1.0 && git push origin app-v0.1.0`.
3. `.github/workflows/release-app.yml` builds every platform and attaches the
   artifacts to a **draft** GitHub Release. Review, then publish.

You can also run the workflow manually (Actions → Release app → Run workflow)
with a version input; that builds artifacts but only creates a Release on a tag.

## What CI produces

| Platform | Artifact | Signed? |
|---|---|---|
| Android | `app-release.apk`, `app-release.aab` | Debug keys unless a release keystore is configured (below) |
| iOS | `…-ios-unsigned.zip` (`.app`) | **No**, not installable; needs your Apple signing |
| macOS | `…-macos.dmg` | **No**, needs Developer ID signing + notarization |
| Windows | `…-windows-x64.zip` | **No**, needs an Authenticode cert / MSIX |
| Linux | `…-linux-x64.tar.gz` | n/a |
| Web | `…-web.zip` | n/a |

## The credential boundary

DartPDF ships to the **RES (Railway Engineering Solutions) Google Play
Console**, the same account Trax uses. No separate Play developer registration
is needed; DartPDF is just a new app under it.

**Upload key.** A dedicated DartPDF upload keystore has been generated at
`app/android/app/upload-keystore.jks` (RSA-2048, alias `upload`), referenced by
`app/android/key.properties`. Both are git-ignored; `build.gradle.kts` picks
them up automatically, so `flutter build appbundle --release` is Play-ready.
**Back up the keystore + password off-machine.** Losing them means resetting
the upload key via Play Console support. (Until the first Play upload registers
this cert, it is freely swappable.) Generate a replacement with:
`keytool -genkeypair -v -keystore upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload`.

**First release (Play Console UI, under RES's account):**
1. Create app → name **DartPDF**, type *App*, *Free*, default language.
2. Internal testing track → create release → upload `app-release.aab` → opt in
   to **Play App Signing** (Google holds the app signing key; our keystore is
   the *upload* key).
3. Complete the required declarations to roll out: **privacy policy URL** (host
   `app/PRIVACY.md`), **Data safety** = *no data collected, no data shared*
   (DartPDF is fully on-device), content-rating questionnaire, target audience,
   ads = *no ads*, app access = *no login required*.

**Automated uploads (later releases).** Trax already drives Play via the
`androidpublisher` API using the GCP service account
`codemagic-google-play-api@trax-eb28a.iam.gserviceaccount.com`
(`~/repos/trax/tools/play-store-upload/`). Grant that service account access to
the DartPDF app in Play Console (Users & permissions), then the same
`play-store-upload.py` pattern (or `fastlane supply`) can push subsequent AABs
to the internal track headlessly. The first release must still be created in the
UI to clear the one-time declarations.

In CI, provide the keystore + `key.properties` via repository secrets and write
`key.properties` before the Android build (not wired by default; add it when
you're ready to ship signed AABs from CI rather than locally).

### iOS / macOS (App Store / notarized DMG)

DartPDF ships under the **RES Apple Developer account** (no separate
membership needed). What that means concretely:

- **App ID / Team.** In the RES account's Developer portal, register the bundle
  id `dev.milanko.dartpdf` as an explicit App ID under the RES team. Apple does
  **not** require the bundle id to match RES's reverse-domain. An App ID is
  just a unique string owned by a team, so the existing id can stay. In Xcode,
  set **Signing → Team** to RES's team (Team ID `N5K9GK8B27`) for the Runner
  target (iOS and macOS). Automatic signing then provisions against RES.
- **Seller name.** If RES is an *Organization* account, the App Store listing's
  developer/seller name shown to users is **RES**, not an individual. That is the
  accepted trade for reusing the account. (A Personal account would show the
  account holder's name.)
- **App Store Connect.** You need an **App Manager** (or Admin) role on RES's App
  Store Connect to create the DartPDF app record and upload builds.
- **iOS:** open `app/ios/Runner.xcworkspace`, pick the RES team, archive in Xcode
  (or add Fastlane), then upload to App Store Connect / TestFlight.
- **macOS:** for the **App Store**, archive with the RES team and submit via
  Xcode/Transporter. For a **notarized DMG** distributed outside the store, sign
  with RES's *Developer ID Application* cert
  (`codesign --deep --options runtime`), then `xcrun notarytool submit` with a
  RES App Store Connect API key (or Apple ID + app-specific password) and staple.
  Wire those as CI secrets to automate the release-app.yml macOS/iOS jobs.
- Add privacy-usage strings to `Info.plist` if you later use the camera/photos.

### Windows (Microsoft Store / signed installer)
- An Authenticode code-signing certificate, or package as MSIX (add the
  `msix` dev-dependency + `msix_config`, which also declares the `.pdf` file
  association) and sign with your cert.

### Linux
- The tarball runs as-is. For distribution, wrap as AppImage / Flatpak / Snap /
  `.deb`; the desktop file should declare `MimeType=application/pdf;`.

### Web
- The CI zip is a static bundle. Host it anywhere; for the file-association
  ("open .pdf with the installed app") to work, serve over HTTPS so the PWA can
  install and the File Handling API is available.

## File associations

The receive side ships in the app (see Phase 2). OS registration is per
platform: macOS/iOS via the bundled Info.plist `CFBundleDocumentTypes`,
Android via the manifest intent-filters, web via `manifest.json`
`file_handlers`. Windows and Linux register the association at **install**
time. Declare it in the MSIX manifest / `.desktop` file when you build those
installers.
