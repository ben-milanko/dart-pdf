# Bake the page colour into saved/exported files

The paper colour (`PdfEditingPreferences.pageColor` / `PdfViewer.pageColor`)
was display-only, so a sepia or tinted page reverted to white in every other
reader. It can now be written into the file, opt-in.

## Pieces

- **pdf_document** - `PdfEditor.fillPageBackground(0xRRGGBB, {fromPage,
  toPage})` (`page_background.dart`, a part of editor.dart). Inserts a stream
  at the *front* of each page's /Contents filling the media box (not the crop
  box, so a later re-crop can't expose white), wrapped in
  `/Artifact <</Type /Background>> BDC ... EMC` so tagged-PDF readers skip it.
  Its first line is the comment `%DartPdfPageBackground`; a later fill that
  finds that marker on the first content stream **replaces** it, so re-baking
  (another save of a reopened file, a colour change) never stacks rectangles.
  A filtered (e.g. compressed by Reduce file size) or encrypted stream doesn't
  match - the fallback is one extra rectangle under the new one, harmless.
- **dart_pdf_editor** - `pdfBakePageColor(bytes, color, {source})`
  (`page_color_bake.dart`): incremental update on top of `bytes`, translucent
  colours composited over white first (what the viewer shows). `source` reopens
  via `openAppended` so encrypted files keep their keys. `pdfPageColorNeedsBaking`
  (white = nothing to do) and `pdfPageColorBakeBlocked` (any signature field -
  repainting pages invalidates signatures / breaks DocMDP).
  `PdfEditingPreferences.bakePageColor` (persisted, default off) and a View
  options toggle "Save page color into file" (`pdf-shell-bake-page-color`, both
  the popup and the compact sheet; hidden whenever the page colour itself is not
  editable).
- **app** - `EditorScreen._withBakedPageColor` runs on Save / Save As and on
  the thumbnail panels' Export pages. The edit session is never touched: only
  the bytes handed to disk carry the fill, so every save bakes over the same
  unbaked base. Signed documents save unbaked with a toast. A bake that throws
  saves unbaked rather than failing the save. Export as image uses the page
  colour while the option is on.

Tests: `pdf_document/test/page_background_test.dart`,
`dart_pdf_editor/test/page_color_bake_test.dart`,
`app/test/save_page_color_test.dart`.

The example app (`packages/dart_pdf_editor/example/lib/main.dart`) wires the
same thing into its `onSave` (`_withBakedPageColor`) and Export as image.
Its Export pages opens the pages in a new tab rather than writing a file, so
that tab's own save is where the colour lands. The Cupertino host sample
doesn't write files, so it has nothing to wire.
