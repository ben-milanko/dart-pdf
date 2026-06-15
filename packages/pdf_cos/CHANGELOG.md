# Changelog

## 1.1.0

- Performance: a faster content-stream tokenizer — the heart of the
  render-speed work that puts dart-pdf ahead of PDFium on the benchmark
  corpus.
- Fix: JPEG 2000 tile-part desynchronization, and indexed Lab color
  palettes now decode correctly.

## 1.0.0

First stable release. Changes since 0.1.0:

- JBIG2: Huffman-coded symbol dictionaries and text regions, generic
  refinement regions, and pattern dictionaries with halftone regions.
- JPEG 2000: reset-probabilities (RESET) code-block style support.
- Inline images: correct data-length detection for DCT-filtered streams.

## 0.1.0

Initial release.

- COS object model: dictionaries, arrays, names, strings, streams, references.
- Lenient tokenizer/parser for real-world PDFs (broken /Length, missing
  `endobj`, junk before the header, broken xref chains with object-scan
  recovery).
- Cross-reference tables and streams; lazy object loading; incremental
  updates.
- Filters: Flate, LZW, RunLength, ASCIIHex, ASCII85, DCT passthrough,
  CCITT G3/G4, JBIG2 (embedded profile), JPEG 2000.
- Encryption: RC4, AES-128, AES-256 decryption and encrypt-on-write.
- Crypto primitives for signing/validation: ASN.1, RSA, ECDSA, CMS,
  X.509 chain verification.
- Content-stream tokenizer and a from-scratch document builder.
