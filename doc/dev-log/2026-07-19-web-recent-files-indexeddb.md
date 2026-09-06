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
- `app/lib/file_io.dart` - `readPdfAtPath` gives the snapshot store first
  refusal unconditionally: `readCachedPdf(path)` runs first, and only if it
  declines (returns null) does it read `path` off disk. Native's store always
  declines, so its filesystem read is unchanged; the web store returns the blob
  or throws on a miss (the web has no filesystem to fall back to). No `kIsWeb`
  branch - which also means these shared-file lines execute in the native VM
  tests (see the codecov note below).

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
- The web IDB backend (`pdf_cache_web.dart`) can't be unit-tested in the VM
  suite (needs a real browser), and the repo has no browser-test harness -
  matching the existing untested `persistent_cache_web.dart`. Because it's a
  web-only conditional import it isn't compiled into the VM test run, so
  codecov never counts its lines - the platform-agnostic model logic
  (`RecentFile.cachePath` / `readPath` / `id`) is already covered in
  `recents_test.dart`. Verified with `flutter build web` (compiles + WASM dry
  run passes) and the existing recents/session VM tests.
- **codecov `patch` is a blocking status** (`codecov.yml`, `informational:
  false`, target 65%). The first cut hid the web read behind `if (kIsWeb)` in
  `file_io.dart` - three new lines in VM-compiled files that were structurally
  unreachable in the VM suite, so patch coverage was 0%. The store-first-refusal
  shape above fixed both design and coverage: the shared lines now run in the
  native tests, and everything genuinely web-specific lives in the uncounted
  web-only file. `file_io_test.dart` adds a direct `readPdfAtPath` test to lock
  it in.
