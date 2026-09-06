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

## Reduce file size

```dart
final result = PdfCompressor.optimize(PdfDocument.open(bytes)); // lossless
print('${result.bytesSaved} bytes saved '
    '(${(result.savingsFraction * 100).toStringAsFixed(1)}%)');
final reducedBytes = result.bytes;

// Explicitly opt in to reducing image quality for on-screen reading.
final screenCopy = PdfCompressor.optimize(
  PdfDocument.open(bytes),
  options: PdfCompressionPreset.screen.options,
);

// Includes pending edits; leaves the editor's history intact.
final editedCopy = editor.compress(
  options: const PdfCompressionOptions(targetDpi: 150, jpegQuality: 75),
);
```

Lossless defaults remove unreachable objects and unused resources, compress
unfiltered/Flate streams, write object/xref streams, deduplicate identical
images/font programs/ICC profiles, and subset supported TrueType and CFF fonts.
The result is never larger than the input. `steps` reports actual sequential
file-size changes by category; its savings sum to `bytesSaved`. Options enable
or disable each pass independently, and `warnings` explains content preserved
because it could not be optimised safely.

Presets are **Lossless** (no image changes), **Screen** (72 DPI / JPEG 60),
**eBook** (150 DPI / JPEG 75), and **Print** (300 DPI / JPEG 90). Image sizing
uses the largest placement across pages and nested forms, including page
`UserUnit`. Only eligible 8-bit DeviceRGB/DeviceGray DCT/Flate images are
processed. Masks, bitonal/JBIG2 images, ICC/CMYK images, uncertain placements,
and images over 16 million pixels remain intact. Gray images stay gray and use
Flate after downsampling. Fonts with ambiguous mappings, unsupported formats,
or editable AcroForm consumers are retained; TrueType/CFF subsetting keeps
glyph IDs, used outlines, widths, and required composite/subroutine data.

This produces a rewritten copy, removing incremental revision history.
Encrypted and incomplete progressive sources are refused. Signed PDFs require
`allowInvalidateSignatures: true`, because rewriting invalidates signatures.
The source bytes and parsed document are never modified. The API is pure Dart
and web-compatible; dispatch it to an isolate or web worker when responsiveness
matters for large files. Linearization is not included.

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

## Splitting and extracting pages

Create multiple PDFs in one call, with one output per range:

```dart
import 'package:pdf_document/pdf_document.dart';

final parts = PdfSplitter.split(bytes, const [
  PdfPageRange(0, 2), // pages 1–3
  PdfPageRange(6, 6), // page 7
  PdfPageRange(9, 11), // pages 10–12
]); // List<Uint8List>, three independent PDFs in this order

final firstThree = PdfSplitter.splitRange(bytes, 0, 2);
final fromInput = PdfSplitter.splitExpression(bytes, '1-3, 7, 10-12');
```

API indices are **zero-based and inclusive**. Text expressions use **one-based
page numbers**: each comma starts a separate output. Whitespace, overlapping
ranges, repeated ranges, and caller-chosen range order are supported. Empty
items, reversed ranges, and out-of-bounds pages are rejected. `parseRanges`
validates text without generating PDFs:

```dart
final document = PdfDocument.open(bytes, password: 'secret');
final ranges = PdfSplitter.parseRanges('1-3, 7', pageCount: document.pageCount);
final parts = document.extractPageRanges(ranges); // reuse an open document
final selection = document.extractPages([4, 0, 2]); // one PDF in this order
final span = document.extractPageRange(0, 2); // one contiguous selection
```

The raw-bytes methods also accept `password:`. Each batch opens the source once
and validates all ranges before generating outputs. Programmatic invalid ranges
throw `ArgumentError`/`RangeError`; invalid expressions throw `FormatException`.
All paths work on mobile, desktop, web, and the Dart VM with no `dart:io`.

Extraction semantics:

- Page annotations and objects reachable from each selected page are deep-copied.
  Inherited page attributes are materialized, and the source is unchanged.
- Destinations between retained pages are remapped within each output. A target
  page excluded from that output is not copied along with the link.
- The document information dictionary is retained. Document-level state outside
  the page graph—outlines/bookmarks, the AcroForm field list, and named
  destinations—is omitted. Copied widget annotations are not registered through
  an AcroForm in the output.
- Resources shared by selected pages remain shared within one output where
  possible. Separate output PDFs have their own copies and can be edited
  independently.
- Extracting an encrypted source produces **unencrypted PDFs**.

## The suite

| Package | Layer |
| --- | --- |
| [`pdf_cos`](https://pub.dev/packages/pdf_cos) | file syntax, objects, filters, crypto |
| `pdf_document` | pages, annotations, forms, signatures, editing |
| [`pdf_graphics`](https://pub.dev/packages/pdf_graphics) | content interpreter, fonts, text extraction |
| [`dart_pdf_editor`](https://pub.dev/packages/dart_pdf_editor) | Flutter viewer + editing UI |
| [`pdf_ocr_ondevice`](https://pub.dev/packages/pdf_ocr_ondevice) | optional native offline OCR engine |
| [`pdf_ocr_vlm`](https://pub.dev/packages/pdf_ocr_vlm) | optional HTTP/VLM OCR engine |
