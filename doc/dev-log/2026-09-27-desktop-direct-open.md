# Desktop open: read a fast local file whole instead of previewing it

Every desktop open by path goes through `EditorScreen._openProgressive`. That
covers OS double-click, a single-file File > Open or drop, Recents, and the
active tab of every session restore (`_materializeDeferredPath`). The path
was built for #359's big cloud-synced files: `PdfDocument.openSource`
(`firstPaintPages: 1`) assembles a sparse buffer, `DocumentTab.preview`
mounts a read-only `_ProgressivePreview`, and `readSourceFully` streams the
rest in behind it. Then `_swapPreviewToDocument` builds a fresh
`DocumentTab.document`.

On a local disk the whole read takes about as long as the ranged open, so
the preview is torn down almost as soon as it goes up. It still costs:

- a second parse of the sparse buffer (the preview's `PdfReader`);
- a whole 3-isolate worker generation, each worker copying a full-length
  buffer;
- a page-0 render;
- content, then blank paper, then content again. The edit session's viewer
  starts with an empty preview cache, so the harness logs twice the
  `page-raster miss reason=empty` lines.

## What changed

Only `app/lib/editor_screen.dart`, and only the bounded sequential variant from
the triage:

1. The existing `onProgress` closure on the progressive source now counts
   reads. `PdfFileByteSource`, `PdfBookmarkFileByteSource` and the mobile
   source each call it once per read. `openSource` is timed alone, without
   the source setup.
2. After `openSource` succeeds, the gate opens when both hold:
   - `token == null`: desktop path origins only. The mobile reference pick
     (#364) keeps the preview, because its provider can't be told apart from
     a local file off-device.
   - `openSourceUs / reads <= _directOpenMaxMeanReadMs` (3 ms). The seam is
     `debugDirectOpenMaxMeanReadMs`: negative forces the preview, and
     `double.infinity` forces the attempt.
3. With the gate open, `readSourceFully` starts on the **same** source, and
   only after the ranged reads, so it never competes with them. It is awaited
   with a timeout of `clamp(2 x openSourceMs, 50, 150)` ms.
4. If the bytes land in time, the source is closed, the progress notifier is
   disposed, and the sparse document is dropped. The bytes are committed
   through `_openWholeFile`, which is `_fallbackFullOpen` renamed, with an
   optional already-read `bytes` argument. That means the same
   `DocumentTab.document` + `_replaceLoadingTab` + recents code, and the same
   `onOpenFailed` handling. A restore's `into:` placeholder is replaced in
   place, and `onOpenFailed: (_) => true` still closes it quietly.
   `open-trace: fast-path direct ...` is logged.
5. On a timeout or an error, `open-trace: fast-path missed ...` is logged and
   the preview mounts as before. The in-flight future goes to
   `_finishProgressive(preview, source, fullRead:)`, so the file is never read
   twice. Its catch branch stays the error fallback.

The `open-trace: first-paint` line now also carries `reads=` and
`meanReadUs=`, so a field log shows why the gate stayed shut. Its
`fetchedBytes` is snapshotted before the whole read starts, so it still means
first-paint bytes.

The mean includes the loader's parsing and any event-loop delay on the UI
isolate, so it overstates the real read latency. That only ever errs towards
the preview, which is today's behaviour.

## Numbers

All in-app numbers come from a scratch `flutter test` harness: debug JIT,
Linux platform override, OS-open channel. Each run did 6 warm reps per mode,
interleaved (preview / forced / production gate / bytes-in-payload direct).
The machine was shared, at load average 13-27. Counts are deterministic
PdfPerfLog lines. Times are ms from the open to the edit session's page-0
`page-ready`. The synthetic files are public fixtures repeated with
`PdfMerger.merge`: `photo-jpeg-6p.pdf` x40 (60.4 MB, 240 pages) and
`plan-set-16p.pdf` x10 (20.9 MB, 160 pages).

| | preview (gate off) | production gate | per-rep ratio median | bytes-in-payload |
|---|---|---|---|---|
| open, 60 MB | 419 | 268 | 1.69x | 176 |
| open, 21 MB | 338 | 234 | 1.40x | 180 |
| restore, 60 MB | 578 | 341 | 1.46x | - |
| restore, 21 MB | 351 | 326 | 1.19x | - |

The production gate opened in 28/28 runs, warm-ups included. openSource did
239 and 148 reads at 0.35-0.71 ms each in the measured debug reps, and the
whole read landed 5-61 ms after it, inside the wait. Debug openSource took
51-286 ms, so the wait was 102-150 ms. The 21 MB
restore gains least because, in 2 of its 6 preview reps, the swap pre-empted
the preview before its worker generation started, so those reps paid little
for it.

Counts per open (60 MB):

| | preview path | fast path |
|---|---|---|
| sparse parses | 2 | 1 |
| whole-file parses | 1 | 1 |
| worker generations | 2 | 1 |
| page-0 interprets | 2 | 1 |
| `reason=empty` misses | 12 | 6 |

The fast path's 6 misses match a direct bytes open. An origin/main run of the
same harness logged the same preview-path counts, which confirms the gate-off
path is the old one.

The remaining gap to a direct open is openSource itself, which is still paid.
That is why the gain lands around 1.4-1.7x rather than the ~2.5x a probe
that skips openSource could reach.

AOT (`dart compile exe`), measuring what the gate sees on a local file
through a `RandomAccessFile` source shaped like `PdfFileByteSource`:

- **60 MB:** openSource took 8-18 ms for 239 reads, 35-74 us per read. The
  3 ms threshold has 40-90x headroom there.
- **21 MB:** 5-12 ms for 148 reads, 33-84 us per read, plus one loaded
  outlier of 75 ms (507 us per read).
- **Whole read on the same source:** 13-80 ms for 60 MB and 4-9 ms for
  21 MB.

So in release the wait is usually the 50 ms floor. Under load, 2 of 7 60 MB
reads (56 and 80 ms) overran it and would have taken the old path. They
would still read the file only once. If field logs show many
`fast-path missed` lines on big local files, a size-aware floor (about 1 ms
per MB, still capped at 150) is the obvious follow-up.

## Tests

- `app/test/desktop_direct_open_test.dart`:
  - A fast local file (Linux, gate forced on) goes straight to an edit
    session: 1 sparse parse + 1 whole-file parse, 1 generation, 1 page-0
    interpret. No preview is logged, and the recent is recorded.
  - The gate-off comparison renders page 0 twice (2/1/2/2). The macOS
    bookmark channel is mocked and holds the whole read until the preview
    has painted.
  - A wait that misses hands the same read to the preview: one whole read,
    no `readFile` fallback.
  - A slow source (20 ms per read, production threshold) never waits and
    reads the file whole exactly once.
  - A restored tab takes the direct read and is replaced in place.
- `progressive_open_test.dart` pins the gate off in `setUp`, so the
  preview-and-swap and restore-through-preview tests keep covering that
  path.
- `session_restore_test.dart` needs no change: it runs on the default test
  platform (Android), where `progressiveOpenSupported` is false. As a scratch
  check, it also passes 11/11 under a Linux override, with the gate both at
  production and forced on.

## Not done (deliberately)

- **A native storage-class probe:** macOS `ubiquitousItemDownloadingStatus`,
  Windows recall/offline attributes, Linux `statfs`. It would let a local
  file skip openSource entirely, but it needs Windows/Linux hosts and a real
  cloud-synced session to validate.
- **Holding the preview on screen until the edit session's page is ready.**
  The flash now remains only on the slow path.
- **Building the preview reader from `previewDocument`** (the third parse).
  It is worth about 1 ms.
- **`PdfSourceLoadOptions.firstPaintPageIndices`** for a resumed preview.
  It only matters for slow opens, and needs its own evidence.

**Manual check before merging:** a macOS profile build, opening one
dehydrated iCloud or OneDrive file and one large local file. In the devtools
log, the dehydrated file should show a shut gate (no `fast-path` line, or at
worst `fast-path missed`) and the local file `fast-path direct`. The macOS
bookmarked path measures its reads through `readFileRange` channel round
trips, which the harness only mocks.
