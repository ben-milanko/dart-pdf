# Ship the changelog with the app

The release notes existed in three places a user could not reach from the
running program: `app/CHANGELOG.md` in the repo, the GitHub release body, and
the per-locale Play Store changelogs under `app/fastlane/`. This bundles the
first one into the build.

## What landed

- `app/pubspec.yaml` declares `CHANGELOG.md` as a Flutter asset. The file the
  release is cut from travels inside the binary, so the notes and the build
  cannot drift, and reading them needs no network call (the web build included).
- `app/lib/whats_new.dart`: `parseChangelog` (markdown → `ChangelogRelease`
  sections), `changelogSpans` (inline `**bold**` / `` `code` ``),
  `loadAppChangelog` (memoized `rootBundle` read) and `showWhatsNew` (the
  dialog, newest release first, the running version's section badged from
  `AppInfo.version`).
- Entry points: a **What's new** tile in Settings > About, above View licenses,
  and a command-palette entry (`whats-new`).

## Why a hand-rolled parser

The changelog is written to exactly one shape - `## <version>` over `- `
bullets that hard-wrap at 80 columns, with `**bold**` and `` `code` `` inline,
no nesting and no links. That is four rules; a markdown package would be a new
dependency and a second renderer to theme. The parser rejoins wrapped lines
(indented continuation), treats a blank line as the end of a bullet, and keeps
the heading text verbatim - so a build cut before the release rolls
`## Unreleased` into `## X.Y.Z` shows "Unreleased" rather than inventing a
version.

## Where it is *not*

Not in the app menu. The App section deliberately holds one row (Settings), and
`_appMenuItems` only draws a section header over two rows or more - a second
row would turn the bare divider into an `APP` header for a feature that belongs
under About anyway. So the palette command is registered by hand in
`_paletteCommands()` rather than falling out of `_appActions()`, and its source
column reads "Settings", which is where it actually lives.

There is no automatic pop-up after an update. Everything here is one call
(`showWhatsNew`) away from becoming one - store the last-seen version in
`PdfEditingPreferences` and compare on launch - but an unrequested modal on
first launch is a product decision, not a plumbing one.

## Test gotcha

`rootBundle` memoizes the load per asset key, and a future that completed
inside a finished widget test's fake-async zone never resolves for the *next*
test's listeners: the completion microtask is scheduled in the dead zone, the
dialog's spinner never stops, and `pumpAndSettle` times out. Both the parsed
memo (`debugResetChangelogCache`) and the bundle's own cache
(`rootBundle.evict`) have to be cleared in `setUp` so each test gets a cold
read. Note the symptom is order-dependent: the test passed on its own and hung
only when a previous test in the same file had already read the asset.

`app/test/whats_new_test.dart` covers the parser, the span splitter, both
dialog entry points, and - deliberately without a fake bundle - one read of the
real bundled asset, so deleting the pubspec asset line fails a test instead of
shipping an empty dialog.
