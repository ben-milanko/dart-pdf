# 2026-07-22 — make the recorded single-walk render the default (#394)

The bitmap render path (`renderImage`/`renderImageWithPlan`) defaulted to
`renderPictureWithPlan`, which interprets the page **twice**: a scan-only
`ImageCollector` walk to discover images, then the paint walk. The
record/replay path (`renderPictureRecordedWithPlan`) walks once — the
`RecordingPdfDevice`'s `drawImage` calls double as image discovery — then
replays the flat command buffer onto the canvas.

Per the verification pass on #394, this is a **consolidation, not a 2×**:
`scanImagesOnly` already short-circuits colour parsing, shading, path building,
and glyph emission, so the collect walk is a fraction of the paint walk. The
win is removing a whole walk's operator dispatch + per-glyph advance cost and
collapsing the pipeline onto one path — the same recorded transcript the
deep-zoom/tile route, `worker.record`, and the strip bins already consume, so
it is well-exercised and parity-tested, not experimental.

## Change

- `renderImage` / `renderImageWithPlan` default `recorded: false → true`.
- The two remaining direct `renderPictureWithPlan` production callers switched
  to `renderPictureRecordedWithPlan`: the page colour sampler
  (`PdfPageColorSampler.of`) and the deep-zoom detail patch
  (`_detailPictureFromWorker`'s workerless branch in `pdf_page_view.dart`).
- **Decoupled the strips device axis from `recorded`.** The strips gate was
  `deviceMode == strips && !recorded`; since `recorded` is now the default, that
  would have stopped the strip benchmark/parity harnesses (which set
  `deviceMode = strips` and call `renderImage` with the default) from engaging
  strips. Strips is an independent opt-in device mode, so the gate is now just
  `deviceMode == strips`. No production caller combines the two (deviceMode is
  only ever set by the benchmark tests, which restore it to canvas).

`renderPictureWithPlan` (the two-walk path) stays — it is what
`render_record_replay_test` renders as the `direct` reference to prove the
recorded path is pixel-identical, and it is still reachable via
`renderImage(recorded: false)`.

## Pixel-identity proof

- `render_record_replay_test` (zero-tolerance direct-vs-recorded compare): pass.
- `strip_parity_test`: pass (canvas reference is now the recorded path; strips
  vs canvas diffs unchanged, within the relaxed edge gate).
- **Ghent render baselines** — the 54-PDF conformance suite renders through
  `renderImage` with the (now recorded) default and diffs against the two-walk
  baselines: identical result to the base commit (+40 pass, ~13 known colour
  deviations tolerated, GWG030 the one pre-existing spot/overprint failure). No
  new pixel diffs — the recorded path matches the two-walk output byte-for-byte
  across the whole conformance suite.
- `pdfjs_render_test` smoke (164): pass.
- Full `dart_pdf_editor` Flutter suite: green.

## Note on measurement

The maintainer's #394 comment asks for a `tool/perf.sh diff` on a text-dense
and a vector-dense scenario before quoting a number publicly. This PR is the
correctness/consolidation half (proven pixel-identical); it deliberately makes
no headline perf claim. The A/B is worth running before citing a figure.

## Ticket

Closes **#394**.
