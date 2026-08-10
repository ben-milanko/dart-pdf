# Changelog

## 0.1.0

- Add an opt-in Impeller `flutter_gpu` backend for retained-scene LoD tiles.
- Retain geometry and byte-budgeted image textures across tile renders and
  combine supported image soft masks directly in the tile shader.
- Fall back to the Canvas backend for unsupported pages and expose a web stub
  that preserves the same host API.
