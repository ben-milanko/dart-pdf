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
shrinks to fit, nothing covers the page. Third follow-up: "users should have
the option between docked and floating toolbars, and the breakdown of docked
toolbars should be different to floating". So docked is Bluebeam-style:

- **No group switcher.** The main toolbar (undo/redo, Hand/Select) and *every*
  group's toolbar (`⠿ SHAPES ▭ ◯ ─ →…`) are always visible, side by side in
  one toolbar area per edge (`_toolbarArea`): a `Wrap` that flows them into
  further rows (top/bottom, `_toolbarRowExtent` 40) or rail columns
  (left/right) as space runs out, each set off by a hairline. One click arms
  any tool, from any group.
- **Each group's toolbar drags to any edge on its own** (`toolStripDocks`,
  else the main toolbar's edge - `_dockedGroupEdge`). Main toolbar: top by
  default (`toolbarDock` default changed bottom → top), bottom, or a side rail.
- **Properties bar** - always present, fixed height (`_bandExtent` 48) so the
  page never moves as tools and selections change: the selection's strip
  (actions, alignment, style), a selected element's actions, the crop
  controls, or the armed tool's options + style, led by a label naming it
  (`⠿ RECTANGLE ● ● ● …`); "PROPERTIES" + a hint while nothing applies. On
  `styleBarDock`, else beside the main toolbar - except a side-rail main
  toolbar puts it on top (a row of sliders reads as a bar, not a rail).
- **Group-wide actions ride in the group's toolbar** (`_groupActions`):
  Edit's Flatten and Insert's annotation library act on the document, not a
  tool, so docked they sit after the group's tools - otherwise, with no
  group to "open", they would only appear once one of its tools was armed.
  Floating, they stay in the open group's strip.
- Docked toolbars wrap to 3 rows at 1280px and 4 at 800px. A short panel
  beside them drops the thumbnail strip's Add page footer under
  `_minExtentForFooter` (120) rather than overflowing
  (`panel_dock_test`'s top-docked annotation panel at 800x600 leaves the
  strip 64px).
- **Every group's toolbar is always built**, and the toolbar rebuilds on every
  controller tick (a style slider writes one per frame), so a stroke-width
  drag rebuilt all seven: `app_prefs_rebuild_test` went 1,034 → 2,256
  elements per tick. `_cachedGroupSegment` hands back the same widget while
  its signature (armed tool, edge, grip, theme, locale, visibility settings)
  holds, and Flutter skips it: 1,008 per tick. Anything a group toolbar
  newly reads must join that signature.
- A toolbar longer than its whole edge scrolls inside its own
  capped slot rather than overflowing - a wrap cannot split one. The slot
  carries the `pdf-tool-bar-<id>` key, so its rect is the visible toolbar.

**Mode switch** in three places: View options → "Floating toolbars" (a check
item, `pdf-shell-floating-toolbars`), the app's Settings screen
(`settings-floating-toolbars`), and the main grip's menu.

**Floating (`toolbarFloating`).** The previous card layout - group
switcher + contextual strip - kept as an option, with the same per-edge tool bars (`overlay` + `_ToolbarEdgesLayout`)
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
  edge, scrolls along the edge on overflow), or - inside the properties bar
  and the docked toolbar area (`_bare`) - no surface at all. Docked surfaces
  use `_denseTheme` (minimum visual density, shrink-wrapped tap targets),
  memoized per source theme: rebuilding the ThemeData on every toolbar build
  cost the `toolbar-arm` web scenario ~10% p95. That is how the existing selection/element/crop strips
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

23 new `tb*` keys (edges, "With main toolbar", "Inside tool bars", "Separate
style bar", docked/floating, "Float over the page", "Floating toolbars" + its hint, the properties hint, the
dialog's sections/hints/reset, the grip tooltip), translated in all 19
non-English locales; en_AU/en_GB synced (colour).

## Tests

`test/toolbar_layout_test.dart`: prefs round trip + reset; docked: every
group is its own toolbar with no switcher, one click arms a tool from any
group and its properties never move the page, an 800px window wraps the
toolbars without overflow; a right-docked Shapes rail sits beside the
content, vertical, with its properties in the properties bar;
dragging the tools section's grip docks the group right; the main toolbar
docks left as a rail with properties on top; the main grip and View options toggle floating
and back; floating: pinned palette, style bar, style bar toggle; the layout
dialog (mode, properties edge, a tool bar edge, reset). `pdf_shell_test.dart`:
the floating rail/drag tests opt into floating; "wide: docks above the
viewer" asserts no overlap and no scroll tail.
