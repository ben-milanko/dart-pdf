# pdf_graphics

[![pub package](https://img.shields.io/pub/v/pdf_graphics.svg)](https://pub.dev/packages/pdf_graphics)
[![pub points](https://img.shields.io/pub/points/pdf_graphics)](https://pub.dev/packages/pdf_graphics/score)
[![CI](https://github.com/ben-milanko/dart-pdf/actions/workflows/ci.yml/badge.svg)](https://github.com/ben-milanko/dart-pdf/actions/workflows/ci.yml)
[![codecov](https://codecov.io/gh/ben-milanko/dart-pdf/branch/main/graph/badge.svg?flag=pdf_graphics)](https://codecov.io/gh/ben-milanko/dart-pdf)
[![License: Apache-2.0](https://img.shields.io/github/license/ben-milanko/dart-pdf)](https://github.com/ben-milanko/dart-pdf/blob/main/LICENSE)

The rendering core of the
[dart-pdf suite](https://github.com/ben-milanko/dart-pdf): a
content-stream interpreter, a device interface, a font engine, and text
extraction.

Pure Dart with no `dart:ui` or Flutter dependency, so it runs on the VM,
in CLIs and servers, and on the web. The Flutter canvas device lives in
[`dart_pdf_editor`](https://pub.dev/packages/dart_pdf_editor); implement
`PdfDevice` to render anywhere else (SVG, raster, print pipelines).

## Features

- Interpreter covering the full content operator set: paths, clipping,
  text, images and inline images, XObjects, transparency groups, soft
  masks, blend modes, optional content, and type 0–4 functions.
- Fonts: Type 1, TrueType, CFF, Type 0/CID, and Type 3, embedded or with
  standard-14 metrics; encodings, CMaps, and glyph outlines.
- Color: ICC profiles (validated against littleCMS), Separation/DeviceN
  with tint transforms, Indexed, Lab, and calibrated spaces.
- Shadings and patterns: types 1–7 including the mesh families, with
  `/Extend` semantics; tiling and shading patterns.
- Text extraction: run geometry for selection and search, reading in
  document order, rotation-aware page geometry.
- Annotation appearance-stream rendering for view-accurate annotation
  and form-field display.

Conformance is pinned by two checked-in corpora: the Ghent PDF Output
Suite V5.0 and 171 edge-case files from the PDF.js test corpus.

## Usage

```dart
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';

final doc = PdfDocument.open(bytes);

// Extract text with geometry
final text = PdfPageText.extract(doc, 0);
print(text.text);

// Render by implementing PdfDevice and feeding it to PdfInterpreter
```

## The suite

| Package | Layer |
| --- | --- |
| [`pdf_cos`](https://pub.dev/packages/pdf_cos) | file syntax, objects, filters, crypto |
| [`pdf_document`](https://pub.dev/packages/pdf_document) | pages, annotations, forms, signatures, editing |
| `pdf_graphics` | content interpreter, fonts, text extraction |
| [`dart_pdf_editor`](https://pub.dev/packages/dart_pdf_editor) | Flutter viewer + editing UI |
