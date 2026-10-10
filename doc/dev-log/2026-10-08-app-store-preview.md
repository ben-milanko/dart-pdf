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
  information provided". Software GL draws several times slower than a
  device, which frame time (below) absorbs.
- The simulator only runs debug builds. The tour starts after the warm-up, so
  JIT jank stays off the clip.

## Motion and punch-ins

- `_Hand` motion follows eased Bézier arcs (`_arc`), a tap leaves a ripple,
  and the page move is a `fling`: hold past the long-press threshold, a quick
  arcing flick that overshoots 14 px, then a settle onto the target.
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
- The tour runs on frame time (`_FrameClock`). The simulator only runs debug
  builds, and on a CI runner they stall: typing into the form field and
  picking up a page thumbnail each held the UI thread for 1.4-2.4 s, so the
  recording had no frames there. The typed name never appeared and the page
  move jumped. Timing the tour by the wall clock, or slowing it with
  `timeDilation`, can only shrink such a stall. So once the tour starts, the
  clock wraps `PlatformDispatcher.onBeginFrame`/`onDrawFrame`: every counted
  frame gets an engine timestamp exactly 1/30 s after the last, which the app's
  animations see, and the tour's own pauses and motion (`_pause`, `_animate`,
  pointer timestamps) count the same frames. While the app is stalled, its
  world stands still. A frame that comes less than 34 ms of wall-clock time
  after the last counted one redraws the same instant, so tour time never runs
  ahead of the real-time timers that recognisers use (a long press is 500 ms
  of real time). The clock keeps requesting frames, so it ticks even when
  nothing moves.
- Each counted frame paints its number in a 4-logical-pixel strip along the
  bottom edge (`_StampPainter`): white and black reference cells, 13 bits,
  and a parity bit. The composer decodes every captured frame in order, reads
  the strip (`read_stamp`), and writes tour frame k from the latest capture
  stamped k, repeating the previous frame for any number the capture missed
  (none in the Chromium test). It crops 5 logical pixels off the bottom. This
  also replaces the magenta sync flash and the host timestamps: markers are in
  tour milliseconds, which are frame times. The `start` marker carries the
  logical screen size (`start 440x956@3`), which sizes the strip.
- simctl's H.264 has B-frames whose decode timestamps run seconds behind
  their presentation timestamps. ffmpeg uses the presentation clock unless
  one frame arrives out of order (a duplicate timestamp is enough), and then
  quietly switches to the decode clock for the whole file. Before frame time,
  one take came out with the sync flash on screen and every step about 2 s
  early. Frames are now placed by their stamps, but the composer still
  decodes with `-fflags +igndts` (`SOURCE`) to keep them in presentation
  order.
- A headless-Chromium screencast only sends a frame when the page changes.
  Every counted frame changes the stamp, so each one arrives;
  `record_web.cjs` keeps them all (`-fps_mode passthrough`).
- Tour time is slower than real time on the simulator (one tour second took
  about 5.4 s on CI), and the gesture recognisers time presses by the wall
  clock. A tap held for 70 ms of tour time lasted almost a second there and
  read as a long press, so the form field never opened. `_Hand.tap` holds for
  70 ms of real time; long presses and drags are safe because tour time never
  runs ahead of real time. The tour also finds the form editor by its key
  (`pdf-form-text-editor`) and waits for it, rather than looking for the
  focused field.
- `_type` checks after the last character that the field shows the whole
  name, so a take where the text never made it into the field fails.
- The system keyboard is switched off for the scripted typing:
  `TextInput.setInputControl(null)` before the tap on the field, then
  `restorePlatformInputControl()` after the commit. Calling `TextInput.hide`
  once was not enough on the simulator: the keyboard came back up during
  typing, covered the frame stamps (so the composer dropped those frames) and
  shrank the viewer until the field sat behind it. Chromium has no on-screen
  keyboard, so web drafts never showed this.
- `simctl io recordVideo` keeps up with about 16 fps on a CI runner. With
  34 ms frames it missed 338 of 657 tour frames, so record_ios.py passes
  `--dart-define=PREVIEW_FRAME_MS=100`. That alone still missed 163: opening
  the page grid and dragging a thumbnail kept the debug raster thread busy
  for seconds while the UI thread kept counting frames, and the engine never
  shows the frames it skips (one stretch drew 19 tour frames in 3.2 s with
  nothing on screen). So a frame now counts only after the engine has
  reported the previous counted frame rasterised (`addTimingsCallback`, about
  every 100 ms in debug builds, matched on `frameData.frameNumber`), and then
  shown it for `PREVIEW_FRAME_MS`. After 2 s without a report it counts
  anyway, and the tour prints how often that happened. In Chromium every
  frame was captured (38 timeouts, which only cost recording time). The
  composer warns when more than 1% of tour frames repeat the one before.
- iPad (1200×1600): the tablet toolbar has different keys, so the tour needs a
  tablet path.
- Localised captions (`CAPTIONS` is English only).
