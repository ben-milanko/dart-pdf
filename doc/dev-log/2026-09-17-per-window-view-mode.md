# The view mode belongs to the window (2026-09-17)

Report: "when switching to page grid view, all windows switch. This setting
should be per window."

## What was wrong

The app owns exactly one `PdfEditingPreferences` and hands it to every window -
deliberately, so tool styles, panel layout, theme, and viewport memory are the
same wherever you look (`DartPdfEditorApp._prefs`, and the comment above it
saying secondary windows reuse this state). The view mode lived there too, as
`showReflowView` / `showThumbnailView` behind `PdfEditingPreferences.viewMode`,
and every shell read it live:

```dart
final gridActive = features.thumbnails && prefs.showThumbnailView;
```

So the page grid was not a window's view of its document, it was a process-wide
setting with a UI that looked local. Pick it in one window and every other
window dropped its page out from under the reader - the pref notified, they all
rebuilt, all of them went to the grid.

That it persists is right; that it is shared while you are looking at it is
not. Two windows are two documents on two screens - two reading surfaces - and
the surface owns its mode. Panel layout and tool colour are device preferences
you set once; "am I looking at the pages or at a grid of them" is where you
are right now.

## What landed

**A holder interface and a per-window controller** (`editing_preferences.dart`).
`PdfViewModeHolder` is the two-member surface the chrome binds to - `viewMode`
plus `Listenable`. `PdfEditingPreferences` already had both, so it implements
it as-is. `PdfViewModeController` is the new one: it holds one window's live
mode and writes each change through to the preferences, which keeps the value
persisted - as the mode the NEXT window starts in, not as an order to the
windows already open.

**The shells take one.** `PdfEditorView(viewMode:)` and `PdfReader(viewMode:)`
accept a holder; `EditorScreen` (one per window) creates a controller in
`_viewMode` and passes it to every shell that window builds, plus its own View
commands in the palette. Because the window owns it and not the shell, the mode
survives a tab switch - the app builds a fresh `PdfEditorView` keyed by tab, so
anything owned by the shell would be re-seeded per tab instead.

**A shell given none owns one**, seeded from and written back to its
preferences. That is the whole behaviour a single-window host had, so nothing
embedding `PdfEditorView`/`PdfReader` changes, and the existing tests that set
`prefs.showReflowView = true` before pumping still land in reflow.

## The startup race, and how it is settled

Preferences load asynchronously; the app's first window is built before the
store answers. A controller constructed then reads `PdfViewMode.pages` - the
default, not the user's mode - so it adopts the stored one when `ready`
completes. Unless the user has already picked a mode in that window, which
wins: the same rule (and the same reason) as `PdfEditingPreferences._modified`,
which lets a value set during the read beat the stored one. `_picked` is set
before the equality check in the setter, because choosing the mode you are
already in is still a choice.

Passing `initialMode:` means "this is the window's mode" and skips the adoption
entirely. The shells use it when they have to rebuild an owned controller
because the preferences under them were swapped: the window's mode outlives the
swap, only where it persists changes.

## Tests

- `editing_preferences_test.dart`: one window's choice leaves another's alone
  while still persisting for the next window; the late-load adoption; a mode
  picked during the read beating the stored one.
- `pdf_shell_test.dart`: two `PdfEditorView`s over one preferences object, each
  with its own controller - the grid appears in the first window's subtree and
  not the second's.
- `multi_window_test.dart`: the same at app level with two `EditorScreen`s, and
  the complement - after another window writes a different mode to the shared
  preferences, this window's next tab still opens into the mode this window is
  in. That second one is what fails if the wiring is dropped and each shell
  seeds itself from the preferences: per-tab looks right until another window
  moves.
