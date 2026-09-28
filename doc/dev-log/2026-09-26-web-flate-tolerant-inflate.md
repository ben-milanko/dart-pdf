# Web Flate: tolerant zlib inflate, and a worker killed by one bad stream

**Symptom.** On the web only, a FlateDecode stream with bytes after its
Adler-32 decoded to nothing. The usual shape is an EOL (LF, CR or CRLF) left
inside the stream data before `endstream`. In the checked-in test corpora
that is 23 of 2,624 Flate streams, spread over 8 documents: pdf.js `rotation.pdf` renders blank, and
`devicen`, `font_ascent_descent`, `issue2761`, `issue5138`, `SimFang-variant`,
Ghent GWG090 and V50 lose font programs or content. The private real-world
corpus has none (0 of 10,592 streams). Two worse effects follow from it:

- **Reduce file size wrote the loss into the file.** `CosCompactor` (run by
  the web compression worker) inflated the stream to `[]`, re-deflated that
  (8 bytes, smaller than the original) and replaced the payload.
  `rotation.pdf` compacted in JS came out 1,734 bytes and blank for every
  reader, the VM included.
- **One such stream disabled the render worker.** The browser's
  `DecompressionStream('deflate')` rejects trailing bytes as well. In
  `_inflateBrowserFlateSamples` the `arrayBuffer()` future is created before
  the write is awaited, so when the write threw, that future's rejection went
  unobserved, escaped as an uncaught error, fired `Worker.onerror`, and the
  host's `_fail()` sent every later page of the document to main-thread
  rendering.

**Cause.** archive 4.3.0's web `ZLibDecoder` (`_zlib_decoder_web.dart`) loops
while input remains. After the first zlib stream it parses the trailing EOL
as a second header, fails the check, and `return false` fires before the
first stream's buffer is written, so `decodeBytes` returns `[]`. A missing
Adler-32 throws a RangeError. On the VM, archive's `ZLibDecoder` is dart:io's
zlib, which stops at the end of the stream, so no VM test and no Ghent
baseline could see any of this.

**Fix.**

- `inflateZlib(data, {strict})` in pdf_cos (`filters/zlib_inflate.dart`,
  a conditional export on `dart.library.js_interop`):
  - VM/native (`zlib_inflate_io.dart`): archive's `ZLibDecoder`, the same
    dart:io call as before. `strict` is not consulted.
  - Web (`zlib_inflate_web.dart`): check CMF/FLG (CM 8, CINFO <= 7, FCHECK,
    no FDICT), then run archive's exported `Inflate.stream` over the body. It
    stops after the final block and ignores what follows, as zlib and pdf.js
    do. A header that is not zlib keeps archive's old result (empty); no
    raw-deflate leniency the VM lacks. `strict: true` reads the Adler-32 at
    the byte after the final block and throws a `FormatException` on a bad
    header, truncation, or a missing or wrong checksum.
- Callers: `FlateFilter` (non-strict), `CosCompactor._copyStream` (strict, so
  a damaged stream still takes the "preserve exactly" path) and
  `PngImage.decode` (non-strict).
- Compactor guard: an empty inflate result from a payload longer than 16
  bytes never replaces the payload. Real writers emit 8-11-byte empty
  streams (the corpora have 9- and 10-byte ones), and those still
  recompress, so VM output is unchanged.
- Worker: `output.ignore()` right after creating the `arrayBuffer()` future,
  in `_inflateBrowserFlateSamples` (render_worker_web_entry.dart) and
  `inflateZlibWithBrowser` (browser_jpeg_decode_web.dart). The existing
  catch then falls back to `decodeStreamData`, which is now tolerant, so the
  worker needs no retry logic of its own.
- Speed, web only: `_PdfInflateOutput` is archive's `OutputStream` over its
  own `Uint8List`, with a byte loop for back-references under 64 bytes. On
  dart2js every `setRange` allocates a typed-array view, and deflate matches
  are mostly a few bytes long, so that copy was the hot spot.

**Evidence.**

- Per-stream sweep (VM, every Flate stage input after decryption, native
  zlib vs the web implementation imported directly):
  - Checked-in test corpora (245 documents): native decodes 2,616 of 2,624
    streams.
    The web path now matches it byte for byte on all 2,616, strict or not;
    archive's web decoder differed on 23. Of the 8 fuzzed streams native
    rejects, the web path returns nothing for 4 and a short prefix for 4
    (lenient reading). Strict never accepts a stream native rejects.
  - Private corpus: 10,592 of 10,592 identical, strict too.
- dart2js -O2 under node, records and extracted text: `rotation.pdf` page 0
  goes from 2 commands / 0 characters to 10 / 80, which is the VM's result.
  All 8 affected documents now match the VM's command and text counts.
- Reduce file size in JS: `rotation.pdf` compacts to 2,414 bytes, and the VM
  reads 290/232 bytes of page content from it (base: 1,734 bytes, 0).
- Headless Chrome, driving the real worker bundle (init plus two record
  messages):
  - base: `Worker.onerror` on each page, and 5-byte records.
  - fixed: no onerror, 2,003- and 1,622-byte records.
  - tolerant inflate without `output.ignore()`: correct records, but onerror
    still fires, so both halves are needed.
  - control `text-report-40p`: 61,773 / 59,950 bytes in both builds.
- VM identity: `CosCompactor` output is byte-identical base vs fixed on 293
  compactable documents (test corpora + private corpus, 9,280 streams
  recompressed). Ghent and overprint render tests pass unchanged, and the
  perf counter gate is unchanged.

**Measurements.** Flate kernel: `FlateFilter.decode` over every Flate stream
of a document. Process CPU, median of 5 reps per process, 7 interleaved
rounds, median of rounds. Output bytes are identical in every run.

| build | document | base ms | fixed ms | fixed/base |
|---|---|---:|---:|---:|
| JS -O2 (worker) | plan-set-16p | 164.9 | 56.6 | 0.34 |
| JS -O2 | diagram-dense-3p | 109.3 | 37.3 | 0.34 |
| JS -O2 | text-report-40p | 5.84 | 3.49 | 0.60 |
| JS -O4 | plan-set-16p | 111.1 | 51.6 | 0.46 |
| JS -O4 | diagram-dense-3p | 73.3 | 30.8 | 0.42 |
| JS -O4 | text-report-40p | 4.61 | 4.15 | 0.90 |
| AOT (VM) | plan-set-16p | 13.07 | 13.02 | 1.00 |

Memory, deterministic (JS): bytes kept alive by the buffers behind the
decoded Flate streams, against the bytes they hold.

| suite | base | fixed |
|---|---:|---:|
| dartpdf | 296.6 MB | 286.1 MB |
| pdf.js | 18.2 MB | 4.8 MB |
| Ghent | 196.3 MB | 150.4 MB |

archive's decoder copies into a second buffer that starts at 32 KB, so every
small stream pinned 32 KB and mid-size ones up to twice their size.

**What this does not speed up.** First paint and scrolling in the web worker
barely move. The worker's browser predecoder already inflates `/Contents`
and resource streams of 4 KB or more natively. An earlier real-Chrome A/B of
worker record latency during the investigation moved 0.97-1.18x, within
noise; it was not re-run here. The kernel gain lands on the Dart-side paths:
main-thread and fallback renders, extraction of pages not yet rendered,
small resource and appearance streams, editing, and open.

**Gotchas.**

- Only tests can see this. `zlib_inflate_test.dart` imports the web file
  directly for the VM run, and CI also runs it with `dart test -p node`,
  where `inflateZlib` itself is the web implementation. That covers
  `FlateFilter` and the compactor on the dart2js path.
  `zlib_inflate_corpus_test.dart` (VM only) compares the web path with
  native zlib over the pdf.js and Ghent streams up to 64 KB (about 2 s).
- The web file's non-zlib fallback names `ZLibDecoderWeb` explicitly. On the
  VM, archive's `ZLibDecoder` is native zlib, which throws where the web
  decoder returns empty, so the VM test of the web file would otherwise test
  a different fallback.
- `Future.ignore()` needs `import 'dart:async'`: dart:core re-exports
  `Future` but not its extensions.
- strict and native zlib differ on a missing Adler-32 or a truncated body:
  native returns what it decoded, strict throws. So the compactor keeps such
  a stream as it was on the web and re-deflates the recovered bytes on the
  VM. Neither loses data, and the corpora contain no such stream.
- An earlier version returned a view of the output buffer, which starts at
  4x the payload. Retained memory went from 1.04x to 1.40x of the decoded
  bytes on the dartpdf suite. `takeBytes` now copies to an exact-size buffer
  unless the spare capacity is under 1/16 of the output, so there is still
  one final copy, as in archive's decoder. The kernel gain comes from the
  back-reference loop.

**Files.** `packages/pdf_cos/lib/src/filters/zlib_inflate{,_io,_web}.dart`,
`filters/flate.dart`, `compactor.dart` (`_copyStream`,
`_maxEmptyZlibLength`), `packages/pdf_document/lib/src/png.dart`,
`packages/dart_pdf_editor/lib/src/render_worker_web_entry.dart`
(`_inflateBrowserFlateSamples`), `browser_jpeg_decode_web.dart`
(`inflateZlibWithBrowser`); tests `packages/pdf_cos/test/zlib_inflate_test.dart`
and `zlib_inflate_corpus_test.dart`; CI step "Test pdf_cos zlib inflate
under dart2js".
