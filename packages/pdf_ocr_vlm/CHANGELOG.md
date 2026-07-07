# Changelog

## 1.4.0

- Version bump to align with `dart_pdf_editor` 1.4.0. No public OCR API
  changes since 1.3.2.

## 1.3.2

- Version bump to align with `dart_pdf_editor` 1.3.2. No API changes since
  1.3.1.

## 1.3.1

- Version bump to align with `dart_pdf_editor` 1.3.1. No API changes since
  1.2.3.

## 1.2.3

- Version bump to align with `dart_pdf_editor` 1.2.3. No API changes since
  1.2.2.

## 1.2.2

- Version bump to align with `dart_pdf_editor` 1.2.2. No API changes since
  1.2.1.

## 1.2.1

- Add a package example and shorten the pubspec description for pub.dev
  scoring.

## 1.2.0

- Version bump to align with `dart_pdf_editor` 1.2.0.

## 0.1.0

- Initial release. `VlmOcrEngine` implements `dart_pdf_editor`'s
  `PdfOcrEngine` by POSTing each page raster to an HTTP OCR service and
  mapping the recognized boxes back into PDF user space.
- `VlmOcrEngine.dotsOcr` preset targets a vLLM server hosting
  `rednote-hilab/dots.ocr` over its OpenAI-compatible chat API, with no
  adapter required.
- A small default JSON contract (`{image, width, height} → {spans: [...]}`)
  plus `requestBody`/`responseParser` hooks for custom or cloud backends.
