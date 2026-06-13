# pdf_cos

[![pub package](https://img.shields.io/pub/v/pdf_cos.svg)](https://pub.dev/packages/pdf_cos)
[![pub points](https://img.shields.io/pub/points/pdf_cos)](https://pub.dev/packages/pdf_cos/score)
[![CI](https://github.com/ben-milanko/dart-pdf/actions/workflows/ci.yml/badge.svg)](https://github.com/ben-milanko/dart-pdf/actions/workflows/ci.yml)
[![codecov](https://codecov.io/gh/ben-milanko/dart-pdf/branch/main/graph/badge.svg?flag=pdf_cos)](https://codecov.io/gh/ben-milanko/dart-pdf)
[![License: Apache-2.0](https://img.shields.io/github/license/ben-milanko/dart-pdf)](https://github.com/ben-milanko/dart-pdf/blob/main/LICENSE)

The COS (Carousel Object System) layer of the
[dart-pdf suite](https://github.com/ben-milanko/dart-pdf): everything a
PDF file is made of, before any notion of pages or rendering.

Pure Dart with no `dart:io` or Flutter dependency, so it runs on the VM,
in CLIs and servers, and on the web.

## Features

- Object model: dictionaries, arrays, names, strings, numbers, streams,
  and indirect references, with lazy object loading through the
  cross-reference machinery.
- Lenient parsing. Real-world PDFs are broken (wrong `/Length`, missing
  `endobj`, junk before the header); the parser tolerates them on input
  and stays strict on output, including full xref recovery by scanning
  for object headers when the chain is broken.
- Filters: Flate, LZW, RunLength, ASCIIHex, ASCII85, CCITT G3/G4, JBIG2
  (embedded profile), JPEG 2000, plus predictors. The image codecs are
  validated against reference implementations (libtiff, jbig2dec,
  OpenJPEG).
- Encryption: RC4, AES-128, and AES-256 decryption, and encrypt-on-write
  for incremental saves.
- Crypto primitives (ASN.1, RSA, ECDSA, CMS, X.509 chain verification)
  used by the document layer for digital signatures.
- Writing: incremental updates that append to the original bytes, and a
  from-scratch document builder.

## Usage

```dart
import 'dart:typed_data';
import 'package:pdf_cos/pdf_cos.dart';

final doc = CosDocument.open(bytes);
final catalog = doc.catalog; // the /Root dictionary
final info = doc.trailer['Info'];
```

## The suite

| Package | Layer |
| --- | --- |
| `pdf_cos` | file syntax, objects, filters, crypto |
| [`pdf_document`](https://pub.dev/packages/pdf_document) | pages, annotations, forms, signatures, editing |
| [`pdf_graphics`](https://pub.dev/packages/pdf_graphics) | content interpreter, fonts, text extraction |
| [`dart_pdf_editor`](https://pub.dev/packages/dart_pdf_editor) | Flutter viewer + editing UI |
