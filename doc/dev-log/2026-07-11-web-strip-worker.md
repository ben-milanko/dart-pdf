# 2026-07-11 — Web Worker strip binning (#217)

The web backend now implements the native strip-plan protocol instead of
inheriting `PdfRenderWorker.binStrips`'s null fallback.

## Protocol and cache

`render_worker_web.dart` queues RECORD and BIN requests together, preserving
the existing priority/sequence ordering. BIN messages carry the six
page-to-device coefficients, device dimensions, and pixel ratio as primitive
properties. The result is `encodeStripPlan` bytes in the existing transferable
`ArrayBuffer` response shape; the main side reconstructs it with
`decodeStripPlan`.

The worker entry keeps a two-page LRU of command recordings. Recordings are
round-tripped through the command codec before caching, matching the main
scene's float32 path/glyph geometry and preserving object identity for the
glyph and shape strip caches across repeated settles. `cancelBinStrips` drops
queued BINs and signals a matching in-flight bin's cooperative cancellation
token. Pool routing remains static by page index, so successive geometries hit
the same worker and its cache.

## Browser proof

The bundled worker was regenerated and loaded from the built example's real
package-asset URL. A temporary compile-time probe (removed after validation)
used the same worker-recorded commands on both sides:

```text
web-bin-probe plan=11 same=true image=612x792
```

`same=true` is a byte-for-byte comparison of the worker's encoded plan with a
main-side `StripPlanBinner` pass. The image dimensions come from rendering the
worker plan through `PdfRetainedScene.rasterizeStrips`, proving the web fragment
asset/device path as well as the protocol. That proof enables the dense-page
strip router on web; native software Skia stays excluded by the existing
Impeller capability gate.

`flutter test --platform chrome` is not suitable for this particular boundary:
its test server constructed the package-asset Worker but did not execute the
worker entry (the 12-second ready watchdog fired). The production-shaped built
app served the same asset successfully and is the authoritative browser check.

## Verification

- `dart analyze packages/dart_pdf_editor`
- `dart compile js -O2` of the bundled worker entry
- `fvm flutter build web --debug` for the example
- built-app browser probe above (worker plan parity + strip raster)

