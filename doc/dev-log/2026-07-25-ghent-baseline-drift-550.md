# 2026-07-25 — Ghent baseline drift: two root causes, not one (#550)

`ghent_render_test` failed **20 of 54** pages on pristine main. #550 guessed a
single cause — the overprint compositing landing (#502) — and asked for either a
reviewed re-baseline or a bisect if it turned out to be a regression. It was
neither exactly: **two** separate intentional rendering changes had drifted, and
the second one was invisible in the issue's framing.

## Method — separate the causes before accepting anything

The overprint landing shipped a kill switch (`CanvasPdfDevice.
debugOverprintCompositing`), so the cheapest discriminating experiment was to
turn it off and re-run:

- **11 of 20 failures disappeared** → those are the overprint delta.
- **9 kept failing with byte-identical deviation percentages** (53.201%,
  38.570%, 13.370%, …). Identical to the digit means overprint has *zero*
  influence on them. A second cause.

`git bisect run` over the 115 commits since the baselines were last touched,
with the single worst page (`GWG1610`, 53.2%) as the predicate, landed on:

```
84b591f8 fix(render): composite blended transparency groups into their own layer (#505)
```

Its own commit message says it "corrects the Ghent transparency blend-mode and
softmask test pages" — so it knew, and the baselines were never re-accepted.

## Why neither was caught

The baselines are **macOS-rendered goldens**; Linux CI rasterizes text with
different fonts/AA, so `ghent_render_test` skips the pixel diff under `CI` and
only asserts non-blank. #515's commit message states this plainly ("CI is
unaffected: the render suite's pixel diff is macOS-only"). The suite is
therefore structurally unable to catch drift — the only guard is a developer
running it locally on a Mac, and two landings in a row didn't. Worth knowing;
not fixed here.

## Visual review (the baselines-pin rule: never blanket-accept)

Sampled across both causes and all three suite folders:

| page | before | after |
|---|---|---|
| GWG1610 Softmasks Text | **near-blank** — one cyan "A" | full page; the "Actual test objects" row matches the page's own "Reference Images" row |
| GWG168 Softmasks Vector | 3 of 10 swatches, labels missing | all 10, matching the reference row |
| GWG040 White Overprint | 6 fail-marker X's visible | markers cleared on the "over spot" patches; the "over CMYK" ones remain — exactly the documented tolerated deviation |
| GWG220 Colour Conversion | X visible | X visible; backdrop darker |
| GWG161 Blend Knockout | X visible | X visible; blend colour shifted |

The softmask pages are a large correctness gain — the old baseline pinned a
**broken** render. The blend/knockout pages (GWG161/162/164/220) still print
their own fail marker both before and after: knockout groups and faithful
subtractive overprint remain unimplemented (tracked by #431 and #502), and #505
changed *how* the group composites, not whether knockout works. Accepting those
pins a more spec-correct intermediate, not a pass.

## The 38-vs-20 trap

`GHENT_UPDATE=1` re-seeded **38** baselines though only **20** were failing: 18
pages had drifted *below* the 0.05% threshold and were silently rewritten. Those
18 were restored, so the committed diff is exactly the 20 pages reviewed above.
Sub-threshold churn is unreviewed by definition, and re-seeding it would let a
genuine small regression ride in under cover of a big accepted batch.

This is the concrete form of the "a green `ghent_render_test` is not proof of
correctness" rule: the update command accepts more than the failure list.
