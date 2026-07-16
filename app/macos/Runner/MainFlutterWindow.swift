import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  // Pages accumulated for the current native print job (JPEG bytes), and its
  // title. See the `native_print` channel below - printing renders here with
  // our own engine and spools through AppKit, never a bundled PDF engine.
  private var printPages: [Data] = []
  private var printJobTitle = "Document"

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

    // Print without a bundled PDF engine: the Dart side renders each page and
    // streams it here as a JPEG; endJob spools them through AppKit's own print
    // system (NSPrintOperation).
    let nativePrintChannel = FlutterMethodChannel(
      name: "dev.milanko.dartpdf/native_print",
      binaryMessenger: flutterViewController.engine.binaryMessenger)
    nativePrintChannel.setMethodCallHandler { (call, result) in
      switch call.method {
      case "beginJob":
        self.printPages = []
        self.printJobTitle =
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
        self.printPages.append(typed.data)
        result(true)
      case "endJob":
        result(self.runPrintJob())
      case "cancelJob":
        self.printPages = []
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }

  /// Spools the accumulated page images through AppKit's print panel. Returns
  /// false when there is nothing to print or the user cancels.
  private func runPrintJob() -> Bool {
    let images = printPages.compactMap { NSImage(data: $0) }
    printPages = []
    guard !images.isEmpty else { return false }

    let printInfo = (NSPrintInfo.shared.copy() as? NSPrintInfo) ?? NSPrintInfo.shared
    printInfo.topMargin = 0
    printInfo.bottomMargin = 0
    printInfo.leftMargin = 0
    printInfo.rightMargin = 0
    printInfo.horizontalPagination = .fit
    printInfo.verticalPagination = .fit

    let view = ImagePrintView(images: images, pageSize: printInfo.paperSize)
    let operation = NSPrintOperation(view: view, printInfo: printInfo)
    operation.jobTitle = printJobTitle
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

/// An off-screen view that lays out one image per printed page, top to bottom,
/// each aspect-fitted and centred on the sheet. Drives NSPrintOperation's page
/// range so AppKit spools one image per page.
private final class ImagePrintView: NSView {
  private let images: [NSImage]
  private let pageSize: NSSize

  init(images: [NSImage], pageSize: NSSize) {
    self.images = images
    self.pageSize = pageSize
    super.init(frame: NSRect(
      x: 0, y: 0,
      width: pageSize.width,
      height: pageSize.height * CGFloat(max(images.count, 1))))
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func knowsPageRange(_ range: NSRangePointer) -> Bool {
    range.pointee = NSRange(location: 1, length: images.count)
    return true
  }

  // Page 1 is the top of the (unflipped, y-up) view.
  override func rectForPage(_ page: Int) -> NSRect {
    let index = page - 1
    let y = CGFloat(images.count - 1 - index) * pageSize.height
    return NSRect(x: 0, y: y, width: pageSize.width, height: pageSize.height)
  }

  override func draw(_ dirtyRect: NSRect) {
    for (index, image) in images.enumerated() {
      let y = CGFloat(images.count - 1 - index) * pageSize.height
      let pageRect = NSRect(
        x: 0, y: y, width: pageSize.width, height: pageSize.height)
      image.draw(
        in: ImagePrintView.aspectFit(imageSize: image.size, into: pageRect),
        from: .zero, operation: .sourceOver, fraction: 1.0)
    }
  }

  private static func aspectFit(imageSize: NSSize, into rect: NSRect) -> NSRect {
    guard imageSize.width > 0, imageSize.height > 0 else { return rect }
    let scale = min(rect.width / imageSize.width, rect.height / imageSize.height)
    let width = imageSize.width * scale
    let height = imageSize.height * scale
    return NSRect(
      x: rect.minX + (rect.width - width) / 2,
      y: rect.minY + (rect.height - height) / 2,
      width: width, height: height)
  }
}
