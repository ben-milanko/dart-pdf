# Changelog

## 0.1.0

- Initial release. `VlmOcrEngine` implements `dart_pdf_editor`'s
  `PdfOcrEngine` by POSTing each page raster to an HTTP OCR service and
  mapping the recognized boxes back into PDF user space.
- `VlmOcrEngine.dotsOcr` preset targets a vLLM server hosting
  `rednote-hilab/dots.ocr` over its OpenAI-compatible chat API, with no
  adapter required.
- A small default JSON contract (`{image, width, height} → {spans: [...]}`)
  plus `requestBody`/`responseParser` hooks for custom or cloud backends.
