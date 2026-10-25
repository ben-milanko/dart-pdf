# Indexed image decode: palette LUT + direct box filter

Triggered by a slow 33-page "Combined" CAD set (Acrobat-merged, 22 MB, all
pages /Rotate 90). Profiling it with the Flutter phase split (record /
decode / replay / raster at 1x) put **image decode at 9.7 s of ~20 s**:
pages 1/4/7 draw 728 tile images each (503 distinct streams per page, every
copy of the sheet carrying its own objects, so the image cache can't share
them across pages), all `[/Indexed /DeviceCMYK n <lookup>]` Flate, 8-bit,
~258x174, displayed ~8x smaller.

Two costs, both in `pdf_graphics/lib/src/image_pixels.dart`:

- `_indexedToRgba` resolved the palette once but then paid a division, a
  modulo, a colour-key test and four byte stores **per pixel** (~24 ns/px
  AOT). It now builds one 2^bits-entry RGBA word table (out-of-range clamp
  to entry 0 and the raw-sample colour key folded in) and expands each
  sample with a single `Uint32List` store - the same idiom the 1-bit
  DeviceGray path already used. ~3x on the full decode.
- A display-sized decode of an Indexed image expanded the native RGBA
  surface and then box-filtered it (`downsamplePdfDecodedPixels`).
  `decodePdfImageBase` now sends an opaque, unmasked, unkeyed Indexed image
  with a target through `_indexedToRgbaDownsampled`, which sums palette
  channel tables straight into the target cells. Same cell geometry, same
  no-upscale clamp, same truncating mean, so it is **byte-identical** to
  full-decode + downsample (checked over all 2,828 image/target pairs in the
  file, and pinned by the `Indexed palette expansion` test group for 2/4/8
  bits over RGB and CMYK bases). Masked/keyed images keep the native base
  their compositing paths expect; unmasked 1-bit Indexed still takes the
  older point-sampled `_scaledIndexed1Region` from
  `decodePdfImagePixelsScaled` (pre-existing, not changed here).

Measured (AOT, serial, page 1's 503 tiles at 1/8 size): 854 ms -> 173 ms;
page 19's 117 tiles 278 -> 49 ms. Full-resolution decode 802 -> 263 ms.
Flutter phase test, whole file: decode 9.7 s -> 4.9 s (JIT; the remainder
there is mostly per-image `ui.Image` upload in the headless engine).

Gotcha while measuring: in **JIT** a store through `Uint32List.view` is ~3x
slower than into an owned `Uint32List`, which made the LUT look like a weak
win. AOT (what ships) compiles the view store to within ~25% of the owned
one, so the view idiom is fine - measure codec loops with
`dart compile exe`, not `dart run`.

Not done, for the record: the vector pages (3/6/9 carry 16.5 MB of content,
362k separate `m l S` strokes) spend their time in `CosLexer` number
scanning (already single-pass) and per-stroke `drawLine`; batching strokes
into one path would change AA where lines meet and move render baselines.
Text extraction re-walks the full content stream (~0.4 s on those pages)
even though they carry almost no text.
