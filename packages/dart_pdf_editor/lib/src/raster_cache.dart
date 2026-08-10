import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:pdf_document/pdf_document.dart';

import 'tile_store.dart';

/// Serialized representation of a full-resolution page raster on disk.
///
/// Neither choice dominates - see the encoding measurements in
/// `test/benchmark_full_raster_disk_test.dart` and the summary in
/// doc/dev-log/2026-07-29-persistent-full-raster-disk-tier.md:
///
///  * [png] is 3-15x smaller on vector/CAD and form pages (large flat areas
///    compress hard), so far more pages fit a given byte budget - at the cost
///    of a real encode on the store path and a real decode on the load path.
///  * [rawRgba] is `width * height * 4` bytes with no compression work at all.
///    On photo/scan pages, where PNG barely compresses, it is both smaller in
///    CPU and competitive in size, and its decode is a straight buffer upload.
///
/// [png] is the default because the byte budget, not the CPU, is what usually
/// bounds how much of a document survives to the next session.
enum PdfRasterDiskFormat {
  /// Lossless PNG via [ui.ImageByteFormat.png].
  png,

  /// Uncompressed premultiplied RGBA via [ui.ImageByteFormat.rawRgba].
  rawRgba,
}

/// Counters for the persistent full-raster tier: whether it is paying for
/// itself, and what it costs.
///
/// Shared by every [PdfRasterCache.forDocument] view of one cache, so a host
/// reads one object for the whole session. Counters are plain ints; the
/// latency totals are microseconds measured only around the encode/decode
/// calls themselves.
class PdfRasterCacheStats {
  int _hits = 0;
  int _misses = 0;
  int _stores = 0;
  int _rejects = 0;
  int _errors = 0;
  int _bytesRead = 0;
  int _bytesWritten = 0;
  int _encodeMicros = 0;
  int _decodeMicros = 0;

  /// Disk lookups that produced a usable raster.
  int get hits => _hits;

  /// Disk lookups that found nothing (or nothing valid).
  int get misses => _misses;

  /// Rasters written to the store.
  int get stores => _stores;

  /// Stores declined before any I/O (tier disabled, no document key, an
  /// encode that produced nothing).
  int get rejects => _rejects;

  /// Corrupt payloads, failed encodes/decodes, and backend exceptions - each
  /// one degraded to an ordinary render.
  int get errors => _errors;

  /// Bytes handed back by successful loads.
  int get bytesRead => _bytesRead;

  /// Bytes handed to the store by successful stores.
  int get bytesWritten => _bytesWritten;

  /// Total microseconds spent encoding rasters for storage.
  int get encodeMicros => _encodeMicros;

  /// Total microseconds spent decoding stored rasters.
  int get decodeMicros => _decodeMicros;

  /// Mean encode microseconds per stored raster (0 with no stores).
  double get meanEncodeMicros => _stores == 0 ? 0 : _encodeMicros / _stores;

  /// Mean decode microseconds per hit (0 with no hits).
  double get meanDecodeMicros => _hits == 0 ? 0 : _decodeMicros / _hits;

  /// Clears every counter (a benchmark opening a fresh measurement window).
  void reset() {
    _hits = 0;
    _misses = 0;
    _stores = 0;
    _rejects = 0;
    _errors = 0;
    _bytesRead = 0;
    _bytesWritten = 0;
    _encodeMicros = 0;
    _decodeMicros = 0;
  }

  @override
  String toString() => 'full-raster disk hits=$_hits misses=$_misses '
      'stores=$_stores rejects=$_rejects errors=$_errors '
      'bytesRead=$_bytesRead bytesWritten=$_bytesWritten '
      'encodeUs=$_encodeMicros decodeUs=$_decodeMicros';
}

/// Persists low-resolution page rasters to a [PdfDiskCache] so a document
/// reopened in a later session shows soft page content immediately -
/// instead of blank paper - while the (heavy, twice-over-the-content-
/// stream) full render computes.
///
/// This is the raster half of the library's on-disk caching, layered on the
/// same pluggable [PdfCacheStore] seam as the text cache. The primary cache
/// stores small page previews. Hosts may also provide independent byte-budgeted
/// stores for exact page rasters and LoD tiles. Keeping the three workloads in
/// separate namespaces prevents a handful of large page images from evicting
/// the previews that make cold navigation resilient. Rasters are encoded as
/// PNG via [ui.Image] (no extra dependency) and decoded with
/// [ui.instantiateImageCodec].
///
/// A cache is bound to one document via [documentKey]; call [forDocument]
/// to derive a view for the currently-open file (its [pdfContentKey], or
/// a host-supplied stable id). With an empty key every operation no-ops,
/// so an un-bound cache is harmless.
class PdfRasterCache implements PdfTilePersistence {
  PdfRasterCache(
    this.cache, {
    this.documentKey = '',
    this.fullRasters,
    this.tiles,
    this.fullRasterFormat = PdfRasterDiskFormat.png,
    PdfRasterCacheStats? fullRasterStats,
    PdfRasterCacheStats? tileStats,
  })  : fullRasterStats = fullRasterStats ?? PdfRasterCacheStats(),
        tileStats = tileStats ?? PdfRasterCacheStats();

  /// The byte store these rasters persist into.
  final PdfDiskCache cache;

  /// Identifies the document these rasters belong to; empty disables I/O.
  final String documentKey;

  /// Optional persistent tier for **exact full-resolution page rasters**
  /// (issue #615). Host opt-in and deliberately a *separate* [PdfDiskCache]:
  /// full rasters are two to three orders of magnitude larger than a preview,
  /// so sharing one budget would let a handful of page images evict the whole
  /// preview/thumbnail set that makes cold navigation resilient. Give it its
  /// own namespace and its own [PdfDiskCache.maxBytes]:
  ///
  /// ```dart
  /// PdfRasterCache(
  ///   PdfDiskCache(store, namespace: 'previews', maxBytes: 64 << 20),
  ///   fullRasters: PdfDiskCache(store,
  ///       namespace: 'page-rasters', version: '1', maxBytes: 512 << 20),
  /// )
  /// ```
  ///
  /// Null (the default) leaves full rasters memory-only, exactly as before.
  final PdfDiskCache? fullRasters;

  /// Optional persistent tier for LoD tiles. Keep this separate from previews
  /// and full-page rasters so each workload has an independent byte budget.
  /// Tile reads race the live raster path and writes happen after admission,
  /// so enabling this tier never blocks a cache miss from rendering.
  final PdfDiskCache? tiles;

  /// How full rasters are serialized (see [PdfRasterDiskFormat]).
  final PdfRasterDiskFormat fullRasterFormat;

  /// Diagnostics for the full-raster tier, shared across [forDocument] views.
  final PdfRasterCacheStats fullRasterStats;

  /// Diagnostics for the persistent tile tier.
  final PdfRasterCacheStats tileStats;

  /// A view of this cache bound to [documentKey] - share one underlying
  /// [PdfDiskCache] (and its byte budget) across every document the
  /// session opens.
  PdfRasterCache forDocument(String documentKey) => PdfRasterCache(
        cache,
        documentKey: documentKey,
        fullRasters: fullRasters,
        tiles: tiles,
        fullRasterFormat: fullRasterFormat,
        fullRasterStats: fullRasterStats,
        tileStats: tileStats,
      );

  /// Whether exact full-resolution rasters can be read and written right now
  /// (the host wired [fullRasters] *and* the view is bound to a document).
  bool get storesFullRasters => fullRasters != null && documentKey.isNotEmpty;

  /// Whether LoD tiles can be read and written for this bound document.
  bool get storesTiles => tiles != null && documentKey.isNotEmpty;

  static const String tileVersion = '1';

  String _tileKey(PdfTileKey key, ui.Rect region, double pixelRatio, int width,
      int height) {
    final id = key.id;
    final plan = id.plan;
    final color = plan.pageColor
        .toARGB32()
        .toUnsigned(32)
        .toRadixString(16)
        .padLeft(8, '0');
    return '$documentKey/lod$tileVersion/'
        '${id.pageEpoch}.${id.contentStamp}.${id.destructiveStamp}/'
        '${id.pageIndex}/$color/${plan.annotations ? 'annots' : 'noannots'}'
        '/r${plan.rotation ?? 0}/${key.rung}/${key.tx}.${key.ty}'
        '/${pixelRatio.toStringAsFixed(8)}/${width}x$height'
        '/${region.left},${region.top},${region.right},${region.bottom}';
  }

  @override
  Future<ui.Image?> loadTile(
    PdfTileKey key, {
    required ui.Rect region,
    required double pixelRatio,
    required int width,
    required int height,
  }) async {
    final disk = tiles;
    final stats = tileStats;
    if (disk == null || documentKey.isEmpty) return null;
    try {
      final bytes =
          await disk.read(_tileKey(key, region, pixelRatio, width, height));
      if (bytes == null) {
        stats._misses++;
        return null;
      }
      final sw = Stopwatch()..start();
      final codec = await ui.instantiateImageCodec(bytes);
      try {
        final frame = await codec.getNextFrame();
        final image = frame.image;
        if (image.width != width || image.height != height) {
          image.dispose();
          stats._errors++;
          stats._misses++;
          return null;
        }
        stats._hits++;
        stats._bytesRead += bytes.length;
        stats._decodeMicros += sw.elapsedMicroseconds;
        return image;
      } finally {
        codec.dispose();
      }
    } catch (_) {
      stats._errors++;
      stats._misses++;
      return null;
    }
  }

  @override
  Future<void> storeTile(
    PdfTileKey key,
    ui.Image image, {
    required ui.Rect region,
    required double pixelRatio,
  }) async {
    final disk = tiles;
    final stats = tileStats;
    if (disk == null || documentKey.isEmpty) {
      stats._rejects++;
      return;
    }
    // clone() is synchronous and shares the engine handle, keeping pixels
    // alive if the in-memory LRU evicts the master during PNG readback.
    final retained = image.clone();
    final width = retained.width;
    final height = retained.height;
    try {
      final sw = Stopwatch()..start();
      final data = await retained.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) {
        stats._rejects++;
        return;
      }
      final bytes =
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      stats._encodeMicros += sw.elapsedMicroseconds;
      await disk.write(_tileKey(key, region, pixelRatio, width, height), bytes);
      stats._stores++;
      stats._bytesWritten += bytes.length;
    } catch (_) {
      stats._errors++;
    } finally {
      retained.dispose();
    }
  }

  /// Empties the persistent LoD tile tier. Previews and exact full-page
  /// rasters use different stores and are untouched.
  Future<void> clearTiles() async => tiles?.clear();

  String _key(int pageIndex) => '$documentKey/$pageIndex';

  // Page thumbnails persist under a resolution-tagged namespace, distinct
  // from the low-res previews above: the page grid and strip render sharper,
  // size-bucketed rasters, and several sizes can coexist for one page.
  String _thumbKey(int pageIndex, int pixelWidth,
      {int pageColor = 0xFFFFFFFF, bool annotations = true}) {
    final color = pageColor.toUnsigned(32).toRadixString(16).padLeft(8, '0');
    return '$documentKey/t$pixelWidth/$color/${annotations ? 'annots' : 'noannots'}/$pageIndex';
  }

  /// The stored thumbnail for [pageIndex] at the [pixelWidth] bucket, decoded
  /// to a [ui.Image] the caller owns (and must dispose), or null on a miss /
  /// decode failure. Lets the page grid open onto already-rendered thumbnails
  /// in a later session instead of re-interpreting every page.
  Future<ui.Image?> loadThumbnail(int pageIndex, int pixelWidth,
      {int pageColor = 0xFFFFFFFF, bool annotations = true}) async {
    if (documentKey.isEmpty) return null;
    final bytes = await cache.read(_thumbKey(pageIndex, pixelWidth,
        pageColor: pageColor, annotations: annotations));
    if (bytes == null) return null;
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      try {
        final frame = await codec.getNextFrame();
        return frame.image;
      } finally {
        codec.dispose();
      }
    } catch (_) {
      return null;
    }
  }

  /// Encodes [image] as PNG and writes it as [pageIndex]'s thumbnail at the
  /// [pixelWidth] bucket. Best-effort and fire-and-forget at the call sites;
  /// [image] stays owned by the caller.
  Future<void> storeThumbnail(int pageIndex, int pixelWidth, ui.Image image,
      {int pageColor = 0xFFFFFFFF, bool annotations = true}) async {
    if (documentKey.isEmpty) return;
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) return;
      await cache.write(
          _thumbKey(pageIndex, pixelWidth,
              pageColor: pageColor, annotations: annotations),
          data.buffer.asUint8List());
    } catch (_) {
      // a readback can fail mid page-swap; a missing thumbnail just renders
      // fresh as it did before this cache
    }
  }

  /// The stored preview for [pageIndex] decoded to a [ui.Image] the caller
  /// owns (and must dispose), or null on a miss / decode failure.
  Future<ui.Image?> loadPreview(int pageIndex) async {
    if (documentKey.isEmpty) return null;
    final bytes = await cache.read(_key(pageIndex));
    if (bytes == null) return null;
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      try {
        final frame = await codec.getNextFrame();
        return frame.image;
      } finally {
        codec.dispose();
      }
    } catch (_) {
      return null;
    }
  }

  /// Encodes [image] as PNG and writes it as [pageIndex]'s preview.
  /// Best-effort and fire-and-forget at the call sites; [image] stays
  /// owned by the caller.
  Future<void> storePreview(int pageIndex, ui.Image image) async {
    if (documentKey.isEmpty) return;
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) return;
      await cache.write(_key(pageIndex), data.buffer.asUint8List());
    } catch (_) {
      // a readback can fail mid page-swap; a missing preview just means
      // the page renders blank-then-full as it did before this cache
    }
  }

  /// Reads the raw stored PNG bytes for [pageIndex] (test hook / advanced
  /// callers that decode themselves).
  Future<Uint8List?> readBytes(int pageIndex) =>
      documentKey.isEmpty ? Future.value(null) : cache.read(_key(pageIndex));

  // --- exact full-resolution rasters (#615) --------------------------------

  /// Generation of the stored full-raster payload *and* of the renderer that
  /// produced the pixels. Bump it whenever either changes meaning: it is part
  /// of the key, so old entries simply stop matching and age out of the LRU.
  static const String fullRasterVersion = '1';

  // 20-byte container header. Everything a decode needs to reject a payload
  // it must not hand to the compositor lives here rather than being inferred
  // from the key, so a truncated write, a store that returns another entry's
  // bytes, or a key collision is a miss instead of a garbled page.
  static const int _magic = 0x50524153; // 'PRAS'
  static const int _headerBytes = 20;

  /// The persistent key for one exact page raster.
  ///
  /// Every input that changes the baked pixels is in it: the document
  /// ([documentKey]), the payload/renderer generation ([fullRasterVersion]),
  /// the page's content [revision] (so an edited or redacted page cannot load
  /// a stale-by-index raster), the page index, the physical raster size, the
  /// paper colour, annotation visibility, and rotation. Anything that differs
  /// is a different key, hence a miss.
  String fullRasterKey(
    int pageIndex, {
    required int width,
    required int height,
    required int pageColor,
    required bool annotations,
    required int? rotation,
    String revision = '',
  }) {
    final color = pageColor.toUnsigned(32).toRadixString(16).padLeft(8, '0');
    return '$documentKey/f$fullRasterVersion/${revision.isEmpty ? '-' : revision}'
        '/$pageIndex/${width}x$height/$color'
        '/${annotations ? 'annots' : 'noannots'}/r${rotation ?? 0}';
  }

  /// The stored exact raster for [pageIndex] at exactly [width] x [height],
  /// decoded into a [ui.Image] the caller owns (and must dispose), or null on
  /// any miss: absent entry, corrupt payload, dimension disagreement, decode
  /// failure, or a throwing backend. Every one of those degrades to an
  /// ordinary render.
  Future<ui.Image?> loadFullRaster(
    int pageIndex, {
    required int width,
    required int height,
    required int pageColor,
    required bool annotations,
    required int? rotation,
    String revision = '',
  }) async {
    final disk = fullRasters;
    if (disk == null || documentKey.isEmpty) return null;
    final stats = fullRasterStats;
    Uint8List? bytes;
    try {
      bytes = await disk.read(fullRasterKey(
        pageIndex,
        width: width,
        height: height,
        pageColor: pageColor,
        annotations: annotations,
        rotation: rotation,
        revision: revision,
      ));
    } catch (_) {
      // PdfDiskCache already swallows backend failures; belt and braces for a
      // store that throws synchronously out of its own Future.
      stats._errors++;
      stats._misses++;
      return null;
    }
    if (bytes == null) {
      stats._misses++;
      return null;
    }
    final sw = Stopwatch()..start();
    try {
      final image = await _decodeFullRaster(bytes, width, height);
      sw.stop();
      if (image == null) {
        // A payload that exists but cannot be trusted is both an error (worth
        // seeing in diagnostics) and a miss (the caller renders normally).
        stats._errors++;
        stats._misses++;
        return null;
      }
      stats._hits++;
      stats._bytesRead += bytes.length;
      stats._decodeMicros += sw.elapsedMicroseconds;
      return image;
    } catch (_) {
      stats._errors++;
      stats._misses++;
      return null;
    }
  }

  /// Encodes [image] and stores it as [pageIndex]'s exact raster.
  ///
  /// Callers treat this as fire-and-forget background work: it performs a GPU
  /// readback plus (for [PdfRasterDiskFormat.png]) a compression pass, and
  /// must never sit between a completed render and the frame that shows it.
  /// [image] stays owned by the caller.
  Future<void> storeFullRaster(
    int pageIndex,
    ui.Image image, {
    required int pageColor,
    required bool annotations,
    required int? rotation,
    String revision = '',
  }) async {
    final disk = fullRasters;
    final stats = fullRasterStats;
    if (disk == null || documentKey.isEmpty) {
      stats._rejects++;
      return;
    }
    final width = image.width;
    final height = image.height;
    try {
      final sw = Stopwatch()..start();
      final payload = await _encodeFullRaster(image);
      sw.stop();
      if (payload == null) {
        stats._rejects++;
        return;
      }
      stats._encodeMicros += sw.elapsedMicroseconds;
      await disk.write(
        fullRasterKey(
          pageIndex,
          width: width,
          height: height,
          pageColor: pageColor,
          annotations: annotations,
          rotation: rotation,
          revision: revision,
        ),
        payload,
      );
      stats._stores++;
      stats._bytesWritten += payload.length;
    } catch (_) {
      // A readback can fail mid page-swap and a store can hit a quota wall;
      // a missing entry only means the page renders as it did before.
      stats._errors++;
    }
  }

  /// Empties the persistent full-raster tier. Previews and thumbnails (a
  /// different [PdfDiskCache]) are untouched.
  ///
  /// Hosts must expose this somewhere: page rasters are pixel-exact copies of
  /// document content, and a PDF may hold material a user needs gone.
  Future<void> clearFullRasters() async => fullRasters?.clear();

  /// Raw stored bytes for one exact raster (test hook).
  Future<Uint8List?> readFullRasterBytes(
    int pageIndex, {
    required int width,
    required int height,
    int pageColor = 0xFFFFFFFF,
    bool annotations = true,
    int? rotation,
    String revision = '',
  }) async {
    final disk = fullRasters;
    if (disk == null || documentKey.isEmpty) return null;
    return disk.read(fullRasterKey(
      pageIndex,
      width: width,
      height: height,
      pageColor: pageColor,
      annotations: annotations,
      rotation: rotation,
      revision: revision,
    ));
  }

  Future<Uint8List?> _encodeFullRaster(ui.Image image) async {
    final data = await image.toByteData(
      format: fullRasterFormat == PdfRasterDiskFormat.png
          ? ui.ImageByteFormat.png
          : ui.ImageByteFormat.rawRgba,
    );
    if (data == null) return null;
    final payload = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    final out = Uint8List(_headerBytes + payload.length);
    final header = ByteData.sublistView(out, 0, _headerBytes);
    header.setUint32(0, _magic);
    header.setUint8(4, 1); // container version
    header.setUint8(5, fullRasterFormat.index);
    header.setUint16(6, 0); // reserved
    header.setUint32(8, image.width);
    header.setUint32(12, image.height);
    header.setUint32(16, payload.length);
    out.setRange(_headerBytes, out.length, payload);
    return out;
  }

  Future<ui.Image?> _decodeFullRaster(
      Uint8List bytes, int width, int height) async {
    if (bytes.length < _headerBytes) return null;
    final header = ByteData.sublistView(bytes, 0, _headerBytes);
    if (header.getUint32(0) != _magic) return null;
    if (header.getUint8(4) != 1) return null;
    final formatIndex = header.getUint8(5);
    if (formatIndex >= PdfRasterDiskFormat.values.length) return null;
    final format = PdfRasterDiskFormat.values[formatIndex];
    // The key already pins the dimensions; re-checking them against the
    // payload is what turns a store mix-up into a miss rather than a page
    // drawn at the wrong size.
    if (header.getUint32(8) != width || header.getUint32(12) != height) {
      return null;
    }
    final payloadLength = header.getUint32(16);
    if (payloadLength != bytes.length - _headerBytes) return null;
    final payload = Uint8List.sublistView(bytes, _headerBytes);

    if (format == PdfRasterDiskFormat.rawRgba) {
      if (payload.length != width * height * 4) return null;
      final buffer = await ui.ImmutableBuffer.fromUint8List(payload);
      final descriptor = ui.ImageDescriptor.raw(
        buffer,
        width: width,
        height: height,
        pixelFormat: ui.PixelFormat.rgba8888,
      );
      try {
        final codec = await descriptor.instantiateCodec();
        try {
          final frame = await codec.getNextFrame();
          return frame.image;
        } finally {
          codec.dispose();
        }
      } finally {
        descriptor.dispose();
        buffer.dispose();
      }
    }

    final codec = await ui.instantiateImageCodec(payload);
    try {
      final frame = await codec.getNextFrame();
      final image = frame.image;
      if (image.width != width || image.height != height) {
        image.dispose();
        return null;
      }
      return image;
    } finally {
      codec.dispose();
    }
  }
}
