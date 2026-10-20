# Progressive / optimised loading

Open a large PDF without reading the whole file up front. The parser is
network-agnostic: it asks a `PdfByteSource` for the byte ranges it needs
(header, cross-reference chain, the objects a page references) rather than
requiring the complete buffer. This is how you keep a viewer responsive on a
198-page scan sitting in a slow cloud-synced folder, or a multi-hundred-MB CAD
sheet served over HTTP.

This guide is for **consumers of the `dart_pdf_editor` / `pdf_document`
packages**. If you just have bytes, keep using `PdfDocument.open(Uint8List)` /
`PdfViewer(bytes:)` / `PdfReader(bytes:)` - none of that changes.

## The API

- `PdfByteSource` (from `pdf_cos`, re-exported by `dart_pdf_editor`): the
  contract - `Future<int?> get length` and
  `Future<Uint8List> readRange(int start, int endExclusive)`, plus an optional
  `close()`. Implementations must be safe to call `readRange` on concurrently.
- `PdfDocument.openSource(source, {password, options})`: opens a document from a
  source, fetching only the bytes it needs and falling back to a plain download
  when the source can't serve useful ranges.
- `PdfSourceLoadOptions`: tuning - `onProgress`, window sizes, and
  `firstPaintPages` (below).
- `PdfHttpByteSource` (from `dart_pdf_editor`): a ready-made HTTP(S) source using
  Range requests, with auth headers, `PdfCancelToken`, and progress.

## Remote files (HTTP)

```dart
final source = PdfHttpByteSource(
  Uri.parse('https://host/big.pdf'),
  headers: {'Authorization': 'Bearer $token'},
  cancelToken: cancelToken,
  onProgress: (received, total) => setState(() => _progress = received / total!),
);
final document = await PdfDocument.openSource(source);
// ...show it, then:
await source.close();
```

On the web, cross-origin Range loading needs the server to expose
`Accept-Ranges`/`Content-Range` via `Access-Control-Expose-Headers`; without
that the browser hides them and the source transparently falls back to a single
full download.

## Local files (native, off the web)

`dart:io` can't live in the packages (they compile for the web too), so there's
no bundled file source - implement the two-method contract over a
`RandomAccessFile`. Reads share one handle's cursor, so serialise them:

```dart
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:pdf_cos/pdf_cos.dart';

class FileByteSource implements PdfByteSource {
  FileByteSource(this.path);
  final String path;
  RandomAccessFile? _file;
  int? _length;
  Future<void> _lock = Future.value();

  Future<T> _sync<T>(Future<T> Function() action) {
    final done = Completer<T>();
    _lock = _lock.then((_) async {
      try { done.complete(await action()); }
      catch (e, s) { done.completeError(e, s); }
    });
    return done.future;
  }

  @override
  Future<int?> get length async => _length ??= await File(path).length();

  @override
  Future<Uint8List> readRange(int start, int end) => _sync(() async {
        final f = _file ??= await File(path).open();
        final total = _length ??= await f.length();
        final s = start < 0 ? 0 : start;
        if (s >= total || end <= s) return Uint8List(0);
        await f.setPosition(s);
        return f.read((end > total ? total : end) - s);
      });

  @override
  Future<void> close() =>
      _sync(() async => _file?.close()).whenComplete(() => _file = null);
}
```

The example app (`app/lib/pdf_file_source_io.dart`) ships a fuller version with
progress and cancellation, plus a variant that reads a sandboxed macOS file
through a security-scoped bookmark over a platform channel - reach for that
shape if your app is sandboxed and reopens files across launches.

## Fast first paint (`firstPaintPages`)

`PdfDocument.openSource` fetches every live object before it returns. For a
lightly-packed PDF that's a few MB; for a **scan or CAD sheet the live objects
are the page images**, so it's essentially the whole file - and "first paint"
becomes a long wait on a slow source.

`firstPaintPages` fetches only what the first N pages need (the whole page tree,
so page count and navigation still work, plus those pages' content, resources,
fonts and image XObjects) and leaves the rest of the buffer unfetched:

```dart
final preview = await PdfDocument.openSource(
  source,
  options: PdfSourceLoadOptions(
    firstPaintPages: 1,
    onProgress: (received, total) => report(received, total),
  ),
);
```

**The buffer is deliberately incomplete.** The covered pages render; the rest
render blank until you complete it. So:

- Render-only. Do **not** edit or sign a `firstPaintPages` document - those need
  every byte (edits append to one buffer; signing hashes byte ranges).
- Complete the buffer in the background - read the whole `source` sequentially -
  then reopen for the full document once every page is available.

A typical Flutter flow: show `PdfReader`/`PdfViewer` over the first-paint
document for an instant page 1, read the whole source behind it (report
`onProgress` on a bar), then swap to a full `PdfDocument.open(completeBytes)` /
editing session when the read lands. The example app wires exactly this
(`EditorScreen._openProgressive`).

## Notes

- `PdfDocument.open(Uint8List)` and the byte-based widgets are unaffected;
  `openSource` is purely additive.
- Progress + cancellation live on the source (`PdfHttpByteSource`) and the
  loader (`PdfSourceLoadOptions.onProgress`), not on `PdfByteSource` itself.
- `PdfPerfPhase.sourceFetch` (via `package:pdf_cos/perf.dart`) times the fetch if
  you want to measure it.

See [`doc/dev-log`](dev-log) for the loader internals (the ranged xref walk, the
page-scoped closure, and the sparse-buffer parser contract).
