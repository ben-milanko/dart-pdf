import Flutter
import UIKit

/// Receives PDFs opened in the app — "Open in…", the share sheet, the Files
/// browser — and forwards them to the Dart `IncomingFileService`. The iOS
/// template is scene-based, so file URLs arrive here rather than in the
/// AppDelegate.
class SceneDelegate: FlutterSceneDelegate {
  private var channel: FlutterMethodChannel?

  /// Files received before the channel was wired (cold start). Drained by the
  /// Dart side's `getInitialFile` call.
  private var pending: [[String: Any]] = []

  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)
    setupChannel()
    handle(connectionOptions.urlContexts)
  }

  override func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    handle(URLContexts)
  }

  private func setupChannel() {
    guard channel == nil,
      let controller = window?.rootViewController as? FlutterViewController
    else { return }
    let ch = FlutterMethodChannel(
      name: "dev.milanko.dartpdf/incoming",
      binaryMessenger: controller.binaryMessenger)
    ch.setMethodCallHandler { [weak self] (call, result) in
      if call.method == "getInitialFile" {
        if let first = self?.pending.first {
          self?.pending.removeFirst()
          result(first)
        } else {
          result(nil)
        }
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
    channel = ch
  }

  private func handle(_ contexts: Set<UIOpenURLContext>) {
    for ctx in contexts {
      guard let payload = readPayload(ctx.url) else { continue }
      if let channel = channel {
        channel.invokeMethod("openFile", arguments: payload)
      } else {
        pending.append(payload)
      }
    }
  }

  /// Reads a (possibly security-scoped) file URL into a Dart-friendly payload.
  private func readPayload(_ url: URL) -> [String: Any]? {
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    guard let data = try? Data(contentsOf: url) else { return nil }
    return [
      "name": url.lastPathComponent,
      "bytes": FlutterStandardTypedData(bytes: data),
    ]
  }
}
