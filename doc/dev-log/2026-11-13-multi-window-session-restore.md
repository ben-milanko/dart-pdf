# Resume multi-window sessions (2026-11-13)

Request: "add support to resume multi window sessions on close."

Before this, only the primary window persisted the restore list
(`ownsApplicationSession`), so quitting with three windows open relaunched
into one window holding the primary's tabs - every secondary window's
documents were lost.

## What landed

- **`WindowSessions`** (`app/lib/window_sessions.dart`) - the process-wide
  session, owned by `DartPdfEditorApp` (only when `multiWindowSupported`).
  Each window holds a `WindowSessionSlot`, which *is* that window's
  `SessionPersistence`, so `DocumentLibrary` is unchanged: every tab change
  saves the window's documents into its slot, and the slot writes the whole
  session. Slots are ordered by window open order; empty windows are not
  persisted.
- **`SessionStore` is now `WindowSessionPersistence`** (`loadWindows` /
  `saveWindows`). The flat key `dart_pdf_editor_app.session` is still written
  (every document, deduped across windows) and the grouping goes under
  `dart_pdf_editor_app.session.windows`. `load()` returns the flat list, so
  single-window platforms and older builds restore everything into one window.
  The grouping is trusted only while its flattening equals the flat list - an
  older build rewrites only the flat key, and its set then wins.
- **Restore** (`EditorScreen._restoreSession`): the primary reopens window 0
  itself and asks `onRestoreWindow` to open each other window with a slot
  pre-seeded with its documents (`sessions.open(documents:)`), so the session
  keeps describing that window while it reopens. The new window's
  `EditorScreen(sessionSlot:)` reopens them (`_restoreWindowSession`, the same
  `_reopenSessionDocuments` loop as the primary). If the native window can't
  be created, the slot is discarded and its documents restore into the
  primary. `markLoaded()` (after the primary's restore) starts writing;
  nothing is written before, so early opens can't clobber the stored session.

## Close semantics (browser rule)

- Closing one window while others remain forgets it
  (`_requestNativeWindowClose` -> `slot.close()`; also covers the window
  that closes itself when its last tab is dragged out).
- Closing the **last** window keeps its slot: on Windows/Linux that close is
  the quit, and the next launch should resume it.
- Quitting (macOS Cmd+Q) tears windows down via `onWindowDestroyed` without a
  close request; `dispose` only `detach()`es, which keeps the slot and ignores
  any later writes from it. A detached slot doesn't count as "another window
  open", so closes during teardown can't forget the remaining windows.

A secondary window not restoring now sets `sessionLoaded` immediately (and
persists, which records a tab handed over at creation). Side effect: its
welcome screen shows Recent thumbnails, which were previously gated forever
on secondaries because `sessionLoaded` never flipped.

## Not done

- Window size/position and the active tab are not persisted - windows reopen
  at the default size, with the same active-tab rule as single-window
  restore.
- An explicit launch target (a `.pdf` on the command line) still skips
  restore and then overwrites the stored session, as it did single-window.

## Tests

- `window_sessions_test.dart` - write gating, ordering, empty windows,
  close-one vs close-last, quit/detach, failed restore.
- `session_store_test.dart` `windows` group - round-trip, flat fallback,
  legacy session as one window, older-build rewrite wins.
- `multi_window_session_test.dart` - primary splits the restore and hands the
  rest to `onRestoreWindow`; failed window restores into the primary; a
  restored secondary reopens its documents and closing it (with another open)
  drops it; closing the last window keeps it.
