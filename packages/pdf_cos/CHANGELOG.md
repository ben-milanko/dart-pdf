# Changelog

## 3.7.0

- Lockstep minor release to align the dart-pdf package suite at 3.7.0. No
  public `pdf_cos` API changes since 3.6.0.

## 3.6.0

- Lockstep minor release to align the dart-pdf package suite at 3.6.0. No
  public `pdf_cos` API changes since 3.5.1.

## 3.5.1

- Decode JBIG2 refined text symbols, including refinement deltas, offsets, and
  shared arithmetic contexts, so scanned MRC text layers render correctly.

## 3.5.0

- Add `PdfSourceLoadOptions.completeFirstPaintPageTree`. Progressive preview
  callers can stop the initial page-tree walk after `firstPaintPages`, avoiding
  one range request per leaf before page one can paint; the default remains the
  correctness-first complete walk for existing callers.
- Reduce allocation and cache pressure in byte sources, the lexer, and content
  parsing while retaining the parser's lenient handling of malformed PDFs.

## 3.4.0

- Lockstep minor release to align the dart-pdf package suite at 3.4.0. No
  public `pdf_cos` API changes since 3.3.1.

## 3.3.1

- Lockstep patch release to align the dart-pdf package suite at 3.3.1. No
  public `pdf_cos` API changes since 3.3.0.

## 3.3.0

- Lockstep minor release to align the dart-pdf package suite at 3.3.0. No
  public `pdf_cos` API changes since 3.2.0.

## 3.2.0

- Lockstep minor release to align the dart-pdf package suite at 3.2.0. No
  public `pdf_cos` API changes since 3.1.1.

## 3.1.1

- Lockstep patch release to align the dart-pdf package suite at 3.1.1. No
  public `pdf_cos` API changes since 3.1.0.

## 3.1.0

- Lossless structural compaction: new `CosCompactor`/`CosCompactionResult`
  rewrite a document's reachable object graph, packing non-stream objects
  into compressed object streams behind a PDF 1.5 xref stream and
  re-deflating streams stored uncompressed (kept only when smaller).
  `CosDocumentBuilder` gains an `objectStreams:` mode (W [1 4 2]). The
  user-facing entry point is `PdfEditor.compress()` in `pdf_document` (#368).
- JPX (JPEG 2000) resolution-level skip: decode at a reduced `cp_reduce`
  level when an image is displayed far below its native size, instead of
  decoding full resolution and downscaling (#525).
- Cache decoded JBIG2 globals dictionaries across images on the same page -
  scanned books with shared `/JBIG2Globals` decode once, not per image (#532).
- Int-key the loaded-object cache so warm resolves allocate nothing (#522),
  and drop the double copy of every inflated stream (#533).

## 3.0.0

Lockstep major release: a breaking change in `dart_pdf_editor` moves the whole
suite to 3.0.0. `pdf_cos`'s own public API is unchanged.

- Cache decoded stream bytes on `CosDocument` so a stream inflated once (xref
  reconstruction, content parsing, image extraction) is not re-decoded on the
  next access (#392).
- Perf micro-batch: chunked message-digest hashing, an in-place JPX inverse
  DWT, and predictor/lexer/regex fast-path fixes (#407).

## 2.1.0

- Append incremental saves to the existing bytes instead of rebuilding the
  whole file: `CosUpdater.saveTail()` returns only the new tail (the appended
  objects, xref, and trailer), so an incremental revision costs the size of
  the change rather than the size of the document. Save cost no longer scales
  with the base file - a guard test pins that a 2.78x larger base does not
  make a same-sized edit 2.78x more expensive (#413).
- Memoise the per-object decryption key so a page's streams and strings derive
  it once per object rather than once per access, cutting repeated MD5/AES key
  derivation on encrypted documents (#400).

- Speed up CCITT G3/G4 decoding by ~4x on dense scanned pages: a monotonic
  cursor for the 2-D reference-row scan (was O(transitions^2) per row),
  peek-once prefix tables for run and mode codes, byte-run span fills, and
  a byte-at-a-time bit reader. The JBIG2 MMR path, which reuses the same
  decoder, gains a byte-at-a-time bitmap unpack. Output is byte-identical
  on well-formed, malformed, and truncated input, locked by golden digests
  captured from the previous implementation (#398).

## 2.0.0

- Major version bump for the 2.0.0 package suite. A breaking API change in
  `dart_pdf_editor` moves every package to 2.0.0 in lockstep; the COS object
  model, syntax, and (de)serialization API is source-compatible with 1.4.7.
- Add an asynchronous byte-source API (`PdfByteSource`) for progressive PDF
  loading: the reader pulls ranged slices on demand instead of requiring the
  whole file up front, so remote and large local files can paint their first
  page before the full download or read completes (#328, #359).
- Decode PDF text strings as PDFDocEncoding rather than Latin-1, so document
  metadata and outline titles that use PDFDocEncoding-specific code points
  round-trip correctly (#347).
- Add the crypto primitives behind one-tap and keyless signing identities:
  P-256 `EcPrivateKey.generate`, deterministic RFC 6979 `ecdsaSign`, the X.509
  v3 builders `buildSelfSignedCertificate` / `buildCaCertificate` /
  `issueCertificate`, and `ecSubjectPublicKeyInfo` / `pemEncode` for
  Sigstore/Fulcio (#322, #337, #355).
- Internal refactors with no public API change: extract `CosXrefReader` from
  `CosDocument`, move the encryption object-graph walk behind the security
  handler, share file-tail framing between the builder and updater, and dedupe
  ObjStm header parsing between recovery and the stream decoder.

## 1.4.7

- Version bump to keep the dart-pdf package suite aligned at 1.4.7. No COS API
  changes since 1.4.6.

## 1.4.6

- Version bump to keep the dart-pdf package suite aligned at 1.4.6. No COS API
  changes since 1.4.5.

## 1.4.5

- Version bump to keep the dart-pdf package suite aligned at 1.4.5. No COS API
  changes since 1.4.4.

## 1.4.4

- Version bump to keep the dart-pdf package suite aligned at 1.4.4. No COS API
  changes since 1.4.3.

## 1.4.3

- Version bump to keep the dart-pdf package suite aligned at 1.4.3. No COS API
  changes since 1.4.2.

## 1.4.2

- Version bump to keep the dart-pdf package suite aligned at 1.4.2. No COS API
  changes since 1.4.1.

## 1.4.1

- Speed up dense content parsing with byte-level real-number parsing, operator
  interning, and streaming content-token handling.
- Keep the low-level parser and writer compatible with the rendering and
  editing improvements in the 1.4.1 package suite.

## 1.4.0

- Version bump to keep the dart-pdf package suite aligned at 1.4.0. Low-level
  parser, writer, filter, and crypto maintenance supports the higher-level
  editor and document features in this release.

## 1.3.2

- Version bump to keep the dart-pdf package suite aligned at 1.3.2. No COS
  API changes since 1.3.1.

## 1.3.1

- Add `ContentStreamSerializer` for writing parsed content-stream operations
  back to PDF syntax, including inline-image (`BI`/`ID`/`EI`) operations.

## 1.2.3

- Version bump to keep the dart-pdf package suite aligned at 1.2.3. No COS
  API changes since 1.2.2.

## 1.2.2

- Version bump to keep the dart-pdf package suite aligned at 1.2.2. No COS
  API changes since 1.2.1.

## 1.2.1

- Add a package example for pub.dev scoring.

## 1.2.0

- Version bump to keep the dart-pdf package suite aligned at 1.2.0. No
  low-level COS API changes since 1.1.0.

## 1.1.0

- Performance: a faster content-stream tokenizer. This is the heart of the
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
