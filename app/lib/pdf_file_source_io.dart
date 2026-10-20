import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';

/// A [PdfByteSource] that reads a local file on demand through a single
/// [RandomAccessFile], so the progressive loader can open a document by
/// fetching only the header, cross-reference chain, and live-object ranges it
/// needs - the local-file counterpart of [PdfHttpByteSource].
///
/// This is the "missing half" of the byte-source API for the app's own open
/// path: cloud-synced folders (OneDrive/Dropbox/iCloud) are the normal home of
/// this app's big scanned documents, where reading the whole file up front is
/// tens of seconds of pure byte transport. Ranged reads let the viewer paint
/// from a few MB while the rest streams in behind it.
///
/// Reads are serialized on the one handle (a [RandomAccessFile] is stateful -
/// its position is shared - so concurrent `setPosition`+`read` pairs would
/// interleave), which still satisfies the concurrency-safety contract of
/// [PdfByteSource.readRange]. Pass a [PdfCancelToken] to abort an in-flight or
/// later read, and [onProgress] to observe the running byte total (mirrors
/// [PdfHttpByteSource]).
///
/// On sandboxed macOS a file reopened across launches needs its security scope
/// reactivated from a bookmark, which a raw [RandomAccessFile] cannot do - use
/// the native-channel `PdfBookmarkFileByteSource` there instead (see
/// `file_io.dart`'s `pdfByteSourceForPath`). This source covers fresh picks
/// (whose scope is live for the session) and every non-sandboxed platform.
class PdfFileByteSource implements PdfByteSource {
  PdfFileByteSource(
    this.path, {
    this.cancelToken,
    this.onProgress,
  });

  /// The on-disk path to read.
  final String path;

  /// Optional cooperative cancellation. A fired token makes pending and later
  /// reads throw [PdfHttpCancelledException].
  final PdfCancelToken? cancelToken;

  /// Called after each read with the running total of bytes pulled and the
  /// file length once known.
  final void Function(int received, int? total)? onProgress;

  RandomAccessFile? _file;
  int? _length;
  int _received = 0;

  /// Serializes access to the shared [RandomAccessFile] position.
  Future<void> _lock = Future.value();

  Future<T> _synchronized<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _lock = _lock.then((_) async {
      try {
        completer.complete(await action());
      } catch (error, stack) {
        completer.completeError(error, stack);
      }
    });
    return completer.future;
  }

  Future<RandomAccessFile> _open() async {
    return _file ??= await File(path).open();
  }

  @override
  Future<int?> get length async {
    cancelToken?.throwIfCancelled();
    return _length ??= await File(path).length();
  }

  @override
  Future<Uint8List> readRange(int start, int endExclusive) async {
    cancelToken?.throwIfCancelled();
    final s = start < 0 ? 0 : start;
    if (endExclusive <= s) return Uint8List(0);
    return _synchronized(() async {
      cancelToken?.throwIfCancelled();
      final file = await _open();
      final total = _length ??= await file.length();
      if (s >= total) return Uint8List(0);
      final end = math.min(endExclusive, total);
      await file.setPosition(s);
      final data = await file.read(end - s);
      cancelToken?.throwIfCancelled();
      _received += data.length;
      onProgress?.call(_received, total);
      return data;
    });
  }

  @override
  Future<void> close() async {
    // Drain the queue first so a read in flight finishes on the current handle;
    // clearing [_file] before draining would make a queued read reopen a fresh
    // handle that then leaks.
    await _synchronized(() async {});
    final file = _file;
    _file = null;
    if (file != null) {
      try {
        await file.close();
      } catch (_) {
        // Already closed / gone - nothing to release.
      }
    }
  }
}
