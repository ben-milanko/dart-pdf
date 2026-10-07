import Cocoa
import FlutterMacOS

/// Per-window file drops for DartPDF's multi-window runner.
///
/// `desktop_drop` installs its drop view on the registrar's implicit view at
/// plugin registration. The multi-window runner registers plugins on a
/// headless engine that has no implicit view, so `desktop_drop` silently
/// installs nothing and Finder drops never reach Dart. Dart instead registers
/// each window it creates here (by its NSWindow address, the handle Flutter's
/// multi-window controllers expose), and every event carries that handle so a
/// drop in one window cannot notify the identically-positioned body of
/// another. The Dart side is `NativeWindowDropTarget`; the Windows runner
/// speaks the same channel protocol.
final class WindowDropService {
  private let channel: FlutterMethodChannel
  private var targets: [Int: WindowDropView] = [:]

  init(binaryMessenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(
      name: "dev.milanko.dartpdf/windows_drop",
      binaryMessenger: binaryMessenger)
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
  }

  private func handle(_ call: FlutterMethodCall, result: FlutterResult) {
    guard let args = call.arguments as? [String: Any],
          let handle = (args["handle"] as? NSNumber)?.intValue else {
      result(FlutterError(
        code: "bad_args",
        message: "\(call.method) expects a window handle",
        details: nil))
      return
    }
    switch call.method {
    case "register":
      result(register(handle: handle))
    case "unregister":
      targets.removeValue(forKey: handle)?.removeFromSuperview()
      result(true)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func register(handle: Int) -> Bool {
    if let existing = targets[handle], existing.window != nil { return true }
    guard let window = NSApp.windows.first(where: {
      Int(bitPattern: Unmanaged.passUnretained($0).toOpaque()) == handle
    }), let host = window.contentViewController?.view ?? window.contentView
    else { return false }

    let target = WindowDropView(
      frame: host.bounds, handle: handle, channel: channel)
    target.autoresizingMask = [.width, .height]
    var types = NSFilePromiseReceiver.readableDraggedTypes.map {
      NSPasteboard.PasteboardType($0)
    }
    types.append(.fileURL)
    types.append(NSPasteboard.PasteboardType("NSFilenamesPboardType"))
    target.registerForDraggedTypes(types)
    // Appended last so the FlutterView stays the wrapper's first subview
    // (AppDelegate's key-window repair relies on that).
    host.addSubview(target)
    targets[handle] = target
    return true
  }
}

/// A transparent drop destination laid over one window's Flutter view - the
/// same overlay `desktop_drop` installs in a single-view runner.
private final class WindowDropView: NSView {
  private let handle: Int
  private let channel: FlutterMethodChannel
  private let itemsLock = NSLock()

  init(frame: NSRect, handle: Int, channel: FlutterMethodChannel) {
    self.handle = handle
    self.channel = channel
    super.init(frame: frame)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
    channel.invokeMethod("entered", arguments: payload(sender.draggingLocation))
    return .copy
  }

  override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
    channel.invokeMethod("updated", arguments: payload(sender.draggingLocation))
    return .copy
  }

  override func draggingExited(_ sender: NSDraggingInfo?) {
    channel.invokeMethod(
      "exited", arguments: payload(sender?.draggingLocation ?? .zero))
  }

  override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
    let pasteboard = sender.draggingPasteboard
    var event = payload(sender.draggingLocation)
    var paths: [String] = []
    var seen = Set<String>()
    func push(_ url: URL) {
      itemsLock.lock()
      defer { itemsLock.unlock() }
      if seen.insert(url.path).inserted { paths.append(url.path) }
    }

    // Real file URLs first (Finder); legacy filename arrays from older apps;
    // file promises (Mail, browsers) only when neither is present.
    let urls = (pasteboard.readObjects(
      forClasses: [NSURL.self],
      options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
    let legacy = (pasteboard.propertyList(
      forType: NSPasteboard.PasteboardType("NSFilenamesPboardType"))
      as? [String]) ?? []
    let group = DispatchGroup()
    if !urls.isEmpty || !legacy.isEmpty {
      urls.forEach(push)
      legacy.forEach { push(URL(fileURLWithPath: $0)) }
    } else if let receivers = pasteboard.readObjects(
      forClasses: [NSFilePromiseReceiver.self]) as? [NSFilePromiseReceiver] {
      let destination = Self.promiseDestination()
      let queue = OperationQueue()
      queue.qualityOfService = .userInitiated
      for receiver in receivers {
        group.enter()
        receiver.receivePromisedFiles(
          atDestination: destination, options: [:], operationQueue: queue
        ) { url, error in
          defer { group.leave() }
          if error == nil { push(url) }
        }
      }
    }

    group.notify(queue: .main) { [channel] in
      event["paths"] = paths
      channel.invokeMethod("performOperation", arguments: event)
    }
    return true
  }

  /// The event payload in the Flutter view's physical, top-left coordinates
  /// (what the Windows runner sends; Dart divides by the pixel ratio).
  private func payload(_ windowPoint: NSPoint) -> [String: Any] {
    let local = convert(windowPoint, from: nil)
    let y = isFlipped ? local.y : bounds.height - local.y
    let scale = window?.backingScaleFactor ?? 1
    return ["handle": handle, "x": local.x * scale, "y": y * scale]
  }

  private static func promiseDestination() -> URL {
    let destination = FileManager.default.temporaryDirectory
      .appendingPathComponent("Drops", isDirectory: true)
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try? FileManager.default.createDirectory(
      at: destination, withIntermediateDirectories: true)
    return destination
  }
}
