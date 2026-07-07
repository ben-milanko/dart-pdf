# Offer the host platform's installed fonts in the editor font menu

## Platform fonts in the editor font menu (load by default)

Goal: offer the host OS's installed fonts as embeddable choices in the
editor's font menu, by default - on top of the base-14 families, the bundled
DejaVu/Fira/Spectral/Lobster set, and the host's `PdfFontPicker` ("Load
font…").

Layering constraint drives the design: `dart_pdf_editor/lib` can't read font
files (`dart:io` is banned in every package `lib/` for web support), so
discovery is a **host seam** like the persistent cache. The library exposes a
`PdfPlatformFont` (`label`, optional engine `family` to preview with, and a
lazy `Future<Uint8List?> Function() loadBytes`) plus a module-global
`pdfPlatformFonts` registry (mirrors the existing `const pdfBundledFonts`
default - module-level mutable state is already used here for the embedded
font-preview maps). A host fills the registry once at startup; every
`showPdfFontMenu`/`PdfFontMenuButton` reads it by default (new optional
`platformFonts` arg overrides; defaults to the registry via `?? pdfPlatformFonts`
because a mutable global can't be a `const` default value). No new param is
threaded through the viewer/toolbar/properties tree. Picking a platform font
calls `loadBytes`, `PdfEmbeddedFont.parse`es it, and routes through the
existing `pdfApplyFont` so the outline bytes embed into the document - same
path as a bundled font; an unreadable/`.ttc`/WOFF font is caught and leaves
the active font unchanged (the new `_PlatformChoice` case + a `pdf-font-
platform-$i` menu section between bundled and "Load font…").

Discovery lives in the hosts (`app/lib` and the package example), both via a
conditional-import shim (`platform_fonts.dart` → `_io`/`_stub`, same pattern
as `persistent_cache.dart`): native scans the standard per-platform font dirs
(`/usr/share/fonts` & `~/.fonts` on Linux, `/System/Library/Fonts` &
`~/Library/Fonts` on macOS, `%WINDIR%\Fonts` on Windows, `/system/fonts` on
Android), web returns `const []`. Only filenames are read at scan time - the
program bytes load lazily on pick - so listing hundreds of installed fonts
never reads their (sometimes large) bytes upfront. One entry per family (the
regular face preferred, `.ttf`/`.otf` only - `.ttc` can't embed directly),
sorted, capped at 300. Family names are derived from filenames (split a
trailing `-Style`, space out CamelCase/underscores); good enough as labels,
and used as the preview `family` too (a name the engine doesn't recognize
just falls back to the default face, so a wrong guess is harmless). The app
(`app.dart`) and example (`main.dart`) `initState` fire-and-forget
`pdfPlatformFonts = await loadPlatformFonts()`; the registry is read when a
menu opens, so an empty/slow result just leaves the other choices. Note the
app previously passed no `fontPicker`, so this also gives it more than the
base-14 + bundled set out of the box. Tests in `editing_fonts_test.dart`:
registry fonts appear in the menu and embed on pick (Type0 /F0 appearance),
and an unreadable one (`loadBytes` → null) leaves the font unchanged; a
top-level `tearDown` resets the global registry so it can't leak between
tests.
