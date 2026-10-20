# Decode a page's images concurrently, not one at a time (#454)

## What

`decodeImages` (image_decoder.dart) awaited each image in a `for` loop, one
after another. `ui.instantiateImageCodec` (and the browser JPEG codec on web)
hand the actual work to a codec thread, so awaiting serially left that thread
idle between images. On an image-heavy page that serialisation is a real slice
of the first-paint wait — #454's cold trace showed page 0 spending ~643 ms
decoding two DCTDecode images on the UI thread, and page 1 four images.

Now the misses decode concurrently (`Future.wait`). Same pixels out - this is
purely overlap of work already being done.

## The catch the ticket flagged, and how it's handled

The old loop deduped by key and consulted the cache *as it went*. A naive
concurrent version could decode a repeated image twice or race the cache. So
the rewrite splits into two passes:

1. **Synchronous planning** (before any `await`): dedup by `pdfImageKey`,
   resolve cache hits (`cache.take`), and collect the misses as
   `_PendingDecode`. Because this runs to completion before the first await,
   a repeated image is decoded once and no two tasks ever hold the same key.
2. **Concurrent decode** of the misses. Dart is single-threaded, so the tasks
   interleave only at their awaits; the result map and the distinct-key cache
   puts cannot collide.

## Scope / risk

- No visual change - identical decoded pixels, just produced with the codec
  kept busy. Verified by the existing decode/cache byte-identical suites plus
  three new tests: every distinct image in a batch decodes, a thrice-repeated
  image collapses to one decode, and a warm cache serves the second batch.
- Cross-platform: helps native too (DCTDecode images the worker can't decode
  run the platform codec on the main thread) and web (the browser codec).
- Concurrency is unbounded (one task per distinct un-cached image on the
  page). Images per page are typically few and the decoded results are all
  retained regardless, so peak memory is unchanged in the steady state; a
  pathological many-image page could add a modest transient. A concurrency
  cap is an easy follow-up if a trace ever shows it mattering.

## Validate

Image-heavy page open on the web preview with the perf overlay: the `decode`
phase of the first image-bearing pages should shrink versus a serial baseline,
with no change to the rendered pixels.
