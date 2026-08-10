# Changelog

## 0.1.0

- Add an opt-in Impeller `flutter_gpu` backend for retained-scene LoD tiles.
- Retain geometry and byte-budgeted image textures across tile renders and
  combine supported image soft masks directly in the tile shader.
- Pack command-heavy CAD geometry into backend-wide reusable 16 MiB device
  buffers under a strict byte budget, releasing leases only after GPU work
  completes and falling back instead of overshooting the ceiling.
- Fall back to the Canvas backend for unsupported pages and expose a web stub
  that preserves the same host API.
