# Image /SMask composite turned black on Impeller (#675)

Reported against 3.5.0 on Android: one page of a 62-page print PDF (a
card-sheet page dense with JPEGs) rendered as black rectangles where the
artwork should be. The same build on Android **web** was correct.

## What was actually broken

Not the decoder, not Android. `CanvasPdfDevice.drawImage` composited a
deferred image /SMask with a single paint carrying **both**
`BlendMode.dstIn` **and** a red→alpha `ColorFilter.matrix`:

```dart
canvas.drawImageRect(softMask, src, unit, Paint()
  ..blendMode = BlendMode.dstIn
  ..colorFilter = const ColorFilter.matrix(_redToAlpha));
```

Skia honours both. **Impeller drops the blend mode when the same draw paint
carries a colour filter** - the mask then composites `srcOver`, painting its
filtered samples (opaque black wherever the mask is white, transparent
wherever it is black) *over* the base instead of cutting the base's alpha.
The result is an inverted, blackened image: exactly the reported page.

Both the blend and the filter now live on a `saveLayer` paint, which both
engines honour. That is the same shape `beginSoftMaskComposite` already used
for group soft masks - which is why /SMask **groups** were never affected.

## Why only some images, and why only native

The companion-mask path (`_gpuSoftMasks`, added with the deferred-DCT
soft-mask work in #659) is only reached when the base image comes back from
the **platform JPEG codec**: `deferSimpleDctSoftMask` keeps the grayscale
mask as its own GPU surface rather than multiplying it into the base's
pixels. So the failing set is precisely:

- **non-CMYK DCTDecode images** - `decodePdfImageBase` returns null for them
  (`image_pixels.dart`), so `_decodeOne` runs `ui.instantiateImageCodec` and
  attaches a companion mask;
- everything else - CMYK JPEGs, Flate, Indexed, CCITT, JPX - decodes in pure
  Dart with the mask already multiplied in, so it has no companion and never
  took the broken paint.

On **web** neither half applies: the worker decodes colour JPEGs with the
libjpeg-turbo WASM accelerator / the browser codec (`jpeg_accelerator_web`,
`browser_jpeg_decode_web`), so the pixels arrive pre-masked. That is the whole
of "broken on Android, fine on Android web".

On the reported page this split is stark and made the diagnosis easy: the
CMYK logos rendered perfectly while every DeviceRGB JPEG went black.

## Reproducing without a device

`flutter test --enable-impeller` reproduces it exactly on Linux - the render
of the reported page under Impeller is pixel-for-pixel the user's screenshot.
That also names the gap that let it ship: **every render test in CI runs on
Skia**, while the Android app enables Impeller in its manifest.

`test/image_soft_mask_composite_test.dart` pins the invariant with a JPEG
base under a half-transparent Flate /SMask: the masked-out half must keep the
page background. It passes on Skia with *either* paint shape, so ci.yml now
runs that one file a second time with `--enable-impeller`. Broadening that
job to more of the render suite is the obvious follow-up - the engines differ
by ~2/255 mean on antialiased content, so the pixel-baseline suites (Ghent,
PDF.js) need their own tolerance before they can join it.

## The flutter_gpu tile backend had its own half of this

Fixing the canvas device exposed a second divergence on exactly the same
images. `FlutterGpuTileRasterBackend` uploads **one texture per image** and
never consults `pdfGpuSoftMaskOf`, so a companion mask was silently dropped
and the base painted opaque - and a cut-out sticker's JPEG is solid black
outside the subject, so the tile still rendered a black rectangle. That
backend is the **default wherever the platform supports it**, and Android's
manifest enables flutter_gpu, so at the deep zoom in the report it owned the
visible tiles.

`_unsupportedReason` now declines a scene carrying such an image
(`'deferred image soft mask'`), which routes the page to the now-correct
Canvas path - the same conservative fallback the backend already uses for
gradients, tiled patterns and non-normal blends. Corpus acceptance is
unchanged (PDF.js 90/89, Ghent 16/41), so no page in either suite has this
shape - which is also why the GPU/Canvas parity suite never caught it.

Uploading the mask as its own texture and sampling it in `pdf_tile_texture.frag`
would recover the GPU path for these pages; the readback branch of
`_uploadImageTexture` already pays a `toByteData`, so the alternative of
multiplying the mask into the base's alpha at upload is also open. Neither is
needed for correctness.

## Sibling worth knowing about

The stencil (`/ImageMask`) branch of the same method still sets
`ColorFilter.mode(..., srcIn)` alongside `_elementBlend`. When that blend is
not `srcOver` - an explicit /BM, or `BlendMode.src` inside a knockout group -
Impeller will drop it the same way. It is deliberately left alone here: the
layer rewrite that fixes the /SMask case would change knockout semantics
(§11.4.5 elements must replace only their own coverage, with no full-bounds
layer), and no corpus page currently exercises the combination.
