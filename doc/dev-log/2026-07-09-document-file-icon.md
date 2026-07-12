# 2026-07-09 — Branded document (file) icon for macOS + Windows

## Problem

Finder (and Windows Explorer) showed a generic page icon for `.pdf` files
handled by DartPDF instead of the DartPDF logo.

## Root cause

The file icon a shell draws for a document is supplied by whichever app is
the user's **default handler** for that type. On Ben's Mac DartPDF *is* the
default PDF handler (`LSCopyDefaultApplicationURLForURL` →
`/Applications/DartPDF.app`), but its `CFBundleDocumentTypes` entry declared
no `CFBundleTypeIconFile`, so Launch Services had no doc-type icon to draw and
fell back to the generic page. On Windows the NSIS installer already set the
`DartPDF.pdf` ProgID `DefaultIcon` to `…exe,0` (the app icon), but only when
DartPDF is the default handler — and it used the app tile, not a document icon.

## Change

New `app/tool/gen_document_icon.py` composes a document icon (white sheet,
folded top-right corner, brand-coloured content lines, app-icon logo badged
lower-right) from `app_icon_1024.png` and emits both platform assets
byte-reproducibly:

- `macos/Runner/DocumentIcon.icns` (via `iconutil`)
- `windows/runner/resources/document_icon.ico` (via ImageMagick, 16–256px)

Wiring:

- **macOS**: added `CFBundleTypeIconFile = DocumentIcon` to the PDF doc-type
  dict in `macos/Runner/Info.plist`, and added `DocumentIcon.icns` as a
  Copy-Bundle-Resource in `Runner.xcodeproj/project.pbxproj` (file ref +
  build file + Resources phase + group). Verified: after
  `flutter build macos`, the bundle contains `DocumentIcon.icns` and
  `lsregister -dump` shows the `PDF document` claim with
  `iconFiles: Contents/Resources/DocumentIcon.icns` (absent before).
- **Windows**: embedded the `.ico` as resource id `102` (`IDI_DOC_ICON`) in
  `windows/runner/Runner.rc` / `resource.h` (app icon stays id 101 / index 0),
  and changed the installer's `DartPDF.pdf\DefaultIcon` in
  `.github/workflows/release-app.yml` from `…exe,0` to `…exe,-102` (negative =
  reference by resource id, order-independent). Not built here (no Windows).

## Caveat (documented in RELEASING.md)

The icon only appears once DartPDF is the user's default PDF app — neither OS
lets an app silently claim the default. We only *offer* DartPDF as a handler
(macOS `LSHandlerRank = Alternate`; Windows `.pdf` `OpenWithProgids`). Existing
installs may also need an icon-cache refresh (`sudo rm -rf
/Library/Caches/com.apple.iconservices.store; killall Finder`, or reinstall).
