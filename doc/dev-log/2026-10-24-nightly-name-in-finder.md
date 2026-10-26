# 2026-10-24 - the nightly DMG shows "DartPDF Nightly" in Finder

The nightly DMG window still labelled the app "DartPDF": the 2026-10-11 change
(`2026-10-11-nightly-identifies-itself.md`) set `CFBundleName` and
`CFBundleDisplayName` to "DartPDF Nightly", but Finder (DMG window,
/Applications, Spotlight) shows the bundle's file name and ignores a plain
`CFBundleDisplayName`.

Finder shows a different name only through a *localized* display name:

- `LSHasLocalizedDisplayName = true` in Info.plist;
- `Contents/Resources/{en,Base}.lproj/InfoPlist.strings` carrying
  `CFBundleDisplayName = "DartPDF Nightly"` (and `CFBundleName`);
- the plain Info.plist `CFBundleDisplayName` must equal the file name
  (`DartPDF`), or Finder assumes the user renamed the bundle and shows the
  file name.

All three are written in nightly-desktop.yml's "Name the bundle DartPDF
Nightly" step, before the ad-hoc re-sign so the seal covers them. The bundle
stays `DartPDF.app` with the same bundle id, so nightly and stable still
replace each other in /Applications (the in-app DMG hand-off and the CLI path
`/Applications/DartPDF.app/Contents/MacOS/dartpdf-cli` rely on that). Renaming
the bundle to `DartPDF Nightly.app` was rejected: dragging it to Applications
would leave two copies with one bundle id side by side.

Finder caches display names; an already-installed copy may need a relaunch of
Finder (or a fresh install) before the new name shows.
