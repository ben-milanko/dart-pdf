import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The method channel the Android/iOS runners expose for reference-based mobile
/// file access: a custom document picker that hands back a *reference* to the
/// user's file (a persisted `content://` URI on Android, a security-scoped
/// bookmark on iOS) rather than a whole-file copy, plus ranged reads over that
/// reference. Shared verbatim with `file_io.dart`.
const mobileFileChannel = MethodChannel('dev.milanko.dartpdf/mobile_file');

/// A [PdfByteSource] over a phone/tablet file addressed by an opaque native
/// [token], reading ranges through the runner (`readRange`).
///
/// The OS document pickers (`file_selector` under the hood) copy the *entire*
/// picked file into an app-sandbox temp location before the app sees a byte -
/// so for a OneDrive/iCloud/Drive file the whole cloud transport is paid inside
/// the picker, before app-level ranged open can intercept it (#364). This
/// source is the mobile counterpart of `PdfBookmarkFileByteSource`: the runner
/// keeps a reference to the *original* file (Android `ACTION_OPEN_DOCUMENT`
/// `content://` Uri with persisted read permission; iOS
/// `UIDocumentPickerViewController` in `.open` mode's security-scoped URL) and
/// serves byte ranges from it on demand, so the progressive loader (and the
/// background full read) fetch only the bytes they need instead of hydrating
/// and slurping the whole thing up front.
///
/// A per-provider caveat drives the design: many cloud providers hand SAF a
/// *non-seekable* `ParcelFileDescriptor` (a pipe), so random access is
/// impossible for exactly the providers this targets. The runner probes
/// seekability up front (`probeSeekable`); the app only opens progressively
/// through this source when the probe passes, and otherwise streams the
/// reference whole - the same cost as the old picker copy, never worse. See
/// `file_io.dart`'s `pickPdfMobileReferences`.
///
/// Ranged native calls carry a per-request copy across the channel, so callers
/// should read in reasonably large chunks (the loader coalesces object ranges;
/// the background full read uses multi-MB chunks). Pass a [PdfCancelToken] to
/// abort, and [onProgress] to observe the running byte total.
class PdfMobileByteSource implements PdfByteSource {
  PdfMobileByteSource(
    this.token, {
    this.cancelToken,
    this.onProgress,
    @visibleForTesting MethodChannel? channel,
  }) : _channel = channel ?? mobileFileChannel;

  /// Opaque native reference to the picked file (see [pickPdfMobileReferences]).
  final String token;

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
      'token': token,
    });
    // A negative length means "unknown" on the native side; normalize to null
    // so the loader falls back to a plain sequential read.
    return _length = (len != null && len >= 0) ? len : null;
  }

  @override
  Future<Uint8List> readRange(int start, int endExclusive) async {
    cancelToken?.throwIfCancelled();
    final s = start < 0 ? 0 : start;
    if (endExclusive <= s) return Uint8List(0);
    final data = await _channel.invokeMethod<Uint8List>('readRange', {
      'token': token,
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
