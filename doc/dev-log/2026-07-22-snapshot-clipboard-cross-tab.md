# Snapshot vector clipboard, shared across tabs

The Snapshot tool captures a page region as **both** a raster PNG (dropped on
the system clipboard) and a detached `PdfVectorSnapshot` kept in-app for
paste-back as sharp vector graphics. But the vector half lived on the
capturing `PdfEditingController` (`_snapshotClipboard`), which is **per tab**.
So a snapshot taken in one document tab and pasted into another had no vector
copy in the target tab: `hasSnapshotClipboard` was false there, `⌘V` fell
through to the system-clipboard image path, and the region pasted as a flat
**image** instead of vector.

## The fix — a shared clipboard singleton

Followed the exact `PdfPageClipboard` pattern (see
`2026-07-16-page-clipboard.md`): a new `PdfSnapshotClipboard`
(`editing_snapshot_clipboard.dart`) is a `ChangeNotifier` holding the current
`PdfVectorSnapshot`, with a process-wide `instance`. Every
`PdfEditingController` defaults to it (new `snapshotClipboard` constructor
arg), so cross-tab paste works with **zero host wiring** — the app's
`DocumentTab` still does `PdfEditingController(bytes, preferences: …)` and
automatically shares it. Pass a private clipboard to isolate a session (tests
do).

The snapshot is already fully detached (page content + resources copied
inline), so it survives the source tab being closed entirely — a paste never
touches the originating document.

## Controller changes (`editing_controller.dart`)

- `_snapshotClipboard` field is gone; `copyVectorSnapshot` publishes to
  `snapshotClipboard.set(…)`, `pasteSnapshot` reads
  `snapshotClipboard.snapshot`, `hasSnapshotClipboard` delegates to
  `snapshotClipboard.isNotEmpty`, and `copySelectedAnnotations`'s "last copy
  wins" now `snapshotClipboard.clear()`s.
- The old public `snapshotClipboard` getter (returned the `PdfVectorSnapshot?`)
  is replaced by the shared-clipboard field of the same name; read the vector
  via `snapshotClipboard.snapshot`.
- Per-document paste bookkeeping (`_snapshotPasteCount`, the shared captured
  `/Cap` form ref `_snapshotCapturedRef`) is now keyed to the active
  snapshot's identity via `_snapshotPasteAnchor`. The shared clipboard can
  change under a controller (recapture here, or a capture in another tab), so
  `pasteSnapshot` resets the cascade and drops the captured-form ref whenever
  the snapshot identity differs — the ref was materialized from the *previous*
  snapshot into *this* document and would otherwise be reused wrongly.
- The controller registers/removes a listener on `snapshotClipboard`
  (mirroring `preferences`/`pageClipboard`), so every tab rebuilds its
  Paste-as-vector affordance the instant any tab captures or clears.

## Tests

- `editing_snapshot_test.dart`: two new tests — a capture in one tab pastes as
  vector (`/Cap Do` in the appearance) in another sharing the clipboard, and
  the shared snapshot survives disposing the source tab. A `setUp` clears
  `PdfSnapshotClipboard.instance` so the default singleton can't leak between
  tests; the two vector-getter assertions moved to `.snapshotClipboard.snapshot`.
- `editing_menu_test.dart` / app `snapshot_clipboard_test.dart`: same `setUp`
  clear (both construct default-singleton controllers).
