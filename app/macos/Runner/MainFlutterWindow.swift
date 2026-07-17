import Cocoa
import FlutterMacOS
import PDFKit

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    // Wire the incoming-file channel to the Dart IncomingFileService.
    let channel = FlutterMethodChannel(
      name: "dev.milanko.dartpdf/incoming",
      binaryMessenger: flutterViewController.engine.binaryMessenger)
    if let appDelegate = NSApp.delegate as? AppDelegate {
      appDelegate.incomingChannel = channel
      channel.setMethodCallHandler { (call, result) in
        if call.method == "getInitialFile" {
          result(appDelegate.takeInitialFile())
          DispatchQueue.main.async {
            appDelegate.flushPendingFiles()
          }
        } else {
          result(FlutterMethodNotImplemented)
        }
      }
    }

    let fileAccessChannel = FlutterMethodChannel(
      name: "dev.milanko.dartpdf/file_access",
      binaryMessenger: flutterViewController.engine.binaryMessenger)
    fileAccessChannel.setMethodCallHandler { (call, result) in
      switch call.method {
      case "bookmarkForPath":
        guard let args = call.arguments as? [String: Any],
              let path = args["path"] as? String else {
          result(FlutterError(
            code: "bad_args",
            message: "bookmarkForPath expects a path",
            details: nil))
          return
        }
        self.createBookmark(path: path, result: result)
      case "readFile":
        guard let args = call.arguments as? [String: Any],
              let bookmark = args["bookmark"] as? String else {
          result(FlutterError(
            code: "bad_args",
            message: "readFile expects a bookmark",
            details: nil))
          return
        }
        self.readFile(bookmark: bookmark, result: result)
      case "writeFile":
        guard let args = call.arguments as? [String: Any],
              let bookmark = args["bookmark"] as? String,
              let typed = args["bytes"] as? FlutterStandardTypedData else {
          result(FlutterError(
            code: "bad_args",
            message: "writeFile expects a bookmark and bytes",
            details: nil))
          return
        }
        self.writeFile(bookmark: bookmark, bytes: typed.data, result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    let imageClipboardChannel = FlutterMethodChannel(
      name: "dev.milanko.dartpdf/image_clipboard",
      binaryMessenger: flutterViewController.engine.binaryMessenger)
    imageClipboardChannel.setMethodCallHandler { (call, result) in
      if call.method == "readImage" {
        result(self.readImageFromClipboard())
        return
      }
      guard call.method == "copyPng" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let typed = call.arguments as? FlutterStandardTypedData else {
        result(FlutterError(
          code: "bad_args",
          message: "copyPng expects PNG bytes",
          details: nil))
        return
      }
      let pasteboard = NSPasteboard.general
      pasteboard.clearContents()
      result(pasteboard.setData(typed.data, forType: .png))
    }

    // Print without a bundled PDF engine: the Dart side hands over the whole
    // PDF and AppKit/PDFKit renders its vector content itself (CoreGraphics),
    // keeping text selectable.
    let nativePrintChannel = FlutterMethodChannel(
      name: "dev.milanko.dartpdf/native_print",
      binaryMessenger: flutterViewController.engine.binaryMessenger)
    nativePrintChannel.setMethodCallHandler { (call, result) in
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
          name: (args["name"] as? String) ?? "Document"))
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }

  /// Spools the whole PDF through AppKit's print panel via PDFKit. Returns
  /// false when the data isn't a readable PDF or the user cancels.
  private func runPrintJob(pdf: Data, name: String) -> Bool {
    guard let document = PDFDocument(data: pdf) else { return false }

    let printInfo = (NSPrintInfo.shared.copy() as? NSPrintInfo) ?? NSPrintInfo.shared
    guard let operation = document.printOperation(
      for: printInfo, scalingMode: .pageScaleDownToFit, autoRotate: true)
    else {
      return false
    }
    operation.jobTitle = name
    return operation.run()
  }

  private func readImageFromClipboard() -> FlutterStandardTypedData? {
    let pasteboard = NSPasteboard.general
    if let data = pasteboard.data(forType: .png) {
      return FlutterStandardTypedData(bytes: data)
    }
    if let data = pasteboard.data(forType: NSPasteboard.PasteboardType("public.jpeg")) {
      return FlutterStandardTypedData(bytes: data)
    }
    if let data = pasteboard.data(forType: .tiff),
       let converted = pngData(fromTiff: data) {
      return FlutterStandardTypedData(bytes: converted)
    }
    if let image = NSImage(pasteboard: pasteboard),
       let tiff = image.tiffRepresentation,
       let converted = pngData(fromTiff: tiff) {
      return FlutterStandardTypedData(bytes: converted)
    }
    return nil
  }

  private func createBookmark(path: String, result: FlutterResult) {
    let url = URL(fileURLWithPath: path)
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    do {
      let data = try url.bookmarkData(
        options: [.withSecurityScope],
        includingResourceValuesForKeys: nil,
        relativeTo: nil)
      result(FlutterStandardTypedData(bytes: data))
    } catch {
      result(FlutterError(
        code: "bookmark_failed",
        message: error.localizedDescription,
        details: nil))
    }
  }

  private func resolveBookmarkedURL(_ bookmark: String) throws -> URL {
    guard let data = Data(base64Encoded: bookmark) else {
      throw NSError(
        domain: "DartPdfFileAccess",
        code: 1,
        userInfo: [NSLocalizedDescriptionKey: "Invalid bookmark data"])
    }
    var stale = false
    return try URL(
      resolvingBookmarkData: data,
      options: [.withSecurityScope],
      relativeTo: nil,
      bookmarkDataIsStale: &stale)
  }

  private func readFile(bookmark: String, result: FlutterResult) {
    do {
      let url = try resolveBookmarkedURL(bookmark)
      let scoped = url.startAccessingSecurityScopedResource()
      defer { if scoped { url.stopAccessingSecurityScopedResource() } }
      let data = try Data(contentsOf: url)
      result(FlutterStandardTypedData(bytes: data))
    } catch {
      result(FlutterError(
        code: "read_failed",
        message: error.localizedDescription,
        details: nil))
    }
  }

  private func writeFile(bookmark: String, bytes: Data, result: FlutterResult) {
    do {
      let url = try resolveBookmarkedURL(bookmark)
      let scoped = url.startAccessingSecurityScopedResource()
      defer { if scoped { url.stopAccessingSecurityScopedResource() } }
      try bytes.write(to: url, options: .atomic)
      result(true)
    } catch {
      result(FlutterError(
        code: "write_failed",
        message: error.localizedDescription,
        details: nil))
    }
  }

  private func pngData(fromTiff data: Data) -> Data? {
    guard let bitmap = NSBitmapImageRep(data: data) else {
      return nil
    }
    return bitmap.representation(using: .png, properties: [:])
  }
}
