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

Only the app: `app/lib/editor_screen.dart` and a new `app/lib/paced_read.dart`.
This is the bounded sequential variant from the triage, plus a throughput
check.

1. The existing `onProgress` closure on the progressive source now counts
   reads. `PdfFileByteSource`, `PdfBookmarkFileByteSource` and the mobile
   source each call it once per read. `openSource` is timed alone, without
   the source setup.
2. After `openSource` succeeds, the fast path is tried when all of these hold:
   - `token == null`: desktop path origins only. The mobile reference pick
     (#364) keeps the preview, because its provider can't be told apart from
     a local file off-device.
   - The file length is known (it always is for the desktop sources).
   - `openSourceUs / reads <= _directOpenMaxMeanReadMs` (3 ms). The seam is
     `debugDirectOpenMaxMeanReadMs`: negative forces the preview, and
     `double.infinity` forces the attempt.
3. The rest of the file is read on the **same** source, only after the
   ranged reads, so it never competes with them. The read is a
   `PacedWholeRead` with a budget of `clamp(2 x openSourceMs, 50, 150)` ms
   (seam: `debugDirectOpenWaitMs`). The wait ends at whichever comes first:
   the bytes, or the read falling behind its pace.
4. If the bytes land, the source is closed, the progress notifier is
   disposed, and the sparse document is dropped. The bytes are committed
   through `_openWholeFile`, which is `_fallbackFullOpen` renamed, with an
   optional already-read `bytes` argument. That means the same
   `DocumentTab.document` + `_replaceLoadingTab` + recents code, and a
   restore's `into:` placeholder is replaced in place. `open-trace:
   fast-path direct ...` is logged.
5. If it falls behind, the preview mounts as before and the in-flight read
   goes to `_finishProgressive(preview, source, fullRead:)`, so the file is
   never read twice. An early fall is logged as `fast-path skipped ...
   behindAtBytes= waitedMs=`. A read that ran to the end of its budget, or
   failed, is logged as `fast-path missed ... reason=deadline|error`.

The `open-trace: first-paint` line now also carries `reads=` and
`meanReadUs=`, so a field log shows why the gate stayed shut. Its
`fetchedBytes` is snapshotted before the whole read starts, so it still means
first-paint bytes. Every fast-path line carries `firstChunkUs=`.

### Why the read checks its own pace

The per-read gate only measures **latency**. openSource does about 150-240
reads of ~1.7 KB each on a 20-60 MB file, so its mean time per read is the
storage's latency plus parse CPU. The first version of this change waited out
the whole budget for any file that passed that gate. Review showed a
common class of storage that passes it and then can't deliver: low latency,
limited throughput.

- gigabit network shares (SMB/NFS, ~110 MB/s);
- USB 2 sticks and SD cards (~30 MB/s);
- external spinning disks (~150 MB/s);
- a cold SATA SSD, for files of about 60 MB and up.

On those, every open waited the full 50-150 ms before mounting the preview,
and gained nothing. In a simulated gigabit-share run (0.4 ms + 110 MB/s per
read, 60 MB), first content went from 299 to 446 ms.

`PacedWholeRead` (pure Dart, `pdf_cos` only) now reads the file in growing
chunks and checks each one against a due time:

- **Pace line.** The chunk ending at byte `e` is due
  `min(budget, slack + budget * e / length)` after the read starts, with 6 ms
  slack. The last chunk is due at the budget itself, so the budget is still
  the deadline.
- **First chunk.** The first read (1 MB) is also due within 10 ms when there
  is more to come. A local disk delivers 1 MB in a millisecond or two; the
  classes above take 7-35 ms. This catches them at the first chunk, even for
  a file that is only a little too big for the budget.
- **Chunk sizes.** Reads double from 1 MB up to readSourceFully's 8 MB while
  there is a decision to make. Once behind, they go straight to 8 MB. Each
  read boundary is a hop through the UI isolate, which is busy with the
  preview by then, and the storage sits idle during it. In the simulated
  share run, ramping after falling behind cost 55 ms of editable time. Going
  straight to 8 MB made it equal to the old path.
- **Two checks.** Each due time is checked by a timer while the chunk is in
  flight, and again as it lands, in case the isolate was too busy for the
  timer to run. A last chunk that has landed is never "late".

Falling behind never stops the read; it just stops the wait.

### Behaviour notes

- **Parse failure on the fast path.** If the whole-file parse fails after a
  direct read (the read itself worked), the tab becomes an error tab.
  `onOpenFailed` is not called. That matches what the preview's swap did,
  and keeps `onOpenFailed` for an origin that can't be read. Recents keeps the
  entry, and a restore shows the error instead of closing quietly. The first
  version passed `onOpenFailed` through, which silently changed this.
- **Closing the tab during the wait.** If the loading tab (or restore
  placeholder) is closed while the read is in flight, the wait ends, the
  cancel token fires, and nothing is built: no whole-file parse, and no
  preview. The first version built and then disposed a full edit session.

## Numbers

In-app numbers come from a scratch `flutter test` harness: debug JIT,
OS-open channel, gate off (the old path) vs production. Modes are
interleaved ABBA in one process; the first rep is a cold warm-up and is
dropped. Times are ms from the open to page-0 `page-ready`. "First content"
is the first page 0 of any generation; "editable" is the edit session's. The
files are synthetic, one raw pseudo-random RGB image per page: 60.7 MB with
240 pages, and 20.8 MB with 160 pages. Local runs use the Linux override and
`PdfFileByteSource`. Slow-storage runs mock the macOS bookmark channel with a
per-read latency plus a per-byte cost, as the review did.

Local files, 12 warm ABBA pairs (machine load average 5-7):

| | gate off | production | per-rep editable ratio | fast path taken |
|---|---|---|---|---|
| open, 60 MB (editable) | 316 | 250 | 1.29x | 12/12 |
| open, 21 MB (editable) | 236 | 194 | 1.03x | 11/12 |
| restore, 60 MB (editable) | 476 | 345 | 1.39x | 11/12 |
| restore, 21 MB (editable) | 320 | 247 | 1.29x | 12/12 |

- **21 MB open is bimodal.** On a quiet machine the old path's own swap often
  lands before its preview renders (5 of 12 gate-off reps parsed once and
  spun up one generation), and then the two paths tie. Hence the 1.03x
  per-rep median against a 236 -> 194 difference in the mode medians.
- **Review's independent runs.** On an earlier build of this change, the
  review measured editable page 0 at 1.30x for 60 MB and 1.19x for 21 MB
  (in-process ABBA, 8 pairs). A cross-process A/B against origin/main gave
  513 -> 370 ms for 60 MB, 1.39x. Those numbers match these.
- **Size of the gain.** Expect about 1.2-1.4x on editable page 0 for local
  files of tens of MB, and less when the old swap already beats its own
  preview. The first version of this entry reported 1.4-1.7x. That came from
  a harness that always ran the preview mode right after the previous rep's
  direct mode, and the figure did not survive a fair interleave.
- **First content.** For opens, first content is the same or earlier (60 MB:
  302 -> 250). For restores, the first pixels arrive a little later than the
  old preview's (60 MB: 288 -> 345), because the direct path's first paint is
  the edit session's. Those pixels are editable and don't flash away.

Low-latency, limited-throughput storage (the miss class), mocked through the
bookmark channel:

| profile | file | gate off: first / editable | production: first / editable | outcome | waited |
|---|---|---|---|---|---|
| 0.4 ms + 110 MB/s (gigabit share) | 60 MB | 290 / 893 | 312 / 898 | skipped 12/12 | 8-19 ms |
| 0.4 ms + 110 MB/s | 21 MB | 224 / 432 | 238 / 430 | skipped 12/12 | 9-15 ms |
| 0.5 ms + 30 MB/s (USB 2) | 60 MB | 337 / 2440 | 348 / 2492 | skipped 6/6 | 9-10 ms |
| 0.15 ms + 150 MB/s (external HDD) | 60 MB | 258 / 808 | 311 / 834 | skipped 8/8 | 8-20 ms |
| 0.15 ms + 150 MB/s | 21 MB | 250 / 459 | 352 / 438 | 6 skipped, 1 direct, 1 missed | 11-59 ms (the miss: 151) |

- **Editable time** is unchanged on these profiles (per-rep 0.98-1.04x).
- **The first version** measured 446 vs 299 ms first content on the
  gigabit-share profile at 60 MB. Every run there logged `fast-path missed`
  and waited the full 150 ms.
- **The 21 MB external-disk row is the one borderline case.** That storage
  moves the file in almost exactly the budget, about 140 ms against 150. A
  read that close to its line can hug it and then miss at the deadline (1 of
  8 here); on this profile the preview is not clearly better either. In
  release, openSource is faster, so the budget is tighter and this case skips
  at the first chunk (see the AOT table).
- **Deterministic counts.** On every skip or miss, the counts equal the
  gate-off path's, and the file is read once. The harness counts whole-read
  bytes on the channel.

Counts per open (60 MB, local), deterministic PdfPerfLog lines:

| | preview path | fast path |
|---|---|---|
| sparse parses | 2 | 1 |
| whole-file parses | 1 | 1 |
| worker generations | 2 | 1 |
| page-0 interprets | 2 | 1 |
| `reason=empty` misses | 12 | 6 |

The fast path's 6 misses match a direct bytes open. An origin/main run of the
same harness logged the same preview-path counts, which confirms that the
gate-off path is the old one.

### AOT decision times

AOT (`dart compile exe`). The source is a `RandomAccessFile` shaped like
`PdfFileByteSource`, with the same latency and throughput simulation. The
bench runs openSource and then `PacedWholeRead` with the production budget.
"Decided" is how long after openSource the direct/preview decision came; on
a skip, that is the whole first-paint delay.

| profile | file | openSource | budget | outcome | decided | whole read |
|---|---|---|---|---|---|---|
| local page cache | 21 MB | 5-29 ms | 50-57 ms | direct 7/7 | 5-10 ms | 5-10 ms |
| local page cache | 60 MB | 11-66 ms | 50-131 ms | direct 7/7 | 17-26 ms | 17-26 ms |
| local page cache | 240 MB | 60-201 ms | 120-150 ms | direct 7/7 | 66-100 ms | 66-100 ms |
| 0.4 ms + 110 MB/s | 60 / 21 MB | 104-116 / 69-71 ms | 150 / 138-140 ms | skipped 10/10 | 11-12 ms | 573-578 / 198-202 ms |
| 0.5 ms + 30 MB/s | 60 MB | 139 ms | 150 ms | skipped 3/3 | 11 ms | 2045-2049 ms |
| 0.15 ms + 150 MB/s | 60 / 21 MB | 43 / 28 ms | 85-88 / 56-57 ms | skipped 10/10 | 8 / 17 ms | 424 / 148 ms |
| 0.1 ms + 500 MB/s (cold SATA) | 60 MB | 29 ms | 57-59 ms | skipped 5/5 | 14-16 ms | 136-138 ms |
| 0.1 ms + 500 MB/s | 21 MB | 19 ms | 50 ms | direct 5/5 | 48-50 ms | 48-50 ms |

The skip decision on slow storage comes at 8-17 ms, where the first version
always waited out the budget (50-150 ms).

## Tests

- `app/test/paced_read_test.dart` (unit, a fake `PdfByteSource`):
  - every byte is read once, in 1 KB, 2 KB, 4 KB ... windows;
  - a file no bigger than the first chunk is one read, held only to the
    budget;
  - slow throughput falls behind the pace line before the chunk lands;
  - the first chunk is due within `firstChunkDue` whatever the budget, and
    the rest then goes in one full-size read;
  - a mid-read chunk that drops off the pace falls behind then;
  - a chunk that lands late while the isolate is blocked still counts, via
    the landing check;
  - a stalled last chunk falls behind at the deadline, and a late last chunk
    that is in is not behind;
  - errors fail the bytes, and an over-long answer is clamped.
- `app/test/desktop_direct_open_test.dart`:
  - A fast local file (Linux, gate forced on) goes straight to an edit
    session: 1 sparse parse + 1 whole-file parse, 1 generation, 1 page-0
    interpret. No preview is logged, and the recent is recorded.
  - The gate-off comparison renders page 0 twice (2/1/2/2). The macOS
    bookmark channel is mocked and holds the whole read until the preview
    has painted.
  - A stalled read misses at the deadline and hands the same read to the
    preview: one whole read, no `readFile` fallback.
  - A slow source (20 ms per read, production threshold) never waits and
    reads the file whole exactly once.
  - A restored tab takes the direct read and is replaced in place.
  - **New, the miss class.** A ~3.8 MB file whose reads are instant to
    answer but cost 300 ms per MB. It logs `fast-path skipped ...
    behindAtBytes=0` and never `fast-path missed`. The same read finishes
    the swap, and its chunks tile the file exactly once.
  - **New.** A tab closed while its direct read is in flight builds nothing:
    no whole-file parse, no worker generation, no preview.
  - **New.** A direct read whose bytes don't parse leaves an error tab on a
    restore, where `onOpenFailed` would have closed it.
- `progressive_open_test.dart` pins the gate off in `setUp`, so the
  preview-and-swap and restore-through-preview tests keep covering that
  path.

## Not done (deliberately)

- **A native storage-class probe:** macOS `ubiquitousItemDownloadingStatus`,
  Windows recall/offline attributes, Linux `statfs`. It would let a local
  file skip openSource entirely, and would name network shares outright
  instead of measuring them. It needs Windows/Linux hosts and a real
  cloud-synced session to validate.
- **Holding the preview on screen until the edit session's page is ready.**
  The flash now remains only on the slow path.
- **Building the preview reader from `previewDocument`** (the third parse).
  It is worth about 1 ms.
- **`PdfSourceLoadOptions.firstPaintPageIndices`** for a resumed preview.
  It only matters for slow opens, and needs its own evidence.

**Manual check before merging:** a macOS profile build, opening four files:

- a dehydrated iCloud or OneDrive file: shut gate (no `fast-path` line) or
  `fast-path skipped`;
- a large local file: `fast-path direct`;
- a file on a network share or USB stick, if one is at hand:
  `fast-path skipped` with a small `waitedMs`;
- a large local file via Recents or restore, so the bookmarked
  `readFileRange` channel path is exercised. The harness only mocks that
  path.
