# Documents open in Select mode; long-press selects text there

- `app/lib/document_tab.dart`: a new tab's session now arms
  `PdfEditTool.select` instead of `activateHandMode()`. Hand mode is one
  toolbar click away. Test: `app/test/select_mode_default_test.dart`
  (renamed from `hand_mode_default_test.dart`).
- Touch long-press text selection was gated on `editing.tool == null`, so
  on mobile it did nothing in Select mode - now the mode a document opens in.
  `PdfViewer._selectionLongPressEnabledAt` lets the viewer's
  `_SelectionLongPressRecognizer` join the arena in Select mode too, except
  when the press is on a selectable annotation (the overlay keeps the press so
  it can drag the annotation or open its long-press menu). Drawing tools, Hand
  mode and the eyedropper still own the press. The recognizer's `isEnabled`
  now takes the press position.
- Touch drags in Select mode still scroll through the overlay's viewport pan.
  The long-press only wins once the finger has held still past the timeout.
  Tests: the "in Select mode" group in
  `packages/dart_pdf_editor/test/pdf_touch_selection_test.dart`.
