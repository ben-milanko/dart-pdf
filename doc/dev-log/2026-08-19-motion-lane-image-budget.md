# Ordinary documents have images: the motion lane's image budget

Follow-up to
[2026-08-19-motion-safe-renders.md](2026-08-19-motion-safe-renders.md). The
reader's verdict on that work was "feels better but not as good as the built
in browser pdf viewer", with a fresh trace of a 113-page report. Three things
in that trace, in the order they matter.

## 1. Every grant still read `cost=held`

```
[perf 965] scheduler grant page=74 focus=75 cost=held hold=off remaining=0
[perf 2301] scheduler grant page=75 focus=75 cost=held hold=off remaining=2
```

The lane was never engaging on this document. The reason was its own
request-time gate:

```dart
if (xObjects is CosDictionary && xObjects.entries.isNotEmpty) {
  return PdfRenderMotionClass.held;   // any XObject at all
}
```

The document is a corporate report with a letterhead mark on every page -
the trace decodes them: `jpeg rgba-accelerated 42x10`, `126x29`, `184x42`.
Three postage stamps, and they switched the lane off for the whole file.

The premise of the rule was right (a three-operator content stream can hide
a hundred megapixels) but its evidence was wrong: an image's size is a
dictionary entry, not something that needs decoding to find out. So
`_xObjectsWithinMotionBudget()` sums the declared `/Width x /Height` of the
page's image XObjects and compares against
`PdfPageView.motionSafeMaxImagePixels` (1 MP ~ 4 MB of RGBA - a
decode/upload that fits a frame). A Form XObject, an image that will not
declare its size, or a resource dictionary that will not resolve still
answer "held", exactly as before. The verdict is cached per page.

The record-time half moved the same way:
`!PdfPageRenderer.hasImageDraws(commands)` became a pixel budget over the
actual draws (`PdfPageRenderer.imageDrawPixels`), which also covers inline
images and Form XObject contents nothing at page level advertises. It
returns -1 for an image that will not say how big it is, so "unknown" can
never be mistaken for "small".

## 2. `scene-cache reject reason=image-lod have=1.79 need=2.00`

Scroll back onto a page and its retained display list was thrown away over a
10% difference in embedded-image resolution - blank paper plus a 40 ms
re-interpret for something no one can see. `_restoreRetainedScene` was
comparing against `_imageRatioTarget()`, which includes the 2x
`focusedImageDecodeHeadroom` a *fresh* render aims for. What a cached scene
has to clear is display sharpness - one decoded sample per physical pixel at
the current zoom - so it now compares against `_effectiveRatio()`. A page
that is genuinely soft (the 1.25x prefetch buffer) is still rejected; the
existing soft-to-sharp refinement collects the headroom behind the painted
raster.

## 3. `path=recorded(no-worker)`, and what it says about the session

The diagnostic added at the end of the previous session paid for itself:

```
interpret page=74 path=recorded(no-worker) FIRST interpret=39.8ms
thumbnail page=77 tile px=128 local interpret+raster=83.4ms (no worker)
```

Session-wide, not per page. Over the 8.8 s the trace covers: 10 page
interprets = 419 ms and **25 thumbnail tiles = 1317 ms**, all on the UI
thread, against 51 janked frames totalling 2.6 s. And `jpeg
rgba-accelerated` only exists on web (`installPdfJpegAccelerator` is a no-op
on native), so this is a browser session whose **render web worker never
became active** - the cause is in the `webworker ...` lines above the
snippet, which the trace does not include.

That is the dominant cost in the trace and it is a configuration failure,
not a rendering one. Everything else here is about making the no-worker path
survivable, not about accepting it.

## The corpus was missing the shape

Nothing in `test_corpora/dartpdf/` looked like the document that exposed
this: `text-report-40p` has no images at all, `image-scan`/`photo-jpeg` are
full-page rasters. `letterhead-report-40p.pdf` is the ordinary middle -
office text under one small shared image XObject per page - with
`wheel-letterhead` / `wheel-letterhead-noworker` scenarios over it.

## Measured

`tool/perf.sh webdiff 7236031 wheel-letterhead`, 3 interleaved iterations,
headless Chrome (medians):

| metric | 7236031 | this tree |
|---|---|---|
| `wheelSettleMs` | 644 | **0.22** |
| `wheelSharpWhileScrollingPct` | 15.0 | **96.0** |
| `wheelSharpPct` | 10.7 | 96.0 |
| `wheelPagesNeverSharp` | 3 | **0** |
| `wheelSoftP50Ms` | 1300 | **0** |
| `wheelSoftMeanMs` | 650 | 69 |
| `buildP50` / `buildP95` | 2.31 / 6.37 ms | 2.14 / **4.82** ms |
| `agentMemoryBytes` | 72 MB | **173 MB** |

The letterhead document now behaves exactly like the image-free
`wheel-text` one - which is the whole claim, since it *is* that document
with a postage stamp on each page. Frame build times are flat-to-better
(p95 −24%): pages render during motion, but each is a text page whose
replay is cheap, and the settle no longer piles three of them into
consecutive frames.

The cost is memory, and it is the same trade the previous session priced:
a scroll that renders and retains five pages holds five pages' worth of
display list, where the baseline held none because it drew none. 173 MB is
within the web envelope's own ceiling, and `pdfDefaultRetainedSceneBytes()`
(64 MB on web) plus `PdfCacheRegistry` still govern it; the measured 32 MB
alternative documented there is the knob if a smaller working set matters
more than scroll-back.

`jankCount` reads +10.5% in the table, which is the harness counting one
line per sampled frame: the run drew 84 frames against the baseline's 76 in
the same wall-clock, and the frames themselves are faster at every
percentile. Frame count is not a jank measure.

And the same document with the worker off (`wheel-letterhead-noworker`,
5 completed runs - the sixth was lost to a container restart, so these are
per-arm medians of 3 current / 2 baseline rather than a full triple):

| metric | 7236031 | this tree |
|---|---|---|
| `wheelSettleMs` | 621 | **360** |
| `wheelSharpWhileScrollingPct` | 15.0 | 15.0 |
| `agentMemoryBytes` | 60 MB | 60 MB |

That is the honest shape of the no-worker path: the wait after the reader
stops nearly halves (the quiet lane now grants these pages at all, three per
frame instead of one), and what is on screen *during* a fling does not
improve, because it cannot. Walking a page's content stream on the UI thread
inside a moving frame is the dropped frame the hold exists to prevent; the
lane deliberately admits local walks only in the scroll-quiet window, never
inside a live gesture. A session without a worker has a ceiling here, and the
fix for such a session is to get its worker back, not to loosen this.
