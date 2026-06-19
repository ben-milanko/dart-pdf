# Changelog

## Unreleased

- Print the open document through the OS print dialog on every platform
  (browser print on the web), from ⌘P / Ctrl+P or the DartPDF menu.

## 1.2.2

- View rotation, deeper zoom, and smoother touch scrolling in the viewer.
- Free-text editing improvements: any embedded TrueType/OpenType font,
  paste-to-text-box, autosize, right-to-left text, and fixes for non-Latin
  glyphs and rotated pages.
- Background render worker preempts superseded jobs and recovers from a slow
  or silent worker, so large CAD drawings no longer hang while scrolling.
- Save As (Ctrl/Cmd+Shift+S), "Set up as default application", and "Open
  containing folder" in the tab context menu.
- Windows on-device OCR model path staging fix.
- Android: support 16 KB memory page sizes.
