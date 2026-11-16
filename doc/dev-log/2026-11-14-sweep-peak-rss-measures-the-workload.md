# 2026-11-14 - The VM sweep's peakRssBytes now measures the workload

`tool/perf.sh diff` reported a 5% peak-RSS regression (+35 MB on every file,
including a one-page 0.4 ms one) for a change that could not have caused it.
Chasing that turned up two separate problems with the vm-sweep's
`peakRssBytes`, both fixed here in the harness (no library code).

## 1. It was mostly the compiler

Each file is measured in a child process started as `dart perf_sweep.dart
--one <file>`, so every child compiled the script before running it, and the
front end's memory was the peak: ~510 MB for every file, large or tiny.
What the PDF cost was a rounding error on top.

It also depended on the checkout more than on the code. A `.dart_tool/`
holding a `native_assets.yaml` (dartdev writes one during `dart test` and
builds, even with an empty mapping) makes that compile ~30 MB heavier. A
working checkout has usually run tests; the cached worktree `perf_diff.sh`
creates never has. Copying just that file into a clean worktree reproduces the
whole difference. `dart pub get` vs `flutter pub get` and `--disable-dart-dev`
make no difference.

The sweep now compiles its child scripts to kernel snapshots once
(`_ChildScripts`, in a temp directory) and runs children from those. If the
compile fails it falls back to source and says so; `params.child` in the
envelope records which (`kernel-snapshot` / `source`).

## 2. A Linux child inherits its parent's peak

`ProcessInfo.maxRss` is `ru_maxrss`, which on Linux survives `exec`: a child
starts out with its parent's peak and can only report a larger one. With
snapshot children that made every file read as the sweep driver's own ~377 MB.
`peakRssBytes()` (perf_run_context.dart) reads `VmHWM` from /proc/self/status
on Linux - the high-water mark of the process's own address space - and falls
back to `ProcessInfo.maxRss` elsewhere. (Before this change the inheritance
was masked: the child's own compile was always the bigger number.)

## Result

`dartpdf-corpus`, same commit, before -> after:

| file | before | after |
|---|---|---|
| cmyk-jpeg-1p | 516 MB | 124 MB |
| scan-book-12p | 515 MB | 126 MB |
| annotated-10p | 506 MB | 163 MB |
| text-report-40p | 522 MB | 168 MB |
| plan-set-16p | 507 MB | 182 MB |
| hatch-sections-4p | 523 MB | 186 MB |

The number now moves with the document, which is what a memory metric is for.
A full sweep is also faster to run (no per-file compile).

Timings are not affected: both forms JIT the same kernel. Checked with 16
alternating source/snapshot runs per file on three files - minima, medians
and quartiles agree (e.g. plan-set interpret 127.3 / 146.3 ms vs 127.7 /
139.6 ms min / median). A first comparison at n=3-6 looked like the snapshot
was slower on small files; that was sampling noise, which on a 10-30 ms
cold-JIT measurement is large either way.

## Consequences

- **The trend steps down by ~350 MB** at this commit. `maxPeakRssBytes` on
  the dashboard and the nightly ratio check will see a large improvement once;
  it is the metric changing meaning, not the code. Old and new values are not
  comparable (SCHEMA.md says so).
- `perf_record_images.dart` (the `decodeImagesAtTarget` child) uses the same
  `peakRssBytes()`. When `backfill.sh` grafts the harness onto a commit old
  enough to carry its own copy of that script, that child still reports the
  inherited value.
- `perf_diff.sh` needed no change: with the compiler out of the measurement,
  the two checkouts' `.dart_tool/` state no longer shows up in it.
