import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  private let fileAccess = FileAccessExecutor()
  private var windowingEngine: FlutterEngine?
  private var windowingServicesWindow: MainFlutterWindow?

  /// Channel to the Dart `IncomingFileService`; set by MainFlutterWindow once
  /// the engine exists.
  var incomingChannel: FlutterMethodChannel?

  /// Files opened before the engine was ready (cold start). Drained by the
  /// Dart side's `getInitialFile` call.
  var pendingFiles: [[String: Any]] = []

  /// True once Dart has installed its `openFile` handler and called
  /// `getInitialFile`. A FlutterMethodChannel can exist before that point
  /// during cold start; sending then drops the file on the floor.
  var dartIncomingReady = false

  override func applicationDidFinishLaunching(_ notification: Notification) {
    guard DartPdfWindowingBootstrap.isEnabled else {
      super.applicationDidFinishLaunching(notification)
      return
    }

    // Keep the NIB-created object only as the owner of DartPDF's native
    // services. It deliberately has no FlutterViewController in this mode;
    // Dart's RegularWindowController creates the visible primary window.
    guard let servicesWindow = mainFlutterWindow as? MainFlutterWindow else {
      assertionFailure("DartPDF multi-window bootstrap has no services window")
      return
    }
    servicesWindow.orderOut(nil)
    windowingServicesWindow = servicesWindow

    let engine = FlutterEngine(name: "dartpdf-windowing", project: nil)
    windowingEngine = engine
    _ = engine.run(withEntrypoint: nil)
    servicesWindow.configureWindowingEngine(engine)
  }

  override func applicationWillTerminate(_ notification: Notification) {
    windowingEngine?.shutDownEngine()
    windowingEngine = nil
    super.applicationWillTerminate(notification)
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    // Hiding the NIB-created services window briefly leaves AppKit with no
    // visible window while Dart constructs its primary RegularWindow. Letting
    // AppKit terminate at that point races the experimental bootstrap and can
    // tear down every Dart-owned view just after launch. The Dart window
    // lifetime coordinator calls SystemNavigator.pop after its final window;
    // the normal single-window runner keeps the historical AppKit behavior.
    return !DartPdfWindowingBootstrap.isEnabled
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  /// "Open With" / double-click / drag-onto-icon, delivered as URLs. This is
  /// the method AppKit actually calls on macOS 10.13+: because our superclass
  /// `FlutterAppDelegate` implements `application(_:open:)` (for deep links),
  /// AppKit routes document opens here and never calls the deprecated
  /// `openFile:`/`openFiles:` below. File URLs are ours; anything else (custom
  /// URL schemes, universal links) belongs to Flutter's deep-link handling.
  override func application(_ application: NSApplication, open urls: [URL]) {
    var forwarded: [URL] = []
    for url in urls {
      if url.isFileURL {
        deliver(path: url.path)
      } else {
        forwarded.append(url)
      }
    }
    if !forwarded.isEmpty {
      super.application(application, open: forwarded)
    }
  }

  /// Fallback for macOS < 10.13, which predates `application(_:open:)`.
  /// "Open With" / double-click / drag-onto-icon for a single file.
  override func application(_ sender: NSApplication, openFile filename: String) -> Bool {
    deliver(path: filename)
    return true
  }

  /// Fallback for macOS < 10.13. Multiple files at once.
  override func application(_ sender: NSApplication, openFiles filenames: [String]) {
    for filename in filenames { deliver(path: filename) }
    sender.reply(toOpenOrPrint: .success)
  }

  /// Sends a freshly opened file to Dart, or buffers it until the engine is up.
  private func deliver(path: String) {
    // Finder can deliver an iCloud/OneDrive placeholder during cold launch.
    // Reading it or resolving its security scope here blocks AppKit's main
    // thread and produces a beachball before Flutter can paint. Build the
    // payload on the same background executor used by the file-access channel,
    // then return to the main thread to touch the channel/queue state.
    fileAccess.perform {
      let payload = self.payload(for: path)
      DispatchQueue.main.async {
        self.deliver(payload: payload)
      }
    }
  }

  private func deliver(payload: [String: Any]) {
    guard dartIncomingReady, let channel = incomingChannel else {
      pendingFiles.append(payload)
      return
    }
    channel.invokeMethod("openFile", arguments: payload)
  }

  /// Marks Dart ready for warm file-open pushes and returns the first queued
  /// cold-start file for the `getInitialFile` response, if any.
  func takeInitialFile() -> [String: Any]? {
    dartIncomingReady = true
    guard !pendingFiles.isEmpty else { return nil }
    return pendingFiles.removeFirst()
  }

  /// Sends any extra files queued before Dart was ready. The first queued file
  /// travels as the `getInitialFile` response; the rest use the warm stream.
  func flushPendingFiles() {
    guard dartIncomingReady, let channel = incomingChannel else { return }
    let files = pendingFiles
    pendingFiles.removeAll()
    for payload in files {
      channel.invokeMethod("openFile", arguments: payload)
    }
  }

  func payload(for path: String) -> [String: Any] {
    let url = URL(fileURLWithPath: path)
    var payload: [String: Any] = [
      "name": url.lastPathComponent,
      "path": path,
    ]
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    if let bookmark = securityBookmark(for: url) {
      payload["bookmark"] = bookmark.base64EncodedString()
    } else if let data = try? Data(contentsOf: url) {
      // A bookmark should normally succeed. Preserve the old whole-byte
      // fallback for unusual providers, but it now runs off the AppKit thread.
      payload["bytes"] = FlutterStandardTypedData(bytes: data)
    }
    return payload
  }

  func securityBookmark(for url: URL) -> Data? {
    try? url.bookmarkData(
      options: [.withSecurityScope],
      includingResourceValuesForKeys: nil,
      relativeTo: nil)
  }
}
