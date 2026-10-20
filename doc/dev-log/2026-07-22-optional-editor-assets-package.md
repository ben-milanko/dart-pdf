# 2026-07-22 - Split optional editor assets into `dart_pdf_editor_assets`

Issue #459: viewer-only apps paid ~1.74 MB (compressed) on every Flutter target
for assets they never used - the six editor fonts (~1.26 MB) and the web render
worker (~0.48 MB, useless off the web).

## Why a separate package (not a runtime flag)

Flutter bundles a package's `flutter: assets:` declarations on *every* build
target; there is no per-consumer or per-platform way to un-bundle a dependency's
declared assets (asset tree-shaking only covers icon fonts). So the only lever
that actually removes the bytes from an APK is to keep the declarations out of
the package every consumer depends on. Hence a new workspace package,
`packages/dart_pdf_editor_assets`, which *declares* the fonts + worker and
depends on `dart_pdf_editor` (one-way; the editor must not depend back, or the
whole point is lost).

## Shape

- `dart_pdf_editor_assets` exports `registerBundledEditorAssets({fonts, webWorker})`.
  It assigns `pdfBundledFonts = bundledEditorFonts` and
  `pdfRenderWorkerScriptUrl = defaultPdfRenderWorkerScriptUrl`. One call at
  startup restores the historical defaults.
- `dart_pdf_editor` degrades gracefully with nothing registered:
  - `pdfBundledFonts` is now a **mutable, empty-by-default** `List` (was a
    `const` of six faces). Default-parameter uses (`showPdfFontMenu`,
    `PdfFontMenuButton`) became nullable-and-resolve-to-registry because a
    non-const global can't be a default value.
  - `PdfBundledFont` gained `package` (for the menu preview's `Text(package:)`,
    now the asset's owning package rather than a hardcoded `'dart_pdf_editor'`)
    and an optional `loadBytes` byte loader - the issue's "let apps provide font
    bytes" path, and what the tests use.
  - `loadFallbackFonts()` already reads from `pdfBundledFonts` by label, so it
    returns `[]` when nothing is registered (composite-text fallback simply
    off). No call-site changes needed - `replaceText(fallbackFonts: [])` is a
    no-op.
  - `pdfRenderWorkerScriptUrl` now defaults to **null** (main-thread web
    rendering) instead of the old package-asset path. `defaultPdf...Url` still
    exists but points at the new `dart_pdf_editor_assets` asset path.

## Wiring the repo's own apps

`app/` and `example/` depend on the assets package and call
`registerBundledEditorAssets()` (app in `app.dart` initState - note `main.dart`
is deliberately kept free of the editor stack for the deferred web split;
example + the screenshot/benchmark mains call it directly). Moved the checked-in
worker asset and every path that names it: the four CI workflows + `ASSET` env,
`tool/ci/regen_web_worker.sh` comment, `tool/web_cache_bust.sh`,
`app/tool/build_web.sh`, and `.gitattributes` (`-merge -diff` on the generated
`.js`).

## Test note

`editing_fonts_test.dart` can't reach the moved assets through this package's
test asset bundle, so `setUp` registers the six faces backed by the moved files
via `loadBytes: () async => File(...).readAsBytesSync()` - a sync read wrapped in
a future, so it completes on the microtask queue `pumpAndSettle` drains rather
than on a real I/O turn the fake clock wouldn't await.
