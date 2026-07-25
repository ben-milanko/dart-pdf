import 'package:pdf_cos/pdf_cos.dart';

import 'image_pixels.dart';

/// Remembers decoded image pixels between `serializeCommands` calls, so a page
/// recorded more than once does not pay its image decode more than once.
///
/// A render worker records the same page repeatedly within one scroll - the
/// vector-first pass, the full pass, a prerender warm, a thumbnail tile - and
/// each `serializeCommands` call decoded every image from scratch. A device
/// trace (#451) showed one page paying ~900 ms of pure-Dart decode three times
/// in a single scroll, and ~6.9 s of such decodes across seven records, every
/// one of them a `DeviceCMYK` JPEG the browser codec declined.
///
/// The cache is deliberately **exact-match**: an entry is reused only for the
/// same stream at the same requested target size. It never downsamples one
/// entry to serve a smaller request, because for the formats that have a
/// genuinely scaled decode path (Flate, CCITT, JPX reduced levels) that would
/// substitute a different - and slightly different-looking - set of pixels for
/// the one the decoder would have produced. Reuse here is byte-identical to
/// decoding again, so the cache can never change what a record renders.
///
/// Ownership is the caller's: pass one per open document (a worker holds its
/// document for the session, and `CosDocument` memoises loaded objects, so
/// stream identity is stable across records). Keys hold the [CosStream], so a
/// cache outliving its document pins those streams - drop it with the document.
class PdfImageDecodeCache {
  PdfImageDecodeCache({this.maxBytes = 64 << 20});

  /// Decoded RGBA bytes retained before the least-recently-used entry is
  /// dropped. One 2 MP image is ~8 MB, so the default holds a working set of a
  /// few heavy pages without competing with the viewer's own image cache.
  final int maxBytes;

  // Insertion-ordered, and re-inserted on every hit, so the first key is the
  // least recently used. Dart's LinkedHashMap makes that free.
  final _entries = <_Key, PdfDecodedPixels>{};
  int _bytes = 0;
  int _hits = 0;
  int _misses = 0;

  /// Decoded pixels retained for [stream] at this exact target size, or null.
  int get hits => _hits;
  int get misses => _misses;
  int get bytes => _bytes;
  int get length => _entries.length;

  /// Returns the pixels [decode] produces for [stream] at
  /// [targetWidth]x[targetHeight], reusing a retained decode when one matches
  /// exactly. A null target means "native resolution", which is its own key.
  ///
  /// [decode] is not called on a hit. A null result is not cached - a decline
  /// is cheap to rediscover and caching it would pin the failure across a
  /// document edit.
  PdfDecodedPixels? decode(
    CosStream stream,
    int? targetWidth,
    int? targetHeight,
    PdfDecodedPixels? Function() decode,
  ) {
    final key = _Key(stream, targetWidth, targetHeight);
    final hit = _entries.remove(key);
    if (hit != null) {
      _entries[key] = hit; // most recently used
      _hits++;
      return hit;
    }
    _misses++;
    final decoded = decode();
    if (decoded == null) return null;
    final size = decoded.rgba.length;
    // An image larger than the whole budget would evict everything and then
    // sit alone; keep it out rather than let one underlay own the cache.
    if (size > maxBytes) return decoded;
    _entries[key] = decoded;
    _bytes += size;
    while (_bytes > maxBytes && _entries.isNotEmpty) {
      final oldest = _entries.keys.first;
      _bytes -= _entries.remove(oldest)!.rgba.length;
    }
    return decoded;
  }

  void clear() {
    _entries.clear();
    _bytes = 0;
  }
}

/// A stream at one requested size. [CosStream] has no `==`, so this keys by
/// object identity - which is what we want: the same loaded stream object,
/// not a re-read of the same bytes.
class _Key {
  const _Key(this.stream, this.width, this.height);
  final CosStream stream;
  final int? width;
  final int? height;

  @override
  bool operator ==(Object other) =>
      other is _Key &&
      identical(other.stream, stream) &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(identityHashCode(stream), width, height);
}
