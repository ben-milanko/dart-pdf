# Changelog

## 0.2.0

- Require the dart-pdf 4.0.0 suite and its expanded tile-backend warm-up and
  transparency interfaces.

- Render content-free interior tiles with a color-only pass that clears
  directly to the folded paper color. This avoids stencil, MSAA, host-buffer,
  and pipeline work when spatial selection proves that no retained command can
  affect the tile, while boundary tiles keep the exact antialiased paper path.
- Discard exactly transparent advanced-blend source texels before sampling the
  backdrop or evaluating the PDF blend equation. The destination is already a
  native copy of that backdrop, so sparse sources avoid redundant fragment
  reads, arithmetic, and writes without changing the resolved pixels.
- Initialize tiles wholly inside the transformed crop box with the folded
  opaque paper color in the render-pass clear, skipping the transparent clear
  and full-tile paper draw. A one-device-pixel guard keeps rotated and
  translucent page boundaries on the exact antialiased-quad path.
- Keep intermediate transparency-group targets single-sample while retaining
  4x MSAA on the final page target. This removes a redundant color/stencil
  raster and resolve, cuts live group attachment estimates from 40 to 8 bytes
  per pixel, and preserves diagonal-edge parity with Canvas.
- Flatten nested alpha-one, normal source-over groups into their parent
  retained group, preserving distinct per-paint clips without a nested render
  target or Canvas fallback.
- Run requested scene warm-up for route-change benchmarks, matching the
  viewer's idle-prepared production path while suppressing the unmatched timing
  marker when the Canvas base has no GPU session.
- Add a deterministic repeated-advanced-blend CI workload whose twelve ordered
  destination-sampling passes provide a higher-signal same-host comparison for
  future blend optimizations.
- Coalesce consecutive same-mode straight strokes into one exact advanced-blend
  source and destination-sampling pass when conservative raster-space capsules
  prove that no resolved pixel can contain both strokes. The mixed group/blend
  benchmark now uses two advanced passes per tile instead of thirteen while
  overlapping strokes retain ordered passes.
- Rasterize advanced-blend sources into page-pixel-aligned cropped attachments
  when their conservative union occupies at most half the tile. The full-sized
  backdrop ping-pong targets remain byte-exact, while the blend shader remaps
  the bounded source coordinates; padded offscreen groups and low-LoD
  hairlines stay inside the crop.
- Retain solid-black overprint paints inside single- and multi-paint
  transparency groups, matching the existing exact top-level path. Unsafe
  process-color, gradient, and mesh overprint still fall back to Canvas and
  now report that cause instead of a generic group rejection.
- Retain axial/radial gradient and Gouraud mesh paints in single-paint and
  mixed offscreen transparency groups.
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
  paints share one blend pass, while overlapping paints retain painter order
  and scissor each sequential shader draw to its conservative command bounds.
  Preserve the untouched ping-pong destination with a byte-exact GPU texture
  blit instead of a full-tile textured draw before every advanced blend.
  Offscreen groups can now coexist with those destination-sampling paints in
  exact painter order and can use one advanced outer blend themselves;
  oversized tiles keep the conservative Canvas fallback.
- Retain isolated knockout groups made entirely from vector fills. Later
  sibling shapes use exact source replacement only inside their retained path,
  while the group's alpha and outer blend remain a single offscreen composite.
- Retain opaque non-isolated knockout groups whose declared backdrop is one
  uniform color. The bounded single-sample group target is seeded with that
  color and clipped to the form BBox, preserving exact Canvas output for
  ordered vector fills and strokes without admitting unsafe overprint.
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
