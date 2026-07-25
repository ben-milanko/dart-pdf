# 2026-07-23 — Desktop in-place app updates

Branch `claude/desktop-in-place-updates-xhvrb8`. Turn the desktop update
*checker* into an actual updater: "Update now" downloads the newer release
in-app and applies it, instead of only opening a browser tab at the release
download. Deliberately still user-initiated and confirmed — not a silent
background swap — because the bundles are unsigned (the reasoning the old
`update.dart` header called out).

## The apply strategy (per platform)

`app/lib/update_installer.dart`'s `UpdateInstaller.modeFor(assetName)` picks
one of three modes, keyed off the artifact CI produces and how the process is
running:

- **Linux AppImage → `inPlaceRelaunch`.** An AppImage is a single executable,
  so the update is clean: download the new image, write it *next to* the
  running one (same directory, so the replace is a same-filesystem atomic
  rename — a temp dir is often a different mount and `rename` would `EXDEV`),
  `chmod +x`, rename over `$APPIMAGE`, then relaunch and `exit(0)`. Only taken
  when `$APPIMAGE` is set **and** points at a real file (`appImagePath`), so a
  tarball/`flutter run` install never hits it.
- **macOS `.dmg` / Windows `.exe` → `openArtifact`.** Swapping a running,
  unsigned app bundle is fragile, so instead download to the Downloads folder
  and hand the file to the OS: the `.dmg` mounts (user drags the app over),
  the installer `.exe` runs. Downloaded, not silently applied.
- **Everything else → `unsupported`.** Linux tarball, mobile, or a release
  with no matching artifact (only the page URL): fall back to the old browser
  download.

## Testability: the `dart:io` seam

All filesystem/process work lives behind `UpdatePlatformOps`
(`update_platform.dart`, no `dart:io`), with the real implementation in
`update_platform_io.dart` pulled in through a conditional import
(`update_platform_stub.dart` on web, where update checks are disabled anyway).
`UpdateInstaller` takes the ops and an `http.Client` factory injected, so the
whole download→verify→apply flow is unit-tested with a fake ops (records
`write`/`replace`/`relaunch`/`open`) and a `MockClient` — no real disk, no
real network, and crucially no real `exit(0)` (the fake's `relaunchAndExit`
throws a sentinel the test asserts on). See `test/update_installer_test.dart`
(mode selection, the AppImage write/replace/relaunch sequence, hand-off,
size-mismatch/empty/non-200/cancel guards, progress monotonicity).

## Integrity + progress

The download streams through `http.Client.send`, reports `(received, total)`
for the progress dialog, polls an `isCancelled` closure (dialog Cancel
button), and — when GitHub reported an asset `size` — rejects a download whose
byte count doesn't match before anything is written over the install. Sizes
are new on `ReleaseInfo.assetSizes`, parsed from the release JSON's
`asset.size`; `UpdateService` exposes `downloadAssetName` / `downloadAssetSize`
alongside the existing `downloadUrl`.

## UI wiring

`update_install_flow.dart`'s `startUpdateInstall(...)` is shared by the
Settings → Updates button and the startup banner: it shows a progress dialog,
runs the installer, and on hand-off toasts a confirmation (the AppImage path
just relaunches). On `unsupported` or any failure it falls back to
`launchUrl(downloadUrl)`, so nothing regresses where in-place can't apply. The
banner button reads "Update now" when an in-app apply path exists, else the
old "Download". `EditorScreen` and `showAppSettings` gained an injectable
`updateInstaller` seam mirroring the existing `updateService` one.

## macOS sandbox gotcha

The macOS build is sandboxed. Two things had to change for the hand-off to
actually work there:

- `openArtifact` goes through `url_launcher` (`NSWorkspace` on macOS,
  `ShellExecute` on Windows, `xdg-open` on Linux), **not** `Process.start`
  — spawning `open`/`cmd` is denied under the App Sandbox.
- Added `com.apple.security.files.downloads.read-write` to both
  `macos/Runner/*.entitlements` so the download can land in `~/Downloads`.

The AppImage self-replace (Linux, unsandboxed) and the Windows hand-off keep
using `Process`/relaunch directly.
