# Releasing DartPDF

> Releasing the pub.dev **packages** (not the app) is documented separately in
> [`doc/RELEASING-packages.md`](../doc/RELEASING-packages.md).

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
   artifacts to a **draft** GitHub Release. Review, then publish - the in-app
   update checker cannot see a draft. Publishing also triggers
   `.github/workflows/publish-flatpak.yml` and
   `.github/workflows/publish-snap.yml`, which package and smoke-test the
   Linux tarball, then update the official Flatpak repository and Snap Store.
4. Write the store "What's New" text into
   [`release-notes/`](release-notes/) (`<version>-stores.txt` for Play,
   `<version>-appstore.txt` for both App Store platforms). See that
   directory's README for the length caps and the Guideline 2.3.10 rule.

You can also run the workflow manually (Actions → Release app → Run workflow)
with a version input; that builds artifacts but only creates a Release on a tag.

## Nightly Windows builds

`.github/workflows/nightly-windows.yml` checks `main` each night and starts a
Windows runner only when the commit differs from the last successfully
published nightly. It updates the rolling `app-nightly` prerelease with an
unsigned per-user NSIS installer, a portable ZIP, checksums, and the commits
since the previous build.

Windows users opt in under **Settings → Updates → Nightly updates**. The choice
persists, participates in the normal startup update check/banner, and uses the
same download-and-installer hand-off as final GitHub releases. CI stamps the
source SHA into nightly and final Windows binaries so an installed nightly is
not offered again; dismissing one nightly suppresses only that source commit,
not the next rolling build.

> **The CI artifacts are not store-uploadable.** The Android bundle is
> debug-signed and the iOS build is unsigned; store builds are made locally
> (`flutter build appbundle --release`, `flutter build ipa`, and an
> `xcodebuild archive` + `-exportArchive` for macOS) and staged into
> `app/build/releases/<version>/`.
>
> Keep the hosted Android compatibility patch in `release-app.yml` until the
> affected plugins migrate to Flutter's current Android toolchain. Local
> release builds use the app's configured compile SDK and should be verified
> before each Play upload.

## In-app update checker

The app checks these Releases for a newer build (`app/lib/update.dart`,
surfaced in Settings → Updates and a startup banner). On **desktop** the
check is followed by a user-initiated *in-place update*
(`app/lib/update_installer.dart`): "Update now" downloads the matching
artifact in-app (with a progress dialog and a byte-size integrity check
against the release metadata) and then applies it. A **Linux AppImage** is a
single executable, so the new image is written next to the running one and
atomically renamed over it before the app relaunches. On **macOS and
Windows** — where swapping a running, unsigned bundle is fragile — the
artifact is downloaded and handed to the OS installer (the `.dmg` mounts, the
`.exe` runs). Anywhere without an in-app apply path (a Linux tarball install,
mobile, a release page with no matching artifact) falls back to the old
browser download. The apply and hand-off are still user-confirmed, not a
silent background swap. Stable app Releases must keep the
**`app-v<version>` tag** and the artifact file names CI produces
(`dartpdf-macos.dmg`, `dartpdf-windows-portable.exe` /
`dartpdf-windows-installer.exe` / `dartpdf-windows-x64.zip`,
`dartpdf-linux-x86_64.AppImage` /
`dartpdf-linux-x64.tar.gz`, `app-release.apk`). Other tags, such as this
repo's pub-package releases, are ignored. The one exception is the exact
rolling tag `app-nightly`, recognized on Windows only after the user enables
nightly updates; it must provide the source markers and
`dartpdf-nightly-windows-installer.exe`/ZIP assets documented below. Publish
stable draft Releases so the GitHub `/releases` API exposes them (drafts
aren't visible unauthenticated). Flatpak and Snap installations skip the
GitHub checker and update through their package repositories. The web build is
always served fresh, so it skips the check.

## What CI produces

| Platform | Artifact | Signed? |
|---|---|---|
| Android | `app-release.apk`, `app-release.aab` | Debug keys unless a release keystore is configured (below) |
| iOS | `…-ios-unsigned.zip` (`.app`) | **No**, not installable; needs your Apple signing |
| macOS | `…-macos.dmg` | Ad-hoc signed with `Runner/AdHoc.entitlements`; needs Developer ID signing + notarization for public distribution |
| Windows | `…-windows-installer.exe`, `…-windows-portable.exe`, `…-windows-x64.zip` | **No**, needs an Authenticode cert for non-Store distribution |
| Windows (Store) | `dartpdf-windows-store.msix` (separate workflow, see below) | Intentionally unsigned - Microsoft re-signs Store submissions |
| Linux | `…-linux-x64.tar.gz`, `…-linux-x86_64.AppImage` | Flatpak repository is GPG-signed; raw artifacts are unsigned |
| Web | `…-web.zip` | n/a |

### Desktop CLI / MCP sidecar

Every macOS, Windows, and Linux native build compiles the VM-only
`packages/dart_pdf_cli/bin/dartpdf.dart` entrypoint into a self-contained target
executable. It uses the same architecture as the Flutter runner; a universal
macOS release compiles its arm64 and x64 slices on native GitHub runners and
merges them with `lipo` before codesigning. (A local macOS build contains the
host-native sidecar.) Mac App Store archives omit the optional sidecar because
the standalone Dart runtime imports a private dyld unwind SPI that App Store
validation rejects; the GUI and non-Store macOS distributions are unaffected.
The native project files otherwise place it in:

- macOS: `DartPDF.app/Contents/MacOS/dartpdf-cli` (the suffix avoids a
  case-insensitive collision with the `DartPDF` GUI executable; it is signed as
  nested code before the outer app bundle);
- Windows: `dartpdf.exe` beside `dart_pdf_editor_app.exe`;
- Linux: `dartpdf-cli` beside `dart_pdf_editor_app` (`dartpdf` remains the
  established GUI launcher in Linux packages).

Because the release packagers archive those native bundles, the sidecar also
travels in the DMG, Windows installer/portable/MSIX outputs, Linux tarball, and
AppImage. Linux store packages expose it as `/app/bin/dartpdf-cli` for Flatpak
and `dartpdf.cli` for Snap; the AUR package installs `/usr/bin/dartpdf-cli`.
The macOS and Windows installers deliberately do not alter `PATH`. See the CLI
package README for MCP registration commands.

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
- **macOS:** the build re-signs the `.app` and embedded native libraries
  consistently, and Release carries a library-validation exception so the
  ad-hoc hardened app can load the bundled ONNX Runtime dylib. This is only a
  local consistency signature, not Developer ID signing. For the
  **App Store**, archive with the RES team and submit via
  Xcode/Transporter. For a **notarized DMG** distributed outside the store, sign
  with RES's *Developer ID Application* cert
  (`codesign --deep --options runtime`), then `xcrun notarytool submit` with a
  RES App Store Connect API key (or Apple ID + app-specific password) and staple.
  Wire those as CI secrets to automate the release-app.yml macOS/iOS jobs.
- Add privacy-usage strings to `Info.plist` if you later use the camera/photos.

### Windows (Microsoft Store / signed installer)
- CI produces an unsigned per-user NSIS installer. It installs under
  `%LOCALAPPDATA%\Programs\DartPDF`, creates Start Menu shortcuts, registers
  uninstall metadata, and adds DartPDF to the PDF "Open with" list.
- For distribution **outside** the Store, sign that installer with an
  Authenticode code-signing certificate.
- **Microsoft Store** shipping is automated and entirely CLI-driven:
  `.github/workflows/release-windows-store.yml` builds the Store MSIX
  (`dart run msix:create --store`, configured by `msix_config` in
  `app/pubspec.yaml` — which also declares the `.pdf` file association) and
  uploads it with the Microsoft Store Developer CLI. Store submissions are
  **unsigned**; Microsoft re-signs them, so no Authenticode cert is needed for
  this channel. An `app-v*` tag uploads a **draft** submission; committing to
  certification is an explicit manual workflow run.

  The one-time account setup is *not* scriptable — the app must be created and
  its name reserved in Partner Center by hand, an Azure AD app has to be
  associated with the account, and the first submission's listing/age-rating
  must be completed in the UI (the same boundary as Play and the App Store
  above). Registration itself is free as of 2026. Configuration is four
  repository **variables** (the public MSIX identity values + Store ID) and four
  **secrets** (the Azure AD credentials); until they are set the workflow
  **skips** rather than fails.
  See [`packaging/msstore/README.md`](packaging/msstore/README.md).

### Linux
- The preferred distribution is the official GPG-signed Flatpak remote at
  <https://dartpdf-flatpak.web.app>. Users install it with
  `flatpak install --from https://dartpdf-flatpak.web.app/dartpdf.flatpakref`.
- `.github/workflows/publish-flatpak.yml` runs when an `app-v*` release is
  published. It digest-verifies the Linux tarball, builds and signs the app
  commit and repository summary, installs and smoke-tests the signed package,
  then deploys the dedicated `dartpdf-flatpak` Firebase Hosting site.
- Snap Store is the secondary package-managed channel. Install it with
  `sudo snap install dartpdf`; its public listing is
  <https://snapcraft.io/dartpdf>.
- `.github/workflows/publish-snap.yml` digest-verifies the same Linux release
  asset, builds, lints, installs, and launches the strictly confined snap,
  uploads it to `stable`, then verifies a clean install from the Store. The
  repository secret `SNAPCRAFT_STORE_CREDENTIALS` must contain an exported
  credential scoped to the `dartpdf` snap, stable channel, and
  `package_push,package_release,package_update` ACLs. Rotate it with
  `snapcraft export-login` before it expires; packaging details live in
  [`packaging/snap/README.md`](packaging/snap/README.md).
- The private repository key lives in the Actions secret
  `FLATPAK_GPG_PRIVATE_KEY`. Its pinned fingerprint is
  `32E53D6314CF1F1448462E2319EFDD96AD44514D`; backup details are in
  [`../flatpak-hosting/README.md`](../flatpak-hosting/README.md). Do not rotate
  it casually: existing clients trust this key.
- AppImage and portable tarball artifacts remain available as fallbacks. The
  AppImage uses the in-app updater; Flatpak and Snap builds deliberately leave
  updates to their package managers.

### Web
- The CI zip is a static bundle. Host it anywhere; for the file-association
  ("open .pdf with the installed app") to work, serve over HTTPS so the PWA can
  install and the File Handling API is available.

## File associations

The receive side ships in the app (see Phase 2). OS registration is per
platform: macOS/iOS via the bundled Info.plist `CFBundleDocumentTypes`,
Android via the manifest intent-filters, web via `manifest.json`
`file_handlers`. Windows and Linux register the association at **install**
time: the NSIS installer writes the ProgID registry keys, the Store MSIX
declares it via `msix_config`'s `file_extension: .pdf`, and Linux ships it in
the `.desktop` file's `MimeType`.

### Document (file) icon

The branded page icon Finder / Explorer draw for an associated `.pdf` is
generated by `tool/gen_document_icon.py` (white sheet + folded corner + the
app-icon logo badged lower-right). Rerun it after any app-icon change; it
overwrites `macos/Runner/DocumentIcon.icns` and
`windows/runner/resources/document_icon.ico` in place.

- **macOS**: `macos/Runner/Info.plist`'s `CFBundleDocumentTypes` entry sets
  `CFBundleTypeIconFile = DocumentIcon`; the `.icns` is a Copy-Bundle-Resource
  in `Runner.xcodeproj`.
- **Windows**: `windows/runner/Runner.rc` embeds the `.ico` as resource id
  `102` (`IDI_DOC_ICON`), and the NSIS installer points the `DartPDF.pdf`
  ProgID `DefaultIcon` at `dart_pdf_editor_app.exe,-102`.

**Caveat:** the file's icon is drawn by whichever app is the user's *default*
handler for PDFs — our icon only appears once DartPDF is set as default.
Neither macOS nor Windows lets an app silently claim the default; the
installer/`Info.plist` only offers DartPDF as a handler (macOS
`LSHandlerRank = Alternate`; Windows `.pdf` `OpenWithProgids`).
