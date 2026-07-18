import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The method channel the macOS runner exposes for security-scoped file
/// access (bookmark create / whole-file read+write, and the ranged reads this
/// source uses). Shared verbatim with `file_io.dart`.
const _fileAccessChannel = MethodChannel('dev.milanko.dartpdf/file_access');

/// A [PdfByteSource] over a sandboxed macOS file addressed by a security-scoped
/// bookmark, reading ranges through the native runner (`readFileRange`).
///
/// Sandboxed macOS reopens (OneDrive/iCloud/Dropbox folders reached across app
/// launches) can only be read after reactivating their security scope from a
/// bookmark - something a raw `RandomAccessFile` cannot do. This source is the
/// bookmark-aware sibling of [PdfFileByteSource]: each [readRange] re-resolves
/// the bookmark natively, so the progressive loader (and the background full
/// read) fetch only the bytes they need from a cloud-synced file instead of
/// hydrating and slurping the whole thing.
///
/// Ranged native calls carry a per-request copy across the channel, so callers
/// should read in reasonably large chunks (the loader coalesces object ranges;
/// the background full read uses multi-MB chunks). Pass a [PdfCancelToken] to
/// abort, and [onProgress] to observe the running byte total.
class PdfBookmarkFileByteSource implements PdfByteSource {
  PdfBookmarkFileByteSource({
    required this.bookmark,
    this.cancelToken,
    this.onProgress,
    @visibleForTesting MethodChannel? channel,
  }) : _channel = channel ?? _fileAccessChannel;

  /// Base64 security-scoped bookmark for the file (see `securityBookmarkForPath`).
  final String bookmark;

  /// Optional cooperative cancellation. A fired token makes pending and later
  /// reads throw [PdfHttpCancelledException].
  final PdfCancelToken? cancelToken;

  /// Called after each read with the running total of bytes pulled and the
  /// file length once known.
  final void Function(int received, int? total)? onProgress;

  final MethodChannel _channel;
  int? _length;
  int _received = 0;

  @override
  Future<int?> get length async {
    cancelToken?.throwIfCancelled();
    if (_length != null) return _length;
    final len = await _channel.invokeMethod<int>('fileLength', {
      'bookmark': bookmark,
    });
    return _length = len;
  }

  @override
  Future<Uint8List> readRange(int start, int endExclusive) async {
    cancelToken?.throwIfCancelled();
    final s = start < 0 ? 0 : start;
    if (endExclusive <= s) return Uint8List(0);
    final data = await _channel.invokeMethod<Uint8List>('readFileRange', {
      'bookmark': bookmark,
      'offset': s,
      'length': endExclusive - s,
    });
    cancelToken?.throwIfCancelled();
    final bytes = data ?? Uint8List(0);
    _received += bytes.length;
    onProgress?.call(_received, _length);
    return bytes;
  }

  @override
  Future<void> close() async {}
}
