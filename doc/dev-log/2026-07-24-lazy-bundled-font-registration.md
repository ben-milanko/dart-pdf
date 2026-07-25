# 2026-07-24 — Lazy bundled-font registration (cold-start trim)

## Why

Prompted by a Reddit note on Flutter cold-start wins. Of its three tips, two
don't apply here — the app has no BaaS clients to defer, and everything
non-critical at startup is already `unawaited`/deferred (app metadata, update
check, platform-font discovery, session restore, and the render-worker
prewarm that deliberately overlaps the user picking a file; the whole editor
is a deferred loading unit). The third — "asset preloading is a trap: the
font cache locks while it parses declared fonts" — did land.

`dart_pdf_editor_assets` declared all six editor fonts (~2.55 MB of TTF) in
its pubspec `fonts:` block. Anything in that block goes into
`FontManifest.json`, and under **CanvasKit web** (a first-class target here)
the engine fetches and parses every manifest font at startup, before the
first frame. The only Flutter-side consumer of those families is the
font-menu preview (`editing_fonts.dart`, `_FontEntry.fontFamily`), which most
sessions never open. Font *embedding* on pick and composite-text fallback
(`loadFallbackFonts`) read raw bytes via `loadBundledFont`, not the engine
family, so they never needed the declaration.

## The catch that shaped the change

One face can't be deferred: `CanvasPdfDevice._defaultFontFallbacks`
(`canvas_device.dart:1071`) names `packages/dart_pdf_editor_assets/DejaVu Sans`
as a `fontFamilyFallback` for Arabic/Hebrew/Greek/Cyrillic in arbitrary PDFs,
and that family is registered *by the pubspec declaration*. Deleting the whole
block would have produced tofu on real non-Latin PDFs — and the tests would
have stayed green, because `flutter_test_config.dart` registers DejaVu
manually. A trap. Only `DejaVu Sans` appears in any render fallback list;
the other five are preview-only.

## What changed

- `packages/dart_pdf_editor_assets/pubspec.yaml`: keep **only `DejaVu Sans`**
  in `fonts:`; drop DejaVu Serif, DejaVu Sans Mono, Fira Sans, Spectral,
  Lobster (~1.85 MB, ~72% of the payload). All six stay under `assets:`.
- `editing_fonts.dart`: new `_ensureBundledFontPreview` mirrors the existing
  `_ensureDocumentFontPreview` — lazily `FontLoader`-registers a bundled
  face under its label on first font-menu open, cached per session.
  `showPdfFontMenu` registers bundled previews in the same `Future.wait` as
  the document fonts; the bundled `_FontEntry` now previews with that
  lazily-registered family. Removed the now-dead `_FontEntry.package` field
  (the pubspec `package:` qualification was its only source).
- New test: `a bundled font row previews in its own lazily-registered face`.

## Follow-up: don't block the dialog on registration

First cut registered the bundled previews inside the `await Future.wait([...])`
that runs *before* `showDialog` — so the first click on the font button
stalled while ~1.85 MB parsed, then the menu popped open with everything at
once. Moved registration into `_PdfFontPickerDialogState.initState`, fired but
never awaited: the dialog opens immediately, already-registered faces preview
synchronously (instant re-open), and first-time faces `setState` their row
into their own face as each `FontLoader.load()` completes. `_FontEntry` gained
a `bundledFont` reference so the dialog knows which rows to register and can
map results back (recents included). Regression guard: `the menu opens without
waiting on bundled font registration` asserts the dialog is present after a
single frame.

## Net

~1.85 MB of font fetch/parse moves off cold start to first font-menu open
(one-time, off the hot path). DejaVu Sans render fallback unchanged. No engine
fork. Measure the web cold-start delta with `tool/perf.sh webdiff`.
