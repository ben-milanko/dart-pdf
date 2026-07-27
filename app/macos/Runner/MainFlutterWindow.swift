import Cocoa
import Darwin
import FlutterMacOS
import PDFKit

/// Runs security-scoped filesystem work away from AppKit's main thread.
///
/// Flutter invokes macOS method-channel handlers on the main thread. A read
/// from an iCloud/OneDrive placeholder may block while File Provider hydrates
/// it, so doing the work inline freezes every frame and input event. The queue
/// is concurrent so one slow remote document does not prevent another restored
/// tab backed by a local file from loading. Results return on the main thread,
/// where Flutter's binary messenger expects them.
final class FileAccessExecutor {
  private let queue: DispatchQueue

  init(
    queue: DispatchQueue = DispatchQueue(
      label: "dev.milanko.dartpdf.file-access",
      qos: .userInitiated,
      attributes: .concurrent)
  ) {
    self.queue = queue
  }

  func perform(
    errorCode: String,
    result: @escaping FlutterResult,
    _ operation: @escaping () throws -> Any?
  ) {
    queue.async {
      do {
        let value = try operation()
        DispatchQueue.main.async {
          result(value)
        }
      } catch {
        DispatchQueue.main.async {
          result(FlutterError(
            code: errorCode,
            message: error.localizedDescription,
            details: nil))
        }
      }
    }
  }

  /// Runs native file work without a Flutter result callback.
  ///
  /// AppDelegate uses this for files delivered by Finder before the Flutter
  /// method channels are ready.
  func perform(_ operation: @escaping () -> Void) {
    queue.async(execute: operation)
  }
}

class MainFlutterWindow: NSWindow {
  private let fileAccess = FileAccessExecutor()

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

    let memoryChannel = FlutterMethodChannel(
      name: "dev.milanko.dartpdf/memory",
      binaryMessenger: flutterViewController.engine.binaryMessenger)
    memoryChannel.setMethodCallHandler { (call, result) in
      guard call.method == "snapshot" else {
        result(FlutterMethodNotImplemented)
        return
      }
      var snapshot: [String: Any] = [
        "physicalBytes": Int64(ProcessInfo.processInfo.physicalMemory),
        "lowMemory": false,
      ]
      if let available = Self.availableProcessMemory() {
        snapshot["availableBytes"] = Int64(available)
      }
      result(snapshot)
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
      case "fileLength":
        guard let args = call.arguments as? [String: Any],
              let bookmark = args["bookmark"] as? String else {
          result(FlutterError(
            code: "bad_args",
            message: "fileLength expects a bookmark",
            details: nil))
          return
        }
        self.fileLength(bookmark: bookmark, result: result)
      case "readFileRange":
        guard let args = call.arguments as? [String: Any],
              let bookmark = args["bookmark"] as? String,
              let offset = args["offset"] as? Int,
              let length = args["length"] as? Int else {
          result(FlutterError(
            code: "bad_args",
            message: "readFileRange expects a bookmark, offset and length",
            details: nil))
          return
        }
        self.readFileRange(
          bookmark: bookmark, offset: offset, length: length, result: result)
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

  /// `os_proc_available_memory` is not exposed by Swift's Darwin module map.
  /// Resolve the documented libSystem function dynamically so the app can use
  /// its advisory per-process headroom without a private API or helper plugin.
  private static func availableProcessMemory() -> UInt64? {
    guard let handle = dlopen(nil, RTLD_NOW) else { return nil }
    defer { dlclose(handle) }
    guard let symbol = dlsym(handle, "os_proc_available_memory") else {
      return nil
    }
    typealias AvailableMemory = @convention(c) () -> UInt
    let function = unsafeBitCast(symbol, to: AvailableMemory.self)
    let bytes = function()
    return bytes > 0 ? UInt64(bytes) : nil
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

  private func createBookmark(path: String, result: @escaping FlutterResult) {
    fileAccess.perform(errorCode: "bookmark_failed", result: result) {
      let url = URL(fileURLWithPath: path)
      let scoped = url.startAccessingSecurityScopedResource()
      defer { if scoped { url.stopAccessingSecurityScopedResource() } }
      let data = try url.bookmarkData(
        options: [.withSecurityScope],
        includingResourceValuesForKeys: nil,
        relativeTo: nil)
      return FlutterStandardTypedData(bytes: data)
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

  private func readFile(bookmark: String, result: @escaping FlutterResult) {
    fileAccess.perform(errorCode: "read_failed", result: result) {
      let url = try self.resolveBookmarkedURL(bookmark)
      let scoped = url.startAccessingSecurityScopedResource()
      defer { if scoped { url.stopAccessingSecurityScopedResource() } }
      let data = try Data(contentsOf: url)
      return FlutterStandardTypedData(bytes: data)
    }
  }

  /// The byte length of a bookmarked file, for the progressive/ranged loader.
  private func fileLength(bookmark: String, result: @escaping FlutterResult) {
    fileAccess.perform(errorCode: "length_failed", result: result) {
      let url = try self.resolveBookmarkedURL(bookmark)
      let scoped = url.startAccessingSecurityScopedResource()
      defer { if scoped { url.stopAccessingSecurityScopedResource() } }
      let values = try url.resourceValues(forKeys: [.fileSizeKey])
      return values.fileSize ?? 0
    }
  }

  /// Reads `length` bytes starting at `offset` from a bookmarked file. Lets the
  /// progressive loader (and the background full read) pull only the ranges it
  /// needs from a sandboxed / cloud-synced file without slurping the whole
  /// thing - the security scope is reactivated per call and released right
  /// after, so no handle or scope leaks between reads. A short read near EOF
  /// returns fewer bytes; an offset past EOF returns an empty list.
  private func readFileRange(
    bookmark: String, offset: Int, length: Int,
    result: @escaping FlutterResult
  ) {
    fileAccess.perform(errorCode: "read_failed", result: result) {
      let url = try self.resolveBookmarkedURL(bookmark)
      let scoped = url.startAccessingSecurityScopedResource()
      defer { if scoped { url.stopAccessingSecurityScopedResource() } }
      let handle = try FileHandle(forReadingFrom: url)
      defer { handle.closeFile() }
      handle.seek(toFileOffset: UInt64(max(0, offset)))
      let data = handle.readData(ofLength: max(0, length))
      return FlutterStandardTypedData(bytes: data)
    }
  }

  private func writeFile(
    bookmark: String, bytes: Data, result: @escaping FlutterResult
  ) {
    fileAccess.perform(errorCode: "write_failed", result: result) {
      let url = try self.resolveBookmarkedURL(bookmark)
      let scoped = url.startAccessingSecurityScopedResource()
      defer { if scoped { url.stopAccessingSecurityScopedResource() } }
      try bytes.write(to: url, options: .atomic)
      return true
    }
  }

  private func pngData(fromTiff data: Data) -> Data? {
    guard let bitmap = NSBitmapImageRep(data: data) else {
      return nil
    }
    return bitmap.representation(using: .png, properties: [:])
  }
}
