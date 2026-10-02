# Docked toolbars (Acrobat/Bluebeam-style), tool bars, properties bar

Request: let the toolbars dock to the top/side/bottom like other PDF editors,
including the sub-toolbars ("shapes can go on the right"), and show the
styling controls in one consistent place. Follow-up after a first cut: "I
want the UI to look like Bluebeam or Adobe Acrobat. Dock is the opposite of
floating" - the first cut had only moved the *floating* cards between edges.

## Where it started

The editing toolbar was a set of floating cards over the viewer: a dock card
plus a contextual strip (a group's tools + settings, or the selection's
actions + restyle controls) glued beside it. The dock card could already be
dragged to any edge (`prefs.toolbarDock`), but it was still a card over the
page, the strip could not move independently, and the style controls jumped
around as the strip's content changed.

## The model now

**Docked (the default, `prefs.toolbarFloating == false`).** Solid bars along
the window edges that take layout space - the content (side panels + viewer)
shrinks to fit, nothing covers the page:

- **Main toolbar band** - undo/redo, Hand/Select, the group chips. Top by
  default (`toolbarDock` default changed bottom → top), or bottom, or a
  vertical rail on the left/right (Acrobat's tool rail). It spans the window,
  outside the side panels.
- **Properties bar** - always present, fixed height (`_bandExtent` 56) so the
  page never moves as tools and selections change. It leads with the open
  group's tools (`⠿ SHAPES ▭ ◯ ─ →…`), then the context: the selection's
  strip (actions, alignment, style), a selected element's actions, the crop
  controls, or the armed tool's options + style (`⠿ RECTANGLE ● ● ● …`); a
  hint while nothing applies. On `styleBarDock`, else beside the main toolbar
  - except a side-rail main toolbar puts it on top (a row of sliders reads as
  a bar, not a rail; a side properties rail is a fixed `_propertiesRailWidth`
  so it never changes width).
- **Tool bars docked to their own edge** (`toolStripDocks`) - a pinned band or
  rail with that group's tools only, present whether or not the group is open
  (a persistent palette, as in Bluebeam). Its group's tools then leave the
  properties bar; the armed tool's options/style still show there.

Why tools lead the properties bar instead of joining the main band: the first
docked cut appended them after the group chips, and at 800px the tools
scrolled out of sight (`color_processing_test` and the markup tests caught it
- they could not tap the tools). A second row that starts with the tools
always shows them, and the main band never changes length.

**Floating (`toolbarFloating`).** The previous card layout, kept as an
option, with the same per-edge tool bars (`overlay` + `_ToolbarEdgesLayout`)
and an optional style bar (`styleBarDock` null = style inline at the strip's
trailing end).

**Grips and settings.** Every bar or section has a grip: drag it onto the
shell's edge drop zones (`PdfToolbarDragData(onDock:)`), or click/tap it for
a placement menu through `PdfEditorPresenter.menu`. The main grip's menu also
toggles "Float over the page". View options → **Toolbar layout**
(`showPdfToolbarLayoutDialog`) has every choice as `PdfDropdown`s - docked or
floating, each bar's edge - and a reset (docked, main on top).

## Implementation notes

- `PdfEditingToolbar(body:)` is the docked mode: the toolbar lays `body` out
  with its bands around it (`_buildDocked`: top bands, then a row of left
  rails · body · right rails, then bottom bands; outermost first per edge).
  The shell takes `toolbarFrame: (content) => toolbar(body: content)`
  (`PdfShellPanelLayout.toolbarFrame`) and wraps the panels + viewer in it.
  **The content carries a GlobalKey** (`_contentKey`): the frame comes and
  goes (page grid, sheets, compact width, floating mode) and without the key
  the viewer would rebuild from scratch and lose its scroll position.
- Bars are built inside `_onEdge`, which sets `_buildEdge` so `_stripAxis`
  follows the bar's own edge. **Gotcha**: `LayoutBuilder`/`Builder` callbacks
  run after `_onEdge` restored it, so `_centeredCard` and `_barGrip` capture
  `_cardAlignment`/`_stripAxis` eagerly.
- `_centeredCard` is the one surface switch: a floating card, a docked band
  (`_band`: `Material` in `surfaceContainerLow` with a hairline on the inner
  edge, compact visual density so content fits the 56px band, scrolls along
  the edge on overflow), or - inside the properties bar (`_bare`) - no
  surface at all. That is how the existing selection/element/crop strips
  become properties-bar content unchanged.
- `_groupSettings` = `_groupOptions` (ink commit, signature/annotation
  library, count tally, scale chip, form type, flatten, apply redactions) +
  `_groupStyle`; `_groupToolButtons` and `_toolBarGrip` are shared by the
  floating strip, the docked tool bar and the properties bar. The mobile
  sheet still calls `_groupSettings` inline.
- **Semantics gotcha (pre-existing, now on the default path).** With
  semantics on, the app's Save As and print flows hit Flutter's
  `'node.built'` assertion in `PipelineOwner.flushSemantics` whenever the
  viewer's bottom padding was exactly its page spacing (`trailingPadding: 0`)
  - reproducible on main by dragging the floating toolbar to the top. The
  stale node is a page child (`IndexedSemantics` under
  `_ExactRenderSliverVariedExtentList`) skipped as parent-data-dirty during
  the build pass. A 1px tail is enough to avoid it, 144 (the floating-bottom
  tail) always did; turning off the list's automatic keep-alives did not
  help, and nothing was skipped for needing layout. The editor view now
  leaves `_lastPageGap` (12) below the last page whenever no floating bar
  covers the bottom - a mitigation, not a root cause; a follow-up task tracks
  the real fix. The isolated repros tried (semantics + revision swap across
  window heights, in the editor package) did not trigger it; the app tests
  `print_menu_test` "printing commits buffered ink" and `tabs_menu_test`
  "reveal follows a Save As" do.
- Editor view: one `stockToolbar({body})` builder used three ways - compact
  bottom bar, floating overlay (`floatingToolbarFillsViewer`), docked frame.
  A host `toolbarBuilder` toolbar always floats as before. `trailingPadding`
  only applies to a floating toolbar with a bar on the bottom.
- Prefs: `toolbarFloating`, `toolStripDocks`/`setToolStripDock`,
  `styleBarDock`, `resetToolbarLayout`; `toolbarDock` defaults to top.

## Strings

21 new `tb*` keys (edges, "With main toolbar", "Inside tool bars", "Separate
style bar", docked/floating, "Float over the page", the properties hint, the
dialog's sections/hints/reset, the grip tooltip), translated in all 19
non-English locales; en_AU/en_GB synced (colour).

## Tests

`test/toolbar_layout_test.dart`: prefs round trip + reset; docked bars sit
above the content, span the window above the side panels, and arming tools
or switching groups never moves the viewer; a right-docked Shapes rail sits
beside the content, vertical, with its properties in the properties bar;
dragging the tools section's grip docks the group right; the main toolbar
docks left as a rail with properties on top; the main grip toggles floating
and back; floating: pinned palette, style bar, style bar toggle; the layout
dialog (mode, properties edge, a tool bar edge, reset). `pdf_shell_test.dart`:
the floating rail/drag tests opt into floating; "wide: docks above the
viewer" asserts no overlap and no scroll tail.
