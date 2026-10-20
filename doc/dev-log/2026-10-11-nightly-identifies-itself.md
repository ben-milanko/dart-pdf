# 2026-10-11 - the nightly build identifies itself

An installed nightly used to be indistinguishable from a stable DartPDF: same
window title, About line, Start menu entry and Installed apps row. It now calls
itself **DartPDF Nightly** everywhere it names itself.

- `--dart-define=PDF_BUILD_CHANNEL=nightly` (nightly-desktop.yml, both
  platforms). `app/lib/build_channel.dart` reads it into `kBuildChannel` /
  `kIsNightlyBuild` / `kProductDisplayName`. It has no imports so the eager
  `window_support.dart` can use it without pulling in the deferred
  `app_info.dart` unit. `AppInfo.displayName` / `displayVersion` (e.g.
  `2.3.0 nightly (abc1234)`) feed the window titles, the welcome hero, the
  Settings About + update status lines, and the licenses page. DevTools
  diagnostics add `buildChannel`.
- Windows: `build-installer.ps1 -ProductName 'DartPDF Nightly'` sets the
  installer title, Start menu shortcut and Installed apps DisplayName. The
  install dir, uninstall key and `DartPDF.pdf` ProgID are deliberately shared,
  so nightly and stable still replace each other in place (the in-app updater
  depends on that). Each installer deletes the other channel's shortcut, and
  both uninstallers delete both names. The stable NSIS script inline in
  release-app.yml got the same two `Delete` lines.
- macOS: PlistBuddy sets `CFBundleName`/`CFBundleDisplayName` to
  "DartPDF Nightly" before the ad-hoc re-sign. The bundle stays `DartPDF.app`
  with the same bundle id, so prefs and the DMG hand-off carry over.
- Not a side-by-side install. Running both channels at once would need a
  separate bundle id/AppUserModelID, install dir, ProgID and single-instance
  mutex.
