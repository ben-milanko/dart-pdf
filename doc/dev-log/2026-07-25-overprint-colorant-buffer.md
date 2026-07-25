# Faithful overprint: the CMYK/spot colorant buffer (issue #502)

Third and last session on overprint, after `2026-07-22-overprint-state.md`
(parsing `/OP` `/op` `/OPM` into the graphics state) and
`2026-07-23-overprint-compositing.md` + `2026-07-23-overprint-rgb-ceiling.md`
(the `BlendMode.darken` approximation, and the measurement showing it is the
RGB optimum). This session builds the thing those two concluded was needed:
a real colorant buffer. GWG030 now renders with **all twelve** self-grading
patches uniform and leaves `_knownBaselineDeviations`.

## Why RGB could not close it

Overprint is defined over *device colorants*: an overprinting paint writes
only the colorants its colour space specifies and leaves every other colorant
of the backdrop alone. GWG030's trap is that its two backdrops - a DeviceN
spot green and a `.5 0 1 .5 k` DeviceCMYK green - are **the same sRGB pixels**
and must overprint differently. A compositor that sees only the RGB backdrop
cannot tell them apart, so no blend mode can be right for both. That is the
ceiling the previous session measured.

## Where the fix sits

Not in the device. The colour spaces are still known one layer up, in the
interpreter, so overprint is resolved there and painting devices receive an
already-composited colour:

```
interpreter --(colorants)--> PdfOverprintCompositor --(resolved sRGB)--> device
```

Three new pure-Dart pieces in `pdf_graphics` (no `dart:ui`, so the VM, the
render worker and the web all agree, and the canvas and strip devices agree by
construction because they get the same colour):

- **`colorants.dart`** - `PdfColorants` (four process tints plus a sorted list
  of named spot colorants) and `PdfInkColorants` (a paint's colorants plus the
  overprint semantics of its space). `PdfInkColorants.over(backdrop, mode)` is
  the whole of overprint in one method.
- **`raster/colorant_raster.dart`** - the buffer's storage: a page-sized grid
  of palette indices with its own scanline rasterizer over the existing
  `flattenPath` / `strokeToContours`, plus a clip. Binary coverage, cell
  centres, 384 px on the long side. It never reaches a screen; it only answers
  "what colorants is this draw landing on", so it needs no AA and no colour.
  Backdrop selection is by **area share** - an index covering under 4% of a
  draw is boundary bleed from the region next door, not a backdrop - which is
  what makes the answer independent of the grid's resolution. (A fixed
  one-cell erosion was tried first and is resolution-sensitive in exactly the
  wrong way: it ate small shapes whole as the grid coarsened, and GWG030's
  patches started failing below 512.)
- **`overprint_compositor.dart`** - the policy. Every draw records the
  colorants it leaves behind; an overprinting draw reads the distinct backdrop
  vectors under its own coverage, composites each in ink space, and returns the
  colour when they all agree.

`PdfColorSpace.inkColorants(values)` is the new reading: DeviceCMYK and
DeviceGray decompose into process colorants, Separation/DeviceN into the
colorants they name (`_TintColorSpace` now keeps its colorant names, which it
previously discarded), and everything else returns null - an RGB-ish or ICC
colour has no colorant decomposition, and inventing one would knock backdrops
out that a real separations device leaves alone.

## The rule that keeps it pixel-exact

Converting a composite colorant vector back to sRGB is the obvious place to
introduce a shade of drift - and a shade of drift *is* a visible marker on a
self-grading patch. So the compositor prefers an exact answer over a round
trip:

- composite == the backdrop's colorants → reuse the **backdrop's** rendered
  colour (the "over spot" patches: the overprint changed nothing, so it must
  be invisible);
- composite == the ink's own colorants → reuse the **ink's** colour (the "over
  CMYK" knockouts: the result is the ink painted over nothing, which the page
  also paints elsewhere);
- otherwise → `colorantsToSrgb`, the separations-preview model (spot
  equivalents from the space's own tint transform, accumulated per process
  channel and clamped).

On GWG030 the third branch never fires, which is why every patch comes out
exactly flat rather than nearly flat. The palette is keyed by
(colorants, colour) rather than colorants alone: `0 0 0 .5 k` and `.5 g` are
the same colorant vector but different sRGB, and collapsing them would have
made a patch's own base fill disagree with its marker.

## Where it declines

The buffer models opaque, Normal-blend painting onto the page. Anything else
records "colorants unknown" over its coverage, and an overprint landing on
unknown returns null - leaving the device's `darken` stand-in exactly as it
was. That covers images, shadings, meshes, tiling patterns, translucent paint,
non-Normal blends, transparency groups (bracketed with
`beginIsolated`/`endIsolated`), text (marked by its em box - see the cost
section), and colour spaces with no colorant reading. A soft-mask *form*'s own
content is not recorded at all: it becomes an alpha channel, not page ink. It
also declines when the composite is not one colour across the draw, because a
device paints one colour per call.

## Cost, and how it was brought down

The buffer is built only for a page that actually enables overprint -
`_declaresOverprint` walks the resource tree's ExtGStates for `/OP` or `/op`
true (bounded in depth and breadth) before interpreting. Deriving colorants in
the colour operators is guarded on the buffer existing, so `g`/`k`/`sc` stay
allocation-free everywhere else, and `resolveOverprint: false` turns the whole
path off for consumers that never look at colour (text extraction; the
image-collect scan disables it automatically). `PdfInterpreter.
debugResolveOverprint` is the process-wide kill switch, used by the guard test
and the A/B harness. Past 20 000 rasterized draws the compositor stops
resolving rather than slowing a pathological page down.

That gate turned out to be far weaker than it sounds: **most of the Ghent
corpus declares overprint**, because `/op` is routinely set defensively, so
"only pages that use it" is ~40 of 54 pages. The first working version measured
**`interpretMs` 4.2x** (`tool/perf.sh diff HEAD ghent-suite-open`) - not
shippable. `tool/bench_overprint_buffer.dart` (new; A/Bs
`debugResolveOverprint` over a corpus, which makes the buffer's cost
attributable in isolation) drove four fixes:

- **The clip became a box**, with a mask only for a clip path that is not a
  rectangle. This was the single worst offender by a distance: a page-sized
  `Uint8List` allocated and zeroed per `W n`, and real content clips
  constantly.
- **Text is marked by its em box**, not its glyph outlines. Rasterizing
  outlines is the most expensive thing the buffer could be asked to do, and
  over-marking only sends a later overprint back to the device approximation.
- **A rectangle fast path** in `fillSpans`: an axis-aligned rectangle needs no
  flattener, no edge table and no scanline, and it is what pages overwhelmingly
  fill and clip to. Extending it to cubics whose control points sit on their
  endpoints matters more than it sounds - the GWG patches build every box out
  of `m/v/v/v/v/h`, so without it the pages that use this buffer were the ones
  taking the slow path.
- **A soft-mask form's own content is muted** rather than recorded: it never
  puts colorants on the page (it becomes an alpha channel), so recording it was
  both wrong and expensive. The rasterizer's edge/crossing lists and span
  builder are reused across draws too.

Resolution turned out **not** to be the lever it looked like - 256 and 384
measure the same - so it sits at 384 for fidelity headroom.

### Where it landed, honestly

`perf.sh diff HEAD ghent-suite-open` still reports **REGRESSED**:
`interpretMs` 1.55x median, `firstPageMs` 1.22x median, with the outliers being
exactly the pages that use the feature (GWG010 3.2x, GWG030 3.1x, GWG040 3.8x,
GWG161 3.2x). `openMs`, `extractMs`, `saveMs` and `peakRssBytes` are unchanged,
the deterministic counter gate is unmoved (12 inputs, 13 counters within 3%),
`perf_gate_test` and the `PDF_PERF=false` DCE proof pass, and the scenario's
own budget passes with room to spare - **p95 interpret 23ms against a 150ms
budget**.

So: interpretation of a page that declares overprint costs more, materially so
on pages that actually overprint, and interpretation is one phase of a render
that rasterization dominates. That is the price of the feature as built, and it
is confined to the pages that need it (`resolveOverprint: false` opts a
consumer out entirely; text extraction and the image-collect scan already do).

The obvious next cut, if it becomes worth it: **defer the recording**. Most
declaring pages never resolve a single draw - they set `/op` and paint over
white - yet they pay for the buffer on every draw. Logging draws as an ordered
op list (clip / save / restore / paint) and only rasterizing it when the first
draw actually needs a backdrop would make those pages free and cost the rest
nothing but the deferral.

## A leak fixed on the way

Overprint used to be delivered to the device only from `gs` and `Q`. A form
XObject, a tiling-pattern cell and a soft-mask group each start from a fresh
graphics state *without* a `Q`, so overprint switched on inside one stayed
switched on for everything drawn after it. `_paint` now re-syncs the tuple
before every fill and stroke through `_deliverOverprint` (which no-ops when
unchanged), which both closes that leak and carries the case this session
needs: a resolved draw is delivered with its flag **cleared**, because the
composite is already in the colour. GWG041's patch b is the visible proof -
its near-white cross used to be swallowed by a leaked `darken` and painted the
red cross underneath solid; it now paints white as written.

## Measured effect on the Ghent suite

Every page rendered before and after, same platform, and diffed. **13 pages
change, all overprint pages**, and every one is an improvement:

| page | before → after |
|---|---|
| GWG030 Gray Overprint Patch | 3 markers → **0 of 12** |
| GWG040 White Overprint Patch | 3 markers → **0 of 12** |
| GWG041 White Overprint Mode | solid red X → gone (AA fringe only) |
| GWG011 CMYK Overprint Mode | OPM-0 X gone; OPM-1 X down to AA fringe |
| GWG010 CMYK Overprint Test | both vector patches → uniform |
| GWG190/191/192 DeviceN Overprint | **both vector patches solid** on all three |
| CMYK / SPOT master pages | the panels above, same result |
| GWG020 | max delta 2/255 (below tolerance) |
| GWG031 Gray Image Overprint | unchanged in substance (image overprint is out of scope) |
| GWG161 Transparency Blend Modes | the leaked-overprint darkening above, removed |

Note the A/B is against the *rendered* pages, not the baselines: every Ghent
page was rendered before and after on the same machine and diffed, because the
checked-in baselines are macOS renders and the suite's pixel diff is skipped on
Linux.

GWG190/191/192 stay in `_knownBaselineDeviations`: their *image* patches still
grade as failing, because decoded pixels carry no colorant reading, so an image
neither overprints nor is overprinted onto. Their note now says which half was
fixed. GWG192 also confirmed a spec detail the fixture grades directly - the
overprint-mode-1 zero rule is **DeviceCMYK's alone** (§8.6.7.3); applying it to
a Separation/DeviceN is exactly the "colour space was converted to DeviceCMYK
upfront (OPM 1)" failure its patch c flags. DeviceGray likewise ignores OPM,
which is what GWG030's patches e and k grade.

`_resolveInk` deliberately mirrors `_resolveScn`'s leniency: GWG011 issues
`0.9 0.1 0.9 0 sc` with no matching `cs`, and the colour falls back to a
DeviceCMYK reading by operand count, so the colorants must too - otherwise the
paint looks colorant-less and everything over it declines.

## Baselines

Seven pixel-enforced baselines change with this render and were re-seeded:
GWG010, GWG011, GWG030, GWG031, GWG040, GWG041, GWG161. They were first
deleted for the maintainer to re-seed - the suite's baselines are documented as
macOS renders and the pixel diff is skipped on Linux - but after merging main's
baseline re-accept (#597) the whole Ghent suite passes byte-clean on this Linux
machine, i.e. every one of the ~37 other pixel-enforced baselines already
matches what this environment renders. Seeding the seven here is therefore
equivalent to re-seeding on the reference machine, and it keeps GWG030
pixel-enforced from the moment this lands rather than on someone's next
`GHENT_UPDATE=1` run.

## Tests

- `pdf_graphics/test/colorant_buffer_test.dart` (new): the composite rule per
  colour space and mode, the colorant readings, and the compositor itself -
  including the one-assertion statement of the whole problem ("a spot backdrop
  and a process backdrop of one colour diverge").
- `dart_pdf_editor/test/overprint_render_test.dart`: rewritten from the
  neutral-fraction measure into a per-patch flatness + colour check across
  three compositing modes (colorant buffer / darken only / neither). The old
  patch boxes overlapped their neighbours, which the coarser metric had
  tolerated; they are re-derived and inset. It now pins that all twelve
  markers vanish, that the nine "no new colorant" patches settle on the
  backdrop green and the three knockouts on a neutral, that none of them is
  flat without overprint, and that `darken` alone still cannot reach d/e/k -
  the ceiling this buffer removes, kept as a live assertion.
- `pdf_graphics/test/overprint_test.dart`: header rewritten; interprets with
  `resolveOverprint: false` so it keeps pinning the parsed state rather than
  the (deliberately flag-cleared) resolved delivery.
- `ghent_render_test.dart`: GWG030 removed from `_knownBaselineDeviations`.

## Still out of scope

Image overprint (GWG031, and the image halves of GWG190/191/192): a decoded
raster has no colorant reading, so it neither overprints nor accepts overprint.
Doing it means carrying colorants per pixel through image decode - a much
larger change, and the natural follow-up if those patches ever matter.
