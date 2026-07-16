import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var nativePrintChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    // Print without a bundled PDF engine: the Dart side hands over the whole
    // PDF and UIKit renders its vector content itself (CoreGraphics), keeping
    // text selectable.
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "NativePrint") {
      let channel = FlutterMethodChannel(
        name: "dev.milanko.dartpdf/native_print",
        binaryMessenger: registrar.messenger())
      channel.setMethodCallHandler { [weak self] call, result in
        self?.handleNativePrint(call, result)
      }
      nativePrintChannel = channel
    }
  }

  private func handleNativePrint(
    _ call: FlutterMethodCall, _ result: @escaping FlutterResult
  ) {
    switch call.method {
    case "printPdf":
      guard let args = call.arguments as? [String: Any],
            let typed = args["pdf"] as? FlutterStandardTypedData else {
        result(FlutterError(
          code: "bad_args", message: "printPdf expects pdf bytes", details: nil))
        return
      }
      presentPrint(
        pdf: typed.data,
        name: (args["name"] as? String) ?? "Document",
        result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// Hands the whole PDF to UIKit's print controller. Returns false when
  /// printing is unavailable or the user cancels.
  private func presentPrint(
    pdf: Data, name: String, result: @escaping FlutterResult
  ) {
    guard UIPrintInteractionController.isPrintingAvailable else {
      result(false)
      return
    }

    let controller = UIPrintInteractionController.shared
    let info = UIPrintInfo.printInfo()
    info.outputType = .general
    info.jobName = name
    controller.printInfo = info
    controller.printingItem = pdf  // PDF data - printed as vector

    let completion: UIPrintInteractionController.CompletionHandler = {
      (_, completed, _) in
      result(completed)
    }
    // iPad requires an anchor for the popover; fall back to full screen.
    if let rootView = window?.rootViewController?.view {
      controller.present(
        from: rootView.bounds, in: rootView, animated: true,
        completionHandler: completion)
    } else {
      controller.present(animated: true, completionHandler: completion)
    }
  }
}
