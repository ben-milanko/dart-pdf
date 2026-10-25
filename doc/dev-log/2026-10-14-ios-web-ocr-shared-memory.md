# Web OCR on iOS: onnxruntime-web's 4 GB shared memory

Browser OCR failed on every iOS browser (all WebKit) with:

    OCR failed: Error: no available backend found. ERR: [webgpu] RangeError:
    Out of memory, [wasm] Error: previous call to 'initWasm()' failed.

**Cause.** Both onnxruntime-web 1.30 builds (`ort-wasm-simd-threaded` and the
WebGPU `.asyncify` one) create their heap as
`new WebAssembly.Memory({initial: 256, maximum: 65536, shared: true})` -
unconditionally, whatever `env.wasm.numThreads` says - and the wasm imports a
memory declared `max 65536` (4 GB). WebKit reserves a shared memory's whole
maximum up front, and iOS won't hand a web content process 4 GB of address
space, so the constructor throws `RangeError: Out of memory`. ORT caches the
failed `initWasm()` per module, which is why the `wasm` fallback in the same
build then fails with "previous call ... failed". `numThreads = 1` does not
help: the memory is shared either way.

**Fix (`app/web/index.html`).**

- `installSharedMemoryFallback()` wraps `WebAssembly.Memory` the first time
  OCR starts. A constructor call that succeeds is untouched; a *shared*
  request that throws `RangeError` is retried with the maximum halved
  (32768, 16384, ... pages), down to a 256 MB floor. A smaller maximum is a
  valid import for the module (an import may promise less than the declared
  limit), so ORT runs as before, just with a capped heap - plenty for the
  PP-OCRv5 mobile models. No user-agent sniffing: only a call that would
  otherwise have thrown changes.
- If session creation on the WebGPU build fails, the bridge now retries on
  the WASM-only build. They are separate modules, so the WebGPU build's
  cached init failure doesn't carry over.

**Sizing the work to a capped heap.** Loading in 1 GB is not the whole
story: detection runs up to 4000 px on the long side, and that does not fit.
Measured on ORT 1.30 + PP-OCRv5 mobile (headless Chromium, simulated cap):

| heap | detection | recognition (lines x 3200 px) |
|---|---|---|
| 2 GiB | 4000x2848 (11.4 MP) ok | |
| 1 GiB | 2880x2048 (5.9 MP), 2240^2 ok; 4000x2848, 2816^2 (7.9 MP) `bad_alloc` | 6 ok |
| 512 MiB | 1568^2 ok | 1-2 ok, 6 `bad_alloc` |
| 256 MiB | 1120^2 ok | 1 ok |

Detection's working set follows the pixel count, so `detectionResize` /
`PpOcrPipeline` gained an optional `detectionPixelLimit` (pdf_ocr_ondevice;
default null = unchanged). The bridge records the granted maximum and exposes
it as `__dartPdfOcrHeapLimit()` (0 = not capped); `OnDeviceOcr.start` (web)
now loads the bridge first and builds the pipeline through
`browserOcrPipeline` (`app/lib/ocr_web_budget.dart`): uncapped keeps the
defaults, capped gets 5 MP per GiB of detection and one recognition line per
256 MiB (1..6). The trade-off on a capped heap is lower detection resolution
for large drawings - tiny text may be missed where desktop would find it.

**Verification.** No WebKit in the sandbox, so the refusal was simulated in
headless Chromium (cross-origin isolated, local copies of the ORT 1.30 dist)
by wrapping `WebAssembly.Memory` to throw `RangeError('Out of memory')` for any
shared memory with `maximum > 16384`. With that wrapper, the old bridge
reproduces the iOS error exactly ("no available backend found. ERR: [wasm]
RangeError: Out of memory"), and the new one loads both sessions, runs `det`
and `rec`, and reports the 1 GiB cap through `__dartPdfOcrHeapLimit()` (0
without the simulated refusal; a faked WebGPU adapter path also passes). Still worth confirming on a real iPhone after deploying.
