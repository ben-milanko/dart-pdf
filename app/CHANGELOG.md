# Changelog

## 1.3.2

- Editing polish from the 1.3.2 package suite: no-flicker annotation
  appearance updates, zoom-stable chrome, improved gesture rendering, right-click
  form-field editing, and more direct highlight styling.
- Custom stamps can now be built from vector templates with dynamic fields,
  saved signatures, image components, metadata, and configurable date/time
  placeholders.
- macOS release builds more reliably re-sign embedded native libraries.

## 1.3.1

- Text boxes can use installed platform fonts through the editor font menu;
  selected fonts are embedded so documents render and print consistently.
- Includes the 1.3.1 package-suite updates for custom editor toolbar chrome,
  OCR rasterization, rendering, annotation editing robustness, and interpreter
  color handling.

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
