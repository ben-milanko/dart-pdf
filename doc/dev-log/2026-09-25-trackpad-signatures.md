# Trackpad signatures (Preview-style), 2026-09-25

The signature pad can now be drawn with a finger on a Mac trackpad, the way
Preview does it: press **Use trackpad**, draw, press any key to finish.

## Shape

- **Seam (dart_pdf_editor, `editing_signature.dart`)**:
  `PdfTrackpadSignatureCapture` is a one-method interface,
  `Stream<PdfTrackpadSignatureEvent> capture()`. Listening starts a capture,
  cancelling ends it, and so does the stream closing. Events are
  `down`/`move`/`up` with `x`,`y` in 0–1 across the trackpad surface (y down),
  plus `finish`. `PdfSignatureDialog(trackpad:)` shows the button only when a
  capture is supplied; `showPdfSignatureDialog` falls back to the static
  `PdfTrackpadSignatureCapture.platform`, so all four existing call sites
  (toolbar draw, library add/redraw, stamp designer, app digital-signature
  dialog) get it without threading a parameter through.
- **Mapping**: the whole trackpad surface maps onto the whole 360x180 pad,
  as in Preview. The trackpad is about 1.6:1 and the pad is 2:1, so strokes
  stretch slightly horizontally, the same as Preview. Strokes carry no
  pressure (`NSTouch` has none).
- **App (`app/lib/trackpad_signature.dart`)**: `MacTrackpadSignatureCapture`
  wraps the `dev.milanko.dartpdf/trackpad_signature` EventChannel and is
  installed from `app.dart`'s `initState` on macOS only.
- **Runner (`app/macos/Runner/TrackpadSignatureCapture.swift`)**: on listen, a
  transparent `TrackpadSignatureOverlay` (with `allowedTouchTypes = .indirect`)
  goes over the key window's content view and becomes first responder. It
  follows the first finger down until that finger lifts and reports
  `normalizedPosition`.

## Gotchas

- Flutter pointer events never carry absolute trackpad positions, so this
  needs native code. There is no web, Windows or Linux implementation.
- **The cursor has to be detached**
  (`CGAssociateMouseAndMouseCursorPosition(0)`) and hidden during capture.
  Otherwise the drawing finger also moves the cursor, and indirect touches go
  to whatever view is under it. Once the cursor leaves the window, the strokes
  stop arriving.
- **Mouse input is swallowed, and only a key press finishes.** With
  tap-to-click on, dotting an "i" produces a click. If a click ended the
  capture, or reached the dialog, the signature would be cut short or a
  button would be pressed.
- The capture also finishes on `NSWindow.didResignKeyNotification` (for
  example, Cmd-Tab), so the cursor is never left frozen. `stop()` is
  idempotent and restores the previous first responder.

## Verification

`test/editing_signature_trackpad_test.dart` drives the pad with a fake
capture: mapping, the finish/close/dispose paths, and the button hiding when
no capture is supplied. `flutter build macos --debug` compiles the runner.
The real touch path needs a hand on a trackpad.
