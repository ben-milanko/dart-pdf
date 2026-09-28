import Cocoa
import FlutterMacOS
import IOKit

/// Preview-style trackpad signatures for the signature pad
/// (`MacTrackpadSignatureCapture` in app/lib/trackpad_signature.dart).
///
/// Flutter's pointer events only carry the cursor, never where a finger sits
/// on the trackpad, so while Dart listens this lays a transparent view that
/// accepts indirect `NSTouch`es over the key window and streams the drawing
/// finger's absolute position (`normalizedPosition`, flipped to y down) as
/// `{phase: down|move|up, x, y}`. The cursor is hidden and detached from the
/// trackpad for the duration - otherwise the finger strokes would also walk
/// it off the window, taking the touches with it - and pointer input is
/// swallowed, so a tap-to-click while dotting an "i" can't press a button
/// behind the pad. Any key press (or the window losing focus) sends
/// `{phase: finish}` and ends the stream; cancelling from Dart tears the
/// capture down the same way.
final class TrackpadSignatureCapture: NSObject, FlutterStreamHandler {
  private var sink: FlutterEventSink?
  private var overlay: TrackpadSignatureOverlay?
  private weak var window: NSWindow?
  private weak var previousResponder: NSResponder?
  private var resignObserver: NSObjectProtocol?

  /// Whether any multitouch surface (built-in trackpad, Magic Trackpad) is
  /// attached - an iMac on a plain mouse has none, and the pad shouldn't
  /// offer a mode that can't draw. Assumes one when the registry can't be read.
  static func isAvailable() -> Bool {
    var iterator: io_iterator_t = 0
    guard IOServiceGetMatchingServices(
      0, IOServiceMatching("AppleMultitouchDevice"), &iterator) == KERN_SUCCESS
    else { return true }
    defer { IOObjectRelease(iterator) }
    let service = IOIteratorNext(iterator)
    guard service != 0 else { return false }
    IOObjectRelease(service)
    return true
  }

  func onListen(
    withArguments arguments: Any?,
    eventSink events: @escaping FlutterEventSink
  ) -> FlutterError? {
    stop()
    guard let window = NSApp.keyWindow, let host = window.contentView else {
      events(FlutterEndOfEventStream)
      return nil
    }
    sink = events
    self.window = window
    previousResponder = window.firstResponder

    let overlay = TrackpadSignatureOverlay(frame: host.bounds)
    overlay.autoresizingMask = [.width, .height]
    overlay.onTouch = { [weak self] phase, x, y in
      self?.sink?(["phase": phase, "x": x, "y": y])
    }
    overlay.onFinish = { [weak self] in self?.finish() }
    host.addSubview(overlay, positioned: .above, relativeTo: nil)
    window.makeFirstResponder(overlay)
    self.overlay = overlay

    resignObserver = NotificationCenter.default.addObserver(
      forName: NSWindow.didResignKeyNotification,
      object: window,
      queue: .main
    ) { [weak self] _ in self?.finish() }

    CGAssociateMouseAndMouseCursorPosition(0)
    NSCursor.hide()
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    stop()
    return nil
  }

  private func finish() {
    let sink = self.sink
    stop()
    sink?(["phase": "finish"])
    sink?(FlutterEndOfEventStream)
  }

  /// Idempotent: restores the cursor, focus, and input exactly once.
  private func stop() {
    sink = nil
    guard let overlay else { return }
    self.overlay = nil
    if let resignObserver {
      NotificationCenter.default.removeObserver(resignObserver)
    }
    resignObserver = nil
    overlay.onTouch = nil
    overlay.onFinish = nil
    overlay.removeFromSuperview()
    if let window, let previousResponder {
      window.makeFirstResponder(previousResponder)
    }
    window = nil
    previousResponder = nil
    CGAssociateMouseAndMouseCursorPosition(1)
    NSCursor.unhide()
  }
}

/// The capture's input surface: follows the first finger down until it
/// lifts, ignoring any others (a resting thumb, a second finger), and eats
/// every other kind of input while it is up.
final class TrackpadSignatureOverlay: NSView {
  var onTouch: ((String, Double, Double) -> Void)?
  var onFinish: (() -> Void)?

  private var drawing: (NSObjectProtocol & NSCopying)?

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    allowedTouchTypes = [.indirect]
    wantsRestingTouches = false
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) is not supported")
  }

  override var acceptsFirstResponder: Bool { true }

  override func touchesBegan(with event: NSEvent) {
    guard drawing == nil,
          let touch = event.touches(matching: .began, in: self).first
    else { return }
    drawing = touch.identity
    report("down", touch)
  }

  override func touchesMoved(with event: NSEvent) {
    guard let touch = drawingTouch(in: event, matching: .moved) else { return }
    report("move", touch)
  }

  override func touchesEnded(with event: NSEvent) {
    guard let touch = drawingTouch(in: event, matching: .ended) else { return }
    report("up", touch)
    drawing = nil
  }

  override func touchesCancelled(with event: NSEvent) {
    guard let touch = drawingTouch(in: event, matching: .cancelled) else {
      return
    }
    report("up", touch)
    drawing = nil
  }

  private func drawingTouch(
    in event: NSEvent, matching phase: NSTouch.Phase
  ) -> NSTouch? {
    guard let drawing else { return nil }
    return event.touches(matching: phase, in: self).first {
      $0.identity.isEqual(drawing)
    }
  }

  private func report(_ phase: String, _ touch: NSTouch) {
    let position = touch.normalizedPosition
    onTouch?(phase, Double(position.x), Double(1 - position.y))
  }

  // "Press any key when finished", as in Preview. Key equivalents land here
  // too so a stray shortcut can't act on the document behind the pad.
  override func keyDown(with event: NSEvent) { onFinish?() }

  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    onFinish?()
    return true
  }

  override func mouseDown(with event: NSEvent) {}
  override func mouseUp(with event: NSEvent) {}
  override func mouseDragged(with event: NSEvent) {}
  override func rightMouseDown(with event: NSEvent) {}
  override func rightMouseUp(with event: NSEvent) {}
  override func otherMouseDown(with event: NSEvent) {}
  override func otherMouseUp(with event: NSEvent) {}
  override func scrollWheel(with event: NSEvent) {}
  override func magnify(with event: NSEvent) {}
  override func rotate(with event: NSEvent) {}
  override func smartMagnify(with event: NSEvent) {}
  override func pressureChange(with event: NSEvent) {}
}
