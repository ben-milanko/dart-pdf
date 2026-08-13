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
/// Reuse is **byte-identical to decoding again**, which is the whole safety
/// argument, and it is reached two ways:
///
///  * Exact match - the same stream at the same requested target size.
///  * Downsampled from a **native-resolution** entry, but only for streams
///    whose decoder ignores the target anyway ([pdfImageDecodeIgnoresTarget] -
///    in practice DCTDecode). For those, `decodePdfImage(target)` already *is*
///    `downsamplePdfDecodedPixels(decodePdfImagePixels(...), tw, th)`, so
///    doing it from a retained native decode produces the same bytes.
///
/// The native-entry restriction is load-bearing: downsampling an entry that
/// was itself a downsample would not equal downsampling the native pixels.
/// Formats with a genuinely scaled decode path (Flate, CCITT, JPX reduced
/// levels) keep the exact-match rule, because serving them from a downsample
/// would substitute different pixels for the ones their decoder produces.
///
/// The second route is what makes the cache useful in production: a page's
/// repeat records are a full-page pass and a 128px thumbnail tile, at
/// *different* image pixel ratios by construction, so exact match alone almost
/// never fires on the records that matter.
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
    _evict();
    return decoded;
  }

  /// A retained decode for [stream] at this exact size, or null. For callers
  /// whose decode is asynchronous (the web worker's browser-codec pass), which
  /// cannot run through [decode]'s synchronous callback.
  PdfDecodedPixels? get(CosStream stream, int? width, int? height) {
    final key = _Key(stream, width, height);
    final hit = _entries.remove(key);
    if (hit == null) {
      _misses++;
      return null;
    }
    _entries[key] = hit;
    _hits++;
    return hit;
  }

  /// Retains [pixels] for [stream] at this size. Pairs with [get].
  void put(CosStream stream, int? width, int? height, PdfDecodedPixels pixels) {
    final size = pixels.rgba.length;
    if (size > maxBytes) return;
    final key = _Key(stream, width, height);
    final existing = _entries.remove(key);
    if (existing != null) _bytes -= existing.rgba.length;
    _entries[key] = pixels;
    _bytes += size;
    _evict();
  }

  void _evict() {
    while (_bytes > maxBytes && _entries.isNotEmpty) {
      final oldest = _entries.keys.first;
      _bytes -= _entries.remove(oldest)!.rgba.length;
    }
  }

  void clear() {
    _entries.clear();
    _bytes = 0;
  }
}

/// A stream at one requested size. [CosStream] has no `==`, so this keys by
/// object identity - which is what we want: the same loaded stream object,
/// not a re-read of the same bytes.
/// Whether decoding [stream] at a reduced target size costs the same as
/// decoding it whole - i.e. the decoder has no scaled fast path for it and
/// falls back to a full decode plus [downsamplePdfDecodedPixels].
///
/// True for DCTDecode except four-component JPEGs. A CMYK DCT still performs
/// entropy/IDCT at native resolution, but [decodePdfImageBase] reduces its
/// component plane before the expensive PDF colour conversion and mask
/// composite. Its target result is therefore both cheaper and intentionally
/// distinct from RGBA-downsampling a native composite.
///
/// Callers use it to decide whether a retained *native* decode may be
/// downsampled to serve a smaller request. Where it is false, doing so would
/// change pixels; where it is true, it is exactly what the decoder does.
bool pdfImageDecodeIgnoresTarget(CosDocument cos, CosStream stream) =>
    pdfImageFilters(cos, stream.dictionary).contains('DCTDecode') &&
    pdfImageColorFamily(cos, stream.dictionary) != 'DeviceCMYK';

/// Whether [stream] has no source-region entropy path.
///
/// CMYK DCT can honour a whole-image target, but it still has to decode the
/// full JPEG before cropping a deep-zoom slice. Region reuse therefore keeps a
/// native decode even though ordinary target-size caching does not.
bool pdfImageDecodeIgnoresRegion(CosDocument cos, CosStream stream) =>
    pdfImageFilters(cos, stream.dictionary).contains('DCTDecode');

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
