# Recent-files list shows first-page thumbnails

The welcome screen's "Recent" list previously showed a generic
`Icons.description_outlined` beside every entry. It now shows a small
rendered thumbnail of the document's first page, falling back to that icon
while the render is pending or when no thumbnail can be produced.

## What landed

- `app/lib/recent_thumbnails.dart` - `RecentThumbnailCache`. Given a
  `RecentFile`, it reads the entry's bytes from its `readPath` (default
  `readPdfAtPath`, injectable for tests), opens the PDF, and rasterizes the
  first page to PNG bytes via `PdfPageExport.exportPage(page, scale: …)`,
  sized so the longest side is `longestSide` px (default 96). Results are
  memoized by `RecentFile.id` - including a cached *null* for entries with
  no readable source (a web pick with no snapshot) or a file that fails to
  open, so a failed render isn't retried on every rebuild. Bounded LRU
  (`maxEntries`, default 32; the list shows at most ~20).
- `app/lib/welcome_screen.dart` - the row `leading` is now `_RecentLeading`,
  a small `StatefulWidget` that fetches the thumbnail once per entry (keyed
  on `entry.id`) and holds the future across rebuilds so scrolling / recents
  changes don't flash back to the placeholder. Draws the PNG with
  `Image.memory` inside a hairline border, `~40×52`. `WelcomeScreen` gained
  an optional `thumbnails` param; null keeps the old icon-only behaviour.
- `app/lib/editor_screen.dart` - owns one `RecentThumbnailCache` alongside
  `_recents` (disposed with it) and passes it to `WelcomeScreen`.

## Gotchas

- Rendering needs `dart:ui` rasterization, so the cache's render path only
  works under a live binding - the unit tests use `testWidgets` +
  `tester.runAsync`, not bare `test`.
- `PdfBlankDocument` is not re-exported from `dart_pdf_editor`; import it
  from `package:pdf_document/pdf_document.dart` in tests.
- The thumbnail is keyed by `RecentFile.id` (the path / cache path), so
  re-opening the *same* path reuses the cached render for the session; the
  cache is in-memory only (no disk write-through), so a cold launch
  re-renders visible thumbnails lazily.

Tests: `app/test/recent_thumbnails_test.dart` (render → PNG, memoization,
null source, memoized read failure) and `app/test/welcome_screen_test.dart`
(thumbnail appears after render; icon fallback without a cache).
