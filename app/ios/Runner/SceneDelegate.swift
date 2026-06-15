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

  private var pencilChannel: FlutterMethodChannel?
  private var pencilInteraction: AnyObject?

  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)
    setupChannel()
    setupPencilInteraction()
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

  /// Wires the Apple Pencil's hardware double-tap to the Dart side. Flutter
  /// exposes no event for it, so we register a `UIPencilInteraction` on the
  /// Flutter view and forward each gesture over the shared method channel;
  /// the editor toggles its eraser (see `PdfPencilInteraction` in
  /// dart_pdf_editor). This template is scene-based, so — like the file
  /// channel above — the gesture is installed here, not in the AppDelegate
  /// (whose `applicationDidBecomeActive` is never called under the scene
  /// lifecycle).
  private func setupPencilInteraction() {
    guard #available(iOS 12.1, *) else { return }
    guard pencilInteraction == nil,
      let controller = window?.rootViewController as? FlutterViewController
    else { return }
    let ch = FlutterMethodChannel(
      name: "dart_pdf_editor/pencil",
      binaryMessenger: controller.binaryMessenger)
    let interaction = UIPencilInteraction()
    interaction.delegate = self
    controller.view.addInteraction(interaction)
    pencilChannel = ch
    pencilInteraction = interaction
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

@available(iOS 12.1, *)
extension SceneDelegate: UIPencilInteractionDelegate {
  func pencilInteractionDidTap(_ interaction: UIPencilInteraction) {
    // Forward the user's Settings → Apple Pencil choice so the Dart side
    // honors it (notably "Off"); the runner doesn't decide the action.
    pencilChannel?.invokeMethod(
      "pencilDoubleTap",
      arguments: ["preferredAction": preferredActionName()])
  }

  private func preferredActionName() -> String {
    switch UIPencilInteraction.preferredTapAction {
    case .ignore: return "ignore"
    case .switchEraser: return "switchEraser"
    case .switchPrevious: return "switchPrevious"
    case .showColorPalette: return "showColorPalette"
    @unknown default: return "unspecified"
    }
  }
}
