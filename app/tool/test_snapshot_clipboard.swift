// Run with swiftc macos/Runner/SnapshotClipboard.swift
// tool/test_snapshot_clipboard.swift -o /tmp/test_snapshot_clipboard && /tmp/test_snapshot_clipboard
import AppKit

@main
struct ClipboardTest {
  static func main() {
    // A private pasteboard exercises the real AppKit transport without changing
    // the user's clipboard. Simulate a second application via direct writes.
    let pasteboard = NSPasteboard.withUniqueName()
    defer { pasteboard.releaseGlobally() }
    let clipboard = SnapshotClipboard(pasteboard: pasteboard)
    let pdf = Data("%PDF-1.7\nvector payload\n%%EOF".utf8)
    let png = Data([0x89, 0x50, 0x4E, 0x47, 0, 0xFF])
    precondition(clipboard.copy(pdf: pdf, png: png))
    precondition(pasteboard.pasteboardItems?.count == 1)
    precondition(pasteboard.data(forType: .pdf) == pdf)
    precondition(pasteboard.data(forType: .png) == png)
    precondition(clipboard.readExternalPdf() == nil)
    pasteboard.clearContents()
    pasteboard.setData(pdf, forType: .pdf)
    precondition(clipboard.readExternalPdf() == pdf, "external recopy of identical bytes must win")
    pasteboard.clearContents()
    pasteboard.setString("text only", forType: .string)
    precondition(clipboard.readExternalPdf() == nil)
    precondition(!clipboard.copy(pdf: Data(), png: png))
    precondition(pasteboard.string(forType: .string) == "text only")
    print("AppKit PDF/PNG clipboard tests passed")
  }
}
