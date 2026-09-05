# Changelog

## 0.3.1

- Report full-page raster warm-up support to `dart_pdf_editor` via the new
  `supportsFullPageRasterWarmUp` backend getter, so document raster warming can
  use the GPU route where it is available.
- Make deterministic GPU buffer reuse stable under benchmarking.
- Require the dart-pdf 4.2.0 package suite. No public constructor or rendering
  entry point was removed.

## 0.3.0

- Greatly expand exact retained-GPU coverage for blends, transparency groups,
  soft masks, gradients, images, stroked text, overprint, and knockout groups,
  while preserving the Canvas fallback for unsupported or inexact scenes.
- Reduce GPU allocation and submission overhead with completion-fenced buffer
  and attachment pools, compact transient arenas, scene-level texture leases,
  retained bindings, and bounded advanced-blend source targets.
- Import compatible platform-decoded image textures directly, keep mipmapped
  fallback pixels only when needed, and accelerate MRC JPEG 2000 rendering on
  supported Apple devices.
- Add proactive pipeline and live-scene warm-up, exact high-resolution
  colourant retries, off-crop command culling, and deterministic route and
  performance diagnostics.
- Keep dense CAD linework conservative at subpixel scale, retain more exact
  hairlines and clipped vector content, and fix lifetime hazards around
  in-flight GPU resources.
- Require the dart-pdf 4.1.0 package suite. No existing public constructor or
  rendering entry point was removed.

## 0.2.0

- Require the dart-pdf 4.0.0 suite and its expanded tile-backend warm-up and
  transparency interfaces.

- Run requested scene warm-up for route-change benchmarks, matching the
  viewer's idle-prepared production path while suppressing the unmatched timing
  marker when the Canvas base has no GPU session.
- Preserve per-paint Normal, Multiply, and Screen state inside isolated
  offscreen transparency groups.
- Retain ordinary images in single-paint and mixed vector/text transparency
  groups, reusing the scene texture cache and the exact offscreen group pass.
- Retain outlined text in single-paint and mixed vector transparency groups,
  including clipped isolated groups that require the exact offscreen tile
  pass for group alpha and outer blending.
- Retain exact macOS CJK substitutions for Songti, Heiti, Hiragino Sans, and
  Hiragino Mincho, including CFF outlines inside OpenType collections. Six
  additional PDF.js corpus pages now stay on the GPU, with a dedicated CJK
  same-host scenario.
- Render every PDF blend mode exactly with retained GPU destination sampling.
  Advanced modes use bounded ping-pong tile attachments; provably disjoint
  paints share one blend pass, while overlapping paints retain painter order.
  Oversized tiles and scenes that combine advanced blends with offscreen
  transparency groups keep the conservative Canvas fallback.
- Retain isolated knockout groups made entirely from vector fills. Later
  sibling shapes use exact source replacement only inside their retained path,
  while the group's alpha and outer blend remain a single offscreen composite.
- Retain isolated knockout groups containing a base fill and one
  vector-soft-masked fill, including clipped vector mask bounds.
- Render overlapping Normal paints in isolated transparency groups into a
  shader-readable tile attachment, then apply group alpha and outer blend once
  when sampling it into the page pass.
- Elide zero-alpha and zero-area transparency groups before GPU auditing;
  their composite alpha or form BBox clip makes all nested paints exact
  no-ops.
- Retain non-Normal transparency groups whose padded fill bounds are provably
  disjoint, preserving exact outer blending without an offscreen surface.
- Treat C1 controls as non-rendering glyph placements in the exact native
  outline seam, matching Flutter shaping while preserving their PDF advances.
- Retain stroke-only and fill-plus-stroke outline text, including page-space
  alpha and zero-width hairlines, by reusing the exact path stroke pipeline.
  Filled glyphs keep the analytic atlas while their stroke overlays in painter
  order.
- Retain ordinary filled text as six-vertex glyph quads backed by a
  scale-independent analytic curve atlas. The shader derives device scale per
  tile, eliminating repeated flattened outline fans across LoDs while exact
  stencil rendering remains the automatic fallback for unsupported glyphs.
- Add an exact substituted-text outline seam for the retained backend. Hosts
  can resolve their registered TrueType/TTC bytes directly, while the opt-in
  native adapter probes the standard platform substitution faces and declines
  any unavailable, complex-shaped, or unplaceable run. Add the same-host
  system-font route-change benchmark to the Metal CI matrix.
- Render zero-width PDF hairlines as exact one-device-pixel contours generated
  for each tile LoD, while retaining the flattened source path with the scene.
- Collapse isolated transparency groups containing one clipped vector fill or
  stroke into retained stencil geometry, preserving group alpha and the
  group's page blend mode without an intermediate texture; one-element
  knockout groups use the same exact path because they have no sibling elements
  to knock out. Alpha-one, normal-blend non-knockout groups can retain multiple
  ordered fills and strokes because source-over is associative.
- Render platform-decoded images with deferred `/SMask` companion surfaces on
  the GPU by caching both textures and combining them in the soft-mask shader.
- Combine a single vector fill with one opaque grayscale image soft mask in a
  retained stencil pass. Rectangular vector-mask fills, including alpha or
  luminosity `/BC` and linearized `/TR`, stay entirely in retained geometry.
- Render Multiply and Screen exactly with fixed-function blending over the
  backend's opaque page surface.
- Warm the nonzero stencil-cover render state used by retained fills, moving
  its first-use Metal compilation into the existing idle pipeline phase.
- Render tiled stencil images exactly using scene-scoped, hand-built mipmaps.
  Mip levels participate in the shared texture budget and cache identity, and
  worker-reconstructed tiling cells retain their decoded images.
- Warm every tile shader with a one-pixel idle submission, shared per Impeller
  context and MSAA mode, then compile and submit each live page's retained
  scene at one-pixel scale. Both passes wait for useful pixels plus a 750 ms
  quiet window, so first-use driver, geometry, and upload work does not land on
  the first deep-zoom tile or contend with immediate navigation. Proactive
  warm-up defaults to desktop; mobile stays on-demand unless the host opts in,
  avoiding a large idle context allocation on memory-constrained devices.
- Benchmark tiling-pattern and radial-shading pipeline warm-up, scene warm-up,
  first GPU tiles, and Canvas parity three times on the designated macOS
  Metal CI lane. PRs receive a main comparison with details collapsed beneath
  the headline, and retain the normalized trace as a downloadable artifact.
- Accelerate exact vector tiling cells, axial gradients (including embedded
  outline text), and nested-circle radial gradients while retaining explicit
  Canvas fallback for unsafe variants.

## 0.1.6

- Align the experimental Flutter GPU backend with the 3.8.0 package suite. No
  public GPU API changes since 0.1.5.

## 0.1.5

- Align the experimental Flutter GPU backend with the 3.7.0 package suite.

## 0.1.4

- Isolate pipelines, geometry buffers, and image textures by Flutter GPU
  context so native windows never reuse resources owned by another view.
- Keep image-texture leases alive until in-flight command buffers complete,
  preventing stale blocks or unrelated fragments after structural edits.
- Report context identities and switches in the backend diagnostics.

## 0.1.3

- Rebuild the packaged shader bundle with Flutter 3.47's `impellerc` so the
  runtime accepts the new bundle format.

## 0.1.2

- Support both the Flutter 3.44 and 3.47 `flutter_gpu` APIs after shader
  loading became asynchronous and draw vertex counts moved to `draw`.

## 0.1.1

- Fall back to the Canvas renderer for deferred image soft masks that the GPU
  backend cannot yet reproduce exactly, preserving correct output on Impeller.

## 0.1.0

- Render final GPU tile textures directly and admit one per repaint, avoiding
  deferred slab-to-tile texture-copy bursts. Track synchronous issue time and
  command-buffer completion latency, failures, and in-flight submissions.
- Render ordinary non-rectangular PDF clip stacks exactly with retained
  stencil geometry, including nested even-odd/nonzero clips and save/restore;
  rectangular clips keep the cheaper scissor path.
- Report compiled clip paths and per-tile clip-mask rebuilds in backend stats.
- Add an opt-in Impeller `flutter_gpu` backend for retained-scene LoD tiles.
- Retain geometry and byte-budgeted image textures across tile renders and
  combine supported image soft masks directly in the tile shader.
- Pack command-heavy CAD geometry into backend-wide reusable 16 MiB device
  buffers under a strict byte budget, releasing leases only after GPU work
  completes and falling back instead of overshooting the ceiling.
- Fall back to the Canvas backend for unsupported pages and expose a web stub
  that preserves the same host API.
- Expose JSON-safe diagnostics for the latest tile route, accepted/rejected/
  active sessions, runtime fallbacks, compile/replay timings, cache pressure,
  uploads/readbacks, and live GPU resource leases.
