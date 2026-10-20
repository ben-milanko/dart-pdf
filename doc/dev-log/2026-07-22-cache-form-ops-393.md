# 2026-07-22 — cache parsed content ops for forms/appearances/masks (#393)

Tiling patterns and Type3 CharProcs already cached their parsed
`List<ContentOperation>` in the interpreter's `_patternOpsCache` (keyed by
`CosStream` identity). Form XObjects, annotation appearance streams, and
soft-mask groups did not — they ran `cos.decodeStreamData(...)` +
`ContentStreamParser.parse(...)` on **every** use, so a symbol-library form
drawn N times cost 2N filter-decodes + 2N parses per render (image-collect
pass + paint pass), and again on every re-render (zoom, page-colour,
thumbnail).

## Change

`_patternOpsCache` → `_opsCache`, generalised into one decode+parse memo, and
a `_parsedOps(CosStream)` helper that all three previously-uncached sites now
route through:

- `_drawAppearance` (annotation appearances)
- `_runSoftMaskForm` (soft-mask groups)
- `_doXObject` (form XObjects)

The pattern/CharProc sites keep using the same map directly (renamed only).

## Why it's safe

- The cache is a **per-interpreter instance** field, so it never outlives a
  single render — no cross-edit staleness. And stream identity changes when an
  edit rewrites content (the editor builds new `CosStream` objects), so even a
  reused interpreter can't serve stale ops.
- The cached list is **read-only**: `_run` only reads its operations. The
  pattern/CharProc paths already relied on this exact invariant, so reusing the
  list across the appearance/mask/form draws is equally safe.
- `_parsedOps` returns null on decode failure (not cached), preserving the
  original early-return behaviour at each site; the `_doXObject` return stays
  inside its `try`, so the `device.restore()`/state-pop `finally` still runs.

## Verified

- `pdf_graphics` full suite (881) green — the pure-Dart Ghent + PDF.js
  interpret passes exercise every form/appearance/mask draw.
- `dart_pdf_editor` Ghent **render** baseline test: no new pixel diffs. The one
  hard failure (GWG030, spot/overprint) reproduces identically on the base
  commit — pre-existing, unrelated. Parsed ops are deterministic, so caching is
  pixel-neutral by construction.

## Ticket

Closes **#393**. Independent of #392 (decoded stream-bytes cache): this memoises
the *parse*, #392 would memoise the *decode*. They compose — with #392 the
`decodeStreamData` inside `_parsedOps` becomes a cache hit too — but neither
blocks the other.
