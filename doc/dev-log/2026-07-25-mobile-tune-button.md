# 2026-07-25 - Tune button on the mobile toolbar

The wide desktop editing strip has always carried the "tune" trigger (the
`Icons.tune` gear that opens `_StyleMenu` - stroke width / opacity / font
sliders, line endings, box colours) via `_tuneTrailing`. The collapsed
mobile dock (`_buildMobile`, under `PdfEditingToolbar.mobileBreakpoint`)
never did: its trailing cluster (`_mobileTrailing`) only ever offered the
first three palette swatches for a colour-using tool, or a selection's
quick actions. So on a phone the sliders were unreachable while drawing.

Fix: `_mobileTrailing` now appends `_mobileTuneTrailing(context)`, which
resolves the armed tool's group (`_groupForTool(controller.tool)`) and
reuses the same `_tuneTrailing(context, _groupStyleFields(group))` the
desktop strip uses - one code path, so the popup's contents track each
tool's `PdfEditToolBehavior.styleFields` exactly as before (a rectangle
never offers a font picker, ink never offers line endings, etc.). No armed
tool, or a tool whose behaviour exposes nothing to tune, yields an empty
list and no gear.

The dock is width-constrained, so swatches + the gear overflowed the 380px
test dock by 15px. Since the tune popup already carries the full palette,
`_mobileSwatches` gained a `count` and the colour-tool branch now shows two
quick swatches beside the gear (three when there's no gear). That keeps the
whole cluster - undo/redo, tool label, swatches, tune, Tools handle -
inside a narrow phone dock.

Tests: `editing_mobile_tune_test.dart` (gear absent at rest, present once a
stroke tool is armed, opens the sliders); the existing
`editing_mobile_toolbar_test.dart` swatch/selection assertions still hold
(they only check swatch-0).
