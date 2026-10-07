# Insert pages: several documents, interleave, Bluebeam-style options

"Insert document…" (app menu) and the thumbnail strip's "Insert PDF…" used to
merge one picked file straight in after the current page. They now open an
**Insert pages** dialog modelled on Bluebeam Revu's (Document > Pages >
Insert Pages):

- **Several files.** Multi-select picker plus "Add files…", "Sort by name",
  move up/down, remove. Each file is opened as it is added, so its page count
  shows and an unreadable or password-protected file is reported in the
  dialog instead of failing the whole insert.
- **Per-file page choice.** A range field (`1-3, 7`; blank = all), an
  All/Odd/Even filter and a Reverse toggle. Reverse + interleave is the
  duplex-scan case: back sides come out of the scanner last page first.
- **Placement.** Before/After × First page/Last page/Page N, defaulting to
  "after the current page" (the old behaviour, so Enter still does what it
  did).
- **Interleave.** Bluebeam's one-for-one weave, generalised to "N inserted
  pages, then M document pages" so a separator sheet every M pages works too.
- **Bookmarks.** "Include bookmarks" (drop each source's outline) and "Add a
  bookmark for each file", which nests that file's own outline under it.

A positioned file drop on the thumbnails still inserts straight at the
marker; an unpositioned drop's "Insert pages" now opens the dialog pre-filled.

## Where things live

- `pdf_document/lib/src/page_insert.dart` (part of editor.dart):
  `PdfEditor.insertPages(sources, at:, interleave:, bookmarks:)`,
  `PdfPageInsertSource` (+ `select()` resolving range/subset/reverse via
  `PdfSplitter.parseRanges`), `PdfPageInterleave` (+ the pure `order()`
  planner), `PdfPageSubset`. `appendPagesFrom` gained `outlines:`.
- A block insert lands each source in place with `appendPagesFrom(at:)` - the
  old cost. Only a weave appends everything and runs one `reorderPages`.
  Page refs survive the reorder, so per-file bookmarks are created against the
  landing index before it.
- `PdfEditingController.insertPages` - one `apply`, so one undo step for any
  number of files.
- `dart_pdf_editor/lib/src/insert_pages_dialog.dart`: `PdfInsertFile`,
  `PdfPickInsertFiles`, `showPdfInsertPagesDialog` → `PdfInsertPagesPlan`,
  `pdfInsertPagesInteractively` (pick → dialog → apply), `pdfInsertIndex`.
  It is on the design-imports baseline by hand: like the split/page-range
  dialogs it needs Material form controls, which have no widgets-layer seam yet.
- New optional `onPickPdfFilesToInsert` on `PdfEditorView`,
  `PdfThumbnailSidebar` and `PdfThumbnailView`; it takes precedence over the
  single-file `onPickPdfToInsert`, which keeps working for existing hosts.

## Gotchas

- `XFile.fromData(name:)` on native reports `name` from the *path*; tests
  must pass `path:` too or the dialog lists blank names.
- ICU `=1{…}` next to `one{…}` warns as an overridden branch in gen-l10n;
  the Slavic strings use `one/few/many` only.

Tests: `pdf_document/test/page_insert_test.dart`,
`dart_pdf_editor/test/insert_pages_dialog_test.dart`,
`app/test/insert_document_test.dart`.
