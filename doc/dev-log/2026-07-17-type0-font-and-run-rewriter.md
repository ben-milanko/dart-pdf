# One `Type0Font` module + one `TextRunRewriter` (issue #312)

Two entangled duplications in the content-edit stack are collapsed into two
reusable modules. No behaviour change — the win is deletion and testability.

## The duplications (before)

1. **Type0 knowledge** — "a content code is a 2-byte glyph id; text from
   `/ToUnicode`; width from `/W`" was restated in four places:
   `type0_metrics.dart` (parse helpers), `content_elements.dart`'s
   `_Type0Decode` (extraction), `content_editor_type0.dart`'s `_Type0Editing`
   (editing), and `content_reflow.dart`'s `_Type0ReflowFont` adapter. The
   Identity-H/CIDFontType2 eligibility gate lived only in the editor; the
   extractor decoded any Type0 loosely.
2. **The run-rewrite engine** — flatten `Tj`/`TJ` into (glyph | kern) cells,
   find boundary-aligned matches, splice, append a compensating kern
   (`newWidth − oldWidth`), coalesce back to `Tj`-or-`TJ` — was maintained
   three-plus times (simple `_rewriteTextRun`, styled `_rewriteStyledTextRun`,
   Type0 `_rewriteInPlace`, Type0-fallback `_rewriteWithFallback`), differing
   only in cell granularity and glyph encoding. `_replaceText` branched between
   engines inline.

## `Type0Font` — `type0_font.dart` (new)

One object built once from a font dict, with the eligibility check as its
construction contract:

- `Type0Font.decode(cos, dict)` — **lenient**, never null: builds the
  code→text (`/ToUnicode`) and code→width (`/W`+`/DW`) maps for any Type0
  font. Extraction (`content_elements.dart`) consumes this.
- `Type0Font.forEditing(cos, dict)` — **strict**: enforces Identity-H /
  CIDFontType2 / Identity-CIDToGIDMap / embedded-program / usable-`/ToUnicode`
  and parses the program, or returns null. A non-null result *is* the
  guarantee the font can be edited. Editing and reflow consume this.
- Editing surface: `glyphForRune`, `advanceForGlyph`, `measure`,
  `recordGlyph` (records new gid→rune), `encodeIdentity` (reflow line encode,
  null when a glyph is missing), `pickFallback`, and `commitFontDict(updater)`
  which flushes `/W` + `/ToUnicode`.

The three parse helpers (`parseToUnicodeCmap`, `parseCidWidths`,
`cidDefaultWidth`) moved here from the deleted `type0_metrics.dart`.

Document plumbing that a pure font model can't own — allocating a fallback
page `/Font` resource, materializing page resources — stays in the editor
(`_Type0RunEditor` in `content_editor_type0.dart`), which is now thin.

## `TextRunRewriter` — `content_run_rewriter.dart` (new, standalone lib)

The flatten→align→match→splice→kern→coalesce skeleton, parameterized by a
`RunCodec`. Kept free of any document/editor dependency so the kern and
coalescing math is unit-testable against a fake codec.

- Output model: `Emit` = `CellEmit` (a coalescable glyph/kern cell) or
  `OpEmit` (a literal operator that acts as a barrier — flushes pending cells
  before it). This one model expresses both the inline rewrites *and* the
  bracketed styled/fallback rewrites: the `Tf`/colour operators are barriers,
  the surrounding text coalesces around them.
- `RunCodec.coalesce` is the shared cell→show-op coalescer (single unchanged
  `Tj` stays a `Tj`, adjacent kerns sum, hex flag preserved).

The four rewriters became four small codecs over the one engine:

- `_SimpleRunCodec` — one byte per glyph, plain show strings
  (`content_editor.dart`).
- `_StyledRunCodec` — the simple codec plus a style-bracketing decorator; the
  styled face is resolved by a **lazy thunk on the first match**, so a
  non-matching run allocates no page `/Font` and records no embedded glyphs.
  (The old code checked `matches.isEmpty` before resolving; the engine has no
  such pre-check, hence the thunk.)
- `_Type0RunCodec` — 2-byte Identity-H codes, records new glyphs via
  `Type0Font.recordGlyph` (`content_editor_type0.dart`).
- `_Type0FallbackCodec` — draws the replacement in a fallback face between
  `Tf` switches. The only stateful codec: `beforePassthrough`/`finish` restore
  the base font and flush the pending compensation kern, matching the old
  `flushOrig` behaviour.

### Gotcha: `resetUsage` ordering for the embedded styled face

`_embeddedFontResource` calls `PdfEmbeddedFont.resetUsage()`. The recorded
glyphs come from `encodeHex`, so the reset must run *before* the encode. When
name allocation was made lazy, the encode had to move into the same lazy thunk
(after the reset) — doing the encode eagerly wiped the glyphs at first match
and the replacement rendered blank. The thunk now does allocate-then-encode.

## Tests

- `test/type0_font_test.dart` — decode/measure on a **synthetic** font dict,
  the eligibility gate (each rejection path + acceptance), and `recordGlyph` +
  `commitFontDict` writing `/W` and `/ToUnicode` **in isolation** (no page
  rewrite, no re-parsing saved bytes — the win the issue called out).
- `test/text_run_rewriter_test.dart` — match alignment, kern compensation
  (present/absent/zero), coalescing (single-`Tj`, kern-into-`TJ`, summed
  adjacent kerns), and the barrier-op path — all against a fake width table,
  no document.

Full `pdf_document` suite (690, +21 new) and `dart_pdf_editor` content-edit
tests green; `dart analyze` clean workspace-wide.
