# Linux: aliased page rendering under Impeller on OpenGL (#912)

## Symptom

On Flutter Linux, the title page of *Operating Systems: Three Easy Pieces*
(the 675-page Acrobat-merged PDF people pass around) looked thin and jagged in
DartPDF: "THREE EASY PIECES" rendered as "I'HREE EASY PIECES", with serifs
and strokes missing. Okular showed the same page crisp.

## What the PDF actually does

Page 1 has an empty content stream. The title text is two `/FreeText`
`/FreeTextTypewriter` annotations whose appearance streams draw with an
embedded TrueType `BaskervilleOldFace` (`Tj`, fill mode, no stroke). The PDF
contains nothing unusual.

## Ruling out the renderer

- `render_smoke_test.dart` on that page (direct, worker, and
  `--enable-impeller` on macOS/Metal) matches `pdftoppm` at the same scale.
- Metal Impeller output has five coverage levels (0/64/128/192/255, which is
  4x MSAA). The reporter's screenshot has **exactly two** (0 and 255) across
  the whole title, while the app's own UI text in the same screenshot has more
  than 80. The page's vector content was rasterized single-sample.

## Root cause (Flutter 3.47 engine source)

- `shell/platform/linux/fl_dart_project.cc`: `enable_impeller = TRUE` by
  default. `fl_engine.cc` always uses the OpenGL renderer.
- `impeller/renderer/backend/gles/capabilities_gles.cc`: offscreen MSAA is
  reported only for `GL_EXT_multisampled_render_to_texture2` or an **ES 3+**
  context. A desktop GL driver without those gets `SupportsOffscreenMSAA() ==
  false`, so `Picture.toImage` snapshots and entity passes are single-sample.
- Impeller has no analytic AA for arbitrary path fills (the SDF work covers
  rects, rrects, circles and lines). Our glyphs are outline paths
  (`canvas_device.dart` `_appendGlyphOutlines`), so they come out as 1-bit
  masks. The glyph atlas used for Flutter's own text is unaffected, which is
  why the UI chrome looked fine.
- The optional flutter_gpu tile backend isn't involved: it rejects GLES
  contexts (`SupportsFramebufferRenderMipmap` is false there), and even where
  it runs it gets MSAA from the same capability.

## Fix

`app/linux/runner/my_application.cc` (and the example runner) call
`fl_dart_project_set_enable_impeller(project, FALSE)` before any engine or
view is created. Skia antialiases paths without MSAA. `DARTPDF_IMPELLER=1`
turns Impeller back on for A/B comparison (`FLUTTER_ENGINE_SWITCHES` is
ignored in release builds, so the app needs its own switch).
`app/test/linux_runner_renderer_test.dart` pins the call in both runners.

Trade-offs on Linux: the Impeller-only paths (strip shaders gated on
`ui.ImageFilter.isShaderFilterSupported`, flutter_gpu tiles) turn off, so
Linux uses the Canvas + flat-replay path, as it did before Impeller became
the Linux default. flutter_gpu was already rejected on GL.

Third-party Linux hosts embedding `dart_pdf_editor` hit the same aliasing
under the default engine configuration, and need the same runner call.

Not verified on a real Linux desktop from this session (macOS only). The
evidence is the two-level coverage in the report plus the engine source
above.
