# pdf_test_fixtures

[![pub package](https://img.shields.io/pub/v/pdf_test_fixtures.svg)](https://pub.dev/packages/pdf_test_fixtures)
[![pub points](https://img.shields.io/pub/points/pdf_test_fixtures)](https://pub.dev/packages/pdf_test_fixtures/score)
[![CI](https://github.com/ben-milanko/dart-pdf/actions/workflows/ci.yml/badge.svg)](https://github.com/ben-milanko/dart-pdf/actions/workflows/ci.yml)
[![License: Apache-2.0](https://img.shields.io/github/license/ben-milanko/dart-pdf)](https://github.com/ben-milanko/dart-pdf/blob/main/LICENSE)

Programmatic builders for structurally-correct PDF test files, shared by
the [dart-pdf suite](https://github.com/ben-milanko/dart-pdf)'s test
suites and useful for testing any PDF tooling.

Because fixtures are built in code, byte offsets, xref entries, and
stream lengths are always correct, with no hand-edited files to drift.

## Builders

- Classic xref-table and xref-stream documents.
- Multi-page and varied-height documents (defeats uniform-extent
  assumptions in viewers).
- Annotated documents (links, GoTo actions, markup annotations).
- AcroForm documents (text, checkbox, radio, choice fields).
- Encrypted documents.
- A test signer identity (key + certificate) for signature tests.

```dart
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';

final bytes = buildMultiPagePdf(5);
```
