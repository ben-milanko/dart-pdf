import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  private var pencilChannel: FlutterMethodChannel?
  private var pencilInteraction: AnyObject?

  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)
    setupPencilInteraction()
  }

  /// Wires the Apple Pencil's hardware double-tap to the Dart side. Flutter
  /// exposes no event for it, so we register a `UIPencilInteraction` on the
  /// Flutter view and forward each gesture over the shared method channel;
  /// the editor toggles its eraser (see `PdfPencilInteraction` in
  /// dart_pdf_editor). This template is scene-based, so the gesture is
  /// installed here, not in the AppDelegate (whose `applicationDidBecomeActive`
  /// is never called under the scene lifecycle).
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
