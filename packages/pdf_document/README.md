# pdf_document

[![pub package](https://img.shields.io/pub/v/pdf_document.svg)](https://pub.dev/packages/pdf_document)
[![pub points](https://img.shields.io/pub/points/pdf_document)](https://pub.dev/packages/pdf_document/score)
[![CI](https://github.com/ben-milanko/dart-pdf/actions/workflows/ci.yml/badge.svg)](https://github.com/ben-milanko/dart-pdf/actions/workflows/ci.yml)
[![codecov](https://codecov.io/gh/ben-milanko/dart-pdf/branch/main/graph/badge.svg?flag=pdf_document)](https://codecov.io/gh/ben-milanko/dart-pdf)
[![License: Apache-2.0](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](https://github.com/ben-milanko/dart-pdf/blob/main/LICENSE)

Document-level PDF semantics for the
[dart-pdf suite](https://github.com/ben-milanko/dart-pdf): pages,
annotations, forms, signatures, and a full incremental-save editor.

Pure Dart with no `dart:io` or Flutter dependency, so it runs on the VM,
in CLIs and servers, and on the web.

## Features

- Reading: `PdfDocument.open` (with password support), the page tree
  with inherited attributes, metadata, outlines, and parsed annotations.
- Editing: `PdfEditor` saves incrementally, so every revision is a byte
  prefix of the next.
  - Annotations: highlights, ink (with stylus pressure and spline
    smoothing), shapes, free text, notes, stamps, and signatures, all
    with generated appearance streams; move/resize/rotate/restyle, a
    slicing eraser, clipboard snapshots, and flattening.
  - Pages: reorder, remove, append from other documents, extract to a
    new file.
  - Content: stamp text/shapes/images, enumerate and delete page
    elements, replace text.
- OCR text-layer injection: `PdfEditor.injectTextLayer` writes recognized
  `PdfOcrSpan`s as invisible selectable/searchable text, and
  `dart_pdf_editor` adds `applyOcr` to run a pluggable OCR engine first.
- Forms: the AcroForm field model, filling with regenerated appearances
  (text, checkbox, radio, choice, auto-size, quadding), and field
  administration (add, rename, remove, change type, button images,
  flatten).
- Signatures: read and validate (`PdfSignature.validate`, optional
  trust-store chain validation) and sign (`PdfEditor.saveSigned`,
  `adbe.pkcs7.detached`).
- Sync: `/NM`-keyed annotation snapshots, JSON serialization,
  `pdfDiffAnnotations`, and upsert/remove-by-name replay, built for
  collaborative annotation stores.
- Images: embed JPEG (passthrough) and baseline PNG (all bit depths and
  color types, transparency, interlacing) with alpha soft masks.

## Usage

```dart
import 'package:pdf_document/pdf_document.dart';

final doc = PdfDocument.open(bytes);
print('${doc.pageCount} pages');

final editor = PdfEditor(doc);
editor.addHighlight(0, [const PdfRect(72, 700, 300, 716)]);
editor.addFreeText(0, const PdfRect(72, 600, 280, 660), 'Reviewed.');
final saved = editor.save(); // incremental update
```

## Merge PDFs

```dart
import 'package:pdf_document/pdf_document.dart';

final mergedBytes = PdfMerger.merge([coverBytes, reportBytes, appendixBytes]);
final merged = PdfDocument.open(mergedBytes);
print('${merged.pageCount} pages');
```

For protected inputs, pass a matching `passwords: ['', 'report-password', '']`
list. The first input supplies the output's encryption, metadata, and viewing
settings, including `/PageMode`. Imported streams are decrypted and re-encrypted
with the first input's settings on save. An unprotected first input produces
unprotected output; a protected first input keeps its password.

Forms remain fillable. Colliding root field names gain `_2`, `_3`, … suffixes
(for example, `client.name` becomes `client_2.name`); form font resources and
default appearances are remapped together. Imported outlines retain their
hierarchy, and named links resolve to their source's pages even when another
input uses the same destination name. Colliding destination names are suffixed
in the merged name tree.

To insert into an existing edit session, use
`editor.appendPagesFrom(source, at: pageIndex)` or Flutter's
`editing.insertPagesFromBytes(bytes, at: pageIndex)`. A subset import keeps only
widgets on the selected pages; destinations on omitted pages become inactive.
Document-level attachments, XFA, and JavaScript from later inputs are not
merged, and their signatures do not certify the output.

## The suite

| Package | Layer |
| --- | --- |
| [`pdf_cos`](https://pub.dev/packages/pdf_cos) | file syntax, objects, filters, crypto |
| `pdf_document` | pages, annotations, forms, signatures, editing |
| [`pdf_graphics`](https://pub.dev/packages/pdf_graphics) | content interpreter, fonts, text extraction |
| [`dart_pdf_editor`](https://pub.dev/packages/dart_pdf_editor) | Flutter viewer + editing UI |
| [`pdf_ocr_ondevice`](https://pub.dev/packages/pdf_ocr_ondevice) | optional native offline OCR engine |
| [`pdf_ocr_vlm`](https://pub.dev/packages/pdf_ocr_vlm) | optional HTTP/VLM OCR engine |
