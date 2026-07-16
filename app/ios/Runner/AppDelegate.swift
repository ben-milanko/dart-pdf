import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  // Pages accumulated for the current native print job (JPEG bytes) and its
  // title. Printing renders with our own engine and spools through UIKit's own
  // print system, never a bundled PDF engine.
  private var printPages: [Data] = []
  private var printJobTitle = "Document"
  private var nativePrintChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    // Print without a bundled PDF engine: the Dart side renders each page and
    // streams it here as a JPEG; endJob hands the images to UIKit's own print
    // interaction controller.
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
    case "beginJob":
      printPages = []
      printJobTitle =
        (call.arguments as? [String: Any])?["name"] as? String ?? "Document"
      result(["dpi": 300])
    case "printPage":
      guard let args = call.arguments as? [String: Any],
            let typed = args["image"] as? FlutterStandardTypedData else {
        result(FlutterError(
          code: "bad_args", message: "printPage expects image bytes",
          details: nil))
        return
      }
      printPages.append(typed.data)
      result(true)
    case "endJob":
      presentPrint(result)
    case "cancelJob":
      printPages = []
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// Hands the accumulated page images to UIKit's print controller. Returns
  /// false when there is nothing to print, printing is unavailable, or the
  /// user cancels.
  private func presentPrint(_ result: @escaping FlutterResult) {
    let pages = printPages
    printPages = []
    guard !pages.isEmpty, UIPrintInteractionController.isPrintingAvailable else {
      result(false)
      return
    }

    let controller = UIPrintInteractionController.shared
    let info = UIPrintInfo.printInfo()
    info.outputType = .general
    info.jobName = printJobTitle
    controller.printInfo = info
    controller.printingItems = pages  // JPEG data, one item per page

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
