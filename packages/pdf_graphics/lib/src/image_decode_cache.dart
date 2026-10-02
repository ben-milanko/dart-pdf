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
/// Luminosity masks (the images a `/SMask /S /Luminosity` group draws) take
/// the second route for **every** format. Their decode ignores target and
/// region whatever the filter: `decodePdfImage(luminosityMask: true)` is
/// `decodePdfImagePixels(luminosityMask: true)` followed by the same crop or
/// downsample. So the codec keeps one native-resolution luminosity entry per
/// stream and crops or downsamples it per record. A luminosity decode reads
/// the raw samples through a gray LUT, not the page colour pipeline (a PDF/X
/// OutputIntent would manage an ordinary DeviceGray image), so it is a
/// different picture of the same stream: [decode]'s `luminosityMask` is part
/// of the key, and the two never serve each other.
///
/// Ownership is the caller's: pass one per open document (a worker holds its
/// document for the session, and `CosDocument` memoises loaded objects, so
/// stream identity is stable across records). Keys hold the [CosStream], so a
/// cache outliving its document pins those streams - drop it with the document.
class PdfImageDecodeCache {
  /// [maxBytes] is the budget; [maxTransientEntryBytes] (default 2 MB) is the
  /// largest decode a caller that is not `reusable` may retain.
  PdfImageDecodeCache({this.maxBytes = 64 << 20, int? maxTransientEntryBytes})
      : maxTransientEntryBytes = maxTransientEntryBytes ?? 2 << 20;

  /// Decoded RGBA bytes retained before the least-recently-used entry is
  /// dropped. One 2 MP image is ~8 MB, so the default holds a working set of a
  /// few heavy pages without competing with the viewer's own image cache.
  /// A render worker sizes it per platform (`PdfRenderWorker` init).
  final int maxBytes;

  /// The largest decode retained for a call that is not `reusable`.
  ///
  /// Admission is the caller's call, because only the call site knows what a
  /// decode is good for. A **reusable** decode serves requests other than the
  /// one that made it: a native-resolution DCT decode that every target size
  /// and every deep-zoom region crops or downsamples, a luminosity mask, a
  /// browser-codec decode, any native-resolution decode (it serves every
  /// record at or past native size). The rest - a decode at one exact target
  /// size - only ever serve a repeat of the same record at the same ratio,
  /// which the host's record cache (in front of every worker) mostly answers
  /// already. They still earn their keep as small repeated images (a logo on every page), so
  /// they are admitted below this size and never displace a reusable entry.
  final int maxTransientEntryBytes;

  /// The largest single reusable decode retained past [maxBytes], alone, as
  /// the most recently used entry: the old flat budget, so a smaller budget
  /// never holds more than it would have. Without it a mobile budget would
  /// refuse an 8 MP+ JPEG outright and every deep-zoom tile of that page would
  /// repeat its whole decode.
  static const int maxOversizeEntryBytes = 64 << 20;

  // Insertion-ordered, and re-inserted on every hit, so the first key is the
  // least recently used. Dart's LinkedHashMap makes that free.
  final _entries = <_Key, _Entry>{};
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
  /// [luminosityMask] marks a luminosity-mask decode of [stream], which is
  /// keyed apart from its ordinary decode. [reusable] says whether the decode
  /// serves requests other than this one (see [maxTransientEntryBytes]).
  ///
  /// [decode] is not called on a hit. A null result is not cached - a decline
  /// is cheap to rediscover and caching it would pin the failure across a
  /// document edit.
  PdfDecodedPixels? decode(
    CosStream stream,
    int? targetWidth,
    int? targetHeight,
    PdfDecodedPixels? Function() decode, {
    bool luminosityMask = false,
    bool reusable = true,
  }) {
    final key = _Key(stream, targetWidth, targetHeight, luminosityMask);
    final hit = _entries.remove(key);
    if (hit != null) {
      _entries[key] = hit; // most recently used
      _hits++;
      return hit.pixels;
    }
    _misses++;
    final decoded = decode();
    if (decoded == null) return null;
    _admit(key, decoded, reusable);
    return decoded;
  }

  /// A retained decode for [stream] at this exact size, or null. For callers
  /// whose decode is asynchronous (the web worker's browser-codec pass), which
  /// cannot run through [decode]'s synchronous callback.
  PdfDecodedPixels? get(CosStream stream, int? width, int? height) {
    final key = _Key(stream, width, height, false);
    final hit = _entries.remove(key);
    if (hit == null) {
      _misses++;
      return null;
    }
    _entries[key] = hit;
    _hits++;
    return hit.pixels;
  }

  /// Retains [pixels] for [stream] at this size. Pairs with [get]; [reusable]
  /// as for [decode].
  void put(CosStream stream, int? width, int? height, PdfDecodedPixels pixels,
      {bool reusable = true}) {
    final key = _Key(stream, width, height, false);
    final existing = _entries.remove(key);
    if (existing != null) _bytes -= existing.pixels.rgba.length;
    _admit(key, pixels, reusable);
  }

  void _admit(_Key key, PdfDecodedPixels pixels, bool reusable) {
    final size = pixels.rgba.length;
    if (!reusable) {
      if (size > maxTransientEntryBytes || size > maxBytes) return;
      // A transient entry only displaces other transient entries, least
      // recently used first, so a page of small target-sized images can never
      // push out the native decode deep zoom is cropping. When that cannot
      // make room it is not admitted, and nothing is evicted for it.
      var excess = _bytes + size - maxBytes;
      List<_Key>? victims;
      if (excess > 0) {
        for (final MapEntry(key: victimKey, value: entry) in _entries.entries) {
          if (entry.reusable) continue;
          (victims ??= []).add(victimKey);
          excess -= entry.pixels.rgba.length;
          if (excess <= 0) break;
        }
        if (excess > 0) return;
        for (final victim in victims!) {
          _bytes -= _entries.remove(victim)!.pixels.rgba.length;
        }
      }
    } else if (size > maxBytes && size > maxOversizeEntryBytes) {
      // One reusable decode may sit past the budget as the newest entry (see
      // [maxOversizeEntryBytes]); anything bigger stays out rather than let one
      // underlay own the cache.
      return;
    }
    _entries[key] = _Entry(pixels, reusable);
    _bytes += size;
    // A reusable entry displaces anything, least recently used first, but
    // never itself: alone, it is the oversize allowance.
    while (_bytes > maxBytes) {
      final oldest = _entries.keys.first;
      if (identical(oldest, key)) break;
      _bytes -= _entries.remove(oldest)!.pixels.rgba.length;
    }
  }

  /// Drops every retained decode (a revision re-open, or a memory-pressure
  /// trim). Keeps the counters and the object: diagnostics hold on to it.
  void clear() {
    _entries.clear();
    _bytes = 0;
  }
}

class _Entry {
  const _Entry(this.pixels, this.reusable);
  final PdfDecodedPixels pixels;
  final bool reusable;
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
  const _Key(this.stream, this.width, this.height, this.luminosityMask);
  final CosStream stream;
  final int? width;
  final int? height;
  final bool luminosityMask;

  @override
  bool operator ==(Object other) =>
      other is _Key &&
      identical(other.stream, stream) &&
      other.width == width &&
      other.height == height &&
      other.luminosityMask == luminosityMask;

  @override
  int get hashCode =>
      Object.hash(identityHashCode(stream), width, height, luminosityMask);
}
