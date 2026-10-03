# The example switches between Material and Cupertino at runtime

Follow-up to `2026-10-03-cupertino-presenter.md`: the example's Cupertino
host was a separate entry point (`-t lib/cupertino_host.dart`). Now the one
example app (and so the web demo built from it) switches design while it
runs.

## Where the switch lives

- **Material -> Cupertino:** the app menu (the DartPDF logo), right under the
  theme cycle: "Switch to Cupertino design" (`dartpdf-design-cupertino`).
- **Cupertino -> Material:** a Settings button at the end of the Cupertino
  nav bar (`cupertino-settings`) pushes a `CupertinoSettingsPage`: Design
  (Material / Cupertino), Appearance (System / Light / Dark, the same
  `PdfEditingPreferences.themePreference` the Material theme cycle sets),
  and Open documents (pick the active one, open a PDF, open the demo).
- **Persistence:** `ExampleDesignPreference` (`example/lib/workspace.dart`)
  stores the choice under `pdf_viewer_example.design` in the same
  `PdfPreferencesStore` the editor's preferences use (shared_preferences by
  default). Material is the default. `main()` awaits it before `runApp`, so a
  Cupertino user gets no Material flash on launch.
- `lib/cupertino_host.dart` stays as an entry point: `runExample(initialDesign:
  ExampleDesign.cupertino)`, which starts in Cupertino and saves that choice.

## State across the swap

The two designs are different app roots (`MaterialApp` vs `CupertinoApp`), so
a switch rebuilds everything under `ViewerApp`'s state. Rather than try to
reparent the editor between roots (GlobalKeys across two Navigators/Overlays
are fragile), the state people care about moved **above** the root:
`ExampleWorkspace` (owned by `_ViewerAppState`) holds the tabs
(`DocumentTab`, moved out of main.dart: each with its `PdfEditingController`
and `PdfViewerController`), the active index, the `PdfPerformanceController`
and the worker-config epoch, plus a `launched` flag so a host mounted by a
switch does not open the demo again. `ViewerScreen` and
`CupertinoEditorScreen` read and mutate it; neither disposes it.

A switch then re-attaches the same session and viewer controller to the new
host's `PdfEditorView` - exactly what a tab switch already does - so unsaved
edits, the undo stack and the current page carry over. The viewer
controller's detach is identity-checked, so the outgoing viewer's late
dispose cannot unbind the incoming one.

Lost on a switch: per-host chrome state (open menus, the read-only /
context-menu / horizontal-layout demo toggles, which are Material-host
fields), and the demo document's Flutter overlays are Material-only (the
Cupertino host leaves their slots empty). A file still loading when the
switch happens stays a loading tab (its loader belonged to the old screen).

`savePdfBytes` / `pdfSaveFileName` (main.dart) are the Material screen's
save, hoisted so both hosts save the same way and show the result in their
own notice.

## Gotcha

- `CupertinoNavigationBar.transitionBetweenRoutes: false` on the editor's
  bar. With the default, pushing the settings page flies the bar in a Hero
  through the navigator overlay, outside the editor's `Material` surface,
  and the stock page-number/search `TextField`s throw "No Material widget
  found" (seen when the appearance changed with settings open).
- The settings page draws its own back button (`Icons.arrow_back_ios_new`):
  the implied one is a CupertinoIcons glyph, and the example does not
  bundle cupertino_icons, so it rendered as a missing-glyph box.
- Below 1000 logical px the nav bar drops the search field from `middle`
  (it overflowed beside the panel switch, save, controls and Settings at a
  default 800 px macOS window); the search panel still has search.
- Checked on macOS (debug, the example's own bundle id) with in-app
  RepaintBoundary captures of both designs, light and dark.

## Strings

Eleven new example ARB keys (`exUseCupertinoDesign`, `exSettings`,
`exDesign*`, `exAppearance*`, `exOpenDocumentsSection`) in every locale; the
AU/GB bundles via `tool/sync_english_locales.dart --write`, then
`flutter gen-l10n`.

## Tests

`example/test/design_switch_test.dart`: Material -> Cupertino (app menu) ->
Material (settings page) asserting the app root type, the same session and
viewer controller, an unsaved `removePage` still applied and undoable, the
page kept, the stored value, and one tab; a stored `cupertino` restores on
restart; Material by default; the Cupertino appearance setting sets the
`CupertinoApp` brightness (null = platform). `cupertino_host_test.dart` now
starts `ViewerApp` in Cupertino with an in-memory preferences store; its
toast check calls the presenter directly (Save now really saves).
