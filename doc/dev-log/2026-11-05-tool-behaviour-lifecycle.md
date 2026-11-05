# 2026-11-05 - tool gestures live in their behaviours (rest of #1207)

#1242 made the editing mode one sealed value with one transition point. It
left two pieces: the viewer's per-tool gesture branches, and each tool's
gesture → preview → commit lifecycle, which was still spread over three
`switch (_tool)` blocks in the overlay.

## The viewer asks the mode

`PdfEditingMode` answers the questions the viewer used to work out from
tool identity:

- `armsPageTool`: a tool other than Select owns the page. Note popups,
  table open, double-click into a text box, long-press text selection,
  the plain tap, and the form layer's active state now read this.
- `armsSelect`: touch long-press marquee, select-all, and the host layer
  above editing.
- `authorsForms` / `picksFormWidgets`: the field labels and fill layer,
  and what a right-click on a form widget does.
- `drawsFreehand`: `_kindDrawsInk` and `_drawToolArmed`, from the
  behaviour's `isDraw`.
- `escapesFirst`: the signature box's Escape step, from the behaviour.

`pdf_viewer.dart` has 8 `PdfEditTool.` references left, down from 21.
Four are doc comments, three arm a tool (`tool = …`), and one is the
shortcut table's R/rectangle conflict.

## The overlay asks the behaviour

`PdfEditToolBehavior` (`editing_tool_behavior.dart`) gains:

- `drag` (`PdfToolDrag`: none, select, erase, freehand, region, form,
  signature, content). `_panStart` switches on it.
- `tapCreates`, for the tap's interaction intent.
- `commitRegion(host, start, end)` and `commitTap(host, tap)`. The
  per-tool placement code from `_finishPan`'s region branch,
  `_commitRect`, `_commitLineDrag` and the tap switch moved here. That
  covers shapes, the line family, measures and calibrate, free text,
  callouts, stamps, image, form, redact, content delete, link, signature
  box, snapshot, note, count, signature and content.

The tools commit through `PdfToolHost`, a port the overlay implements
with `_OverlayToolHost`. It provides the page, the inline-editor openers,
the prompts and pickers, and the afterimages. Each check for "too small
to be a drag" (4 px box, 4 px segment, 8 px cloud) lives with its tool.
A new tool with an existing gesture shape now lands in its behaviour row.
`_SimpleTool` takes top-level `region:` / `tap:` tear-offs, so the table
stays const.

The overlay has 80 `PdfEditTool.` references, down from 147. The rest are
tool-specific previews and hover cursors (painting).

## Tests

`test/editing_tool_lifecycle_test.dart` holds plain tests through a
recording `PdfToolHost`:

- the mode answers for every mode;
- each tool's drag kind;
- `tapCreates`;
- region commits (shape plus afterimage, click-sized boxes place nothing,
  segment commit, inline-editor opens, the prompt-driven flows, and the
  stamp caption with cancel);
- tap commits (note, count, text tools, stamp, and drag-only tools
  ignoring a tap).
