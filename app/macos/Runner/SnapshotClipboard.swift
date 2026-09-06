import AppKit

/// One owner per process, shared by every Flutter window/engine. Keeping the
/// pasteboard change count lets local paste use the detached vector clipboard
/// while a subsequent external PDF copy supersedes it, even for equal bytes.
final class SnapshotClipboard {
  static let shared = SnapshotClipboard()
  private let pasteboard: NSPasteboard
  private var localChangeCount: Int?

  init(pasteboard: NSPasteboard = .general) {
    self.pasteboard = pasteboard
  }

  func copy(pdf: Data, png: Data) -> Bool {
    guard !pdf.isEmpty, !png.isEmpty else { return false }
    let item = NSPasteboardItem()
    guard item.setData(pdf, forType: .pdf),
          item.setData(png, forType: .png) else { return false }
    pasteboard.clearContents()
    let copied = pasteboard.writeObjects([item])
    localChangeCount = copied ? pasteboard.changeCount : nil
    return copied
  }

  func markLocalCopy() {
    localChangeCount = pasteboard.changeCount
  }

  func readExternalPdf() -> Data? {
    guard pasteboard.changeCount != localChangeCount else { return nil }
    return pasteboard.data(forType: .pdf)
  }
}
