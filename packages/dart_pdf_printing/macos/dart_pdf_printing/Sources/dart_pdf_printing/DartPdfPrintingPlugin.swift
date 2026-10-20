import Cocoa
import FlutterMacOS
import PDFKit

public class DartPdfPrintingPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "dev.milanko.dart_pdf_printing", binaryMessenger: registrar.messenger)
    registrar.addMethodCallDelegate(DartPdfPrintingPlugin(), channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
      switch call.method {
      case "printPdf":
        guard let args = call.arguments as? [String: Any],
              let typed = args["pdf"] as? FlutterStandardTypedData else {
          result(FlutterError(
            code: "bad_args", message: "printPdf expects pdf bytes",
            details: nil))
          return
        }
        result(self.runPrintJob(
          pdf: typed.data,
          name: (args["name"] as? String) ?? "Document",
          useDocumentPageSize: (args["useDocumentPageSize"] as? Bool) ?? false))
      default:
        result(FlutterMethodNotImplemented)
      }
  }

  /// Spools the whole PDF through AppKit's print panel via PDFKit. Returns
  /// false when the data isn't a readable PDF or the user cancels.
  private func runPrintJob(
    pdf: Data, name: String, useDocumentPageSize: Bool = false
  ) -> Bool {
    guard let document = PDFDocument(data: pdf) else { return false }

    let printInfo = (NSPrintInfo.shared.copy() as? NSPrintInfo) ?? NSPrintInfo.shared
    if useDocumentPageSize, let page = document.page(at: 0) {
      let bounds = page.bounds(for: .mediaBox)
      let sideways = page.rotation % 180 != 0
      let size = sideways
        ? NSSize(width: bounds.height, height: bounds.width) : bounds.size
      printInfo.orientation = size.width > size.height ? .landscape : .portrait
      printInfo.paperSize = size
      printInfo.topMargin = 0
      printInfo.bottomMargin = 0
      printInfo.leftMargin = 0
      printInfo.rightMargin = 0
      printInfo.isHorizontallyCentered = false
      printInfo.isVerticallyCentered = false
      printInfo.scalingFactor = 1
      // Copies, order and n-up are already represented by the PDF's sheets.
      // Do not inherit another job's layout or copy count from NSPrintInfo.
      let settings = printInfo.dictionary()
      settings[NSPrintInfo.AttributeKey.copies] = 1
      settings[NSPrintInfo.AttributeKey.mustCollate] = false
      settings[NSPrintInfo.AttributeKey.reversePageOrder] = false
      settings[NSPrintInfo.AttributeKey.pagesAcross] = 1
      settings[NSPrintInfo.AttributeKey.pagesDown] = 1
      settings[NSPrintInfo.AttributeKey.allPages] = true
    }
    guard let operation = document.printOperation(
      for: printInfo,
      scalingMode: useDocumentPageSize ? .pageScaleNone : .pageScaleDownToFit,
      autoRotate: !useDocumentPageSize)
    else {
      return false
    }
    if useDocumentPageSize {
      operation.printPanel.options.subtract([
        .showsCopies, .showsPageRange, .showsPaperSize, .showsOrientation,
        .showsScaling,
      ])
    }
    operation.jobTitle = name
    return operation.run()
  }

}
