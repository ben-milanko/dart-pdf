# Font menu: document fonts, recents, and search focus

## Goal

Three font-menu improvements:

1. Let the user pick a font **already embedded in the open document**, not
   just the base-14 families, the bundled trio, platform fonts, and a
   custom file.
2. Surface **recently-used fonts** (and the document's own fonts) so common
   picks are one tap away.
3. **Focus the search box** as soon as the menu opens, so the user can type
   to filter immediately.

## What landed

### Enumerating a document's embedded fonts (`pdf_document`)

`font_embedder.dart` gained two public statics on `PdfEmbeddedFont`:

- `fromEmbeddedProgram(cos, fontDict)` - the general sibling of the existing
  Type0-only `fromFontDict`. It finds the `/FontDescriptor` whether the dict
  is a simple font (`/TrueType`/`/Type1`, descriptor inline) or a composite
  `/Type0` (descriptor on the descendant CIDFont), pulls the `/FontFile2`
  (TrueType) or `/FontFile3` (OpenType) program, and reparses it via
  `PdfEmbeddedFont.parse`. Bare-CFF `/FontFile3`, Type1 `/FontFile`, and any
  subset stripped of its `cmap` return null - which conveniently leaves only
  the fonts whose glyphs newly-typed text can actually map onto.
- `usedIn(document)` - walks every page's `/Font` resources **and** each
  annotation's normal-appearance `/Resources` `/Font` (so authored
  embedded-font free text counts), plus the AcroForm `/DR`, reparsing each
  through `fromEmbeddedProgram`. Deduplicated by PostScript name; skips
  anything with no reparsable sfnt program. Fonts nested inside Form
  XObjects are not walked (out of scope).

Why annotation appearances too: an embedded font authored via the editor
lives in the free-text box's appearance stream resources, **not** the page
content resources - so a page-only walk would miss exactly the fonts a user
just added. `PdfStamp.text` only draws Helvetica, so there's no page-content
embedding path to lean on for the common case.

### Wiring into the menu (`dart_pdf_editor`)

- `PdfEditingController.documentFonts` caches `PdfEmbeddedFont.usedIn` per
  revision (keyed by `_document` identity; edits reopen the document so the
  cache invalidates for free).
- `showPdfFontMenu` gained a `_DocumentChoice` entry kind and an optional
  `documentFonts` param (defaulting to `controller.documentFonts`). Document
  fonts show under an "In this document" subtitle; picking one applies the
  already-parsed `PdfEmbeddedFont` directly (no byte load).
- **Recents**: `PdfEditingPreferences.recentFonts` / `noteRecentFont(key)`
  mirror the existing `recentColors` pattern (persisted string list, cap 6,
  dedup-to-front). Keys are stable identifiers (`std:sans`, `bundled:<label>`,
  `platform:<label>`, `doc:<postScriptName>`), **not** font bytes - the menu
  resolves each key back to a live catalogue entry on open, so a recent that
  no longer exists (a document font from a since-closed file) just drops out.
  Custom-loaded (`Load font…`) picks aren't tracked - they can't be
  reconstructed from a key. Each entry carries a `recentKey`; recents render
  as a "Recently used" group above the catalogue with their own distinct
  `pdf-font-recent-N` keys (so a font can appear both in recents and its home
  section without a duplicate-key clash). Recents show only while the search
  box is empty; typing filters the whole catalogue instead.
- The dialog now renders a flat row list where a `String` is a section header
  ("Recently used" / "All fonts") and a `_FontEntry` is a tappable font.
- `autofocus: true` on the search `TextField`.

## Tests

- `pdf_document/test/font_used_in_test.dart` - `usedIn` finds/dedups/ignores
  the right fonts; `fromEmbeddedProgram` reparses vs returns null.
- `dart_pdf_editor/test/editing_fonts_test.dart` - document fonts appear and
  embed on pick; a pick reappears under "Recently used" next open and
  re-applies; the search field is focused on open.

## Follow-up (same session)

Three menu refinements after review:

- **Document fonts get their own section.** `_FontEntry` gained a `section`
  label; the dialog now groups the catalogue under headers ("Recently used",
  then "In this document", then "All fonts") while the query is empty, and
  flattens (no headers) while searching. Document entries are ordered first
  so their section leads the catalogue.
- **Rows preview in their own face.** `_ensureDocumentFontPreview` registers
  each document font's `fontBytes` with the engine via `FontLoader` under a
  stable private family (`pdf-doc-font::<postScriptName>`, cached so repeated
  opens don't re-register), and the row's title renders in it. Best-effort:
  a font the engine can't load just renders plain and still embeds on pick.
  Preloaded before the dialog opens (with a `context.mounted` guard after the
  await). Bundled/standard/platform rows already previewed via their declared
  families.
- **Clean names.** `PdfEmbeddedFont.displayName` strips the six-letter
  `ABCDEF+` subset tag producers prepend (`XAAPZZ+HorbseTextured` ->
  `HorbseTextured`). Used by the menu row label, the toolbar font chip
  (`_familyLabel`), the button label (`_fontLabel`), and `activeFontLabel`.

## Gotchas

- Re-embedding a document font only works when its program still carries a
  usable `cmap` (many full embeds do; aggressive subsets may not) - that's
  the same gate `parse` already enforces, so unusable fonts simply never
  reach the menu.
- Dedup is by name-table PostScript name (clean of the `ABCDEF+` subset tag,
  which rides on `/BaseFont`, not the name table), so the same face subset
  across pages collapses to one entry.
