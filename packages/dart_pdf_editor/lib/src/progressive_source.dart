import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';

import 'http_byte_source.dart';

/// Reads a whole [PdfByteSource] into one contiguous buffer, reporting progress
/// as it goes.
///
/// This is the background "finish the download" half of progressive open:
/// [PdfDocument.openSource] paints the first page(s) from a sparse buffer of
/// just the bytes it needs (zeros in the free space the parser never reads),
/// then a host reads the rest with this and swaps the full buffer in. Unlike
/// that first-paint buffer, the bytes returned here are the complete file -
/// what the edit session, signing, and the render workers need.
///
/// Progress is reported to [onProgress] after each read as `(received, total)`;
/// `total` is the document length when the source knows it, else null. Pass a
/// [cancelToken] to abort in flight - a fired token makes this throw
/// [PdfHttpCancelledException] between reads (and any read the source itself
/// aborts propagates). [chunk] bounds each read (and so the progress
/// granularity).
///
/// A known-length source is read forward in [chunk] windows until it is
/// exhausted; an unknown-length one is chunked until a short/empty read signals
/// the end.
Future<Uint8List> readSourceFully(
  PdfByteSource source, {
  void Function(int received, int? total)? onProgress,
  int chunk = 8 << 20,
  PdfCancelToken? cancelToken,
}) async {
  assert(chunk > 0);
  final len = await source.length;
  if (len != null && len >= 0) {
    final out = Uint8List(len);
    var pos = 0;
    while (pos < len) {
      cancelToken?.throwIfCancelled();
      final end = pos + chunk < len ? pos + chunk : len;
      final data = await source.readRange(pos, end);
      if (data.isEmpty) break;
      // Never trust a source to honour the requested length: a misbehaving one
      // can answer with more bytes than asked for (a 200-style full body).
      // Clamp so setRange can't run past the buffer.
      final count = data.length < len - pos ? data.length : len - pos;
      out.setRange(pos, pos + count, data);
      pos += count;
      onProgress?.call(pos, len);
    }
    return pos == len ? out : Uint8List.sublistView(out, 0, pos);
  }
  // Unknown length: chunk until a short read signals EOF.
  final builder = BytesBuilder(copy: false);
  var pos = 0;
  while (true) {
    cancelToken?.throwIfCancelled();
    final data = await source.readRange(pos, pos + chunk);
    if (data.isEmpty) break;
    builder.add(data);
    pos += data.length;
    onProgress?.call(pos, null);
    if (data.length < chunk) break;
  }
  return builder.toBytes();
}

/// Builds a viewer subtree progressively from an asynchronous [PdfByteSource].
///
/// This is the reusable orchestration behind [PdfReader.source] /
/// [PdfEditorView.source], and the entry point for pointing any byte-based
/// viewer at a source: it opens a sparse first-paint document from the source's
/// ranges, calls [builder] with those bytes so page one paints immediately,
/// reads the rest of the file in the background (progress + cancellation), then
/// calls [builder] again with the complete buffer so it can swap in place.
///
/// [builder] receives `(context, bytes, complete)` - the best buffer available
/// so far and whether it is the full file. Give the widget it returns a stable
/// identity (a [PdfReader]/[PdfEditorView] at the same position, or a fixed
/// key) so the first-paint→full swap reopens in place rather than remounting;
/// pass a stable `documentId` down so remembered scroll/zoom survives the swap.
///
/// If the sparse first paint can't be assembled (a source that can't serve
/// useful ranges, a malformed file), this falls back to a plain full read: no
/// early paint, [loadingBuilder] shows until the whole file lands, then
/// [builder] is called once with `complete: true`. The in-flight load is
/// cancelled when the widget is disposed.
class PdfProgressiveSourceBuilder extends StatefulWidget {
  const PdfProgressiveSourceBuilder({
    super.key,
    required this.source,
    required this.builder,
    this.options = const PdfSourceLoadOptions(firstPaintPages: 1),
    this.password = '',
    this.onProgress,
    this.onFirstPaint,
    this.loadingBuilder,
    this.errorBuilder,
  });

  /// The document source. Host-owned; the widget reads from it but never
  /// closes it (a host may reuse it), and does not take ownership.
  final PdfByteSource source;

  /// Builds the viewer for the bytes available so far. `complete` is false
  /// while showing the sparse first-paint buffer, true once the full file has
  /// been read.
  final Widget Function(BuildContext context, Uint8List bytes, bool complete)
      builder;

  /// Tuning for the sparse first-paint open (see
  /// [PdfDocument.openSource]). Defaults to fetching just the first page;
  /// `firstPaintPages: null` opens every object up front (no fast first paint).
  final PdfSourceLoadOptions options;

  /// Password for an encrypted source, forwarded to the open.
  final String password;

  /// Reports the background full-read progress as `(received, total)`; `total`
  /// is null until/unless the source's length is known.
  final void Function(int received, int? total)? onProgress;

  /// Called once, right after the first-paint bytes are handed to [builder].
  final VoidCallback? onFirstPaint;

  /// Shown before any bytes are available (during the first-paint open, or the
  /// whole full read when first paint fell back). Defaults to a centered
  /// [CircularProgressIndicator].
  final WidgetBuilder? loadingBuilder;

  /// Shown when the load fails before any bytes could be produced. Defaults to
  /// a centered error message. A failure of the *background* read after the
  /// first paint is not surfaced here - the first-paint view stays up.
  final Widget Function(BuildContext context, Object error)? errorBuilder;

  @override
  State<PdfProgressiveSourceBuilder> createState() =>
      _PdfProgressiveSourceBuilderState();
}

class _PdfProgressiveSourceBuilderState
    extends State<PdfProgressiveSourceBuilder> {
  /// The sparse first-paint buffer (renderable for the covered pages only).
  Uint8List? _preview;

  /// The complete file, once the background read finishes.
  Uint8List? _full;

  /// A load failure that left us with nothing to show.
  Object? _error;

  /// Cancels the in-flight background read on dispose.
  PdfCancelToken _cancel = PdfCancelToken();
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(PdfProgressiveSourceBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A new source means a new document: cancel the old load and restart.
    if (!identical(widget.source, oldWidget.source)) {
      _cancel.cancel();
      _cancel = PdfCancelToken();
      _preview = null;
      _full = null;
      _error = null;
      _load();
    }
  }

  Future<void> _load() async {
    final token = _cancel;
    // First paint: fetch just the covered pages' bytes into a sparse buffer.
    // Any failure here (a non-ranged source, a malformed file) just means we
    // skip the early paint and wait for the full read - never a hard error.
    Uint8List? preview;
    try {
      final doc = await PdfDocument.openSource(widget.source,
          password: widget.password, options: widget.options);
      preview = doc.cos.bytes;
    } on Object {
      preview = null;
    }
    if (_disposed || !identical(token, _cancel)) return;
    if (preview != null) {
      setState(() => _preview = preview);
      widget.onFirstPaint?.call();
    }

    // Background full read: the complete, editable/persistable buffer.
    try {
      final full = await readSourceFully(widget.source,
          cancelToken: token, onProgress: widget.onProgress);
      if (_disposed || !identical(token, _cancel)) return;
      setState(() => _full = full);
    } on PdfHttpCancelledException {
      // Disposed or superseded mid-read; nothing to do.
    } on Object catch (error) {
      if (_disposed || !identical(token, _cancel)) return;
      // Keep any first-paint view up; only surface when we have nothing.
      if (_preview == null) setState(() => _error = error);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _cancel.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _full ?? _preview;
    if (bytes == null) {
      if (_error != null) {
        return widget.errorBuilder?.call(context, _error!) ??
            _defaultError(context, _error!);
      }
      return widget.loadingBuilder?.call(context) ?? _defaultLoading(context);
    }
    return widget.builder(context, bytes, _full != null);
  }

  static Widget _defaultLoading(BuildContext context) =>
      const Center(child: CircularProgressIndicator());

  static Widget _defaultError(BuildContext context, Object error) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('Could not open document: $error',
              textAlign: TextAlign.center),
        ),
      );
}
