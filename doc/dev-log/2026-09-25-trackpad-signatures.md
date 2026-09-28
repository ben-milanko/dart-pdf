# Trackpad signatures (Preview-style), 2026-09-25

The signature pad can be drawn with a finger on a trackpad, the way Apple
Preview does it. Press **Use trackpad**, draw, then press any key to finish.
It works on macOS, Windows (Precision Touchpads) and Android (touchpads on
Chromebooks and on tablets with keyboard covers).

## Shape

- **Seam (dart_pdf_editor, `editing_signature.dart`)**:
  `PdfTrackpadSignatureCapture` is an abstract class with two methods,
  `isAvailable()` (default true) and
  `Stream<PdfTrackpadSignatureEvent> capture()`. Listening to `capture()`
  starts a capture. Cancelling the subscription, or the stream closing, ends
  it. Events are `down`/`move`/`up` with `x`,`y` from 0 to 1 across the
  trackpad surface (y down), plus `finish`.
  - `PdfSignatureDialog(trackpad:)` asks `isAvailable()` when it opens and
    shows the button only on true.
  - `showPdfSignatureDialog` falls back to the static
    `PdfTrackpadSignatureCapture.platform`. That lets all four existing call
    sites pick it up with no new parameter: the toolbar draw, the library
    add/redraw, the stamp designer and the app's digital-signature dialog.
- **The pad owns the capture policy, so hosts only stream touches.** During a
  capture:
  - a `Focus` takes the keyboard, and any key-down finishes the capture (all
    keys are swallowed);
  - an `AbsorbPointer` blocks clicks;
  - an `AppLifecycleListener` finishes the capture on `inactive`/`hide`, which
    covers focus loss on every platform.
- **Mapping**: the whole trackpad surface maps onto the whole 360x180 pad, as
  in Preview. Trackpads are about 1.4–1.6:1 and the pad is 2:1, so strokes
  stretch slightly horizontally. Strokes carry no pressure.
- **App (`app/lib/trackpad_signature.dart`)**:
  `PlatformTrackpadSignatureCapture` wraps two channels:
  - `dev.milanko.dartpdf/trackpad_signature` (EventChannel), for the capture;
  - `dev.milanko.dartpdf/trackpad_signature_support` (`isAvailable`).

  `app.dart` installs it on macOS, Windows and Android.

## Runners

- **macOS (`TrackpadSignatureCapture.swift`)**:
  - A transparent `TrackpadSignatureOverlay` (`allowedTouchTypes = .indirect`)
    goes over the key window and becomes first responder. It follows the
    first finger's `normalizedPosition`, and it swallows mouse events and
    keys itself.
  - `CGAssociateMouseAndMouseCursorPosition(0)` plus `NSCursor.hide()`: the
    cursor must be detached, because indirect touches go to the view under
    it. If the cursor walks off the window, the strokes stop arriving.
  - `isAvailable` looks for any `AppleMultitouchDevice` in the IORegistry. An
    iMac with only a plain mouse has none.
- **Windows (`trackpad_signature.{h,cpp}`, links `hid.lib`)**:
  - A private message-only window registers raw input for usage page 0x0D,
    usage 0x05 (Precision Touchpad), with `RIDEV_INPUTSINK`. That flag is
    needed because a message-only window is never in the foreground.
  - The finger slots are the link collections carrying X/Y value caps, with
    their LogicalMin/Max.
  - **Hybrid-mode** touchpads split one frame across several reports. Only
    the first report carries the Contact Count, so the remaining count
    carries over (`pending_contacts`). Only that many slots are read, because
    the other slots hold stale data.
  - The contact is identified by Contact ID (0x51) and Tip Switch (0x42).
  - The cursor is parked with `ClipCursor` to a 1px rect and hidden with
    `ShowCursor(FALSE)`.
  - Clicks and keys reach Flutter, and the pad handles them.
- **Android (`TrackpadSignatureCapture.kt`, API 26+)**:
  - `requestPointerCapture()` on the Flutter view (found by walking the view
    tree) makes a touchpad report `SOURCE_TOUCHPAD` contacts with absolute
    positions. Those are normalized by the device's `AXIS_X`/`AXIS_Y` motion
    ranges.
  - Captured non-touchpad events are consumed.
  - `Activity.onPointerCaptureChanged(false)` finishes the capture.
  - Pointer capture hides and freezes the pointer by itself.

## Not possible

Linux, the web and iPadOS give apps no absolute touchpad positions:

- **Linux:** libinput/GTK only expose pointer motion and 3+-finger gestures.
  Reading evdev directly needs `input` group access, which Flatpak and Snap
  deny.
- **Web:** Pointer Lock gives relative deltas only.
- **iPadOS:** UIKit gives indirect pointer events with no contact position.

On these platforms the pad keeps its normal pointer drawing and the button
never appears.

## Verification

- `test/editing_signature_trackpad_test.dart` drives the pad with a fake
  capture. It covers the mapping, finish/close/dispose, the key finishing the
  capture, clicks being ignored, focus loss, and the button being hidden when
  no capture is supplied or no trackpad is attached.
- macOS: `flutter build macos --debug` builds.
- Android: `flutter build apk --debug` builds.
- Windows can't be built on a Mac. Both `trackpad_signature.cpp` and
  `platform_channels.cpp` pass `clang++ -target x86_64-w64-windows-gnu
  -fsyntax-only -Wall -Wextra` against the mingw-w64 v12 headers and this
  engine's `flutter-cpp-client-wrapper.zip`. That check caught mingw's
  `hidpi.h` needing `hidusage.h` included first.
- No real trackpad has been used on any of the three platforms yet.
