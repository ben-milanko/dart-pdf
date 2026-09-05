# An OS file-open lands last in the tab strip, and on screen

Double-clicking a PDF in Finder while DartPDF was closed launched the app,
restored the previous session - and left the user looking at whichever
document restore happened to add last, with the file they had actually
clicked buried at the *front* of the tab strip.

## Root cause

Two asynchronous sources add tabs at startup and neither knows about the
other:

- `_restoreSession()` - recovered unsaved work, then the stored session.
- `_openIncoming()` - the file the OS launched us with.

On Windows the launch file arrives as a command-line argument, so
`_hasExplicitLaunchTarget` sees it synchronously and restore stands down
entirely. macOS has no such signal. `AppDelegate.application(_:open:)`
builds its payload on a background executor (deliberately - resolving an
iCloud placeholder's security scope on the AppKit thread beachballs the
launch), so the file reaches Dart via `getInitialFile` *or* the warm
`openFile` stream, whenever the bookmark is ready. That can be before,
during, or after the store read.

Every `_addTab` appended and took focus, so whoever finished last won the
selection, and the clicked file - which usually arrived first - sat at
index 0. `_replaceLoadingTab` then also yanked focus back to whatever
placeholder it was swapping, which is why the symptom felt intermittent.

## Fix (`app/lib/editor_screen.dart`)

- `_addTab(tab, {restored})`. Restored tabs form a block at the *head* of
  the strip, counted by `_restoredTabs`, and take focus only while nothing
  else is open. A tab the user asked for keeps its place at the end and
  stays the one on screen, whichever order the two sources resolve in.
  The three restore call sites (`_recoverUnsavedChanges`, and both arms of
  `_reopenSessionDocument`) pass `restored: true`; `_openLoading` forwards
  it. `_removeTabs` decrements the count when a restored placeholder is
  dropped (a session file that has since vanished), so the head-block index
  stays honest.
- `_replaceLoadingTab` no longer writes `_activeIndex`. In the normal open
  path the placeholder is already active, so the assignment was a no-op;
  the only case where it did anything was the one where it was wrong.
- `_openIncoming`'s de-dupe moves the matched tab to the end when it is a
  restored placeholder the user has never opened. Without that, the same
  double-click landed in two different places depending on who won the
  race - at the end when the OS beat restore to the file, mid-strip when it
  didn't.

## Tests

`app/test/session_restore_test.dart`:

- *an OS file-open beats session restore to the end of the strip* - gates
  restore on a `_DelayedRecoveryStore` so the `openFile` push lands first
  (the macOS ordering), then asserts strip order and the selected-tab font
  weight.
- *an OS file-open of an already-restored document moves it last* - the
  other half of the race: restore finishes, then the OS hands over a file
  it just restored.

Both fail on the pre-fix `editor_screen.dart`.
