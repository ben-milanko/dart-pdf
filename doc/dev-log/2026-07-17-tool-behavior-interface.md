# PdfEditToolBehavior - a single source of tool identity (#311)

`PdfEditTool` is a 30-value enum whose behaviour used to be smeared across
several `switch (tool)` blocks in separate places, so adding a tool meant
editing every one:

- the overlay's classification getters (`_inkTool`, `_drawTool`, `_polyTool`,
  `_lineDragTool`, `_measureKind`, `_fixedPolyCount`) and its per-phase
  commit switches (`_commitRect`, `_commitLineDrag`, `_finishPolyPath`);
- the controller's persisted-style tables (`_styleScopeKey`,
  `_styleScopeFields`, `_styleScopeDefaults`, `_buffersInk`);
- the toolbar's per-tool tune-popup capability (`_StyleFields` +
  `_groupStyleFields`).

That was four to five independent copies of "what this tool is."

## What landed

`lib/src/editing/editing_tool_behavior.dart` - `PdfEditToolBehavior`, one
authoritative descriptor per tool, mirroring `PdfAnnotationBehavior`
(pdf_document) on the tool side. It owns:

- **classification** the gesture phases dispatch on (`isInk`, `isDraw`,
  `buffersInk`, `isPoly`, `closesPoly`, `isLineDrag`, `measureKind`,
  `fixedPolyCount`);
- the **persisted style scope** the controller remembers (`styleScopeKey`,
  `styleScopeFields`, `styleScopeDefaults`, and `usesColor` derived from
  them);
- the **tune-popup controls** the toolbar shows (`styleFields`, a
  `PdfToolStyleFields` value - the old `_StyleFields`, now shared);
- **commit hooks** for the tools whose placement is a single document
  mutation (`commitShapeRect`, `commitLineDrag`, `commitPoly`).

One adapter per tool is registered in `_behaviors`; look one up with
`PdfEditToolBehavior.of` / `.maybeOf`.

The three consumers now read from it:

- `editing_controller.dart`: the four static tables collapse to
  `PdfEditToolBehavior.maybeOf(tool)?.…`.
- `editing_overlay.dart`: the classification getters delegate to `_behavior`
  (`PdfEditToolBehavior.maybeOf(_tool)`); `_commitRect` (shapes),
  `_commitLineDrag`, and `_finishPolyPath` call the commit hooks.
- `editing_toolbar.dart`: `_StyleFields` is now a typedef for
  `PdfToolStyleFields`; `_groupStyleFields` returns
  `behavior.styleFields` for the armed tool - the per-tool capability
  booleans (which shapes carry endings/fill/corner-radius, which
  measurements carry endings) are gone from the toolbar.

## The test surface

`test/editing_tool_behavior_test.dart` (24 tests) is the payoff the ticket
called for: feed a behaviour a `PdfEditingController` (and page-space
geometry for the commit hooks) and assert what it reports/emits - no pumped
`PdfViewer`, no synthetic pointer streams.

## Faithfulness gotchas

- **The cloud tool is deliberately not an `isPoly` behaviour.** Its drag path
  rubber-bands a rectangle; only its *click* path builds a free-form
  footprint (via `addCloudPolygonPoints`). `_finishPolyPath` still
  special-cases it before the `commitPoly` hook.
- **The volume tool's `commitPoly` returns false** - it must prompt for a
  depth first, so it declines the synchronous commit and the overlay runs
  its async `_commitVolume`.
- **Insert-strip tools share one tune popup.** The old `_groupStyleFields`
  was group-keyed, so note/stamp/count/image/signature all showed
  `opacity + font + boxColors`. Preserved exactly (each carries the same
  `styleFields`) even though it's semantically loose - a behaviour change
  there is out of scope.
- The overlay classification getters were kept (delegating to `_behavior`)
  rather than inlined, so their many call sites and doc comments stay put.

Select-mode manipulation (move/resize/rotate/vertex/marquee), raw-pointer
palm rejection, viewport pan, autoscroll, and the afterimage/preview
bookkeeping stay in the overlay `State` - they are gesture infrastructure
and render concerns, not per-tool identity.
