# X-strip transcript banding (#385)

Follow-up to #383 (grid-cull region replay). On a single flat-content-stream
page the retained `PdfRenderCommand` transcript is an irreducible memory floor
(~60-100 MB on the 8504x842 CAD sheet). #383's spatial cull skips *replaying*
offscreen commands but still *retains* all of them. The remaining lever is the
transcript itself: because such pages are extreme-aspect and panning is
horizontal, partitioning the page into N vertical strips along the pan (X) axis
and retaining only the strips overlapping the viewport bounds retained memory to
roughly `visible strips / total`.

## What landed

The retention/eviction **engine**, the two prototype primitives the #383 session
described, the diagnostic, and the memory-pressure hook. Full viewer adoption
(the page view dropping the flat transcript for extreme pages and driving
eviction off the scroll position) is deliberately a follow-up; this lands the
tested mechanism it will sit on.

- **`PdfBandedTranscript`** (`banded_transcript.dart`) - the engine. Built on
  the same supported subset `PdfRegionReplayIndex` already guarantees (balanced
  save/restore, nestable clips, no transparency/soft-mask group split), so each
  retained unit is an independently replayable paint plus a persistent clip +
  blend snapshot. Key design points:
  - A unit whose bounds span several strips is retained by **every** strip it
    overlaps (its shared command object, not a copy), so evicting the others
    never drops a paint a survivor still needs. `replayRegion` dedupes such a
    unit back to a single draw by keying on painter order, then replays the
    picked units in that order - identical output to the whole-transcript region
    replay (asserted byte-for-byte).
  - `evict` / `evictOutside(keep)` free a strip's exclusive paints;
    `estimatedResidentBytes` (identity-deduped) tracks the distinct paints held,
    so it drops as strips are evicted while `estimatedFullBytes` is the
    whole-page floor traded against.
  - `missingBandsForRegion` reports the evicted strips a viewport overlaps - the
    "panned into a dropped strip" detector - and `restore(freshCommands)`
    re-materializes them from a freshly recorded (deterministic, identical)
    transcript. The caller pays one whole-page interpret to produce the fresh
    commands (the ~760 ms record the decomposition trades against); `restore`
    only re-partitions it.

- **`PdfRegionReplayIndex.unitBandHistogram(bands)`** + `xExtent` - the
  reintroduced `debugUnitBandHistogram` diagnostic. Counts each unit once by its
  centre band, so the counts sum to the unit total and expose the uneven spread
  (the CAD probe's densest 3 of 10 strips carried ~54%). Note the histogram uses
  centre-assignment (a distribution) while retention uses overlap-assignment (a
  spanning unit is in every strip) - documented on both.

- **`PdfRetainedScene`** wiring: `debugUnitBandHistogram`, `bandTranscript` /
  `bands` / `reband` (re-materialize via one `record`), and `dropRegionIndex`
  (the reintroduced primitive - frees the index and any banded transcript; both
  rebuild identically, the authoritative `commands` stay intact). A weak
  process registry of live scenes backs `PdfRetainedScene.handleMemoryPressure`,
  which the viewer's `didHaveMemoryPressure` now drives alongside the cache
  registry. Dropping the index is free of visual regression by construction, so
  it is safe to shed aggressively.

## Gotchas

- "Strip" is heavily overloaded here: `StripPdfDevice`/`StripPlan` are the
  horizontal *scanline* strips of the drawVertices batcher. This feature's
  X-strips are *vertical* page slices along the long axis; I kept the names
  `PdfBandedTranscript` / band to avoid the collision.
- Banding is only available when the transcript is in the region-index supported
  subset - same constraint #383 lives under. A page with a page-spanning
  transparency group stays whole, and `PdfBandedTranscript.build` returns null.
- The genuine memory win requires the owner to stop retaining the flat
  `commands` once banded (an extreme page never does a whole-page replay anyway).
  That adoption is the follow-up; the engine + `estimatedResidentBytes` prove
  the scaling in `banded_transcript_test.dart`.

## Tests

`banded_transcript_test.dart`: partition/histogram sums, resident-strip replay
byte-identical to whole-transcript region replay, retained bytes drop when
offscreen strips are evicted, evicted strips re-materialize to an identical
replay, and the scene-level histogram/drop/pressure primitives.
