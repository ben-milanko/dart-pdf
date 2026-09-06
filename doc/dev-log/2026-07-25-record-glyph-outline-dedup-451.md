# 2026-07-25 — #451: a record's biggest item was the same glyph, written again

A device trace from the #598 build (app 3.0.0+20, web release, 62-page /
24 MB book, 3 render workers) reframed #451. The ticket's headline is a
39 MB record; the trace says the cost of that size is **cache capacity**,
and capacity is what drives everything else.

## What the trace showed

Across ~16 s of scrolling over pages 18–38:

```
575 MB of render records produced for 20 distinct pages
 50 records, 3-5 per page (page 31: five)
193 MB of that is pure duplicate work
```

Both caches sat pinned at their ceiling — record 94.1 MB of 96 MB,
decoded-image 128.1 MB of 134.2 MB. With single records reaching 33–39 MB,
about three fill the cache while the window spans ~20 pages, so a page is
recorded, evicted by its neighbour, and recorded again. Re-recording is not
cheap; pages 28 and 29 each paid a 1.2–1.6 s `serialize` **twice**:

```
page=28  worker=1895ms  ser=1608ms
page=28  worker=1723ms  ser=1505ms   <- same page, again
```

That saturates the workers, and the queue is where the user's time goes:
**17.6 s of cumulative queueing against 20.4 s of work**, page 27 queued
4.18 s. It surfaces as `wait=943.9ms` on the *visible* page's interpret.

So #451's issue 1 (image headroom), demoted to third on the ticket, is
upstream of the rest — but not for the reason recorded there (transfer
bytes; transfer was only 2.1 s across all 50 records).

## Measuring what is in a record

New tool: **`packages/pdf_graphics/tool/bench_record_bytes.dart`**.

The first split it produced was wrong, and worth recording as a trap:
differencing `serializeCommands(decodeImages: true)` against
`decodeImages: false` looks like it isolates the image payload, but the
`false` run still embeds every image's *encoded* stream, so the difference
charges those bytes to the commands. It reported "65% commands" for the
wrong reason. The tool now measures the payload directly, by deserializing
the record and summing what each command actually carries.

Doing that surfaced the real item. A record carries, per image, **both** the
decoded RGBA *and* the source stream beside it (`device.dart` — "the
[stream] is still serialized so the decoded pixels cache by content"). And
in the remainder, over the traced book:

```
62 pages: 394.0 MB of records
   83.1 MB (21%) decoded RGBA
   53.8 MB (14%) source image streams, carried beside the RGBA
  257.1 MB (65%) draw commands and other resources
      of which glyph outlines: 151.7 MB, across 100062 placements
                               85% of it literal repetition
```

**Glyph outlines were the single largest item in a record — larger than the
entire decoded-image payload.** `PdfGlyphPlacement.outline` rides on every
*placement*, so a letter set 500 times serialized its geometry 500 times.

## What landed

The writer emits an outline's geometry once and references it by id
thereafter (tag 0 = none, 1 = geometry follows and takes the next id,
2 = u32 id of one already defined). Format version 3 → 4.

Keyed on **object identity**, which is the detail that makes it free: the
font engine hands the same `PdfPath` instance back for every placement of a
glyph, so identity catches essentially all of the repetition (8464 distinct
by identity vs 7765 by value over the same book) without hashing geometry in
the hot path. Read-back shares one instance per glyph too, so the replayed
commands hold no more copies than a local render.

Version bump is safe: records are in-memory only for a session, producer and
consumer ship together, and the app's IndexedDB caches hold PDF bytes and
sessions — not records.

## Result, including where it does nothing

Byte counts are deterministic, so unlike the timing work in
[#598](2026-07-25-image-decode-colour-memo-451.md) there is no interleaving
caveat — two rounds produced identical figures.

| document | before | after | |
|---|---|---|---|
| tide-quickstart (the traced book) | 394.0 MB | **270.8 MB** | −31% |
| Flutter_CTO_Report | 423.5 MB | 413.1 MB | −2.5% |
| FST-AT-8720-EN | 927.1 MB | 913.0 MB | −1.5% |
| AMT-SP-101 | 208.3 MB | 207.0 MB | −0.6% |
| Combined Design Pack | 1261.3 MB | 1261.3 MB | 0% |
| ghent + pdfjs (495 pages) | 384.6 MB | 376.3 MB | −2.2% |

**The 31% is document-specific and should not be quoted as a general
number.** The saving only exists where embedded fonts yield glyph outlines.
Scanned and CAD documents have none at all, and their records are dominated
by something else entirely:

```
Combined Design Pack  58 pages: 1261.3 MB - 95% decoded RGBA, 0 outlines
FST-AT-8720-EN       344 pages:  913.0 MB - 94% decoded RGBA
```

Those documents reach **61.6 MB in a single page's record — 64% of the
whole 96 MB budget each**, so two cannot coexist in the cache. For that
class, image headroom is the entire problem and this change is irrelevant.

## Testing note worth keeping

The codec's existing round-trip oracle logs `glyphs=${run.glyphs?.length}`
and **never looks at outline geometry**, so all 929 pre-existing tests would
have passed against a dedup that returned the wrong glyph. The new tests
compare paths directly, and each was confirmed to fail against the specific
mutation it targets — dedup disabled, and the table returning the most
recent entry instead of the referenced id.

Zero Ghent baseline movement. pdf_cos 356, pdf_document 805, pdf_graphics
933, dart_pdf_editor 1975, app 321.

## What is left

1. **Image headroom on the focused record** — now clearly the dominant term
   for scanned/CAD documents (94–95% of record bytes; 61.6 MB single pages).
   #473 already caps *prefetch* neighbours; the focused record is uncapped.
   Note #473's cap also means a page is deliberately re-recorded when it
   gains focus, which is some of the 3–5 records per page in the trace.

2. **The RGBA and its source stream are both in the record**, and the same
   pixels are also in the decoded-image cache — 222 MB across both caches in
   the trace. Referencing images by content key instead of inlining them
   would store them once, but a record whose images have been evicted can no
   longer replay, so it needs a fallback path.

3. **Untracked scheduler problems** the trace exposes, neither filed:
   `PdfPageRenderScheduler` grants one request per frame to enforce "no frame
   runs more than one page's walk", but `render` is a `VoidCallback` and on
   the worker path returns before the expensive build happens — so the
   serialization it exists to provide has silently lapsed, and builds run in
   record-arrival order rather than focus order. Separately, **every focus
   page is granted exactly twice** (`(22,22):2, (24,24):2, (25,25):2,
   (27,27):2, (30,30):2, (31,31):2` while neighbours are granted once).

4. **`flate` = 4.66 s over 120 calls** on the main isolate in the trace —
   98.7% of all measured phase time, 54 MB inflated at 11.6 MB/s. Cumulative
   and unattributed; needs a targeted trace before anyone acts on it.
