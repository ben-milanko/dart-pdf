# FDF, XFDF and XDP form-data and comment exchange

Acrobat's data-exchange formats, both directions, in pdf_document, plus app
wiring.

## Library (pdf_document, all `part of 'editor.dart'`)

- `form_data_exchange.dart` - the hub model. `PdfFormData` (fields +
  comments + `/F` target + `/ID`) is what every format reads into and writes
  out of, so FDF ↔ XFDF converts without a PDF. `PdfFormData.of(document)`
  captures a document (Acrobat Export Data + Export Comments);
  `PdfEditor.importFormData` applies one (Import Data + Import Comments).
  `pdfSniffExchangeFormat` tells PDF/FDF/XFDF/XDP apart from the header or
  XML root.
- `fdf_codec.dart` - FDF is PDF object syntax under `%FDF-`. The reader swaps
  the header word for `%PDF` in a copy (same length, so every xref offset
  holds) and hands it to `CosDocument.open`. Its xref recovery covers the
  many FDFs written with no cross-reference table at all. The writer is
  `CosDocumentBuilder` with the first four bytes patched back to `%FDF`.
  pdf_cos is untouched.
- `xfdf_codec.dart` - table-driven attribute ↔ dictionary-key mapping (the
  `_xfdf*` maps), plus a tiny XML escaper/serializer. Parsing uses the
  existing strict `trust_lists/xml_lite.dart` (it refuses DTDs that declare
  entities, which is the right call for untrusted files).
- `xdp_codec.dart` - `PdfXdpPackage`: embedded (`<chunk>` base64) or
  referenced (`<pdf href>`) PDF, the `<xfa:datasets>` packet, and an optional
  `<xfdf>` packet. `toPdf()` is "open the .xdp": the embedded PDF with the
  data applied. `build(document)` keeps an XFA form's own packets verbatim
  and inserts `<pdf>` before `</xdp:xdp>`; for a plain AcroForm it
  synthesizes datasets from the field names.

## Decisions worth knowing

- **Comment identity is /NM.** Import upserts through the sync layer's
  `_findByName`/`upsertAnnotation`, so importing the same file twice
  replaces rather than duplicates. Unnamed comments get a fresh /NM at
  capture/parse time so replies can name their parent. /IRT can't travel as
  a reference, so it rides as `PdfExchangeAnnotation.inReplyTo` and is
  relinked on paste (the clipboard's existing mechanism). Parents are
  imported before replies.
- **Appearances.** An FDF comment with /AP pastes as-is. XFDF never carries
  one, so an appearance-less comment of a subtype the editor draws
  (markup, ink, square/circle, line, polyline, polygon, free text, note,
  stamp) goes through the editor's own `add*` generator. The metadata the
  generator doesn't own (dates, subject, flags, /RC, review state, /IT...)
  is then copied over (`_generatorOwned` is the deny-list). Replies and other
  subtypes (caret, file attachment...) paste without an appearance.
- `_SnapshotCopier` now takes a `CosDocument` rather than a `PdfDocument`,
  because an FDF has no page tree. Call sites pass `document.cos`.
- **Field values** go through the normal fill setters, so appearances
  regenerate and a hybrid form's stale /XFA is dropped exactly as an
  interactive fill does. Unchanged values are skipped (an import that
  changes nothing stages nothing). Check boxes take anything but
  `Off`/empty/`0`/`false`/`no` as checked (XFA data says `1`/`0`). Radio
  groups also accept an /Opt export value and map it to the index-named
  state.
- **XDP → AcroForm matching** (`_matchXdpLeaves`). The leaf name and
  occurrence index must match. The ancestors must then be equal, or one a
  subsequence of the other: XFA hybrids put page subforms like `Page1[0]` in
  AcroForm names that the data tree doesn't have, and unnamed `#subform`
  levels drop. Failing that, the one field with that leaf wins. A dynamic
  XFA form (`isDynamicXfa`) instead gets its datasets packet replaced (array
  or single-stream /XFA), since that's what an XFA viewer fills from.

## App

- The menu export sheet gets "Import form data or comments…" and "Export
  form data as FDF/XFDF…" / "Export as XDP…" (`_importFormData`,
  `_exportFormData`, `_applyFormDataFile`). Import is one undoable
  `session.apply`. Export uses the current revision bytes, so unsaved edits
  are included.
- Open: `_openLoadedBytes` converts an XDP to its PDF (no origin path, so
  Save never writes a PDF over the .xdp; the title becomes `.pdf`). The
  progressive-open path is skipped for `.xdp`. The Open dialog offers XDP
  except on macOS/iOS, which filter by UTI and XDP has none registered
  there.
- Drops: `.xdp` opens in a tab; `.fdf`/`.xfdf` import into the active
  editable document.
- Not done: OS file associations (Info.plist / Android intent filters /
  Windows registration) for .fdf/.xfdf/.xdp; rendering dynamic XFA; FDF
  /EmbeddedFDFs, /JavaScript and page templates; XFDF `<appearance>`
  (Acrobat's base64 AP blob) is ignored in favour of regenerating.

Tests: `packages/pdf_document/test/form_data_exchange_test.dart` (round
trips, hand-written Acrobat-style FDF without xref and XFDF comment sets,
re-import dedup, XDP hybrid/dynamic/single-stream, embedded XFDF) and
`app/test/form_data_exchange_menu_test.dart`.
