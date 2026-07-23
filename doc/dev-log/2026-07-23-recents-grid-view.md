# Recent-files grid view with thumbnails

Follow-on from #508 (first-page thumbnails in the recents list). The welcome
screen's "Recent" section can now render as a **thumbnail grid** in addition
to the list. The grid is the default on larger screens; the list stays the
default on narrow ones (phones / narrow windows), matching how people expect
a file browser to adapt.

## What landed

- `app/lib/welcome_screen.dart` - `WelcomeScreen` became a `StatefulWidget`
  that holds a nullable `RecentsView` override. A `LayoutBuilder` picks the
  default layout from the body's available width: **grid at ≥ 700 px, list
  below** (`_gridDefaultBreakpoint`, aligned with the editor's own mobile
  breakpoint). While the override is null the layout follows the width, so
  resizing flips the default; a `_ViewToggle` (`SegmentedButton` of
  list/grid segments beside the "Recent" header) sets an explicit override
  that then sticks. The `ConstrainedBox` widens to 900 px in grid mode
  (vs 520 for the list) so several tiles fit per row.
  - `_RecentsList` is the old list, unchanged in behaviour.
  - `_RecentsGrid` is a scrolling `Wrap` of `_RecentGridTile`s - a large
    letterboxed thumbnail (150×190) with the title below, a corner remove
    button, tap-to-open, and a tooltip carrying the full title/path. Dimmed
    and non-tappable when the entry isn't reopenable.
  - `_RecentThumbnail` replaces `_RecentLeading` and is shared by both
    layouts. It keeps #508's fetch-once/hold-across-rebuilds behaviour and
    gains a `fill` flag: false (list) hugs the border to the rendered image
    as before; true (grid) sizes the image to fill the box so tiles line up
    regardless of page aspect ratio or device pixel ratio.
- `app/lib/recent_thumbnails.dart` - default `longestSide` bumped 96 → 240
  so the grid's ~150 px tiles stay crisp on high-DPI screens (the list draws
  the same raster at ~40 px). Everything else (LRU, null memoization,
  injectable reader) is unchanged.
- `app/lib/l10n/*` - `welcomeViewAsList` / `welcomeViewAsGrid` tooltip
  strings for the toggle (added to `app_en.arb` and the checked-in generated
  `AppLocalizations` / `AppLocalizationsEn`).

## Gotchas

- The default widget-test surface is 800×600, i.e. wide → grid. Tests that
  want a specific layout pin the surface with `setSurfaceSize` (narrow 420
  for list, wide 1000 for grid).
- `gen-l10n` can't run standalone here (`flutter: generate` isn't enabled),
  so the generated localization Dart is hand-edited to mirror the `.arb`
  additions - same as the rest of the repo's checked-in l10n.
- Layout is chosen from the `LayoutBuilder` constraint (the body width), not
  `MediaQuery`, so it reacts to the actual space the welcome screen gets.

Tests: `app/test/welcome_screen_test.dart` gains narrow-defaults-to-list,
wide-defaults-to-grid, and toggle-overrides-the-default cases (the existing
thumbnail/fallback cases now pin a narrow surface). `recent_thumbnails_test`
is unchanged and still green.
