import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var pencilChannel: FlutterMethodChannel?
  private var pencilInteraction: AnyObject?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func applicationDidBecomeActive(_ application: UIApplication) {
    super.applicationDidBecomeActive(application)
    configurePencilInteractionIfNeeded()
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }

  /// Wires the Apple Pencil's hardware double-tap to the Dart side. Flutter
  /// exposes no event for it, so we register a `UIPencilInteraction` on the
  /// Flutter view and forward each gesture over the shared method channel;
  /// the editor toggles its eraser (see `PdfPencilInteraction` in
  /// dart_pdf_editor). Run once, after the Flutter view controller exists.
  private func configurePencilInteractionIfNeeded() {
    guard #available(iOS 12.1, *) else { return }
    guard pencilInteraction == nil,
          let controller = rootFlutterViewController() else { return }
    let channel = FlutterMethodChannel(
      name: "dart_pdf_editor/pencil",
      binaryMessenger: controller.binaryMessenger)
    let interaction = UIPencilInteraction()
    interaction.delegate = self
    controller.view.addInteraction(interaction)
    pencilChannel = channel
    pencilInteraction = interaction
  }

  private func rootFlutterViewController() -> FlutterViewController? {
    if let controller = window?.rootViewController as? FlutterViewController {
      return controller
    }
    for scene in UIApplication.shared.connectedScenes {
      guard let windowScene = scene as? UIWindowScene else { continue }
      for window in windowScene.windows {
        if let controller = window.rootViewController as? FlutterViewController {
          return controller
        }
      }
    }
    return nil
  }
}

@available(iOS 12.1, *)
extension AppDelegate: UIPencilInteractionDelegate {
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
