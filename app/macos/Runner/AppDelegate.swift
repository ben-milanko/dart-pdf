import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  /// Channel to the Dart `IncomingFileService`; set by MainFlutterWindow once
  /// the engine exists.
  var incomingChannel: FlutterMethodChannel?

  /// Files opened before the engine was ready (cold start). Drained by the
  /// Dart side's `getInitialFile` call.
  var pendingFiles: [String] = []

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
    guard let channel = incomingChannel else {
      pendingFiles.append(path)
      return
    }
    channel.invokeMethod("openFile", arguments: payload(for: path))
  }

  func payload(for path: String) -> [String: Any] {
    return ["name": (path as NSString).lastPathComponent, "path": path]
  }
}
