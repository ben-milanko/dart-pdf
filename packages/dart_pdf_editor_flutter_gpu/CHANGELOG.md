# Changelog

## 0.2.0

- Start per-submission transient GPU arenas at 4 KiB instead of 64 KiB, then
  grow geometrically through 1 MiB for dense dynamic geometry. Common tiles
  keep their single transform upload without reserving sixteen times as much
  host-visible device memory.
- Carry ordinary image tint, alpha, and stencil mode in retained vertex data
  instead of binding a separately aligned fragment uniform for every draw.
  Dense image scenes halve their pooled arena size and avoid one native bind
  call per image without changing texture sampling or PDF mask semantics.
- Pack immutable image, soft-mask, and glyph-atlas uniforms into the
  lifetime-fenced scene arena with device-required alignment. Image-dense
  scenes avoid one standalone native `DeviceBuffer` allocation per draw.
- Pin each unique image texture once per compiled scene instead of once per
  draw. Repeated image commands bypass the shared cache's lease bookkeeping,
  while distinct scenes still acquire independent lifetime-safe leases.
- Retain the image pipeline and page transform across adjacent image draws,
  reusing an unchanged texture/sampler while updating only per-image metadata.
  Intervening geometry invalidates the retained bindings.
- Retain the glyph pipeline, transform, atlas metadata, and sampler bindings
  across adjacent analytic text runs. Intervening geometry invalidates that
  state, while dense text tiles avoid five redundant native calls per run.
- Retain portable decoder RGBA only for scenes whose tiled bitmap-font images
  need a hand-built mip chain, upload those pixels directly, and release them
  after scene compilation. Ordinary images continue through zero-copy platform
  texture import; mipmapped scenes avoid a GPU-to-CPU readback per image.
- Preserve a distinct arbitrary path-clip stack for every paint in an isolated
  offscreen transparency group. Each paint rebuilds its exact stencil before
  the group alpha is resolved, rather than forcing the page onto Canvas.
- Retain every PDF blend mode between paints inside isolated offscreen groups.
  Non-Normal paints sample the group's possibly translucent destination through
  bounded ping-pong attachments before group alpha and the outer blend are
  applied once. The programmable path now implements Multiply and Screen as
  well as the advanced modes instead of falling through to Exclusion.
- Retain ordinary soft-masked images, fills, strokes, gradients, and text as
  individual paints inside transparency groups. Common opaque vector/text mask
  stacks expand into the parent with their exact stencil, composite, clip, and
  conservative blend bounds instead of forcing the whole page onto Canvas.
- Expand alpha-one nested knockout groups with a uniform declared backdrop into
  an isolated parent attachment. The seed becomes a bounded first paint and
  later siblings preserve their shape-limited source-replacement semantics.
- Import compatible platform-decoded `ui.Image` textures directly into
  Flutter GPU instead of reading their pixels back to the CPU and uploading
  them again. CPU-backed and mipmapped images keep the proven upload fallback.
- Stage proactive pipeline compilation: the context-wide idle pass now primes
  only common stencil, solid, and texture variants, while the existing live-
  scene warm-up compiles glyph, soft-mask, and destination-sampling variants
  only for pages that use them. This shortens the universal Metal warm-up
  without moving compilation back onto the first real tile.
- Retry only non-black-overprint scene rejections with a lazily re-recorded
  512-cell colourant grid. Exact scenes such as Ghent GWG164 move to native
  Flutter GPU, while any remaining mismatch continues through Canvas.
- Require the dart-pdf 4.0.0 suite and its expanded tile-backend warm-up and
  transparency interfaces.
- Keep sparse native system-font outlines on retained stencil geometry instead
  of allocating a curve atlas for fewer than 32 glyph placements. Dense text
  still uses the atlas; short Latin/CJK pages avoid its texture construction
  and driver setup while producing the same pixels.
- Render content-free interior tiles with a color-only pass that clears
  directly to the folded paper color. This avoids stencil, MSAA, host-buffer,
  and pipeline work when spatial selection proves that no retained command can
  affect the tile, while boundary tiles keep the exact antialiased paper path.
- Replace Flutter's four-frame `HostBuffer` in tile submissions with a
  completion-fenced single-submission arena. It starts at 64 KiB, grows from
  256 KiB to 1 MiB only for dense dynamic geometry, validates the full aligned
  emplacement before every write, and fixes CAD hairline pages that could
  cross Flutter 3.47's 1,024,000-byte block boundary and throw. An ordinary
  tile now reserves 64 KiB instead of 4,096,000 bytes.
- Discard exactly transparent advanced-blend source texels before sampling the
  backdrop or evaluating the PDF blend equation. The destination is already a
  native copy of that backdrop, so sparse sources avoid redundant fragment
  reads, arithmetic, and writes without changing the resolved pixels.
- Pool retained geometry in power-of-two size classes starting at 64 KiB
  instead of rounding every scene up to 16 MiB. Dense scenes still flush at
  the existing 16 MiB arena boundary and all active buffers remain under the
  same hard byte budget.
- Retire a GPU session to the viewer's exact Canvas fallback when one tile
  selects at least 128 paint units containing positive-width strokes that
  resolve below the 0.25 px coverage quantum of 4x MSAA. This prevents dense
  CAD linework from becoming faint or disappearing at low zoom while isolated
  subpixel strokes retain the established GPU parity and routing.
- Retain positive-width vector strokes under image and axial-gradient soft
  masks, including dashed caps and joins. Zero-width masked hairlines remain
  on the exact Canvas fallback because their geometry depends on tile scale.
- Retain a single ordinary soft-masked source nested inside a transparency
  group by resolving the mask in one bounded offscreen target before applying
  the enclosing group alpha. Explicit backdrops, non-Normal internal blends,
  enabled overprint, and additional paints remain exact Canvas fallbacks.
- Treat paints behind a provably empty rectangular clip as no-ops while
  parsing transparency groups, carrying that clip state through save/restore
  and balanced soft-mask structures. Empty group content no longer forces an
  otherwise supported page onto Canvas.
- Retain arbitrary content-side path clips for a single soft-masked source,
  including the single-image transparency-group route. The resolved source is
  constrained by the existing exact stencil clip instead of requiring an
  axis-aligned shortcut.
- Retain arbitrary path clips inside a single-image soft-mask transcript when
  the alpha/luminosity backdrop and transfer function prove that the mask is
  zero outside the clip. Non-zero outside-mask values remain on Canvas.
- Retain arbitrary path clips around one fill, stroke, text run, image,
  gradient, or mesh inside a single-paint transparency group.
- Consume `pdf_graphics` exact region-clipped spatial overprint strokes as
  ordinary retained clip and stroke commands. Three additional Ghent pages
  stay on the GPU path; unresolved non-black overprint remains on Canvas.
- Preserve shared and per-paint arbitrary path clips while flattening
  alpha-one Normal transparency groups, and keep sub-cell strokes visible to
  the colorant compositor before exact vector replay. One additional Ghent
  transparency page stays on the GPU path.
- Keep sub-cell embedded glyphs represented in the colorant compositor so one
  additional Ghent overprint page stays on the GPU path. Sub-cell multi-glyph
  and unresolved process-color cases remain conservative Canvas fallbacks.
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
