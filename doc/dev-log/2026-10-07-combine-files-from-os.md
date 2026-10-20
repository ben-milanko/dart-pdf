# Combine PDFs opened together from the OS

Selecting several PDFs in Explorer/Finder/Files and choosing "Open with
DartPDF" used to open only the first file (Windows, Linux) or a pile of tabs
(macOS). Now the files the OS hands over in one request arrive as one batch,
and a batch of two or more asks: open them in separate tabs, or **combine**
them into one new document. The dialog lists the files in name order (the
order the OS delivers them is not the order they were selected in on every
platform, and on Windows it is a race) and can be reordered by dragging.

## Pieces

- `IncomingFileService` (`app/lib/incoming_file.dart`) now carries batches:
  `files` is a `Stream<List<IncomingFile>>`; native → Dart `openFiles` (a
  list of the usual `{name, path, bytes?, bookmark?}` payloads) joins
  `openFile` (a batch of one, still sent by iOS/Android); Dart → native
  `getInitialFiles` replaces `getInitialFile`, which `initialFiles()` falls
  back to when a runner answers not-implemented (iOS/Android).
- `EditorScreen._openIncomingBatch` de-duplicates by path; one file goes
  through `_openIncoming` exactly as before, several show
  `showIncomingFilesDialog` (`app/lib/combine_incoming.dart`).
  `_combineIncoming` reads every file, merges with `PdfMerger.merge` via
  `compute`, and opens the result as `Combined.pdf` (numbered like
  `Untitled N.pdf`), `initiallyDirty` with no origin, so its first Save asks
  where to write and no source is overwritten. A merge failure (e.g. a
  password-protected first file) becomes an error tab.
- Linux (`my_application_open`): cold start passes **every** path as an
  entrypoint argument (`_openLaunchArgs` is now Linux-only and opens them as
  one batch); warm start sends one `openFiles`. The `.desktop` entry already
  used `%U`.
- macOS (`AppDelegate.application(_:open:)`): one `deliver(paths:)` per
  request, payloads built together on the file-access executor, sent as one
  `openFiles`; everything queued before Dart is ready is the
  `getInitialFiles` answer (no more first-file + flush).
- Windows: Explorer starts **one process per selected file**, and the second
  and later ones forward their file over `WM_COPYDATA`. So
  `DartPdfPlatformChannels` queues forwarded files and flushes them as one
  `openFiles` once none has arrived for `kIncomingSettleMs` (500 ms, a
  thread timer - `SetTimer(nullptr, ...)` - dispatched by the runner's
  message loop). On a cold multi-select the `getInitialFiles` call is
  **held** for the same settle window, so files the racing processes forward
  during startup join the launch file in one batch. `main.cpp` forwards every
  `.pdf` argument (a "Send to" shortcut or a command line passes several).
  Because of that, Dart no longer reads Windows launch args for files
  (`_hasExplicitLaunchTarget` still does, to skip session restore).
- Web: the launch-queue bridge in `web/index.html` hands Dart one array per
  launch.

## Gotchas

- An earlier cut batched on the Dart side with a time window. Every widget
  test that opens tabs by sending `openFile` back to back then hit the
  dialog. Batching belongs where the OS request is visible: Linux, macOS and
  web know it exactly; only Windows needs a timer, and it lives in the
  runner.
- The Windows/Linux runners were not compiled in this session (no Windows
  toolchain / GTK headers in the container) - review those diffs carefully.

Tests: `app/test/combine_incoming_test.dart` (combine order + page sizes,
separate tabs, single file opens without asking) and
`app/test/incoming_file_test.dart` (`openFiles`, `getInitialFiles` and its
fallback).
