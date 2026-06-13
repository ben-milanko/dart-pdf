# pdf_document

[![pub package](https://img.shields.io/pub/v/pdf_document.svg)](https://pub.dev/packages/pdf_document)
[![pub points](https://img.shields.io/pub/points/pdf_document)](https://pub.dev/packages/pdf_document/score)
[![CI](https://github.com/ben-milanko/dart-pdf/actions/workflows/ci.yml/badge.svg)](https://github.com/ben-milanko/dart-pdf/actions/workflows/ci.yml)
[![codecov](https://codecov.io/gh/ben-milanko/dart-pdf/branch/main/graph/badge.svg?flag=pdf_document)](https://codecov.io/gh/ben-milanko/dart-pdf)
[![License: Apache-2.0](https://img.shields.io/github/license/ben-milanko/dart-pdf)](https://github.com/ben-milanko/dart-pdf/blob/main/LICENSE)

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

## The suite

| Package | Layer |
| --- | --- |
| [`pdf_cos`](https://pub.dev/packages/pdf_cos) | file syntax, objects, filters, crypto |
| `pdf_document` | pages, annotations, forms, signatures, editing |
| [`pdf_graphics`](https://pub.dev/packages/pdf_graphics) | content interpreter, fonts, text extraction |
| [`dart_pdf_editor`](https://pub.dev/packages/dart_pdf_editor) | Flutter viewer + editing UI |
