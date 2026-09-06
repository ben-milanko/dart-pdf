# 2026-07-19 — devtools mobile bottom sheet + touch-input logging

Three things this session, driven by a mobile report: "panning while zoomed
doesn't work from a fresh app open, but works after I pick the select tool."

## 1. Devtools as a bottom sheet on phones

`DevToolsPanel` was always a right-docked side panel (`PdfSidebarPanelFrame`,
`dock: right`). On a phone there's no room for a side dock. Added a
`bottomSheet` flag to `DevToolsPanel`:

- `_buildDocked` — the existing side dock (wide screens).
- `_buildBottomSheet` — a rounded, height-capped (`0.6 * screen`) card anchored
  to the bottom, with a grab-handle affordance and its own close button. It
  runs `PdfSidebarPanelFrame` in `bottomSheet: true` mode (which returns raw
  content — no grip, no fixed cross-axis size), so the sheet owns the surface,
  the height cap, and the handle. The frame's `geometry.closeButton()` is null
  in bottom-sheet mode, so `_header` supplies an explicit close.
- Shared section list factored into `_scrollBody(theme, geometry)`.

`editor_screen.dart` picks the presentation by width (`_isCompactWidth`, the
same 700px breakpoint the mobile tab strip uses): docked in the `Row` on wide
screens, a scrim-less bottom `Positioned` (+`SafeArea`) overlay on phones. Both
are scrim-less so the viewer underneath still takes gestures — matching the
docked panel, which never blocked the viewer either.

## 2. Optional touch-input logging (the diagnostic for #3)

The pan bug does **not** reproduce in `flutter_test` — `editing_ipad_test.dart`'s
"fresh touch pans reach all page edges after a pinch" passes, and a repro with
40 tiny (a-few-px) move steps and `tool == null` also reached the page edge. So
the viewer's gesture arena is correct in isolation; the failure is device-only.
That means we need on-device signal, so I added logging to the devtools:

- **`pdfDebugGestureLog`** (new global in `debug_overlays.dart`) — an optional
  `void Function(String)?` sink. Null by default (one null-check per gesture
  decision, nothing allocated). `pdfLogGesture(msg, [detailsThunk])` is the
  call site helper; the details string only builds when a sink is installed.
  Instrumented the viewer's discrete pan/zoom **decisions** (never per-move):
  - `_zoomedTouchPanEnabledAt` — the enable-gate verdict per pointer-down
    (`ENABLED viewer owns pan` / `DISABLED overlay owns page` / `ENABLED canvas
    gap`), with the current tool.
  - `_onZoomedTouchPanStart/End/Cancel` — the viewer's own zoomed touch pan.
  - `_onPinchStart/End` — the eager pinch recognizer.
  - `InteractiveViewer` `onInteractionStart/End` — reveals when **IV itself**
    claims a touch (it stays wired with `scaleEnabled` and `panEnabled: false`,
    so a single-finger drag it wins is a silent no-op — the leading suspect).
  - overlay `viewport-pan START` in `editing_overlay.dart` — the select-tool /
    armed-tool path.

- **`AppDevTools.logTouchInput`** (persisted option) — when on, sets
  `pdfDebugGestureLog` to funnel the above into the log tagged `gesture:`, and
  captures **raw** pointer summaries tagged `touch:`. A passive `Listener`
  wrapping the editor body (`_devToolsPointerLog`, gated on `kDevToolsEnabled`)
  feeds `logPointerEvent`. It's a `Listener`, not a recognizer, so it never
  joins the arena and can't affect panning. One line per gesture on down and
  up/cancel (net move, path length, move count, duration) — never per move, or
  a 60–120 Hz drag would drown the 500-entry ring. Mouse/trackpad filtered out.

Toggle lives in the panel's Log section ("Log touch input"); filter the log for
`touch` or `gesture` to isolate. Export-snapshot already dumps the log to JSON.

## 3. The pan bug itself — not fixed yet, deliberately

Leading hypothesis (to confirm with on-device logs): with `tool == null` the
viewer's `_ZoomedTouchPanRecognizer` is supposed to own single-finger pans, but
`InteractiveViewer`'s own `ScaleGestureRecognizer` (live because
`scaleEnabled: !_drawToolArmed`, and **select is not a draw tool**) wins the
arena on-device and eats the drag as a no-op (`panEnabled: false`). Select
"fixes" it because arming a tool flips `_zoomedTouchPanEnabledAt` to route the
page through the editing overlay's opaque, deepest `GestureDetector`, which
beats IV. If the logs show `InteractiveViewer interaction START` (and **no**
`viewer zoomed-touch-pan START`) on a fresh-open pan, that confirms it, and the
fix is to stop IV from claiming single-finger touch drags (e.g. gate its scale
recognizer, or claim the pan in `_ZoomedTouchPanRecognizer` without breaking the
second-finger pinch handoff). Not patched blind — a wrong guess in this arena
risks breaking pinch-zoom or text selection for every platform.

Tests: `devtools_panel_test.dart` gains a touch-logging capture test and a
bottom-sheet-on-phone-width test. Full `dart analyze` clean;
`editing_ipad_test.dart` unaffected (sink null by default).
