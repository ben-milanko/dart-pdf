# Mobile: reopen Recent files & restore the last session

The desktop/web app (`app/`) tracked Recent files and the previous session by
the picked file's on-disk **path**. Mobile picks (`file_selector` on Android/
iOS) hand back a sandboxed copy with no durable path, so a Recent entry there
was dead: the welcome list showed "Pick again to reopen" and the tap did
nothing, and session restore was always a no-op. This landed a private byte
snapshot so mobile behaves like desktop - tap a Recent to reopen, and the last
session restores on relaunch.

## What landed

- `app/lib/pdf_cache.dart` (+ `_io.dart`, `_stub.dart`) - a conditional-import
  seam like `platform_fonts.dart`. On Android/iOS (`canCacheRecentPdfs`) it
  copies opened bytes into `getApplicationSupportDirectory()/recent_pdfs/`,
  named by a SHA-1 of the bytes so re-opening the same document reuses one file
  (`cacheOpenedPdf`). `pruneCachedPdfs(keep)` deletes snapshots no Recent entry
  references any more. Desktop keeps the real path (no snapshot), and the web
  stub returns null - re-opening there still needs a fresh pick. New deps:
  `path_provider`, `crypto` (both already transitive).
- `RecentFile.cachePath` + `readPath`/`id`/`isReopenable` - `readPath` is the
  real origin when present, else the snapshot. `cachePath` is **not** a writable
  origin (never fed to in-place save), so mobile saves still go save-as. Persist
  key `'c'`.
- `SessionDocument.cachePath` + `readPath`; `SessionStore.load` now keeps any
  doc whose `readPath` is non-null (was: non-empty `path`), so mobile picks
  persist and restore.
- `DocumentTab.cachePath` - carried on `loading`/`document` tabs so the tab
  re-persists into the session and keeps its Recent entry reopenable across
  edits.
- `editor_screen.dart` wiring:
  - `_openLoadedBytes` snapshots the bytes when there's no `originPath`
    (`cacheOpenedPdf`), threading `cachePath` into the tab and the Recent entry.
    No-op on desktop (has an origin) and web (no store).
  - `_openRecent` reads back `entry.readPath`, but the reopened tab's writable
    origin stays `entry.path` (null on mobile). `_reopenSessionDocument` and
    `_persistSession` mirror this (track by path, else snapshot).
  - Dedup (`_restoreSession`, `_recentMenuEntries`) keys on the effective
    identity: origin path, else snapshot, else title.
  - `_pruneRecentCache()` runs after the Recents load and after a stale entry is
    dropped, so orphaned snapshots don't accumulate as entries roll off the
    capped list.
- `welcome_screen.dart` - a cache-backed (reopenable, no path) entry now reads
  "Tap to reopen" instead of the disabled "Pick again to reopen".

## Gotchas

- `defaultTargetPlatform` is `android` under `flutter_test`, so `cacheOpenedPdf`
  actually runs the `path_provider` channel there - with no mock it throws
  `MissingPluginException`, which is caught and returns null. Widget tests that
  don't mock `path_provider` simply get no snapshot (desktop-equivalent), which
  is fine.
- Content-addressing means a Recent entry snapshots the bytes *as opened*; an
  edited-then-reopened Recent shows the originally-opened version (same as
  desktop reopening the on-disk file, minus any later on-disk change).

## Tests

- `recents_test.dart` - cache-backed entry is reopenable, reads from the
  snapshot, dedupes by it, and round-trips across loads.
- `session_store_test.dart` - cache-backed (empty-path) doc round-trips and
  restores; a doc with neither path nor cache is dropped.
- `session_restore_test.dart` - "restores a mobile document from its private
  snapshot" reuses a real temp file as the snapshot and asserts the tab opens.
