# Changelog

## 1.3.0

- Swap selected page-content images without UI stalls: imported image
  processing now runs asynchronously before the replacement is committed.
- Mobile and narrow editor chrome now exposes selected page-content actions
  for delete, text editing, reflow, and image replacement.
- Platform installed fonts appear in the text font picker on native builds and
  embed into edited PDFs.
- Large-document rendering and navigation improvements for CAD-style PDFs,
  including pooled/preemptible render workers, capped normal-view image
  resolution, optimized deep zoom, and shared preview/thumbnail caching.
- Viewer polish for hyperlinks, configurable single-key editing shortcuts,
  page-content editing, annotation sync, snapshot/vector paste, and app
  release readiness across desktop, mobile, and web.

## 1.2.3

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
