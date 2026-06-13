# Releasing dart-pdf Editor

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
| iOS | `…-ios-unsigned.zip` (`.app`) | **No** — not installable; needs your Apple signing |
| macOS | `…-macos.dmg` | **No** — needs Developer ID signing + notarization |
| Windows | `…-windows-x64.zip` | **No** — needs an Authenticode cert / MSIX |
| Linux | `…-linux-x64.tar.gz` | n/a |
| Web | `…-web.zip` | n/a |

## The credential boundary — what you must provide

### Android (Play Store)
1. Create an upload keystore:
   `keytool -genkey -v -keystore upload.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload`
2. Locally, create `app/android/key.properties` (git-ignored):
   ```
   storeFile=/absolute/path/to/upload.jks
   storePassword=…
   keyAlias=upload
   keyPassword=…
   ```
   `build.gradle.kts` picks it up automatically; `flutter build appbundle
   --release` is then Play-ready.
3. In CI, provide the keystore + properties via repository secrets and write
   `key.properties` in the workflow before the Android build (not wired by
   default — add it when you're ready to ship signed AABs).

### iOS / macOS (App Store / notarized DMG)
- Apple Developer Program membership; a Distribution certificate + provisioning
  profile (iOS) and a Developer ID Application certificate (macOS).
- iOS: open `app/ios/Runner.xcworkspace`, set the team, archive in Xcode (or
  add Fastlane), then upload to App Store Connect.
- macOS: `codesign --deep --options runtime` the `.app`, staple after
  `xcrun notarytool submit`. Add your Apple ID / app-specific password as CI
  secrets to automate.
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
time — declare it in the MSIX manifest / `.desktop` file when you build those
installers.
