# Editor UI follow-ups: reader header, host panels, shortcut intents, signature pad

The non-breaking work left after the control seams
(2026-10-02-editor-ui-control-seams.md), plus the 6.0 exit-gate test
cleanup. Every public change is additive; the 6.0 switch to material_ui is a
separate PR.

## What landed

- **`PdfReader.headerBuilder`.** The reader builds its header once
  (`_buildHeader`) and hands the parts to the host as the same
  `PdfHeaderParts` the editor uses. Its `save` is always null. The compact
  `controls()` part carries the zoom, the Pages/Reflow pair, view options and
  the two panels. `PdfReader.source` forwards it to the inner reader. The app
  draws its app bar through it in read-only mode (`_shellDrawsAppBar`
  replaces `_showsEditor`), so read-only tabs have one header like editable
  ones. The progressive preview tab still uses `Scaffold.appBar`, because its
  progress bar sits at the top of the body.
- **⌘S on compact app windows.** #989 kept the compact app bar's save/share
  button live by passing `alwaysAllowSave: ... || compact`, which also let
  ⌘S/Ctrl+S save an untouched file there. Now the app passes only
  `isUnsaved || isDirty`, and the compact bar uses
  `parts.saveButton(enabledWhenUnchanged: true)`. That button stays enabled
  and calls `onSave` directly (`_saveUnchanged`); `_save` and the shortcut
  keep the `_canSave` check. Test: `app/test/one_header_test.dart`.
- **The bytes-swap bug from the seams log was really a controller swap.**
  Swapping bytes alone never reproduced it. Handing `PdfEditorView`/
  `PdfReader` a `viewerController` where the shell had owned one did: the
  shell disposed its controller in `didUpdateWidget`, but `PdfViewer` binds
  its controller once, in `initState`, and never rebinds. So the viewer kept
  driving the disposed one, and the page states' dispose
  (`_setPageRasterReady` → `_pageRenderActivity.notify()`) asserted. Swapping
  one host controller for another left the new one silently unbound (no
  error, `pageCount` 0). Fix: the shells key the viewer
  `ObjectKey(viewerController)`, so a swap mounts a viewer bound to the new
  one. `PdfShellSessionLifecycle._retire` also disposes a replaced owned
  viewer/performance controller in a post-frame callback, because the old
  viewer only lets go of it in `finalizeTree`, after the build. Test:
  `shell_controller_swap_test.dart`, where 5 of 6 cases fail on main.
- **Host dock panels.** `PdfEditorView.extraPanels: [PdfEditorPanel(...)]`
  (`editing/editor_panel.dart`).
  - `PdfDockablePanel` stays an enum. Host panels are stored by id in
    `PdfEditingPreferences` (`extraPanelDock`/`Width`/`Open`, keys
    `dart_pdf_editor.editing.extraPanel.<id>.*`). Since the ids are unknown
    at load time, they are read from the store on demand, with this
    session's writes in an overlay map.
  - The editor frames each panel in `PdfSidebarPanelFrame(hostPanel:)`. The
    geometry's `moveHandle()` then drags the `PdfEditorPanel` itself, and
    `_DropTarget` accepts it through `PdfShellPanelLayout.onHostPanelDock`.
  - Host panels dock standalone: `PdfPanelTabDropRegion` is a
    `DragTarget<PdfDockablePanel>`, so it ignores them, and they never join
    a tab group. Generalising tab groups to ids would mean changing the
    public `PdfPanelTabEntry.panel` type, which is breaking.
  - `PdfEditorPanel.open` (a `ValueNotifier<bool>`) lets the host own
    visibility; the editor merges it into its rebuild listenable.
    `showInPanelSwitch: false` hides the toggle.
- **App devtools.** Over an editable document on a wide window, F12's panel
  is now `extraPanels` (`_devToolsPanel`, `open: _devToolsOpen`, no switch
  toggle). It is resizable and can be redocked to any edge. Its width now
  persists by id, where it used to be session-local. Other tabs and phones
  keep the app's own Row/overlay (`_devToolsInEditor`): the editor's compact
  sheets hide the toolbar, while the phone overlay is deliberately
  scrim-less over the viewer. `DevToolsPanel(geometry:)` builds only its
  content into the editor's frame.
- **Viewer shortcuts as intents.** `viewer_intents.dart` (widgets-only)
  defines the intents and `pdfViewerDefaultShortcuts`.
  - `PdfViewer` replaced `CallbackShortcuts` with `Shortcuts` + `Actions`.
    The map is static, and the *actions* decide whether they apply: the
    editing-only ones are disabled without a session, and the nudge without
    a selection. A disabled action makes `ShortcutManager` return `ignored`,
    which lets the key bubble exactly as the old conditional bindings did.
    The test checks that an arrow key still reaches an ancestor's
    `ScrollIntent`.
  - Each action is `Action.overridable(context: viewer)`, so an `Actions`
    above the viewer wins.
  - The binding map is cached on its inputs (`_keyBindings`), because the
    per-tool `PdfArmToolIntent`s are not const and an unequal map would
    re-index the manager on every build.
  - It is still empty while an in-place text editor is open.
  - `viewerShortcuts` forwards from `PdfEditorView`/`PdfReader`.
  - The editor-level ⌘S/⌘F/⌘⇧S bindings are still `CallbackShortcuts`; they
    are not viewer commands.
- **`PdfSignaturePad` + controller** (`editing/signature_pad.dart`,
  widgets-only). It holds the strokes and pressures, the ink and pen, the
  stroke API, `toSignature()`, and the trackpad capture. The pad attaches to
  its controller while mounted (`controller._pad`) so that
  `startTrackpad()` can reach the capture, focus and lifecycle state. The
  dialog keeps the `AbsorbPointer` around itself, reading
  `controller.trackpadActive`; the focus node that ends a capture on any key
  moved onto the pad. All the old keys are kept.
- **`PdfPreferencesStore`** (`editing/preferences_store.dart`).
  - The preferences used only `get*`/`set*`/`remove`/`containsKey`, so the
    interface is exactly those methods.
  - `PdfSharedPreferencesStore` is the default (loaded as before, failing
    silently in tests). `PdfMemoryPreferencesStore` keeps values in memory.
  - `PdfEditingPreferences({store})` is a new optional named parameter.
- **Exit-gate test cleanup.**
  - Findings: every negative Material-type finder (17 statements) and most
    positive ones now go through keys or semantics. Enabled, selected and
    toggled checks use `tester.getSemantics(key)` with
    `isSemantics(...)`, because `containsSemantics` is deprecated and fails
    `--fatal-infos`.
  - Casts kept: about 97 casts that read a Material-only property stay, but
    every one is behind a key finder now, so after the switch it fails
    loudly instead of passing for the wrong reason.
  - Keys added: about 30 new `pdf-*` keys, listed in the CHANGELOG.
  - Not converted: most `find.byTooltip` uses stay. They match through the
    tooltip's semantics and keep working under material_ui's `RawTooltip`.
    The one negative left (eraser vs style label) is deliberate.
  - No shared harness helper: small file-local finders read better.

## Gotchas

- `PdfViewer` does not support swapping `controller` in place. Any host that
  swaps it should key the viewer, as the shells now do. A real in-place
  rebind would also have to carry over page count, current page and search
  state.
- `Action.overridable` needs a context. `_keyActions` is a `late final`
  built on first use in `build`, so `context` is ready, and it is created
  once per state, so `Actions` sees the same map every build.
- A test `StreamController` whose only subscription was cancelled never
  completes `close()`, so do not `await` it in a widget test (it hangs for
  the full timeout).
- `PdfViewModeController` owns the mode once a view has one; setting
  `prefs.viewMode` in a test does not move a mounted editor. Pass
  `viewMode:`.

## Verification

See the PR for the suite counts against the origin/main baseline and the
web perf A/B (`wheel-text`, `toolbar-arm`).
