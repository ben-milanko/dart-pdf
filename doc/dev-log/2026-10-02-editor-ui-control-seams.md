# Editor UI control seams (5 stages, ahead of the material_ui switch)

Hosts asked for control over the editor's UI (#195), and the app itself was
working around the gaps: an AppBar stacked over the editor's own header, a
copied save button, a copied 700px breakpoint, hand-copied palette toggles.
At the same time `package:flutter/material.dart` is on its way out in favour
of `material_ui`, a separate set of types. This work adds the control seams
in non-breaking 5.x steps, on today's `flutter/material`, so the 6.0 switch
is a mechanical import change rather than a redesign. Five stages, one
commit each on `feat/editor-ui-control-seams`.

## The layers

Each layer works without the ones below it, and public signatures use only
widgets-layer types (`Color`, `TextStyle`, `IconData`, `Rect`,
`ValueListenable`), so none of them changes type at 6.0.

1. **Tokens** - `PdfEditorThemeData` (`lib/src/design/editor_theme.dart`)
   and the extended `PdfViewerThemeData` (`lib/src/theme.dart`).
2. **Surfaces** - `PdfEditorView.headerBuilder` + `PdfHeaderParts`
   (`design/header_parts.dart`), the menu entry builders
   (`editing_menu.dart`), the presenter's `actionBar`/`readout`.
3. **Presenter** - `PdfEditorPresenter` + `PdfEditorScope`
   (`design/editor_presenter.dart`, stock looks in
   `design/material_presenter.dart`).
4. **Commands** - `PdfEditorCommands` + `PdfCommand` + ordered
   `toolGroups` (`editing/editor_commands.dart`), plus the viewer geometry
   (`PdfViewerController.globalRectOf`, `selectionGlobalRect`).
5. **Headless** - the model types moved out of dialog files
   (`editing/models/`), so `PdfEditingController` and `PdfPageView` import
   no Material.

## Stage by stage

- **1/5 foundations (b14ff658).** Floors to `flutter: '>=3.44.0'`; the
  `floor-analyze` CI job (`tool/floor_analyze.sh`, run outside the workspace
  because printing needs 3.47). `tool/check_design_imports.dart`: an
  allowlist of Material importers that may only shrink, headless import
  closures for the controller and `PdfPageView`, and per-file counters of raw
  `showMenu`/`showModalBottomSheet`/`ScaffoldMessenger`/`DropdownButton`/
  menu-less text fields. Model types moved to `editing/models/`
  (re-exported from their old files). `PdfThemePreference`
  (`themeMode: ThemeMode` deprecated), `PdfDialogSubmit.action`, the last
  English strings localized.
- **2/5 commands (688a4e23).** The toolbar's arming/markup/colour/flatten/
  recent-tools logic became `PdfEditorCommands`, with `catalog()` for
  palettes. Tool groups are ordered data that can hold `PdfCommand`s (no
  more `values.byName(group.id)` or "markup is groups[1]"). Viewer shortcuts
  and the app palette arm through the commands, so prerequisites (scale,
  signature) run - a deliberate behaviour change with its own tests. Adds
  the `toolbar-arm` web perf scenario.
- **3/5 presenter (ce4cd3a5).** One replaceable presenter for dialogs,
  sheets, menus, notices and every prompt, found through `PdfEditorScope`
  (an `InheritedTheme`, so stock dialogs carry it into their routes and the
  prompts *they* open use it too). Fixed the bypasses (direct
  `showPdfTextPrompt`/`showPdfColorPicker` calls, the unreachable link
  prompt). `showPdfDialog` keeps its signature and `DialogRoute` (#687
  native-window promotion and #893 Enter-to-submit untouched).
- **4/5 any host (4348639b).** `PdfMaterialHost` supplies what a
  `CupertinoApp`/`WidgetsApp` host lacks (localizations, a derived theme, a
  transparent `Material`); routes, sheets (a library-owned
  `ModalBottomSheetRoute` subclass), popup menus and text-field context
  menus (`pdfTextContextMenu`) re-inject it. `DropdownButton` became
  `PdfDropdown`, which opens through the presenter's menu. One form-fill
  path (the form tool now runs keystroke/validate scripts). Host test suite
  (`test/any_host_test.dart`, `test/support/pump_host.dart`).
- **5/5 surfaces (this session).** The tokens, `headerBuilder`, menu entry
  builders, `actionBar`/`readout`, `showInlineTextStyleChip`, the geometry
  APIs, the merged breakpoint, the app adopting the header, the Cupertino
  example, printing's dropdowns.

## Stage 5 details

- **One place for fallbacks.** `design/viewer_tokens.dart` (not exported)
  holds `PdfViewerDefaults` and the `PdfViewerTokens` extension
  (`theme.chrome`, `theme.canvas(brightness)`, `theme.snapGrid(primary)`,
  ...). The eight `?? const Color(0xFF1E88E5)` fallbacks are gone; the
  three remaining `0xFF1E88E5` literals are palette swatches, not
  fallbacks. Tokens whose stock value comes from the colour scheme (snap
  grid, rulers, scrollbar markers) still take it as an argument - the
  `Theme.of` read stays at the call site, only as the fallback.
- **Status colours.** The sidebar's `Colors.red/green/orange/blue` pills
  read `PdfEditorThemeData.of(context)`; `fallback` holds the swatches'
  primary values (`MaterialColor` != `Color` under `==`, so tests compare
  `toARGB32()`).
- **Scope theme -> viewer theme.** `pdfInstallPresenter(theme:)` merges the
  inherited scope's tokens and, when they carry `viewer` tokens, installs a
  `PdfViewerTheme` (beneath an ambient one's explicit values). A root
  widget's own `viewerTheme:` still wraps inside and wins wholesale, as
  before. `theme.dart` cannot read the scope itself: it is in
  `PdfPageView`'s headless closure and the scope file imports Material.
- **Breakpoints merged** (plan open decision 7). `PdfEditingToolbar.
  mobileBreakpoint` is now `pdfShellCompactWidth` (700, was 600): between
  600 and 700px the toolbar docks as a solid bar like the header and panels
  already did. `compactWidth` moves all three. The toast's own 600px
  pill/full-width switch is unchanged.
- **Header parts.** `PdfEditorView._buildHeader` builds every part once and
  assembles the stock `PdfShellBar` from them; `headerBuilder` gets the
  same instances. A part is a live widget (the search field owns a focus
  node): mount it once, never alongside `parts.stock`. `parts.bar()` is a
  non-adaptive `PdfShellBar` (new `adaptive`/`color` params);
  `parts.controls(includeSave:)` is the compact Controls button
  (`pdfShowShellControls`, lifted out of `PdfShellBar`).
- **Menus.** The text menu's rows are now `PdfMenuItem<PdfTextMenuItem>`
  whose stock items carry their own `onSelected` (the private
  `_TextMenuAction` enum is gone), so an entries builder can reorder stock
  and host rows freely. The request is always built now (it was only built
  for a `textMenuBuilder`). An entries builder returning `[]` keeps the menu
  closed. `PdfMenuEntry.id` is a concrete getter on the base class (a
  `ValueKey<String>`'s value), so it is non-breaking for subclasses.
- **Chips.** `actionBar`/`readout` return the body only; the editor still
  positions and zoom-compensates it, so a presenter cannot misplace a chip.
  The touch inline style chip has a font/size/colour UI, not a flat action
  list, so it is a flag (`showInlineTextStyleChip`) rather than an
  `actionBar` kind.
- **Geometry.** `globalRectOf(page, PdfRect)` takes a `PdfRect` (the plan
  sketched `Rect`), matching `showRect`/`revealRect`. It is the inverse of
  `_toPageView` through the list-space box's transform, so zoom and
  rotation come for free. `selectionGlobalRect` computes on read and only
  re-checks when it has listeners: after viewport bumps, text selection
  changes and editing-controller notifications (post-frame, after layout).
- **App: one header.** Over an editable document the app's `AppBar` is now
  drawn by `PdfEditorView.headerBuilder`, with the editor's parts as its
  `bottom` row (`_buildAppBar` in `app/lib/editor_screen.dart`); every other
  tab keeps the `Scaffold.appBar`. The cloned `mobile-app-save` button is
  gone - on compact layouts the editor's own `pdf-shell-save` part sits in
  the app bar's actions, kept enabled without edits as the clone was
  (`alwaysAllowSave || compact`). `_mobileTabsBreakpoint` became
  `pdfShellCompactWidth`. Visual change, measured on before/after widget
  screenshots at 1280x760 and 390x844: identical except that the second row
  now shares the app bar's `surface` colour instead of
  `surfaceContainerLow` - one bar with one bottom rule.
- **Cupertino example.** `example/lib/cupertino_host.dart` (run with
  `-t lib/cupertino_host.dart`): a `CupertinoNavigationBar` from the header
  parts, a toolbar of `CupertinoButton`s from `catalog()`, and a presenter
  with `CupertinoActionSheet` menus, `CupertinoAlertDialog` confirm/text,
  and an overlay toast. It overrides only "how" methods; the stock dialogs
  and pickers run as they are. Material Icons glyphs (from the commands'
  `IconData`), not `CupertinoIcons`, which would need `cupertino_icons`.
- **Printing.** The print preview's dropdowns are `PdfDropdown` (now
  exported, with `PdfDropdownItem`) and its text fields use
  `pdfTextContextMenu`; the design-import counters scan
  `dart_pdf_printing/lib` too (all at 0).

## Gotchas

- **material_ui is a separate type universe.** Its `Theme`,
  `MaterialLocalizations`, `ScaffoldMessenger` and `ButtonStyleButton` are
  different types from `flutter/material`'s; only widgets-layer values cross.
  That is why every public signature added here is widgets-only, and why
  Enter-to-submit no longer checks `is ButtonStyleButton`.
- **Enter role detection.** `PdfDialogSubmit` classifies the focused control
  by semantics, not widget type: a value control (checked/toggled/expanded/
  in a mutually exclusive group, or selected without being a button) lets
  Enter submit; a plain button keeps Enter for itself. `PdfDropdown` marks
  itself `expanded` for this reason.
- **Localizations are not an InheritedTheme (stage 4).** Making the
  localizations wrapper an `InheritedTheme` broke the text magnifier:
  captured themes wrap overlay content that must stay a direct child of the
  overlay's stack, and `Localizations` adds a render object. Routes and
  overlays re-inject explicitly (`pdfHostRoute`) instead.
- **Cached fallback theme in tests.** Material and Cupertino both cache their
  fallback `ThemeData` in a static, so `TargetPlatformVariant.all()` passes
  for the wrong reason on iOS/macOS. Put an explicit `Theme(platform:)` above
  the host (`pumpPdfHost` does) or run one platform per process.
- **The real floor was 3.44.** 5.0.0 declared `>=3.24.0` but used
  `ReorderableListView.onReorderItem` (3.44). Declaring 3.44 strands nobody;
  3.47 (material_ui 1.4's floor) belongs in 6.0.
- **GlobalKeys and moving app bars.** The app's tab strip had a `GlobalKey`
  for its geometry; with the app bar now living in the editor for some tabs
  and the `Scaffold` for others, switching tabs reparented it mid-frame and
  tripped a semantics-geometry assertion. It is a `BuildContext` probe now.
- **Rebuild budget.** `app_prefs_rebuild_test` caps element rebuilds per
  preference tick; the editor rebuilds its header on every tick, so the
  app's half of the bar (menu, tabs, actions) is built once per
  `EditorScreen` build and reused as identical instances.
- **Swapping `PdfEditorView.bytes` while a page is rendered** can dispose the
  owned viewer controller before the page states (a
  `_PdfForwardingListenable used after disposed` on unmount); seen while
  writing a test, not fixed here - the test keeps one bytes object.

## Not done

- `headerBuilder` on `PdfReader` (the reader keeps its stock header; the app
  still stacks its `AppBar` over it in read-only mode).
- Host dock panels, `Intents`/`Actions` for viewer shortcuts, a reusable
  signature pad, injectable preference storage (plan 5.6+).
- The 6.0 switch itself (bridge, `material_ui` delegates, removing the
  deprecated APIs) - see the plan's 6.0.0 section.
