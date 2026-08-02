# Deep zoom on a scan: tiles must re-decode the image, not magnify it

A user reported that a scanned drawing rendered "fuzzier than other PDF
editors". The file: one page, 1532.88 x 3764.52 pt (21 x 52 in), whose entire
content is a single 4258 x 10457 `DCTDecode` image - a 200 dpi scan. Vector
documents looked fine; only scans were soft.

## What was actually happening

Three facts compose into the bug.

1. **The full-page raster cap sets a ceiling on image sharpness.**
   `_effectiveRatioAt` clamps the raster to `_maxPixels` (1 << 24) and
   `_maxDimension` (8192). For this page that is
   `sqrt(16777216 / 5770551)` = **1.705 px/pt = 123 dpi**, reached at 100% zoom
   on any retina display and never exceeded however far you zoom.
   `_fullImageRatio()` is `min(_effectiveRatio(), cap)`, so the same number also
   bounds how sharply the page's images are ever *decoded*.

2. **On the web backend the page image budget cuts below even that.**
   `_imageBudgetPixels` takes `min(_maxImagePixels, headroom^2 x
   pageRasterPixels)`. The `headroom^2` term exists so one full-bleed image can
   carry 4x the raster's pixels - but `_maxImagePixels` is *also* `1 << 24`, so
   on a page whose raster already sits at the cap the budget collapses to
   exactly 1x the raster's pixel count. Measured, by running the real
   `serializeCommands` at the highest ratio the pipeline can ever reach:

   ```
   ratio=1.705  rasterPixels=16775155
   WORKER SHIPS -> 2614x6419        (native 4258x10457)
   ```

   The VM/isolate backend escapes this: a non-CMYK `DCTDecode` base cannot be
   decoded purely, so the worker ships the JPEG un-decoded and the platform
   codec runs on the UI isolate, uncapped, landing on native. The web worker
   decodes in-worker (`_withBrowserDecodedImages` + `createImageBitmap`) and
   therefore *does* go through the budget. Same document, two sharpnesses.

3. **Deep zoom never repaired it.** `_updateDetail` short-circuits when
   `_refreshTileGeometry()` claims the view, and the tile layer's `rasterize`
   replayed the **base** retained scene. Vectors and text re-rasterize at the
   tile ratio for free; an image draw can only ever be as sharp as the
   `ui.Image` the scene holds. So on a page that IS one big image, the tile
   pyramid contributed nothing the base raster didn't already have. The legacy
   single detail patch never had this problem - `_detailPictureFromWorker`
   re-records through the worker with an `imageDecodeRegion`, which decodes only
   the visible slice's source pixels at the requested ratio.

Edge energy on one crop, all rendered at the same output size:

| | mean squared gradient |
|---|---|
| PDFium (reference) | 404.7 |
| ours, image decoded at native 4258 px | 367.2 |
| ours as shipped, image capped to 2614 px | 119.7 |

## The fix

`_PdfPageViewState` keeps a second, region-scoped retained scene for the tile
path (`_tileDetailScene` / `_tileDetailRegion` / `_tileDetailRatio`): a
`worker.record(imagePixelRatio: <zoom ratio>, imageDecodeRegion: <visible
slice>)` whose images were decoded for the slice on screen. `rasterize` prefers
it wherever `_tileDetailCovers` says its pixels reach; everything outside
replays from the base scene exactly as before. The decode region carries 50%
of viewport slack per side, so ordinary pans keep hitting it.

Two guards keep it from firing pointlessly:

- `PdfRetainedScene.imagesAtNativeResolution` (memoized - deep zoom asks every
  settle) short-circuits when the base decode already landed on the stream's
  native pixels. That is the ordinary VM case, so desktop pays nothing.
- No worker, no request: region-scoped decoding lives in the command codec and
  only the worker record path reaches it. A local decode has no region and
  would expand the whole image at zoom resolution.

### The veto, and why it exists

The first implementation invalidated the page's tiles when the sharp scene
landed, because a tile's key carries the page's visual identity and zoom
bucket - not the resolution its images were decoded at - so a tile already
rastered from the base scene would be reused unchanged. `tool/perf.sh webdiff`
priced that honestly: **+16.7% buildMax, +14.6% buildP95** on `zoom-scan`. Every
zoom settle rastered its tiles twice.

So instead of rastering blurry and re-rastering sharp, `_tileDetailWanted`
holds the tile back: while a detail request is outstanding, tiles its scene
does not yet cover are **vetoed** through the existing `canRasterize` seam, and
the base raster shows through for one worker round trip - exactly what the view
showed before the pyramid engaged. Each tile is then rastered once, from pixels
that are already sharp, and no invalidation is needed at all. The flag is
cleared whether the request lands *or fails*, so a worker that declines falls
back to base-scene tiles rather than never tiling.

Final A/B, `tool/perf.sh webdiff HEAD zoom-scan --iterations 7`:

```
metric                  baseline    current     Δ         verdict
buildMax                65.84       55.84       -15.2%    ✓ faster
buildP95                8.57        8.49        -0.9%     ·
buildP50                2.91        3.12        +7.0%     ·
agentMemoryBytes        474080452   473956168   -0.0%     ·
✓ no metric regressed past 1.1×
```

`buildP50` +7% (2.91 -> 3.12 ms) is the honest cost of building the region
scene on the UI isolate each new slice; `buildMax`/`buildP95` are flat to
favourable and the frame budget is untouched. On web the crop is taken from the
worker's already-cached native decode (`_withBrowserDecodedImages` retains it
keyed `(stream, null, null)`), so the request is a crop + downsample and a small
`postMessage`, not a second JPEG decode.

## Tooling

`zoom-scan` was added to `app/tool/perf/scenarios.json` - the `scroll` kind
already supports `?zoom=N` settle cycles, so it needed no harness change. It
runs 2 zoom-in/out cycles per page over 4 pages of `scan-book-12p.pdf`: every
page is one big raster, so its zoom sharpness comes entirely from the
region-scoped re-decode. That is the scenario this change must be A/B'd
against.

Note the container needs `PERF_CHROME` pointed at a Chromium binary
(`/opt/pw-browsers/chromium-1194/chrome-linux/chrome` here); the default path is
macOS-only.

## Left alone, deliberately

- **The budget itself.** It lands on exactly 1:1 with the raster in both the
  page and the region case (`budget == regionPixels == footprint pixels`), which
  is the correct answer for a settled view - PDFium downsamples to screen
  resolution too. Raising it to the intended `headroom^2` would quadruple every
  record's image payload to fix a problem that only showed up at zoom.
- **`FilterQuality.medium` in `CanvasPdfDevice.drawImage`.** The residual ~9%
  gap to PDFium on the crop above is magnification filtering from the same
  source pixels, not lost data.
- **`cappedImagePixelSize`'s early return.** It returns native *before*
  applying its own 8192/16 MP ceilings, so a 44.5 MP scan really does reach the
  engine as one 4258 x 10457 texture on the VM path. That predates this work and
  is load-bearing (`_decodeTarget` returns null for a no-op cap so those images
  keep a byte-identical native decode); worth revisiting separately.
