# Right-click "Set as default style"

Adds an annotation context-menu action that captures the right-clicked
annotation's appearance as the creation default for new annotations of
its kind. Requested as "Right click set annotation settings as default".

## What it does

Right-clicking an annotation (or the selection chip's "More" menu) now
offers **Set as default style**. Picking it copies the primary selected
annotation's style - colour, stroke width, opacity, fill, line style, and
for free text the font, size, and alignment - into the persisted style
scope of the tool that draws that subtype. The next annotation you create
with that tool inherits the captured style, and the change persists across
sessions like every other tool default.

## Where the pieces live

- `PdfEditingController.applySelectedStyleAsDefault()` /
  `canApplySelectedStyleAsDefault` (`editing_controller.dart`) - the public
  entry point. `_defaultStyleTargetFor` resolves an annotation to a
  `(scope, fields)` pair: text markup (Highlight/Underline/StrikeOut/
  Squiggly) maps to the shared `markup` scope, everything else routes
  through `_creatingToolFor` → `PdfEditToolBehavior.styleScopeKey/Fields`.
  `_capturedStyleOf` reads the annotation's `behavior.style` (plus line
  endings, cloud scale, and free-text `/DA`) into a field-keyed map using
  the same field names the scopes persist under.
- `PdfEditingPreferences.writeScopedStyle(scope, fields, values)`
  (`editing_preferences.dart`) - writes the captured values into the named
  tool-style slot (filtered to the fields that scope remembers) and, when
  that scope happens to be the active one, replays them through the shared
  `_restoreScope` path so the live defaults update immediately. Null is
  honoured only for the clearable fill colours (means "no fill"); an
  absent value leaves that default untouched.
- The menu row (`editing_menu.dart`, key `pdf-annot-menu-set-default`) sits
  just above Delete and is gated on `canApplySelectedStyleAsDefault`. Both
  the right-click and the "More" chip route through `showPdfAnnotationMenu`,
  so the single addition covers both.
- l10n string `menuSetAsDefaultStyle` across the three
  `lib/l10n/dart_pdf_editor_localizations*` files + the `.arb`.

## Gotchas

- Colours persist as full ARGB ints in the scope slots
  (`snapshotActiveStyleScope`/`_restoreScope`), but `behavior.style.color`
  is 0xRRGGBB, so the capture ORs in `0xFF000000`.
- Only a cloud exposes a readable scallop scale; other shapes bake the
  pattern scale into the dash array with no field to read back, so
  `lineScale` is captured for clouds only.
- Because the write targets the *tool's* scope rather than the live values,
  it works from select mode (no active scope) - the default sticks and
  surfaces when the matching tool is next armed.

Tests: `test/editing_set_default_style_test.dart` (shape/free-text/markup
capture, unrelated-tool isolation, empty selection, and the menu row).
