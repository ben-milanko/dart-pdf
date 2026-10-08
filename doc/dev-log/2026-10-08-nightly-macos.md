# 2026-10-08 - nightly macOS preview build

The rolling `app-nightly` prerelease now carries a macOS DMG alongside the
Windows installer/ZIP.

- `nightly-windows.yml` became `.github/workflows/nightly-desktop.yml`. The
  `changes` gate (skip when `main` hasn't moved past the release body's
  `<!-- main-sha -->` marker) is shared; `macos_cli` builds the arm64
  (`macos-15`) and x64 (`macos-15-intel`) CLI/MCP slices, and `macos` mirrors
  `release-app.yml`'s job: runner-only ad-hoc signing patch, `flutter build
  macos` with `PDF_BUILD_COMMIT`, lipo'd universal sidecar, ad-hoc re-sign with
  `AdHoc.entitlements`, 12s launch smoke test, DMG as
  `dartpdf-nightly-macos.dmg`.
- `release` needs both platforms, so the tag, assets, and SHA marker always
  describe one commit. A macOS-only failure therefore holds the Windows
  nightly back too; the next night retries. `SHA256SUMS.txt` moved to the
  Linux release job so it covers all three assets.
- In-app updater (`app/lib/update.dart`): `nightlySupported` now includes
  macOS, and the macOS asset preference is `dartpdf-nightly-macos.dmg` then
  `dartpdf-macos.dmg`. The DMG hand-off already existed for stable releases.
  The Settings subtitle names both platforms in every locale.
- The DMG is ad-hoc signed and not notarized: Gatekeeper needs right-click →
  Open on first launch; the release notes say so.
