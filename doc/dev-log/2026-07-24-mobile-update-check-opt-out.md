# Mobile opts out of the GitHub-release update check

## Problem

On Android and iOS the "new version available" banner (and the Settings
"Updates" section) fired off the same GitHub Releases check as the desktop
builds. But mobile updates ship through the app stores, and a GitHub release
routinely lands *before* the App Store / Play review clears. So mobile users
were nagged about a version they couldn't install yet, and the "Download"
button just sent them to a GitHub page (iOS: the release page; Android: a
sideload APK) that isn't their update channel.

## Fix

`UpdateService.supported` (`app/lib/update.dart`) is now an **instance** getter
(was `static bool get supported => !kIsWeb`) that gates on the target platform:
only the desktop builds (macOS / Windows / Linux) — the ones distributed as
direct GitHub downloads — are supported. Web (served fresh / PWA service
worker) and Android/iOS (store-updated) opt out.

`supported` already gated `checkForUpdates` (early-returns when off), so the
mobile path now short-circuits before any network call, the startup banner
(`editor_screen.dart` `_onUpdateStatus`), and the Settings section
(`settings_screen.dart`). The two call sites moved from the static
`UpdateService.supported` to the instance getter (`_updates.supported` /
`widget.updates!.supported`) — both already hold an instance.

Making it an instance getter (reading the injected `platform`) also makes the
gate directly unit-testable.

## Fallout

- `_platformAsset` dropped its now-unreachable `TargetPlatform.android =>
  ['app-release.apk']` branch: `downloadUrl` is only ever read on desktop
  (both UI surfaces are gated by `supported`), so the APK mapping was dead.
  The release still ships the APK artifact for manual sideloaders; the app
  just no longer surfaces it.
- Widget/unit tests default to the **Android** target platform, so the
  update-flow tests now pin a desktop platform (the `_service`/`_fakeService`
  helpers default to `TargetPlatform.macOS`). New tests cover the mobile
  opt-out: `supported` false + `checkForUpdates` no-op on Android/iOS
  (`update_test.dart`), and no startup banner / no Settings "Updates" section
  on Android/iOS (`update_settings_test.dart`).
