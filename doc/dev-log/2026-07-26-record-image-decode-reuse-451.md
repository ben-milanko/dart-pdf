# 2026-07-26 — #451: a page recorded four times decoded its images four times

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

## What landed instead

`PdfImageDecodeCache` (`image_decode_cache.dart`) — a bounded LRU threaded
through `serializeCommands` as an optional `imageCache:`, owned one-per-open-
document by both render worker backends.

It is deliberately **exact-match**: an entry is reused only for the same
stream at the same requested target size, and it never downsamples a larger
entry to serve a smaller request. For the formats that *do* have a scaled
decode path that would substitute different pixels for the ones the decoder
would have produced. As built, reuse is byte-identical to decoding again,
so the cache cannot change what a record renders — which is the whole
safety argument, and is asserted directly in both the tool and the tests.

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
   firstMs  secondMs  reuseMs   saved  identical  page
      57.9      17.0       4.5     74%        yes  p1
     251.8     224.6      10.1     95%        yes  p2
     222.4     214.2      15.4     93%        yes  p3
      17.7      25.4       4.4     83%        yes  p8
     244.3     230.6       9.8     96%        yes  p29
       8.1       7.4       2.8     62%        yes  p30
       8.9      10.7       2.9     73%        yes  p31

  re-record uncached 729.8ms -> cached 49.9ms (93% less),
  first record 811.2ms either way.
```

**The saving lands exactly on the pages the device trace flagged** — 2, 3
and 29, the CMYK ones, at 93–96%. The first record of a page is unchanged;
this only removes repetition.

Byte-identical on every page, which is the claim that matters.

## Testing note

Eight unit tests on the cache (reuse, size-keyed separation, native as its
own key, identity not equality, declines uncached, LRU eviction, oversize
bypass, clear) plus one codec-level test that pins the integration — the
unit tests would all pass against a codec that never consulted the cache it
was handed. That test was confirmed to fail against exactly that mutation.

pdf_graphics 966, dart_pdf_editor 1989, analyzer clean.

## What is left

1. **A scaled DCT decode** — the 69%/31% split above says it is the largest
   remaining single lever on this document, and it is the only thing that
   makes a 128 px thumbnail cheaper than a full-page record.
2. The device trace's `wait=` is still 274–1883 ms; this change attacks the
   worker's repeated work, not the queue depth that produces it.
