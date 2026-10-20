import Flutter
import UIKit

public class DartPdfPrintingPlugin: NSObject, FlutterPlugin, UIPrintInteractionControllerDelegate {
  private weak var viewController: UIViewController?
  private var preparedPrintSize: CGSize?

  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = DartPdfPrintingPlugin()
    instance.viewController = registrar.viewController
    let channel = FlutterMethodChannel(
      name: "dev.milanko.dart_pdf_printing", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(
    _ call: FlutterMethodCall, result: @escaping FlutterResult
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
        useDocumentPageSize: (args["useDocumentPageSize"] as? Bool) ?? false,
        pageWidth: (args["pageWidth"] as? NSNumber)?.doubleValue,
        pageHeight: (args["pageHeight"] as? NSNumber)?.doubleValue,
        result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// Hands the whole PDF to UIKit's print controller. Returns false when
  /// printing is unavailable or the user cancels.
  private func presentPrint(
    pdf: Data, name: String, useDocumentPageSize: Bool,
    pageWidth: Double?, pageHeight: Double?, result: @escaping FlutterResult
  ) {
    guard UIPrintInteractionController.isPrintingAvailable else {
      result(false)
      return
    }

    let controller = UIPrintInteractionController.shared
    let info = UIPrintInfo.printInfo()
    info.outputType = .general
    info.jobName = name
    preparedPrintSize = nil
    if useDocumentPageSize, let width = pageWidth, let height = pageHeight,
       width.isFinite, height.isFinite, width > 0, height > 0 {
      preparedPrintSize = CGSize(width: width, height: height)
      info.orientation = width > height ? .landscape : .portrait
    }
    controller.delegate = preparedPrintSize == nil ? nil : self
    controller.printInfo = info
    controller.printingItem = pdf  // PDF data - printed as vector

    let completion: UIPrintInteractionController.CompletionHandler = {
      (_, completed, _) in
      result(completed)
    }
    // iPad requires an anchor for the popover; fall back to full screen.
    if let rootView = viewController?.view {
      controller.present(
        from: rootView.bounds, in: rootView, animated: true,
        completionHandler: completion)
    } else {
      controller.present(animated: true, completionHandler: completion)
    }
  }

  // AirPrint owns supported media and the final printer settings. Start with
  // the closest available paper to the prepared sheet; the PDF itself is
  // handed through without re-layout.
  public func printInteractionController(
    _ printInteractionController: UIPrintInteractionController,
    choosePaper paperList: [UIPrintPaper]
  ) -> UIPrintPaper {
    UIPrintPaper.bestPaper(
      forPageSize: preparedPrintSize ?? CGSize(width: 612, height: 792),
      withPapersFrom: paperList)
  }
}
