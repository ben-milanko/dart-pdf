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
- On touch, a finger drag scrolls the viewer. Text selection, which is how
  the highlighter works, starts with a long press on a word and extends by
  words as the finger drags (`pdf_viewer.dart`, `_onLongPressStart`). The tour
  therefore presses, holds and sweeps. A plain drag happened to select text in
  headless Chromium but failed on the iOS simulator.
- `simctl io recordVideo` prints its status on stdout, and the file only
  appears when recording stops. `record_ios.py` takes time zero from the
  "Recording started" line, or from half a second after launch if that line
  never comes.
- The highlighter snaps to extracted text. If the drag starts before text
  extraction finishes, nothing commits and no error appears. The warm-up is
  12 s, and `_edit` checks `PdfEditingController.revisionId` after each step and
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

## Motion and punch-ins

- `_Hand` motion is timed by the clock (`_animate`), not by counting frames.
  A debug build on the simulator draws slowly, and frame-counted motion
  stretched to match. That was most of why the page drag looked slow and
  stiff. Fingertip moves follow eased Bézier arcs (`_arc`), a tap leaves a
  ripple, and the page move is a `fling`: hold past the long-press threshold,
  a quick arcing flick that overshoots 14 px, then a settle onto the target.
- The tour prints `focus cx cy zoom [now]` and `focus off` (normalised screen
  coordinates). `compose_preview.py` eases between them (`camera_keys`,
  `camera_at`) and renders the screen track in Python: each frame is cropped
  at a fractional window and resized with Lanczos. An ffmpeg
  `scale=eval=frame` + `crop` chain doesn't work for this, because `crop`
  keeps the input size it was configured with while the frame size changes.
- Punch-ins are locked shots, not a follow camera. The first version leaned
  the camera toward the fingertip the whole time it was zoomed in (smoothed,
  with lookahead), and on a phone in the hand that continuous panning read as
  motion sickness. Now the tour logs `hand x y` (about 20 Hz, with a trailing
  `d` while touching) and `hand off`, and `frame_shot` picks one still frame
  per punch-in: the tour's centre, moved the least it can, and widened down
  to a floor of 1.15x if it has to be, so that every point the finger touches
  before the next focus marker sits inside with a 5% margin. The camera only
  moves on the way in and out: 0.6 s of smootherstep, with the zoom eased in
  log space. A tap that should not widen the shot, like the form commit tap,
  goes after `focus off`.
- Alignment comes from the picture, not the logs. One simulator take was cut
  9.5 s late: `simctl` printed "Recording started" 10 s after launch, just past
  the recorder's timeout, and `flutter run` also holds back log lines while it
  syncs files. The tour now flashes the screen magenta for 0.5 s, off-clip,
  and starts its clock on the first frame after the flash. `find_sync` locates
  that frame (60 fps scan) and anchors every marker to it. A recording without
  the flash fails unless `--no-sync` is passed. The warm-up is now 20 s, and
  the recorder waits up to 30 s for simctl.
- A headless-Chromium screencast only sends a frame when the page changes,
  so a static end went missing from drafts. `record_web.cjs` now holds the
  last frame until recording stopped, and the composer pads a short capture
  with its last frame.
- The soft keyboard is hidden while the scripted typing runs, so it doesn't
  cover the field close-up.

## Audio

`compose_preview.py` reuses `doc/marketing/motion/soundtrack.py` unchanged. It
plays the sting's music map from an offset chosen so the 18.55 s chord hit
lands on the closing caption, and turns every `sfx` marker into a soundtrack
cue (`typing` gets a key count from its duration).

## Not yet

- iPad (1200×1600): the tablet toolbar has different keys, so the tour needs a
  tablet path.
- Localised captions (`CAPTIONS` is English only).
