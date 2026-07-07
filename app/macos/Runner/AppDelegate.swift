import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
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

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  /// "Open With" / double-click / drag-onto-icon for a single file.
  override func application(_ sender: NSApplication, openFile filename: String) -> Bool {
    deliver(path: filename)
    return true
  }

  /// Multiple files at once.
  override func application(_ sender: NSApplication, openFiles filenames: [String]) {
    for filename in filenames { deliver(path: filename) }
    sender.reply(toOpenOrPrint: .success)
  }

  /// Sends a freshly opened file to Dart, or buffers it until the engine is up.
  private func deliver(path: String) {
    let payload = payload(for: path)
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
    if let data = try? Data(contentsOf: url) {
      payload["bytes"] = FlutterStandardTypedData(bytes: data)
    }
    if let bookmark = securityBookmark(for: url) {
      payload["bookmark"] = bookmark.base64EncodedString()
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
