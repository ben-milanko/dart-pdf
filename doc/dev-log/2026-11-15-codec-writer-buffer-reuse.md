# 2026-11-15 - The command codec's writers hand their buffer on

The lead left by `2026-11-14-text-path-and-codec-hot-spots.md` was
"`_Writer.takeBytes` copies the whole record once to drop the doubling slack
(~2-3% of a CAD encode)". The copy was the smaller half of it.

## What it was

Every `_Writer` (render_command_codec.dart) started a fresh 64 KB buffer and
doubled it as the record grew. A drawing's page is hundreds of KB to a few MB,
so each page allocated, zeroed and copied 64 + 128 + 256 + ... KB, wrote the
record, copied it out tight - and all of it was garbage a moment later. On the
VM that allocation, not the final copy, was about a third of encoding a CAD
page.

## What it is

A finished writer leaves its buffer for the next one (`_Writer._spare`, one
per isolate, at most 4 MB; `_release`). `takeBytes` still returns a tight copy
- the web transfers that storage and caches hold it - but every record after
the first is written without growing anything.

`PdfStreamingCommandWriter` (what the worker streams a whole page into) had no
"done": `snapshot()` serves partials and the final buffer alike. It gains
`finish()` - the last snapshot, after which the writer is spent - and the
worker's two final call sites use it. `snapshot()` is unchanged.

Safety:

- A spent writer's buffer is replaced with an empty one, so a stray write
  after `finish`/`takeBytes` grows a buffer of its own and can never land in
  bytes the next writer owns.
- Two writers open at once (a streamed record held across awaits) do not
  share: the spare is taken, not borrowed.
- Nothing reads a reused buffer's old contents. Every byte below `_len` is
  written before the copy, path padding included (`_writePath` zeroes it).
  Checked by hashing all 375 corpus pages written by both writers, with
  buffers reused across very different pages: identical to main.

## VM only

Under dart2js nothing is kept (`_keepsSpare`). A browser allocates a typed
array's storage lazily, so there was little to save, and it measured as a
wash in a node loop: CAD pages a few percent faster, a Type3 page ~10% slower
on the median. With the flag off the web build allocates exactly as before.

## Measured

Encode (`serializeCommands`, all pages), min / median of many runs:

| file | VM AOT | VM JIT |
|---|---|---|
| plan-set-16p | 20.3 / 30 -> 13.4 / 14.5 ms | 21.7 / 28 -> 15.0 / 16.6 ms |
| diagram-dense-3p | 14.3 / 20.5 -> 8.5 / 9.2 ms | 15.0 / 18 -> 9.3 / 10.1 ms |
| type3-text-6p | 7.5 / 11.0 -> 5.2 / 5.7 ms | 8.0 / 9.5 -> 5.7 / 6.4 ms |
| styled-booklet-24p | 2.6 / 2.9 -> 2.3 / 2.4 ms | - |
| text-report-40p | 1.47 / 1.63 -> 1.36 / 1.49 ms | 1.49 / 1.72 -> 1.32 / 1.47 ms |

The medians move more than the minima: the old path's cost was GC-shaped, so
it was also the noisier one. Decode is unchanged (text-report's AOT decode
read ~0.1 ms slower in one set of runs and not in the JIT set - the garbage
collection the encode no longer triggers has to happen somewhere).

The VM sweep (`perf.sh diff`) cannot see this: it interprets into a
NullDevice and never serializes.

## Cost

Up to 4 MB held per isolate that has serialized a record (the render worker;
the UI isolate only if it serializes locally). A record that needed more than
4 MB keeps nothing.
