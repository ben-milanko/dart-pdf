# flutter_gpu tile encoder: BindingSet for pass-stable resources (#1267)

Flutter 3.50's `flutter_gpu` adds `GpuContext.createBindingSet` and
`RenderPass.bindSet`. Reading the native `RenderPass::Draw`
(`bin/cache/pkg/flutter_gpu/render_pass.cc`) shows where the cost actually
was. The bind *call* wasn't it.

## What the native pass does

- **Individual binds are replayed on every draw, and allocate each time.**
  `bindUniform`/`bindTexture` entries sit in per-stage maps until
  `clearBindings`. Every `draw` replays each one through `BindDynamicResource`
  with a `std::make_unique<ShaderMetadata>(copy)`: one heap allocation plus a
  metadata copy per bound resource, per draw.
- **Those maps are keyed by the shader's uniform struct, not by slot.** A tile
  that touches the solid, stencil and texture pipelines without a clear
  therefore replays all three `VertInfo` transforms on every later draw.
- **Set entries replay with borrowed metadata.** They go through
  `BindResource`, which doesn't allocate. Sets are applied before individual
  binds, so an individual bind overrides a set.
- **A set applies by stage + binding index, whatever pipeline is bound.** So
  there is one set per pipeline; a single shared set would collide.
- **Set uniforms must be `DeviceBuffer` views.** `_GpuTransientArena` and the
  geometry arena already are, so the per-tile `transform` and a glyph atlas's
  `info` qualify.

## What changed (`backend_native.dart`, `_GpuEncoder`)

- **Tile transform:** every `bindUniform(pipelines.*Transform, transform)` is
  now `bindSet(_transformSet(slot))`. That is one set per pipeline per pass,
  created lazily.
- **Glyph draws:** they bind `_glyphSet(atlas)`, one set per atlas per pass
  holding transform, `GlyphInfo` and the atlas texture (nearest sampler).
- **Still bound individually**, because a set per draw would cost more than
  it saves:
  - blend and soft-mask info, which is emplaced per draw;
  - image textures (the identity check already skips most of these rebinds);
  - offscreen group, copy and blend textures.
- **Every clear goes through `_clearBindings()`.** It also resets the
  `_individualBindings` tracker. `clearBindings` empties set slots too; that is
  fine, because every encode path rebinds its pipeline and slot-0 set on entry.
- **`_GpuPipelines` now keeps its `context`** so the encoder can create sets.
  Pipelines are already cached per context.

## Counters (`FlutterGpuTileBackendStats`)

- `bindingSetsCreated` and `bindingSetBinds`.
- `dynamicBindingReplays`: summed over draws, the individually bound resources
  each draw replays. This is the deterministic proxy for the native cost
  removed.

`tool/gpu_corpus_summary.dart` shows the last two rows once both sides of a
comparison report them. The base revision did replay individual bindings, it
just didn't count them, so a missing value is not treated as zero.

## Floor

`dart_pdf_editor_flutter_gpu` now needs `flutter: '>=3.50.0'`, because
`gpu.BindingSet`/`gpu.TextureBinding` don't exist on 3.47. The package is 0.x
and isn't covered by `floor-analyze`.

## Verification

- This Linux sandbox has no Impeller context, so the GPU tests self-skip.
- The real gates are the macOS Metal `flutter-gpu-smoke` +
  `gpu_corpus_test.dart` lanes, which check GPU/Canvas pixel parity on every
  accepted Ghent/PDF.js page, plus the same-host first-tile A/B in the "Flutter
  GPU validation" PR comment.
- The unit tests assert two invariants: glyph + solid scenes replay no
  individual binding, and image scenes replay at most one per texture draw.
