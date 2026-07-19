# Web recent-files storage via IndexedDB

The app already had the whole recent-files / restore-last-session machinery
(`RecentsStore`, `SessionStore`, the welcome-screen tiles, the Open Recent
menu). It just went dark on the web: a browser pick hands back only bytes with
no reusable path, so there was nowhere to read a recent back from. Web entries
recorded a title but were non-reopenable ("Pick again to reopen"), and session
restore on web was a no-op.

The fix reuses the existing `pdf_cache.dart` byte-snapshot seam - the same seam
that already lets a *mobile* pick reopen from a private-file snapshot - and
gives the web a backend for it.

## What changed

- `app/lib/pdf_cache.dart` - the conditional export grew a third arm:
  `pdf_cache_stub.dart` (default) → `pdf_cache_io.dart` (`dart.library.io`) →
  `pdf_cache_web.dart` (`dart.library.js_interop`). Conditions are evaluated in
  order, first match wins; web has js_interop and not io. Mirrors the example's
  `persistent_cache.dart` seam.
- `app/lib/pdf_cache_web.dart` (new) - an IndexedDB store. `canCacheRecentPdfs`
  is `true`, `cacheOpenedPdf` writes the bytes under a sha1 content-hash key and
  returns the key (content-addressed, so re-picking the same file dedupes and
  keeps a stable Recent identity), `readCachedPdf` reads them back, and
  `pruneCachedPdfs` drops keys no Recent entry still references. The IDB open /
  upgrade robustness (reopen at the next version if the store is missing) is
  lifted from the example's `persistent_cache_web.dart`. `localStorage` was a
  non-starter here - ~5 MB, synchronous, string-only; IndexedDB stores binary
  blobs.
- `app/lib/pdf_cache_stub.dart` / `pdf_cache_io.dart` - gained the new
  `readCachedPdf`. Native returns `null`: its snapshot key is a real filesystem
  path, so `readPdfAtPath` reads it directly and never routes through the store.
- `app/lib/file_io.dart` - `readPdfAtPath` gets a `kIsWeb` fast-path at the top
  that reads from the cache store (the key is not a filesystem path on web).
  Native code below it is untouched (the branch is tree-shaken off-web).

No UI changed. Making `canCacheRecentPdfs` true on the web is enough to light
up the already-built flow: `_openLoadedBytes` now routes web picks through
`_snapshotOpenedDocument` → `cacheOpenedPdf`, which stamps the tab's
`cachePath`; from there the welcome-screen tiles, the Open Recent menu, and
(as a free bonus, since it keys off the same `cachePath`) session restore all
work on the web exactly as they do on mobile.

## Gotchas

- **IndexedDB transactions auto-commit when they go idle.** `pruneCachedPdfs`
  originally reused one readwrite transaction across `getAllKeys()` + awaited
  `delete()`s - the transaction would already be inactive by the second delete.
  It now opens a fresh transaction per delete, matching the reference store's
  one-request-per-transaction shape. Every op also degrades to a miss on
  failure, so a blocked/quota'd IndexedDB (private mode) just leaves entries
  non-reopenable rather than breaking the app.
- The web IDB backend can't be unit-tested in the VM suite (needs a real
  browser), and the repo has no browser-test harness - matching the existing
  untested `persistent_cache_web.dart`. The platform-agnostic model logic
  (`RecentFile.cachePath` / `readPath` / `id`) is already covered in
  `recents_test.dart`. Verified with `flutter build web` (compiles + WASM dry
  run passes) and the existing recents/session VM tests.
