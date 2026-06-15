# Device & marketing screenshots

Automated, native device screenshots of the **DartPDF app** (`app/`) and the
**example app** (`packages/dart_pdf_editor/example/`), framed onto a gradient
marketing canvas at the exact App Store / Play Store dimensions.

```
doc/screenshots/<target>/<platform>/NN-name.png   raw device / window captures
doc/marketing/<target>/<platform>/NN-name.png     framed store shots (gradient + text)
```

`<target>` is `app` or `example`; `<platform>` is `ios`, `macos`, or `android`.

## How it works

1. **Self-driving entry** — each target has a screenshot build that walks a
   fixed list of showcase scenes, holds each still, and prints a marker line:
   - `app/tool/screenshots_main.dart` (hero / editor / dark — all on a loaded
     showcase document; the hero is the clean page, editor + dark add the
     page-thumbnail panel)
   - `packages/dart_pdf_editor/example/lib/screenshots_main.dart`
     (document / graphics / annotations / markup / reader)

   Markers: `@@SHOT@@ <name>` (scene settled — grab it) and `@@SHOT_DONE@@`.

2. **Host orchestrator** — `tool/capture_screenshots.dart` runs the entry with
   `flutter run`, watches stdout for markers, and fires the platform's native
   screenshot tool per marker:
   - iOS — `xcrun simctl io <udid> screenshot`
   - Android — `adb exec-out screencap -p`
   - macOS — `screencapture -l <windowID>` grabs the window's own backing store.
     The window id comes from a tiny CoreGraphics helper (built at runtime) that
     finds the largest on-screen window of the app's pid — the pid we *launched*,
     parsed from the run output, so an installed copy of the same-named app is
     never grabbed instead. No Automation permission, occlusion-proof, and it
     works on a background window. (Falls back to a System Events bounds +
     `-R` region crop, then a full-display grab, if the helper is unavailable.)

3. **Marketing compose** — `tool/compose_marketing.dart` drops each capture onto
   a brand-gradient canvas with a headline + subtitle, rounded corners, and a
   soft shadow, rendered to the exact store size with `rsvg-convert`. The
   standalone-app shots also get a hand-drawn markup flourish (ink squiggle /
   highlighter swipe / underline) drawn over the capture and deliberately
   overrunning the device frame into the gradient.

## Dimensions

| Platform | Orientation | Canvas      | Why |
|----------|-------------|-------------|-----|
| macOS    | landscape   | 1440 × 900  | Mac App Store; matches a 1× window capture so the frame stays crisp (1280×800 / 2560×1600 / 2880×1800 also valid) |
| iOS      | portrait    | 1320 × 2868 | App Store 6.9" display (iPhone 16/17 Pro Max) |
| Android  | portrait    | 1320 × 2640 | Play phone screenshot (2:1, within Play's ≤2:1 limit) |

The iPhone simulator captures natively at 1320 × 2868, already a valid 6.9"
App Store size. macOS is captured a window at a time via its CGWindowID
(`screencapture -l`), which grabs the window's own backing store — no Automation
permission, occlusion-proof, and it works even while the window is in the
background. The pid is the one *we* launched (parsed from the run output), so an
installed copy of the same-named app is never captured by mistake. The marketing
canvas (1440 × 900) pins the macOS store dimension; pick a larger valid size only
when capturing on a Retina display (a 1× window upscaled to 2880 would be soft).

## Running locally

```sh
# Everything (both targets, all platforms):
packages/dart_pdf_editor/example/tool/screenshots.sh

# A subset (tokens in any order):
packages/dart_pdf_editor/example/tool/screenshots.sh app macos
packages/dart_pdf_editor/example/tool/screenshots.sh example ios

# Re-frame existing raw captures only (fast caption/gradient iteration):
packages/dart_pdf_editor/example/tool/screenshots.sh compose example
```

Useful env: `FLUTTER` (flutter binary; defaults to fvm then PATH),
`IOS_DEVICE` (default "iPhone 17 Pro Max", falls back to any Pro Max),
`ANDROID_AVD`, `KEEP_BOOTED=1` (leave sims/emulator up), `SKIP_COMPOSE=1`,
`SHOT_MAC_WINDOW` (window size to request before macOS capture, default
`1440x900`; only takes effect on apps whose windows are visible to Accessibility).

### Requirements

- **`rsvg-convert`** (`brew install librsvg`) for the marketing compose.
- **iOS**: Xcode + an installed iPhone simulator.
- **Android**: Android SDK + an AVD.
- **macOS**: the desktop build toolchain. The primary capture path
  (`screencapture -l`) needs **Screen Recording** permission for the terminal
  (granted once, like any screen capture) but **no** Automation permission, and
  it never raises the window — captures run unobtrusively in the background. The
  optional window-resize step (and the `-R` fallback crop) do use Automation; if
  that's not granted, the window is simply captured at its default size.

## Editing the copy

The headline + subtitle per scene live in one map, `_captions`, at the top of
`tool/compose_marketing.dart`, keyed `<target>/<basename>`. The gradient and
layout are in `_composeSvg` in the same file.

The drawn-on markup flourishes live in the `_annotations` map just below
`_captions` (same key scheme; only `app/*` entries are set). Each builder gets
the device-frame rect and the orientation and returns SVG via the `_squiggle` /
`_highlight` / `_underline` helpers; geometry is in frame fractions, so values
outside `0..1` fall beyond the frame on purpose.

## CI

`.github/workflows/screenshots.yml` (manual `workflow_dispatch`) runs iOS + macOS
on a macOS runner and Android on a KVM-accelerated Linux runner, uploading the
`doc/marketing` + `doc/screenshots` trees as artifacts. The macOS window crop
depends on the runner allowing System Events automation; iOS and Android do not.
