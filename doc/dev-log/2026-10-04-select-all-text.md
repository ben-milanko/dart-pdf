# Cmd/Ctrl+A selects page text again

- Regression from #1002 (Select tool selects text) + #1012 (documents open
  in Select mode): `_PdfViewerState._onSelectAll` sent ⌘A to
  `selectAllAnnotationsOn` whenever the select tool was armed - now the
  default mode - so it selected annotations (or nothing on a page without
  any), and it returned early in Hand mode.
- Now: an existing annotation selection widens to every annotation on the
  page; otherwise ⌘A selects the page's text in any mode. A page with no
  text falls back to its annotations under the select tool.
  `_selectAllTextOn` returns whether it selected anything.
- Tests: the cmd+A cases in
  `packages/dart_pdf_editor/test/editing_multiselect_test.dart`.
