# 2026-07-16 — The DeviceN tint transform ran per pixel, not per distinct sample

Branch `perf/devicen-tint-memo`. A reader on r/FlutterDev reported the web
demo going unresponsive and then crashing on a ~60-page PDF, and guessed it
was "image heavy". The file (a 24 MB, 62-page InDesign print export) does
carry 247 image XObjects / 282 MB of decoded RGBA, but that guess was wrong
and cost some time — worth recording how the measurements actually fell.

## Repro, and what it wasn't

Rendering every page through `PdfPageRenderer.renderImage` at ratio 2:

```
62 pages in 106392 ms, mean 1716 ms, worst page 2 at 32633 ms
```

but the shape was bimodal, not heavy-everywhere: pages 2/21/22/30 took
16–32 **seconds** each and every other page took ~180 ms. So it was never
about the document's total image weight.

Two false leads, both cheap to kill with the existing tools:

- Interpret is innocent. `tool/interp_timing.dart`-style walk to a
  `NullDevice` is 6.0 ms/page mean, 369 ms for the whole document. Page 2
  interprets in 38 ms and rasterizes in 32633 ms.
- Not image count or size. Page 30 has **one** 127×127 icon and took
  16 s. Page 2's own `/Resources /XObject` is empty — its images are nested
  inside Form XObjects, which is why a naive resource-dict probe reported
  "no images" on the slowest page in the file. Walk with
  `scanImagesOnly: true` instead; it sees through forms, Type3 glyphs, and
  tiling patterns.

Phase-timing `renderPictureWithPlan` on page 2 put it beyond argument:

```
parse ops      : 5 ms (334 ops)
collect walk   : 34 ms (8 images)
decode images  : 32927 ms      <-- here
interpret null : 44 ms
```

## The bug

`_alternateToRgba` (image_pixels.dart) is the Separation/DeviceN path. It
called `alternate.colorFor(values)` **once per pixel**, allocating a samples
list and a values list each time. The colour space here is:

```
/DeviceN [/Black] /DeviceCMYK <FunctionType 4 ...>
```

One colorant, 8 bits — **256 possible inputs** — and a type 4 PostScript
calculator tint transform, whose `evaluateAt` re-interprets the token
program on a fresh `List<Object>` stack per call. At 1691×1293 that is
2.19M interpreted program runs (~10 µs each) to produce 256 distinct
answers: 23.7 s for one image.

Fix: resolve each distinct sample *tuple* once, keyed by the packed 8-bit
samples, and index the answer per pixel — the same shape as
`_indexedToRgba` resolving its palette up front. Bounds that matter:

- key packing needs `components <= 8` to fit an int (`_tintMemoMaxComponents`);
- `_tintMemoMaxEntries` (1<<16) caps the table so a wide DeviceN whose tuples
  never repeat can't grow it with the pixel count — past the cap it just
  evaluates directly, which is the old behaviour;
- alpha stays per-pixel. The colour is shared, the colour-key `/Mask` test is
  **not** — it reads the raw sample, so two pixels sharing a colour can still
  differ in alpha;
- the memo keys on **raw** samples, before the `/Decode` LUT. Safe because the
  LUT is fixed per image, so raw sample → same value every time.

## The second bug, found by the first

`decodePdfImagePixels` did:

```dart
final base = decodePdfImageBase(cos, stream);   // full DeviceN conversion
...
if (_softMaskIsDct(cos, dict)) return null;     // ...thrown away
```

and `_decodeOne` (dart_pdf_editor/image_decoder.dart) then called
`decodePdfImageBase` **again** for its platform-JPEG-mask path. Any
non-JPEG base under a DCTDecode `/SMask` — exactly this file's images —
decoded twice. `_softMaskIsDct` is pure dict lookups, so it now runs before
the base decode. Same output, half the work (131 → 98 ms/image here). Mind
the ordering: a stencil `/ImageMask` ignores the soft mask, so it must not
take the early bail.

## Why the corpora never caught it

Worth knowing, because it's a real coverage gap rather than bad luck:

- the unit fixtures are 1–2 px — correct, and the cost is invisible;
- Ghent *has* DeviceN cases, but `ghent_render_test.dart` skips them as
  "known baseline deviation — colour handling is not pixel-exact" and only
  asserts non-blank, and its DeviceN content is vector, where the transform
  runs per fill, not per pixel;
- across all 275 files in ghent + pdfjs + the local corpus, only **7**
  images reach this path and the largest is 0.26 MP.

The trigger needs a large *raster* image in a Separation/DeviceN space with
a calculator transform: a print-production signature (NChannel spot inks).
CAD sheets are vector CMYK; the pdf.js/PDFium benchmark corpora are screen
PDFs. The combination simply wasn't represented.

## Verification

The Ghent baselines can't police this path (see above), so equivalence was
proved directly with `tool/hash_image_decodes.dart`: hash the decoded RGBA
of every Separation/DeviceN image instance across the reader's file plus
all 275 files in ghent + pdfjs + the local corpus, at HEAD and with the
fix, and require the line sets to be identical. 217 instance lines (the
reader's file contributes 206; 12 corpus files are legitimately unreadable
— encrypted or fuzzed pdf.js fixtures). The unfixed side is slow enough
that it needs page-range sharding across cores to finish — which is itself
the point.

Three traps the sweep itself stepped in, all now guarded in the tool,
recorded because each one *silently shrank coverage while still reporting
success*:

- hash **both** entry points. `decodePdfImagePixels` returns null for
  exactly these images (DCT `/SMask`), so hashing only it covered 7 images
  instead of 206 and would have "passed" while checking nothing;
- pass the file list NUL-delimited (`tr '\n' '\0' | xargs -0`). An unquoted
  `$(cat files.txt)` word-split every filename containing a space into
  fragments that each failed to open — as OPEN-FAILED lines, not errors;
- one fuzzed pdf.js file threw from `pageCount` and killed the whole sweep
  mid-output. The tool now guards it per file (and grew
  `PDF_HASH_PAGE_MIN`/`MAX` env knobs so a killed multi-hour sweep can
  resume by page range).

## Numbers (the reader's file, ratio 2)

| | before | after |
|---|---|---|
| worst page | 32633 ms | 695 ms |
| whole document | 106392 ms | 14100 ms |
| the 1691×1293 DeviceN image | 23656 ms | 98 ms |

## Left open

Everything above was measured on the VM and through Flutter's rasterizer.
The fix lands in the pure-Dart decode that *every* path shares — UI thread,
native isolate worker, and the web worker — so the win is not
platform-specific, but the reported symptom was never reproduced in a
browser (none was in the loop here).

Worth not guessing about: on web these images do **not** block the main
thread. `_decodeBrowserImage` (render_worker_web_entry.dart:688) explicitly
handles "pure base + DCT /SMask" by calling `decodePdfImageBase` on the
worker and lifting only the mask through the browser codec — which is
exactly this file's shape. So the 23 s/image was burning on the Web Worker,
and what the reader saw (unresponsive, then a crash) is unexplained in its
specifics. Load the file into the demo and watch it before claiming the
crash is fixed.

Related but separate: `PdfImageCache.instance` is a flat 256 MB on every
platform including web, and this file pegs it at 268 MB for two thirds of
the document — issue #281.
