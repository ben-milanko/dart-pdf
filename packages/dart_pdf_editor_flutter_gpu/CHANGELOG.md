# Changelog

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
