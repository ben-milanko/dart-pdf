# Render-worker seam: measuring (and rejecting) the command-graph transfer half of #309

Issue [#309](https://github.com/ben-milanko/dart-pdf/issues/309) ("stop paying
for copies at the pool/isolate seam") had two halves:

1. **Shared source bytes** across the pool workers - a safe memory win. Landed
   in #333 (see [2026-07-17-pool-shared-bytes.md](2026-07-17-pool-shared-bytes.md)).
2. **Transfer command graphs** by `SendPort`/`Isolate.exit` on native instead
   of the `serializeCommands`/`deserializeCommands` codec round-trip - flagged
   in the issue itself as *speculative* ("not pure win"). This session is that
   half's follow-up.

The remaining work was to actually **measure** the transfer half (the issue's
own "Measure" section) and decide. The measurement says: **don't do it.**

## The current native seam

`_IsolateRenderWorker` (`render_worker_isolate.dart`) records a page in a
background isolate, then:

- the worker calls `serializeCommands` -> one compact `Uint8List` (path
  coordinates packed at float32; image XObjects inline-resolved and their
  pixels decoded off-thread into the same buffer),
- wraps it in `TransferableTypedData.fromList([buffer])` and `port.send`s it -
  a **zero-copy** transfer of the byte buffer,
- the main isolate `materialize()`s it (zero-copy) and calls
  `deserializeCommands` to rebuild the `List<PdfRenderCommand>` it replays.

So of the whole round-trip, only `deserializeCommands` runs on the UI thread;
serialize is off-thread and the buffer crosses without a copy.

The codec is *required* on web (a Web Worker's `postMessage` only accepts
structured-cloneable data, not live Dart objects). #309 asked whether native
should instead hand the `List<PdfRenderCommand>` straight over the port -
"native transfer, web codec" as two adapters behind a real transport seam.

## Measurement

`packages/pdf_graphics/tool/bench_render_seam.dart` (re-runnable:
`cd packages/pdf_graphics && fvm dart run tool/bench_render_seam.dart`) builds a
synthetic image-free page - the dense fills/strokes shape #309 targets ("a
dense CAD page (~100k commands)") - and compares, over real isolates:

- the codec's `serialize` (worker) and `deserialize` (UI) legs, versus
- a real `port.send(commands)` round-trip of the raw object graph (which the VM
  services with a general deep copy of the graph, borne on the *receiving*
  isolate).

Representative run (Dart VM, `flutter 3.44.4`; absolute numbers vary by machine,
the ratio does not):

| workload            | codec deserialize (UI) | raw object graph, one crossing |
| ------------------- | ---------------------- | ------------------------------ |
| 10 000 commands     | ~8 ms                  | ~22 ms                         |
| 100 000 commands    | ~112 ms                | ~422 ms                        |

The raw object-graph transfer is **~2.6x–3.8x slower**, scales worse with
command count, and lands its whole cost on the UI isolate - the exact thread
the offload exists to protect. The VM's general graph copy (every `PdfPath`,
`PdfPathSegment`, `PdfColor`, nested `List`, …) is simply far more expensive
than walking a flat, cache-friendly byte buffer, and the codec's compact buffer
already crosses the isolate boundary zero-copy via `TransferableTypedData`.

## Why `Isolate.exit` doesn't rescue it

`Isolate.exit(port, message)` *is* a zero-copy heap hand-off - but it kills the
sending isolate. Our native backend is a **long-lived pooled worker**: it opens
the document once, keeps decoded-image / strip-command caches warm, and absorbs
edits in place via `updateRevision` (#308). Exiting per page would re-spawn the
isolate and re-open + re-warm the document for every single page - catastrophic,
and incompatible with the whole pooled/revision-aware design. So `Isolate.exit`
is not an option here either.

## Decision

The transfer half is **not implemented**. The codec + zero-copy
`TransferableTypedData` is already close to optimal for the native seam, and the
speculative alternative is a measured regression on its own target workload. The
issue author's caveat ("the transfer half is not pure win") is confirmed with
numbers.

What did land this session:

- `tool/bench_render_seam.dart` - the durable, re-runnable benchmark, so the
  next person who wonders "why not just `port.send` the commands on native?"
  gets the answer by running it instead of re-litigating it.
- A pointer comment at the serialize/deserialize seam in
  `render_worker_isolate.dart` referencing this note.

The safe half (shared bytes, #333) delivered #309's real win; the speculative
half is now closed out with evidence rather than left as an open TODO.
