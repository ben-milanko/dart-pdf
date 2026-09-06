# Changelog

## 4.3.0

- Align dependency constraints with the dart-pdf 4.3.0 package suite.

## 4.2.0

- Lockstep minor release aligned with `dart_pdf_editor` 4.2.0. No public VLM
  OCR API changes since 4.1.0.

## 4.1.0

- Lockstep minor release aligned with `dart_pdf_editor` 4.1.0. No public VLM
  OCR API changes since 4.0.0.

## 4.0.0

- Lockstep major release to align with `dart_pdf_editor` 4.0.0. No public VLM
  OCR API changes since 3.8.0.

## 3.8.0

- Lockstep minor release to align with `dart_pdf_editor` 3.8.0. No public VLM
  OCR API changes since 3.7.0.

## 3.7.0

- Lockstep minor release to align with `dart_pdf_editor` 3.7.0. No public VLM
  OCR API changes since 3.6.0.

## 3.6.0

- Lockstep minor release to align with `dart_pdf_editor` 3.6.0. No public VLM
  OCR API changes since 3.5.1.

## 3.5.1

- Lockstep patch release to align with `dart_pdf_editor` 3.5.1. No public VLM
  OCR API changes since 3.5.0.

## 3.5.0

- Lockstep minor release to align with `dart_pdf_editor` 3.5.0. No public VLM
  OCR API changes since 3.4.0.

## 3.4.0

- Lockstep minor release to align with `dart_pdf_editor` 3.4.0. No public VLM
  OCR API changes since 3.3.1.

## 3.3.1

- Lockstep patch release to align with `dart_pdf_editor` 3.3.1. No public VLM
  OCR API changes since 3.3.0.

## 3.3.0

- Lockstep minor release to align with `dart_pdf_editor` 3.3.0. No public VLM
  OCR API changes since 3.2.0.

## 3.2.0

- Lockstep minor release to align with `dart_pdf_editor` 3.2.0. No public VLM
  OCR API changes since 3.1.1.

## 3.1.1

- Lockstep patch release to align with `dart_pdf_editor` 3.1.1. No public VLM
  OCR API changes since 3.1.0.

## 3.1.0

- Lockstep release to align with `dart_pdf_editor` 3.1.0. No public VLM OCR
  API changes since 3.0.0.

## 3.0.0

- Lockstep major release to align with `dart_pdf_editor` 3.0.0. No public VLM
  OCR API changes since 2.1.0.

## 2.1.0

- Version bump to align with `dart_pdf_editor` 2.1.0. No public VLM OCR API
  changes since 2.0.0.

## 2.0.0

- Version bump to align with `dart_pdf_editor` 2.0.0. No public VLM OCR API
  changes since 1.4.7.

## 1.4.7

- Version bump to align with `dart_pdf_editor` 1.4.7. No public VLM OCR API
  changes since 1.4.6.

## 1.4.6

- Version bump to align with `dart_pdf_editor` 1.4.6. No public VLM OCR API
  changes since 1.4.5.

## 1.4.5

- Version bump to align with `dart_pdf_editor` 1.4.5. No public VLM OCR API
  changes since 1.4.4.

## 1.4.4

- Version bump to align with `dart_pdf_editor` 1.4.4. No public VLM OCR API
  changes since 1.4.3.

## 1.4.3

- Version bump to align with `dart_pdf_editor` 1.4.3. No public VLM OCR API
  changes since 1.4.2.

## 1.4.2

- Version bump to align with `dart_pdf_editor` 1.4.2. No public VLM OCR API
  changes since 1.4.1.

## 1.4.1

- Version bump to align with `dart_pdf_editor` 1.4.1. No public VLM OCR API
  changes since 1.4.0.

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
