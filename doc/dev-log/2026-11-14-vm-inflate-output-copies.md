# 2026-11-14 - VM inflate: join zlib's output once

The lead left open by `2026-11-14-text-path-and-codec-hot-spots.md`: on the VM
every FlateDecode stream went through archive's `ZLibDecoder.decodeBytes`,
which copies each piece of native zlib output into an `OutputMemoryStream`
that starts at 32 KB and doubles (copying again each time), then copies the
result once more if that buffer ends up under half full.

That note said going around it needs `dart:io`. It doesn't:
`ZLibDecoder.decodeStream(input, output)` runs the same native inflate under
the same error rules (`guardDecode`, the unchecked trailer) and writes to an
`OutputStream` of the caller's choosing. `inflateZlib` (zlib_inflate_io.dart)
now passes `InflatedChunks`, which keeps the pieces as they arrive and joins
them once at their exact size. A stream that inflates to one piece is returned
uncopied. The strict path (compactor, `verify: true`) and the web decoder are
unchanged.

## What it relies on

dart:io allocates a fresh list per piece of zlib output and `Sink.add` lets
the receiver keep what it is given; archive's `ZLibOutputSink` passes that
list straight to `OutputStream.writeBytes`. `InflatedChunks.writeBytes` only
holds a piece that is a whole `Uint8List` of its own - a partial write, a view
into a larger buffer or a plain list is copied - so if archive or dart:io ever
changes what it hands over, the cost is speed, not correctness. The class is
public (in an unexported `src/` file) only so the tests can drive those
branches, which the native decoder never takes.

## Verified

- sha256 over the decoded bytes (or the failure) of every stream object in
  `test_corpora/{dartpdf,pdfjs,ghent}`: identical before and after (3,494
  streams, 2,626 Flate, 445 MB decoded, 147 failures failing the same way).
- 25 edge inputs (empty, too short, missing/partial/wrong Adler-32, truncated
  - the decoded prefix is kept -, damaged early and mid-stream, trailing
  bytes, raw deflate, two streams, a view into a larger buffer): same result
  or same exception.

## Measured

Inflate alone, every Flate stream in a file, VM JIT, min of many runs:

| file | before | after |
|---|---|---|
| diagram-dense-3p | ~19.8 ms | ~14.0 ms |
| scan-book-12p | ~62.8 ms | ~46 ms |
| image-scan-4p | ~13.7 ms | ~9.1 ms |
| plan-set-16p | ~27.8 ms | ~23.2 ms |
| styled-booklet-24p | ~3.0 ms | ~2.6 ms |
| text-report-40p | ~0.73 ms | ~0.69 ms |

End to end, `tool/perf.sh diff HEAD dartpdf-corpus --iterations 3`: verdict
OK; interpretMs 0.959x, firstPageMs 0.969x, extractMs 1.006x, openMs 1.018x
(sub-millisecond rows), saveMs 1.005x. The files with large streams moved
most (plan-set interpret 131.6 -> 115.8 ms, diagram-dense 84.2 -> 74.0 ms).

## The peakRssBytes trap in `perf.sh diff`

That run also reported peakRssBytes 1.054x - about +35 MB on **every** file,
including a one-page 0.4 ms one. It is not this change: the same checkout with
the change reverted measures the same ~545 MB, and the cached baseline
worktree measures ~510 MB with identical library code. The child's peak RSS is
dominated by the Dart front end compiling the sweep script, and the two
checkouts differ in how they were resolved (`flutter pub get` here, `dart pub
get` in the worktree perf_diff.sh creates). So a uniform RSS delta across all
files in a `perf.sh diff` says the checkouts differ, not the code; compare
within one checkout before believing it. (The earlier diff in this session
showed 1.002x because its "current" tree had been resolved the same way.)
