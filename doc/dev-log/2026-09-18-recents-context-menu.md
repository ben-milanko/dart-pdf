# Right-click menu for the Open Recent view

A recent entry on the welcome screen (and in the full recent-files browser
behind *Open Recent → View all recent files…*) now answers a right-click -
and a long-press on touch - with a context menu, the way a tab in the strip
already did.

## The menu

`showRecentContextMenu` (`app/lib/welcome_screen.dart`) offers, in order:

- **Open** - the only item shown disabled rather than hidden. An entry that
  can't be reopened (a web pick with no snapshot, an evicted mobile cache)
  is exactly the case the rest of the menu is for, so the menu still opens
  on it and only the open action is greyed.
- **Open in new window** - present only when the host supplies
  `onOpenRecentInNewWindow` *and* the entry is reopenable.
- **Open in Finder / File Explorer / containing folder** - desktop only
  (`supportsOpenContainingFolder`), and only for an entry with a real
  origin path. The macOS reveal reuses the entry's security-scoped
  `bookmark`, same as the tab menu.
- **Copy path** (path-backed entries) / **Copy name** (always).
- **Remove from recent** / **Clear recent files**.

The rows are the app menu's tight 36px on desktop and the full tap target
on touch, mirroring the editor screen's `_appMenuItemHeight`; the two
constants are private there, so the rule is restated (and commented) rather
than reached for.

## Two gesture placements, not one

`_RecentContextMenuTarget` carries the gesture (`onSecondaryTapUp` +
`onLongPressStart`, both of which hand over a global position, so the menu
opens where the user pointed). Where it sits differs by layout:

- the **list** wraps the whole `ListTile` from outside;
- the **grid** wraps *inside* `_RecentGridTile`'s `Tooltip`. A tooltip owns
  a long-press recognizer of its own, and a recognizer nested deeper wins
  the arena - wrapping the tooltip from outside silently lost every
  touch-platform long-press to the tooltip. The regression test long-presses
  a grid tile and expects the menu.

## Opening into a second window

`EditorScreen._openRecentInNewWindowAsync` reads the entry and hands the
bytes to `onNewWindow` as a `DocumentHandoff` with `savedLength ==
bytes.length` (read, not edited - the receiving window starts clean).
Unlike `_openRecent` it can't open progressively: a handoff is bytes in
hand. The read-failure path matches `_openRecent`'s - drop the entry (or
mark the snapshot missing), prune the cache, toast "Could not reopen" - and
a successful hand-off still bumps the entry to the front of the shared
recents, because the document *is* open, just elsewhere.

## Testing note

`app/test/multi_window_test.dart`'s new case reads a real file through
`readPdfAtPath`. Real I/O does not progress inside the binding's fake-async
zone, so the whole interaction (pump, right-click, menu tap) runs under
`tester.runAsync` with interleaved real delays, the pattern
`session_restore_test.dart` already uses for path-backed opens. Awaiting
`Directory.systemTemp.createTemp` from the test body hangs the test for the
same reason - the fixture is written with the `…Sync` calls.
