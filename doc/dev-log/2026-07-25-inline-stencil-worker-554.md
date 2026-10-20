# Inline ImageMask glyphs serialize — Type3 pages reach the worker (#554)

`serializeCommands` (the wire codec the render worker ships transcripts through)
declined **any** transcript containing an inline image (`BI .. ID .. EI`), because
an inline image's `/CS` may name a page-resource colour space unreachable from the
stream alone. Correct for colour inline images — but a TeX-era Type3 bitmap
document is almost entirely **inline ImageMask** glyphs, so those pages declined
the worker wholesale and interpreted + serialized + painted on the UI thread.

## Why a stencil is safe

An `/ImageMask true` inline image has **no colour space** — its paint is the
stencil colour carried on the `PdfImageRequest` (`stencilColor`, from the graphics
state's fill colour at draw time). The interpreter builds its request stream from
the inline dict + inline bytes literally (`_drawInlineImage`), and a stencil dict
carries only direct values (`/W /H /IM /BPC /F /D`) — no indirect refs, no `/CS`.
So the stream is fully self-contained. And XObject ImageMasks already serialize
through the exact same else-branch (`_inlineCos` + optional decode + `_writeImageCommand`,
which already writes `isStencil`/`stencilColor`); the only thing blocking the
inline ones was the `request.isInline` decline.

## The change

One condition, in `render_command_codec.dart`:

```dart
final declineInline = request.isInline && !request.isStencil;
if (declineInline || cos == null) { … decline … }
```

Colour inline images still decline (kept the `_inlineImagePdf` `/CS /RGB` test
green); stencil inline images now take the proven stencil path. Verified on the
fixture: `type3-text-6p.pdf` went from **0 → 6 of 6 pages serialized** (17,424
inline stencil glyphs across the doc that previously forced every page on-thread).

Tests (`render_command_codec_test.dart`): an inline ImageMask serializes (not
null), round-trips with `isStencil`/`isInline`/`stencilColor` intact, and also
decodes off-thread (`decodeImages: true` embeds the mask). The existing
colour-inline-declines test is unchanged.

## Bundle note

Unlike #530 (which touched only `render_worker_isolate.dart`, tree-shaken out of
the web build), this changes shared `pdf_graphics` code reachable from the web
worker entry, so the checked-in `pdf_render_worker.dart.js` bundle is stale and
**rebuilt here** (`dart run dart_pdf_editor:build_web_worker`). With the #422/#571
`WORKER_REGEN_TOKEN` still unset, CI's `worker-bundle` job verifies-and-fails, so
the bundle had to ship in the PR rather than being auto-regenerated. If CI's
rebuild disagrees byte-for-byte (the cross-runner nondeterminism #422 flagged),
that job will fail and needs the token — or a fresh local rebuild taken from CI.

Files: `packages/pdf_graphics/lib/src/render_command_codec.dart`,
`packages/pdf_graphics/test/render_command_codec_test.dart`,
`packages/dart_pdf_editor_assets/assets/web/pdf_render_worker.dart.js` (regenerated).
