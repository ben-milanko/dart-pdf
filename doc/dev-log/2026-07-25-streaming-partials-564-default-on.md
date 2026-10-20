# 2026-07-25 — Progressive reveal on by default (#564 closes)

PR1–5 built the streaming reveal end to end behind
`PdfPageView.progressiveStreamingPaint`, default **off**: partial transport on
the isolate (PR1), dedup fan-out (PR2), cost bounds (PR3), the host paint
consumer (PR4), and the web-worker transport twin (PR5). This flips the default
**on** and removes the app's now-redundant opt-in.

## Why now — the three gates the flag was waiting on

1. **Both backends stream.** PR5 landed the web twin, so a dense page no longer
   loses the #527 bounded prefix without gaining the reveal on web.
2. **Measured, not eyeballed.** Real-Chrome A/B on the dense diagram sheet
   (`tool/perf.sh web open-diagram` vs `open-diagram-progressive`, median of 5):
   first content **~430 ms via `early-prefix` → ~322 ms via
   `progressive-partial`**, ~25% faster first ink, every run ahead. That
   understates it — the baseline shows one bounded snapshot while the reveal
   keeps filling in on the doubling schedule, and the gap widens with density
   (a 249k-command CAD sheet logged first ink ~866 ms against a ~12.9 s full
   raster).
3. **Reviewed.** Each PR went through an adversarial review; no shipping bug was
   found, and every latent finding (concurrent-pass ordering, slug short-circuit,
   pause re-check, emit-cadence burst) was fixed before landing.

## The flip

- `pdf_page_view.dart` — `progressiveStreamingPaint = true`, doc comment
  rewritten to describe the opt-**out** and cite the measurement.
- `app/lib/main.dart` — dropped the explicit `= true` (and the now-unused
  `PdfPageView` import); the app just takes the library default.
- `early_prefix_paint_test.dart` — pins the flag **off** in `setUp`. Not a
  workaround: the reveal deliberately *replaces* the single bounded prefix on a
  dense page, so with the new default that suite would have been asserting a
  path its own subject no longer takes. It now covers the documented fallback,
  and `progressive_streaming_paint_test.dart` covers the default.

## What is actually on

Only a page over `earlyPrefixMinContentBytes` (512 KB raw content) streams — the
same density proxy the bounded prefix used, an O(streams) size check with no
decode. Ordinary pages take exactly the path they took before and are never
charged a second worker job. A backend that doesn't stream (the null worker)
returns the final with no partials and renders as before. `= false` restores the
#527 bounded snapshot.

#564 is complete.
