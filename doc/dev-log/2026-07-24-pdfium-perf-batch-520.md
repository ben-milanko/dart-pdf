# 2026-07-24 — PDFium comparative-study perf batch (#520)

Worked the #520 tracking issue — the subsystem-by-subsystem PDFium-vs-dart-pdf
comparison — landing the cheap allocation wins, the flagship structural
tiling-pattern change, and the whole round-2 gap sweep. Each change was A/B'd
on the real harness (`tool/perf.sh diff`/`webdiff`/`render`); nothing eyeballed.

## Landed (merged)

| # | PR | Change | Measured |
|---|----|--------|----------|
| #533 | #548 | Drop the double copy of every inflated stream (`Uint8List.fromList` over `ZLibDecoder.decodeBytes`, which already returns `Uint8List`) — pdf_cos + png.dart | dartpdf-corpus interpret **0.957x**, peakRss 0.944x |
| #522 | #549 | Int-key the loaded-object cache (`objectNumber * 65536 + generation`) so a warm `getObject` allocates no `CosReference` | ghent open **0.984x** / interpret 0.982x / extract 0.983x |
| #524 | #551, #552 | Record a tiling-pattern cell once, replay per tile (interpret side), then carry it as one nested `PdfDrawTiledCellCommand` through transcript/wire/canvas (transcript side); canvas stamps a cached sub-picture per origin | hatch VM interpret **0.683x** / extract 0.487x; web agent memory **−69%**, jank −50% |
| #534 | #555 | Doc-level `Expando` parse caches for colorspaces/shadings/functions (was re-parsed per `cs`/`sh`); 8/16-bit sampled-function fast read | ghent extract **0.964x**; GWG132 interpret **0.07x** |
| #531 | #556 | Detect sRGB-equivalent ICC profiles behaviourally (decode+re-encode ≤1/255) and bypass the per-pixel transform; allocation-free 8-bit fast path for non-sRGB matrix/TRC RGB | GWG161 ICCBasedRGB blend **829 → 40 ms (0.049x)**; ICC-CMS composite 0.433x |
| #535 | #553 | Record a Type3 glyph once, stamp per occurrence (the #524 sibling on shared machinery); canvas picture cache re-keyed to the cell-list identity | type3 raster **0.616x**; VM interpret 0.716x |
| #532 | #558 | Cache decoded JBIG2 globals dictionaries across images (content-hash keyed; shared bitmaps read-only) | definitional (see gap below) |
| #536 | #560 | Adaptive Coons/tensor patch subdivision by page-size + corner-colour delta (was fixed 8 = 128 triangles), 8 the ceiling, with a large-patch fidelity guard | small-flat patch 128→2 triangles (unit); coons render 0.85x |

(#553/#558/#560 were in CI at write time; PR numbers final.)

## Closed as not-worth-it (measured flat)

- **#521** (memoize simple-font code→gid): the CID path was already O(1); the
  remaining format-4 scan is over a subset font's tiny cmap. Flat on
  dartpdf-corpus and ghent, VM and — since the win would be dart2js GC — web.
  Branch pushed for reference; the memo is harmless but buys nothing.
- **#523** (intern names/dict keys): implemented the full two-tier intern
  (≤6-byte packed int + FNV-verified long tier). Flat everywhere incl.
  `open-text`/`scroll-diagram` webdiff — the existing keyword intern already
  covers the hot repetition; dictionary keys aren't a large enough allocation
  share to register.

The lesson both encode: the study's "Tier 1 cheap wins" that survived
measurement (#533, #522) were the ones removing a *copy* or an *allocation on
the single hottest path*; the ones that didn't (#521, #523) were optimizing a
path the profile doesn't actually dwell in. Measure, don't assume.

## Report-only (Tier 3, by design)

- **#528** (lazy numeric operands): confirmed the editor-contract gate is real
  — `ContentOperation.operands` is consumed as `CosObject`s by the serializer,
  annotation editor, element enumeration, and colour processing. Needs a dual
  representation (numeric buffer + lazy `CosObject`), a scoped project, not a
  session change. Left open.
- **#529** (Skia glyph atlas for embedded fonts): atlas idea rejected —
  subset gid packing + no `ui.Font` handle from `loadFontFromList` limit it to
  clean-cmap embedded TrueType/CFF, a minority. The "cheaper adjacent win" is
  mostly already done (`_drawGlyphOutlines` caches per-glyph em paths by
  outline identity); only the combined-repeated-word path remains uncacheable,
  tracked as a follow-up.

## Remaining structural tickets (not started — the deep tier)

Each is genuinely M–L and correctness-critical; documented here for a running
start rather than rushed:

- **#525** JPX `cp_reduce` resolution-level skip. `reconstruct()` synthesizes
  all levels from r0; needs to stop N levels early, skip the finest bands'
  block-decode + packets, and — the hard part — propagate the reduced output
  dimensions through `_decodeTile`/MCT/plane assembly and out to
  `image_pixels`' scaled-decode path so the RGBA buffer + image transform
  match. Bit-faithfulness required (lossless must stay bit-perfect).
- **#526** base-raster viewport cull (extend the `PdfRegionReplayGrid` to the
  base raster above a command-count threshold, not just deep-zoom detail).
- **#527** within-page progressive reveal (emit the first strip before the
  full transcript; the strip machinery + additive detail handshake exist).
- **#530** resume-from-object time-slicing of a single heavy page.

## New scenarios + fixtures landed on main

- `hatch-sections-4p.pdf` + `hatch-sections-sweep`/`scroll-hatch`
  (`gen_hatch_pdf.dart`) — the #524 tiling anchor.
- `type3-text-6p.pdf` + `type3-text-sweep`/`type3-text-render`
  (`gen_type3_pdf.dart`) — the #535 anchor; half the CharProcs are 1-bit
  inline ImageMasks (which, note, make the worker wire codec DECLINE — filed
  #554).

Both are byte-deterministic (seeded, no timestamps), wired into
`tool/gen_corpus.sh`, and documented in `test_corpora/dartpdf/README.md`.

## Follow-ups filed

- **#550** — ghent_render_test fails 20 baselines on pristine main (stale
  since the overprint landing); found while verifying #524/#531 render
  fidelity. Every perf PR here confirmed its render output was pixel-identical
  to main on those pages, so none caused or fixed them.
- **#554** — inline-ImageMask glyphs decline the worker wire codec (Type3
  bitmap pages never reach the render worker).
- **#557** — no in-repo scenario uses a separate `/JBIG2Globals` stream; a
  jbig2enc-generated doc is needed to put a headline number on #532.
- **#559** — `render_worker_strips_test` "late cancel" is flaky (1-in-3);
  spuriously reddened #553's CI.

## Gotchas for next time

- `tool/perf.sh diff` for gate + 2 scenarios exceeds the 10-minute Bash tool
  ceiling — run detached (`nohup` + done-marker + `Monitor`).
- Single-file VM scenarios (cad-138p-sweep) are noise-bound at sub-ms medians;
  one run flagged a fake REGRESSED that the next run reversed. Use the 54-file
  ghent / 14-file dartpdf-corpus aggregates as the signal.
- CI on branches from the release-probe git user lands as `action_required`
  (first-time-contributor gate) and, crucially, shows as **conclusion**
  `action_required` on a *completed* run — filter on `.conclusion`, not
  `.status`, to find what to `gh api .../approve`. The worker-bundle bot also
  re-pushes a bundle-rebuild commit on any pdf_cos/graphics change, minting a
  new head SHA whose CI needs re-approval.
- Record/replay refactors (#524, #535): verify with a transcript-digest probe
  (a flattening non-sink `PdfDevice` that hashes the geometry stream at 1e-3
  pt). It caught a pre-existing `_paintPath` segment-builder leak that 891 unit
  tests + the ghent baselines all missed.
- Decode-path tickets need pixel-diffing against a *pristine-main worktree*,
  not just "tests pass": #531's sRGB bypass shifted GWG161 by 16/channel on
  2.5% of pixels — which turned out to be *more* correct (it removed the old
  code's redundant sRGB round-trip float error, amplified by the page's blend
  modes), on an already-failing page. Only the worktree diff proved it wasn't a
  regression.
