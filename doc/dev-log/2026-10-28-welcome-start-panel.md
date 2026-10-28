# Welcome screen start panel redesign

The empty-state welcome screen (`app/lib/welcome_screen.dart`) was a 420px
filled card with a 64px PDF glyph, "Drop PDF to open" and one button - a small
grey slab adrift in an empty window that didn't look like a drop target and
didn't say what the app does. Hill-climbed against widget-test renders (real
Roboto + MaterialIcons loaded through `FontLoader`, `RenderRepaintBoundary.
toImage` to PNG) at 1600x900 dark/light, with recents, and 400px phone widths.

What `_StartPanel` is now:

- A **dashed drop zone** (`_DashedBorderPainter`, a `foregroundPainter` - as a
  background painter the fill covers it) on `surfaceContainerLow`, only where
  the host takes window drops (`_acceptsFileDrops`: desktop and desktop web).
  Touch platforms get the same panel without the dashes.
- A tonal `primaryContainer` circle with `upload_file_outlined`, a
  `headlineSmall` headline ("Drop a PDF here", or "Open or create a PDF" where
  nothing can be dropped - the old fallback would have repeated the button
  label) and a one-line capability subtitle.
- **Open a PDF** (filled) beside **New document** (outlined, 48px tall).
  `WelcomeScreen.onNewDocument` is optional; `EditorScreen` wires it to
  `_newDocument`. The pair sits side by side when both labels fit and stacks at
  one shared 280px width otherwise. The decision measures the labels
  (`_buttonWidth`, TextPainter at the current text scaler) - a fixed width
  breakpoint overflowed in the widget tests (Ahem is wide) and would in long
  locales.
- The site's privacy promise under the zone, with a lock icon
  (`welcomePrivacy`; translations reuse `site/i18n/*.json` `privBand_h2`).
- `compact` (recents present on a narrow surface *or* one shorter than
  `_compactHeroHeight` = 760) drops the icon and tightens the padding, so the
  recents stay above the fold. Without the height half, an 800x600 window
  pushed the first grid tile off-screen (`multi_window_test` and
  `progressive_open_test` tap it on the default test surface).

Recent-file placeholders (no thumbnail yet / render failed / no cache) are now
a page-shaped `surfaceContainerHigh` sheet with an `outlineVariant` hairline,
so grid tiles have a visible body and the corner remove button sits on
something instead of floating in space.

New strings: `welcomeDropHeadline`, `welcomeHeadline`, `welcomeNewDocument`,
`welcomePrivacy`, `welcomeSubtitle` (all 22 app locales).

## Second pass

- The **whole zone opens the picker** (`welcome-drop-zone`, a semantics-free
  `GestureDetector` - the buttons keep the accessible actions), and on hover
  the dashes turn `primary` and the fill takes a 6% primary tint.
- **Shortcut hints** inside the buttons (`⌘O`/`⌘N`, `Ctrl+O`/`Ctrl+N`) on
  native desktop only (`_shortcutHint`; the browser claims these chords, and
  touch rarely has a keyboard). `_buttonWidth` includes the hint, so the
  side-by-side/stacked decision still holds.
- Recent grid tiles' **remove button waits for hover** on mouse platforms
  (`_HoverBuilder` + `_revealed`): faded out it ignores pointers but stays in
  the semantics tree; touch platforms keep it shown.
- Harness gotcha: hover fades are `AnimatedOpacity`/`AnimatedContainer`, so a
  single `pump(duration)` captures their first frame - `pumpAndSettle` first.
