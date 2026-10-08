# App Store preview: a scripted recording of the real app

The sting (#1035, #1043) can't be an App Store preview. Guideline 2.3.4 and
Apple's [preview guidance](https://developer.apple.com/app-store/app-previews/)
only accept screen captures of the app, plus captions, touch hotspots, simple
fades and a soundtrack. So the preview is the real app driven by a script and
recorded. How to run it is in `doc/marketing/motion/README.md` (App Store
preview).

## Pieces

- `app/tool/preview_main.dart` is the tour: the app shell (as in
  `screenshots_main.dart`, empty prefs) with an `IgnorePointer` fingertip
  painter on top. `_Hand` sends `PointerDown/Move/Up` (touch) through
  `GestureBinding.handlePointerEvent`, so the app's own recognisers handle every
  tap, drag and long press. Targets are found by `ValueKey` in the element tree
  (`_rectsWhere`). Page coordinates map through the top page's rect, using
  `pdf-editing-layer` or `pdf-page-direct-picture`.
- `app/tool/preview_document.dart` builds the three-page proposal in code, so
  the highlight line, field and signature line sit at known PDF coordinates
  (`PreviewLayout`).
- `app/tool/preview/record_ios.py` records it on the simulator.
  `record_web.cjs` records a draft in headless Chromium.
  `compose_preview.py` cuts, captions, scores and encodes.
- The **Marketing screenshots** workflow has an `app_preview_only` input that
  runs the macOS job and uploads `app-preview-iphone`.

## Gotchas found driving the phone layout

- The Tools sheet has group tabs (`pdf-group-tab-<group>`), and tiles only
  exist under the open tab. Markup tiles (`pdf-markup-highlight`) close the
  sheet; tool tiles (`pdf-tool-ink`) leave it open. The tour waits for it to
  slide away and only dismisses it (scrim tap) if it is still up. An
  unconditional scrim tap landed on the page while the highlighter was armed
  and swallowed the next highlight.
- Sheets slide in, so `_waitFor` only returns a rect once it has held still
  across two polls. A tap on a moving sheet hits the wrong cell.
- The Select tab arms Select and closes the sheet, because it holds one tool.
- `pdf-editing-layer` collapses to 0×0 while a tool arms, so the page rect
  falls back to the page picture and caches the last good answer.
- The highlighter snaps to extracted text. If the drag starts before text
  extraction finishes, nothing commits and no error appears. The warm-up is
  8 s, and `_edit` checks `PdfEditingController.revisionId` after each step and
  fails the take if it didn't move.
- Reordering uses the page grid (`pdf-shell-page-grid-toggle` in the "…" sheet,
  cells `pdf-thumbnail-grid-cell-<i>`): long-press past the threshold, then drag
  onto the left edge of the target cell.
- The tool sheet's palette circles have no keys. They are found by their
  `BoxDecoration` colour (`_isSwatch`).
- Headless Chromium needs `locale: 'en-US'`, or the app throws "Incorrect locale
  information provided". With software GL the tour runs about 3× slower, so the
  composer takes `--speed`.
- The simulator only runs debug builds. The tour starts after the warm-up, so
  JIT jank stays off the clip.

## Audio

`compose_preview.py` reuses `doc/marketing/motion/soundtrack.py` unchanged. It
plays the sting's music map from an offset chosen so the 18.55 s chord hit
lands on the closing caption, and turns every `sfx` marker into a soundtrack
cue (`typing` gets a key count from its duration).

## Not yet

- iPad (1200×1600): the tablet toolbar has different keys, so the tour needs a
  tablet path.
- Localised captions (`CAPTIONS` is English only).
