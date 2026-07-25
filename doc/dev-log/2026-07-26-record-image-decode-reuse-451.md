# 2026-07-26 — #451: a page recorded four times decoded its images four times

## Which build each trace is from

Device traces here are quoted with the commit the web build was cut from.
Without that, a trace is unattributable — and one already was: the 09:50
trace below reads as "the fix did nothing" until you notice it predates the
fix. Record the commit whenever you paste one.

| trace (local time) | branch commit | contains |
| --- | --- | --- |
| 09:34 | `8b43e6ec` | exact-match cache only |
| 09:50 | `8b43e6ec` | exact-match cache only — **not** the 09:46 fix |

`49c6aac4` (cross-ratio reuse + browser-codec cache) was committed at
09:46:37, ~4 minutes before the 09:50 capture, so that build did not include
it. Both SHAs are pre-rebase; the rebase onto #608 renamed them to
`ea82c0b6` and `14d4c970`, which is its own argument for logging the commit
into the trace rather than reconstructing it from timestamps afterwards.

How to tell without the SHA, if you have to: the current code cannot emit two
identical `imageDecode=` tallies for the same page on the same worker — the
second must carry `reused=N`. The 09:50 trace has three such pairs (p5/w2,
p7/w1, p28/w1), so it is pre-fix by construction.

The device trace on [#607](2026-07-26-scheduler-concurrent-grant-451.md)
showed the scheduler race closed and left one cost standing above
everything else — **≈6.9 s of `serialize=` across seven records, every one
of them `cmyk:1`**:

```
[1438]  p2  serialize=908ms   cmyk:1
[2775]  p2  serialize=882ms   cmyk:1
[4031]  p2  serialize=910ms   cmyk:1
[4034]  p3  serialize=950ms   cmyk:1,notDct:2
[5556]  p3  serialize=918ms   cmyk:1,notDct:2
[15138] p29 serialize=1174ms  cmyk:1,notDct:1
[17412] p29 serialize=1148ms  cmyk:1,notDct:1
```

One `DeviceCMYK` JPEG per page that the browser codec declines, decoded in
pure Dart — and **re-paid on every record of that page**. Page 2 pays it
three times in one scroll, pages 3 and 29 twice. That repetition is ~4.6 s
of the 6.9 s.

## The lever that died on contact

The obvious first move was "cap the declined decode to the record's own
pixel budget" — a 128 px thumbnail tile has no business decoding a 2 Mpx
CMYK image. New tool **`tool/bench_image_scale_cost.dart`** decodes each
image three ways (native, page-ratio target, tile target) and reports all
three:

```
  fullMs   pageMs   tileMs  tile/full  native      page        tile
   186.3    184.5    188.5       1.01  1280x1655   1280x1655   257x333   p2  CMYK SMask DCT
   191.2    186.0    188.2       0.98  1280x1655   1280x1655   257x333   p3  CMYK SMask DCT
   201.5    206.9    204.5       1.01  1241x1621   1241x1621   250x326   p29 CMYK SMask DCT
     7.1      5.0      2.6       0.37  1241x1621   1241x1621   250x326   p29 Gray Flate
```

**The thumbnail already asks for the small size and it costs the same.**
#603's budget reaches the codec correctly; the *decoder* ignores the target
for DCTDecode — it decodes the whole JPEG and downsamples (the extra 1–3%
is the downsample). Note the Flate row at `0.37`: that path *does* honour
the target, via `decodePdfImagePixelsRegionScaled`. DCT simply has no
scaled path, the way JPX has `_decodeJpxScaled`.

Splitting the cost further: the JPEG entropy decode + IDCT inside
`package:image` is only **~31%** (58–66 ms); the other ~69% is our own
CMYK→RGBA + /SMask + ICC pass, running at full resolution. So a scaled DCT
decode would be worth far more than 31% — the smaller output would shrink
the colour pass by ~25× too — but it needs a reduced-IDCT decode
`package:image`'s `JpegData` does not expose. Left as future work; the
approximation shortcut (downsampling CMYK planes *before* the colour
transform) changes pixels and wants its own decision.

## First attempt: exact-match only, and it did nothing

The cache first shipped **exact-match only** - reuse an entry solely for the
same stream at the same requested target size, never downsampling a larger
entry, on the grounds that formats with a genuinely scaled decode path would
get different pixels. A bench re-recorded each page twice and reported
**93% off the second record**.

The device trace on that build showed **no win at all**:

```
[29994] p2 worker=2 serialize=876ms  decodedMpx=0.4  cmyk:1  transcript=miss
[32677] p2 worker=2 serialize=884ms  decodedMpx=1.4  cmyk:1  transcript=hit
```

Same page, same worker, same declined CMYK image, ~880 ms twice. Look at
`decodedMpx`: 0.4 against 1.4. A page's repeat records are a full-page pass
and a 128 px thumbnail tile, **at different image pixel ratios by
construction** - so they never ask for the same target and exact match never
fires on the records that matter.

The fault was in the bench, not the trace: it re-recorded at the *same*
ratio, which is a sequence production never performs. A measurement that
does not reproduce the shape of the real workload will confirm anything.
`tool/bench_record_reuse.dart` now records at a page ratio and then a tile
ratio, the pair that actually occurs.

## What landed

`PdfImageDecodeCache` (`image_decode_cache.dart`) — a bounded LRU threaded
through `serializeCommands` as an optional `imageCache:`, owned one-per-open-
document by both render worker backends.

Reuse is reached two ways. **Exact match** — same stream, same requested
target size. And **downsampled from a native-resolution entry**, but only
for streams whose decoder ignores the target anyway
(`pdfImageDecodeIgnoresTarget`, in practice DCTDecode): for those,
`decodePdfImage(target)` already *is*
`downsamplePdfDecodedPixels(decodePdfImagePixels(...), tw, th)`, so doing it
from a retained native decode produces the same bytes. The second route is
what makes the cache useful at all, since a page's repeat records are at
different ratios by construction.

The **native-entry** restriction is load-bearing: downsampling an entry that
was itself a downsample would not equal downsampling the native pixels.
Formats with a genuinely scaled decode path (Flate, CCITT, JPX reduced
levels) keep exact-match, because serving them from a downsample would
substitute different pixels for the ones their decoder produces.

Either way reuse is byte-identical to decoding again, so the cache cannot
change what a record renders — the whole safety argument, asserted directly
in both the tool and the tests.

The web worker's **browser-codec** decode is cached too, and that turned out
to be the larger half: it ran at native resolution on every record and was
entirely uncached, ~330–630 ms a time in the trace. No target means no size
dimension, so it keys on the stream alone. Reuse reports as `reused=N`
beside `codec=N`, so a trace shows it directly rather than as an unexplained
drop in `codec=`.

Keyed on `CosStream` **object identity**. That works because a worker opens
its document once per session and `CosDocument` memoises loaded objects, so
the same page's streams are the same objects across records. The device
trace confirms the affinity holds in practice: page 2's three records all
ran on `worker=2`, page 3's two on `worker=0`, page 29's two on `worker=2`.
A document swap builds a fresh cache; an evicted-and-reloaded stream is
just a miss.

## Result

New tool **`tool/bench_record_reuse.dart`** serializes each page twice with
a shared cache and twice without, and checks the bytes:

```
    pageMs    tileMs  tileCachedMs   saved  identical  page
     105.4      12.1       10.5      13%        yes  p1
     298.9     224.2        9.1      96%        yes  p2
     223.6     220.5       21.3      90%        yes  p3
      37.8      46.6       15.2      67%        yes  p8
     287.5     249.4       22.9      91%        yes  p29
      14.5      14.6        6.7      54%        yes  p30
       9.2      30.1       26.6      12%        yes  p31

  thumbnail record after a full-page record: 797.5ms uncached ->
  112.4ms cached (86% less). The full-page record itself is 977.1ms
  either way.
```

**The saving lands exactly on the pages the device trace flagged** - 2, 3
and 29, the CMYK ones, at 90-96%. The first record of a page is unchanged;
this only removes repetition. Pages 1 and 31 barely move, which is the
honest shape: their images are cheap and there is little to reuse.

Byte-identical on every page, which is the claim that matters.

## Testing note

Eleven unit tests on the cache and the predicate, plus two codec-level tests
that pin the integration - the unit tests would all pass against a codec that
never consulted the cache it was handed.

Both codec tests needed a second attempt, and both times for the same reason:
**a fixture too small to trip the resolution cap**. A 2x2 image decodes
identically at every ratio, so the cross-ratio test passed against a codec
that applied the native-downsample route to *every* format. It now uses a
64x64 gradient drawn into a 64pt box, where ratio 2.0 is a no-op and ratio
0.2 binds - and it asserts the routing structurally (a non-DCT stream must
never be retained natively) rather than hoping two formats disagree on
pixels. Confirmed to fail against the dropped-predicate mutation.

pdf_graphics 970, dart_pdf_editor 1989, zero Ghent baseline movement,
analyzer clean.

## What is left

1. **A scaled DCT decode** — the 69%/31% split above says it is the largest
   remaining single lever on this document, and it is the only thing that
   makes a 128 px thumbnail cheaper than a full-page record.
2. The device trace's `wait=` is still 274-2652 ms; this change attacks the
   worker's repeated work, not the queue depth that produces it.
3. Both caches are per-worker, and the page-to-worker affinity that makes
   them hit is incidental rather than guaranteed. A page that migrates
   between workers pays full price again.
