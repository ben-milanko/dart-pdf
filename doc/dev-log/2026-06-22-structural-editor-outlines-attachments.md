# Structural editor: outlines, attachments, headers/footers, page labels

## Structural authoring batch: outlines, attachments, headers/footers, page labels

Four mostly-independent "complete editor" structural features, all in
`pdf_document` (read models exported standalone; write APIs as
`part of 'editor.dart'` extensions), plus one `dart_pdf_editor` wiring.
A combined-feature PDF was generated and opened in **pdf.js 6.0** (real
reader): it reported the nested outline (with bold/colour flags), the
embedded attachment bytes, page labels `[i, ii, 1, 2, 3, 4]`, and the
stamped header/footer text — all correct.

**1. Outlines / bookmarks** (`outline.dart` read, `outline_editor.dart`
write). `PdfOutline.of(doc)` resolves the `/Outlines` tree into nested
`PdfOutlineItem`s (title, resolved `PdfDestination`, open/bold/italic,
RGB colour). `PdfExplicitDestination` is the write-side value (`.fit`/
`.fitH`/`.fitV`/`.xyz`/`.fitR`) turned into a `[pageRef /Fit ...]` array;
the page reference comes from `cos.referenceTo(page.dict)` (page dicts are
identity-cached so this is sound). `PdfOutlineEditing` exposes
`addOutlineItem` (returns the item's `CosReference`, the handle for the
other mutators), `removeOutlineItem`, `moveOutlineItem`, `setOutlineTitle/
Destination/Style`. Items are linked by First/Last/Next/Prev/Parent; the
robust primitive is `_relinkOutlineChildren(parentRef, orderedRefs)`,
which rebuilds all four sibling links + Parent from an ordered list — every
insert/move/remove reduces to "compute the new ordered child list, relink".
`/Count` is recomputed wholesale after each mutation (`_recountOutline`):
`visible(node)` = Σ over children of `1 + (childOpen ? visible(child) : 0)`,
written as `±visible` per the node's open state (root always positive).
GOTCHA: open state of a *childless* node can't live in `/Count` (spec omits
it with no descendants), so a session-time `_outlineOpenOverride` map (field
on `PdfEditor`, keyed by object number) remembers `open:` until the node
gains children; reopened docs fall back to the `/Count` sign. Move guards
against re-parenting under self/descendant (`_outlineIsDescendant`, walks
the Parent chain). Tests (`outline_test.dart`) assert the full linkage
invariant via a recursive `checkLinkage` that re-derives `/Count`.

**2. Attachments / embedded files** (`attachment.dart` read,
`attachment_editor.dart` write). `PdfAttachments.of(doc)` enumerates both
the `/Names → /EmbeddedFiles` name tree (lenient walk, /Kids + /Names) and
`/FileAttachment` annotations; `PdfEmbeddedFile` lazily decodes bytes via
`cos.decodeStreamData` and exposes name/desc/mime/size/dates/MD5 checksum.
`addEmbeddedFile` builds a proper `/EmbeddedFile` stream (`/Params` /Size +
/CheckSum = MD5 of the *plaintext, uncompressed* bytes per §7.11.3,
optional FlateDecode via `package:archive` `ZLibEncoder`) wrapped in a
`/Filespec` (/F+/UF+/EF), then rebuilds `/EmbeddedFiles` as a single flat,
**key-sorted** name-tree node (name trees must be sorted). `removeEmbeddedFile`
re-writes the tree (clears `/EmbeddedFiles` when empty).
`addFileAttachmentAnnotation` makes a `/FileAttachment` annot with its own
filespec + icon. GOTCHA: when reusing an indirect tree node via
`replaceObject`, also `cos.adoptObject(ref, node)` or a later read in the
same session sees the stale node. Date parsing honours the `Z`/`±HH'mm'`
zone (the writer emits UTC `D:...Z`; the reader returns the same instant —
without this a round-trip compared `12:30:15Z` against a local
`12:30:15`). Encrypt-on-write re-encrypts the new plaintext stream
automatically (updater `_encryptedCopy`).

**3. Headers / footers** (`header_footer.dart`). `PdfHeaderFooter`
(left/center/right templates, size/colour/bold/margin) + `stampHeaderFooter
({header, footer, fromPage, toPage, date})` builds on `stampPage`. Slots
are measured with `measureHelvetica` and placed against `cropBox` (left at
+margin, centre centred, right ending at −margin); header baseline =
`top − margin − size*0.8`, footer = `bottom + margin`. Tokens `{page}`
(1-based), `{pages}`, `{label}` (logical page label when `/PageLabels`
present, else the number), `{date}` (`YYYY-MM-DD`).

**4. Page labels** (`page_labels.dart` read+compute, `page_labels_editor.dart`
write, viewer wiring). `PdfPageLabelStyle` {decimal, romanUpper/Lower,
alphaUpper/Lower, none}; `PdfPageLabelRange` formats labels
(`labelAt(offset)` = prefix + styled `start+offset`; alpha is A..Z, AA..ZZ,
AAA.. per §12.4.2 — NOT spreadsheet base-26). `PdfPageLabels.of(doc)` walks
the `/PageLabels` number tree (/Nums + /Kids), sorts ranges, and
`labelFor(index)` finds the covering range (physical-number fallback).
`PdfPageLabelEditing`: `setPageLabel`/`removePageLabelRange`/`clearPageLabels`/
`setPageLabels` write a flat key-sorted `/Nums`. Viewer: `_PdfViewerState`
caches `PdfPageLabels` (reset in `_loadPages` on document swap);
`PdfViewerController` gains `hasPageLabels`/`pageLabel(i)`/`pageForLabel(s)`;
`PdfPageNumberField` shows the logical label (relaxing the digits-only
formatter and showing `(physical / count)` beside it) and accepts a typed
label or a physical number. Tests: `page_labels_test.dart` (pure-Dart
formatting + round-trip), `page_labels_field_test.dart` (the field shows
"i", a plain doc stays numeric, `pageForLabel` resolves both forms).
