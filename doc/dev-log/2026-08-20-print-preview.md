# DartPDF's own print preview (Windows/Linux)

A 3.7.0 Windows report: hitting Print shows **"This app doesn't support
print preview"**.

## What that message actually is

Not ours — nothing in the tree emits that string. It comes from the Windows
print dialog. Since Windows 11 22H2 the classic common print dialog is
replaced, for Win32 callers of `PrintDlg`/`PrintDlgEx`, by the "unified"
print dialog, which has a preview pane. The legacy print API hands Windows a
DEVMODE and a DC and nothing else — no document content — so that pane has
nothing to render and says so. Every `PrintDlgEx` caller gets it (SumatraPDF,
QCAD, Notepad++ threads all say the same); v4/IPP/class drivers and virtual
printers like Microsoft Print to PDF make it more likely still. **Printing
itself is unaffected** — the job spools normally.

The runner reaches that dialog in `NativePrinter::End`
(`app/windows/runner/native_print.cpp`), and nothing in 3.7.0 touched the
print path, so what changed for the reporter was Windows, a driver, or the
default printer — not us.

Two dead ends worth recording: the documented way back to the legacy dialog
is `PrintDlg` with `PD_ENABLEPRINTHOOK` and a no-op hook proc (or a null
`hwndOwner`), which only trades a wrong message for no preview at all; and
filling the modern pane properly means printing through the WinRT print
stack (`IPrintManagerInterop` + an XPS document source), which needs package
identity and a whole second print path. So: preview it ourselves.

## What landed

`showPrintPreviewDialog` (`app/lib/print_preview_dialog.dart`) — the job as
it will print, plus the page range, before the OS dialog opens:

- The previewed page is rendered by our own engine
  (`PdfPageRenderer.renderImage`, annotations on, because the vector print
  encoder keeps them). Rasterised rather than replayed per paint, like the
  thumbnail strip: cheap to repaint, and a `ui.Image` is safe to dispose the
  moment it is replaced. Renders are bucketed by 32px of width so a resize
  doesn't queue one per pixel, and carry a token so an out-of-order landing
  is dropped.
- Range is All / Current / a typed from–to. The arrows walk **the
  selection**, not the document (`_previewSlot` is an offset into the chosen
  pages), so the preview can only ever show a page that will actually print.

Who sees it is decided by `platformProvidesPrintPreview()`
(`app/lib/printing.dart`): false on Windows and Linux, true on iOS/macOS/
Android (the whole PDF goes to the OS print system, which previews it) and on
web (the browser's dialog does). Previewing where the OS already previews
would just be two previews.

`EditorScreen._print` opens it and then prints what it returns. A narrowed
range prints `document.extractPages(selection)` rather than the whole file —
that is also how the range survives the whole-PDF print paths, and it keeps
`printDocumentPages` (and the `printDocument` test seam) unchanged. The full
range prints the original bytes untouched.

## Gotchas

- `debugDefaultTargetPlatformOverride` has to be set **and cleared inside the
  test body**: the framework's leaked-debug-variable check runs before
  `tearDown`, so setting it in `setUp` fails every test in the group.
- `print_menu_test`'s Ctrl+P case pins Linux, so it now goes through the
  preview — that is the coverage that the shortcut reaches it.
- `AlertDialog` doesn't scroll its content, so the preview box is sized
  against the window with room left for title/actions; the three-way
  `SegmentedButton` sits in a `FittedBox` because it neither wraps nor
  scrolls and translated labels are longer than "All / Current / Range".
