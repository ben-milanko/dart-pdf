import Flutter
import UIKit
import UniformTypeIdentifiers

/// Receives PDFs opened in the app - "Open in…", the share sheet, the Files
/// browser - and forwards them to the Dart `IncomingFileService`. The iOS
/// template is scene-based, so file URLs arrive here rather than in the
/// AppDelegate.
class SceneDelegate: FlutterSceneDelegate {
  private var channel: FlutterMethodChannel?

  /// Files received before the channel was wired (cold start). Drained by the
  /// Dart side's `getInitialFile` call.
  private var pending: [[String: Any]] = []

  private var pencilChannel: FlutterMethodChannel?
  private var pencilInteraction: AnyObject?
  private var imageClipboardChannel: FlutterMethodChannel?
  private var mobileFileChannel: FlutterMethodChannel?
  private var memoryChannel: FlutterMethodChannel?

  /// The in-flight `pickDocuments` reply, held while the document picker is up
  /// (its result arrives asynchronously via the picker delegate).
  private var pendingPick: FlutterResult?

  /// Serializes the (potentially large) ranged reads off the platform thread.
  private let fileIoQueue = DispatchQueue(label: "dev.milanko.dartpdf.mobilefile")

  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)
    setupChannel()
    setupImageClipboardChannel()
    setupMobileFileChannel()
    setupMemoryChannel()
    setupPencilInteraction()
    handle(connectionOptions.urlContexts)
  }

  private func setupMemoryChannel() {
    guard memoryChannel == nil,
      let controller = window?.rootViewController as? FlutterViewController
    else { return }
    let ch = FlutterMethodChannel(
      name: "dev.milanko.dartpdf/memory",
      binaryMessenger: controller.binaryMessenger)
    ch.setMethodCallHandler { (call, result) in
      guard call.method == "snapshot" else {
        result(FlutterMethodNotImplemented)
        return
      }
      result([
        "physicalBytes": Int64(ProcessInfo.processInfo.physicalMemory),
        // Apple's advisory per-app headroom. Unlike system free memory this
        // follows the current jetsam limit and can change over the app life.
        "availableBytes": Int64(os_proc_available_memory()),
        "lowMemory": false,
      ])
    }
    memoryChannel = ch
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

  private func setupImageClipboardChannel() {
    guard imageClipboardChannel == nil,
      let controller = window?.rootViewController as? FlutterViewController
    else { return }
    let ch = FlutterMethodChannel(
      name: "dev.milanko.dartpdf/image_clipboard",
      binaryMessenger: controller.binaryMessenger)
    ch.setMethodCallHandler { (call, result) in
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
      UIPasteboard.general.setData(typed.data, forPasteboardType: "public.png")
      result(true)
    }
    imageClipboardChannel = ch
  }

  /// Reference-based open (#364): a custom picker in `.open` mode that keeps a
  /// security-scoped URL to the *original* file instead of importing a copy,
  /// plus coordinated ranged reads over that URL so a large iCloud/OneDrive PDF
  /// can first-paint before the whole file downloads. iOS File Provider serves
  /// the requested byte ranges on demand.
  private func setupMobileFileChannel() {
    guard mobileFileChannel == nil,
      let controller = window?.rootViewController as? FlutterViewController
    else { return }
    let ch = FlutterMethodChannel(
      name: "dev.milanko.dartpdf/mobile_file",
      binaryMessenger: controller.binaryMessenger)
    ch.setMethodCallHandler { [weak self] (call, result) in
      self?.handleMobileFile(call, result)
    }
    mobileFileChannel = ch
  }

  private func handleMobileFile(
    _ call: FlutterMethodCall, _ result: @escaping FlutterResult
  ) {
    switch call.method {
    case "pickDocuments":
      presentOpenPicker(result)
    case "probeSeekable":
      guard let token = (call.arguments as? [String: Any])?["token"] as? String
      else {
        result(FlutterError(code: "bad_args", message: "probeSeekable expects a token", details: nil))
        return
      }
      fileIoQueue.async { [weak self] in
        let seekable = self?.probeSeekable(token) ?? false
        DispatchQueue.main.async { result(seekable) }
      }
    case "fileLength":
      guard let token = (call.arguments as? [String: Any])?["token"] as? String
      else {
        result(FlutterError(code: "bad_args", message: "fileLength expects a token", details: nil))
        return
      }
      fileIoQueue.async { [weak self] in
        let len = self?.fileLength(token) ?? -1
        DispatchQueue.main.async { result(len) }
      }
    case "readRange":
      guard let args = call.arguments as? [String: Any],
        let token = args["token"] as? String,
        let offset = (args["offset"] as? NSNumber)?.int64Value,
        let length = (args["length"] as? NSNumber)?.intValue
      else {
        result(FlutterError(code: "bad_args", message: "readRange expects token/offset/length", details: nil))
        return
      }
      fileIoQueue.async { [weak self] in
        let data = self?.readRange(token, offset: offset, length: length)
        DispatchQueue.main.async {
          if let data = data {
            result(FlutterStandardTypedData(bytes: data))
          } else {
            result(FlutterError(code: "read_failed", message: "range read failed", details: nil))
          }
        }
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// Presents the document picker in `.open` mode so the returned URL is a
  /// security-scoped reference to the original file, not an imported copy.
  private func presentOpenPicker(_ result: @escaping FlutterResult) {
    guard pendingPick == nil else {
      result(FlutterError(code: "busy", message: "A document picker is already open", details: nil))
      return
    }
    guard let root = window?.rootViewController else {
      result(FlutterError(code: "no_window", message: "No root view controller", details: nil))
      return
    }
    let picker: UIDocumentPickerViewController
    if #available(iOS 14.0, *) {
      picker = UIDocumentPickerViewController(forOpeningContentTypes: [.pdf])
    } else {
      picker = UIDocumentPickerViewController(documentTypes: ["com.adobe.pdf"], in: .open)
    }
    picker.allowsMultipleSelection = true
    picker.delegate = self
    pendingPick = result
    root.present(picker, animated: true)
  }

  /// Builds the Dart-side descriptor for a picked URL: a base64 security-scoped
  /// bookmark [token], display name, length, and a seekability probe. Returns
  /// nil when a bookmark can't be minted (the URL is then unusable by range).
  fileprivate func describePickedURL(_ url: URL) -> [String: Any]? {
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    guard let bookmark = try? url.bookmarkData() else { return nil }
    let token = bookmark.base64EncodedString()
    let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? -1
    return [
      "token": token,
      "name": url.lastPathComponent,
      "length": size,
      // iOS File Provider serves coordinated ranged reads on demand, so a
      // resolvable URL is seekable; confirm by opening a handle.
      "seekable": probeSeekableURL(url),
    ]
  }

  /// Resolves a base64 bookmark [token] back to its security-scoped URL.
  private func resolveToken(_ token: String) -> URL? {
    guard let data = Data(base64Encoded: token) else { return nil }
    var stale = false
    return try? URL(
      resolvingBookmarkData: data, options: [], relativeTo: nil,
      bookmarkDataIsStale: &stale)
  }

  private func probeSeekable(_ token: String) -> Bool {
    guard let url = resolveToken(token) else { return false }
    return probeSeekableURL(url)
  }

  private func probeSeekableURL(_ url: URL) -> Bool {
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    var ok = false
    var coordError: NSError?
    NSFileCoordinator().coordinate(
      readingItemAt: url, options: [], error: &coordError
    ) { readURL in
      guard let handle = try? FileHandle(forReadingFrom: readURL) else { return }
      defer { try? handle.close() }
      // A resolvable, openable file is seekable; a genuinely non-seekable
      // source can't be opened by FileHandle at all.
      ok = true
    }
    return ok
  }

  private func fileLength(_ token: String) -> Int {
    guard let url = resolveToken(token) else { return -1 }
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    var size = -1
    var coordError: NSError?
    NSFileCoordinator().coordinate(
      readingItemAt: url, options: [], error: &coordError
    ) { readURL in
      size = (try? readURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? -1
    }
    return size
  }

  /// Reads `[offset, offset+length)` from the token's file through a coordinated
  /// read + `FileHandle` seek, letting the File Provider fetch just that range.
  private func readRange(_ token: String, offset: Int64, length: Int) -> Data? {
    guard let url = resolveToken(token) else { return nil }
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    var result: Data?
    var coordError: NSError?
    NSFileCoordinator().coordinate(
      readingItemAt: url, options: [], error: &coordError
    ) { readURL in
      guard let handle = try? FileHandle(forReadingFrom: readURL) else { return }
      defer { try? handle.close() }
      handle.seek(toFileOffset: UInt64(offset))
      result = handle.readData(ofLength: length)
    }
    return result
  }

  /// Wires the Apple Pencil's hardware double-tap to the Dart side. Flutter
  /// exposes no event for it, so we register a `UIPencilInteraction` on the
  /// Flutter view and forward each gesture over the shared method channel;
  /// the editor toggles its eraser (see `PdfPencilInteraction` in
  /// dart_pdf_editor). This template is scene-based, so - like the file
  /// channel above - the gesture is installed here, not in the AppDelegate
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

extension SceneDelegate: UIDocumentPickerDelegate {
  func documentPicker(
    _ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]
  ) {
    let reply = pendingPick
    pendingPick = nil
    guard let reply = reply else { return }
    fileIoQueue.async { [weak self] in
      let entries = urls.compactMap { self?.describePickedURL($0) }
      DispatchQueue.main.async { reply(entries) }
    }
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    let reply = pendingPick
    pendingPick = nil
    // An empty list means the user backed out, distinct from an error.
    reply?([])
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
