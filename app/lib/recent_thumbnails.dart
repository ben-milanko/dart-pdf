import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';

import 'devtools.dart';
import 'file_io.dart';
import 'recent_thumbnail_store.dart';
import 'recents.dart';

/// Reads a recent entry's bytes from its [RecentFile.readPath]. Mirrors
/// [readPdfAtPath]'s shape so it is the production default, and is injectable
/// so widget tests can hand back fixture bytes without touching the filesystem.
typedef RecentBytesReader = Future<Uint8List> Function(String path,
    {String? bookmark});

/// Loads one encoded thumbnail from the app's private persistent store.
typedef StoredRecentThumbnailReader = Future<Uint8List?> Function(String key);

/// Writes one encoded thumbnail to the app's private persistent store.
typedef StoredRecentThumbnailWriter = Future<void> Function(
    String key, Uint8List bytes);

/// Removes persistent thumbnails whose keys are not in the current Recent
/// list.
typedef StoredRecentThumbnailPruner = Future<void> Function(Set<String> keep);

/// A rendered first-page thumbnail: the PNG bytes plus the source page's
/// aspect ratio, so the grid can shape each tile to the real page instead of
/// letterboxing it into a fixed box.
class RecentThumbnail {
  const RecentThumbnail({required this.pngBytes, required this.aspectRatio})
      : assert(aspectRatio > 0);

  /// First-page raster as PNG bytes.
  final Uint8List pngBytes;

  /// Source page width / height. Portrait pages are < 1, landscape > 1.
  final double aspectRatio;
}

/// Renders and memoizes small first-page thumbnails for the recent-documents
/// list on the welcome screen.
///
/// [thumbnailFor] reads an entry's bytes, opens the PDF, and rasterizes its
/// first page to a [RecentThumbnail] (PNG bytes + page aspect ratio) sized so
/// its longest side is [longestSide] px. Results are keyed by the entry's
/// [RecentFile.id], retained in memory, and written to app-private local
/// storage. A later app launch therefore paints a network/cloud file's cached
/// thumbnail without opening that source again. Entries with no readable
/// source (a web pick with no snapshot) or a file that fails to open resolve
/// to null, and the list falls back to its generic document icon.
///
/// Owned by the editor screen alongside the recents store; lives for the app
/// session and is bounded to [maxEntries] retained thumbnails.
class RecentThumbnailCache {
  RecentThumbnailCache({
    RecentBytesReader? readBytes,
    StoredRecentThumbnailReader? readStored,
    StoredRecentThumbnailWriter? writeStored,
    StoredRecentThumbnailPruner? pruneStored,
    this.longestSide = 240,
    this.maxEntries = 32,
  })  : readBytes = readBytes ?? readPdfAtPath,
        // An injected source reader normally supplies fixture bytes. Default
        // to a matching isolated in-memory-only mode so a developer machine's
        // persistent cache cannot bypass that fixture and make tests depend on
        // prior runs. Callers testing persistence inject both layers.
        readStored = readStored ??
            (readBytes == null
                ? readStoredRecentThumbnail
                : _readNoStoredThumbnail),
        writeStored = writeStored ??
            (readBytes == null
                ? writeStoredRecentThumbnail
                : _writeNoStoredThumbnail),
        pruneStored = pruneStored ??
            (readBytes == null
                ? pruneStoredRecentThumbnails
                : _pruneNoStoredThumbnails),
        assert(longestSide > 0);

  /// Reads an entry's bytes. Production reads from disk / the byte-snapshot
  /// store via [readPdfAtPath]; tests inject a fixture reader.
  final RecentBytesReader readBytes;

  /// Reads/writes the durable layer. Injectable so tests can emulate an app
  /// restart without depending on a platform storage plugin.
  final StoredRecentThumbnailReader readStored;
  final StoredRecentThumbnailWriter writeStored;
  final StoredRecentThumbnailPruner pruneStored;

  /// Longest side of a rendered thumbnail, in pixels. The list draws it at
  /// ~40 px and the grid at ~150 px, so a modest raster stays crisp on
  /// high-DPI screens in both without paying for a full-page render.
  final double longestSide;

  /// Cap on retained thumbnails; the least-recently-requested entry is dropped
  /// past it. The welcome list shows at most ~20.
  final int maxEntries;

  // Insertion-ordered so the first key is the least-recently-touched. A cached
  // null (the entry has no readable/renderable source) is retained too, so a
  // failed render isn't retried on every rebuild.
  final Map<String, RecentThumbnail?> _cache = {};
  final Map<String, Future<RecentThumbnail?>> _inflight = {};
  Future<void> _renderTail = Future<void>.value();
  bool _disposed = false;

  /// The first-page thumbnail for [entry], rendered once and memoized. Null
  /// when the entry has no readable source or the render fails.
  Future<RecentThumbnail?> thumbnailFor(RecentFile entry) {
    final key = entry.id;
    if (_cache.containsKey(key)) {
      // Touch: move to the most-recently-used end.
      final value = _cache.remove(key);
      _cache[key] = value;
      return Future.value(value);
    }
    final pending = _inflight[key];
    if (pending != null) return pending;
    final future = _enqueue(() => _loadOrRender(entry)).then((thumb) {
      _inflight.remove(key);
      if (!_disposed) _store(key, thumb);
      return thumb;
    });
    _inflight[key] = future;
    return future;
  }

  /// Drops persistent thumbnails for documents no longer in Recent files.
  Future<void> retain(Iterable<RecentFile> entries) => pruneStored({
        for (final entry in entries) _persistentKey(entry.id),
      });

  Future<RecentThumbnail?> _enqueue(
      Future<RecentThumbnail?> Function() operation) {
    final result = Completer<RecentThumbnail?>();
    _renderTail = _renderTail.then((_) async {
      try {
        result.complete(await operation());
      } catch (error, stack) {
        result.completeError(error, stack);
      }
    });
    return result.future;
  }

  void _store(String key, RecentThumbnail? thumb) {
    _cache[key] = thumb;
    while (_cache.length > maxEntries) {
      _cache.remove(_cache.keys.first);
    }
  }

  Future<RecentThumbnail?> _loadOrRender(RecentFile entry) async {
    Uint8List? stored;
    try {
      stored = await readStored(_persistentKey(entry.id));
    } catch (_) {
      // Persistence is an optimization. Fall through to the source whenever
      // the platform store is unavailable or contains an unreadable entry.
    }
    final decoded = stored == null ? null : _decodeThumbnail(stored);
    if (decoded != null) return decoded;

    final path = entry.readPath;
    if (path == null) return null;
    try {
      final bytes = await readBytes(path, bookmark: entry.bookmark);
      final thumb = await _renderBytes(bytes);
      if (thumb != null) await _writePersistent(entry.id, thumb);
      return thumb;
    } catch (e) {
      AppDevTools.instance.addLog('recent thumbnail render failed: $e',
          level: DevLogLevel.error);
      return null;
    }
  }

  Future<void> _writePersistent(String id, RecentThumbnail thumb) async {
    try {
      await writeStored(_persistentKey(id), _encodeThumbnail(thumb));
    } catch (_) {
      // Keep serving the in-memory thumbnail when durable storage is blocked.
    }
  }

  Future<RecentThumbnail?> _renderBytes(Uint8List bytes) async {
    try {
      final doc = PdfDocument.open(bytes);
      if (doc.pageCount == 0) return null;
      final page = doc.page(0);
      final size = PdfPageRenderer.pageSize(page);
      final longest = math.max(size.width, size.height);
      final scale = longest <= 0 ? 1.0 : longestSide / longest;
      // Interpreting a page is the expensive part of thumbnail generation.
      // Doing it through PdfPageExport here used to run synchronously on
      // Flutter's platform thread, so a handful of uncached recents made macOS
      // mark the app unresponsive at launch. Record in a short-lived worker;
      // only the small command replay, 240 px raster, and PNG encoding remain
      // on the platform thread.
      final worker = PdfRenderWorker.startUncached(bytes);
      try {
        final commands = await worker
            .record(0, imagePixelRatio: scale)
            .timeout(const Duration(seconds: 30), onTimeout: () => null);
        // A worker declines pages it cannot serialize (notably some
        // inline-image pages). A generic icon is preferable to falling back to
        // the exact platform-thread render this cache exists to keep off
        // launch.
        if (commands == null) return null;
        final picture = await PdfPageRenderer.pictureFromCommands(
          page,
          commands,
          maxImagePixelRatio: scale,
        );
        final ui.Image image;
        try {
          image = await PdfPageRenderer.rasterize(picture, size, scale);
        } finally {
          picture.dispose();
        }
        final ByteData? data;
        try {
          data = await image.toByteData(format: ui.ImageByteFormat.png);
        } finally {
          image.dispose();
        }
        if (data == null) return null;
        final png = data.buffer.asUint8List(
          data.offsetInBytes,
          data.lengthInBytes,
        );
        final aspect = (size.width > 0 && size.height > 0)
            ? size.width / size.height
            : 1.0;
        return RecentThumbnail(pngBytes: png, aspectRatio: aspect);
      } finally {
        worker.dispose();
      }
    } catch (e) {
      AppDevTools.instance.addLog('recent thumbnail render failed: $e',
          level: DevLogLevel.error);
      return null;
    }
  }

  void dispose() {
    _disposed = true;
    _cache.clear();
    _inflight.clear();
  }
}

Future<Uint8List?> _readNoStoredThumbnail(String key) async => null;

Future<void> _writeNoStoredThumbnail(String key, Uint8List bytes) async {}

Future<void> _pruneNoStoredThumbnails(Set<String> keep) async {}

const _thumbnailMagic = <int>[0x44, 0x50, 0x54, 0x31]; // DPT1
const _thumbnailHeaderLength = 12;

String _persistentKey(String id) => sha1.convert(utf8.encode(id)).toString();

Uint8List _encodeThumbnail(RecentThumbnail thumbnail) {
  final bytes = Uint8List(_thumbnailHeaderLength + thumbnail.pngBytes.length);
  bytes.setRange(0, _thumbnailMagic.length, _thumbnailMagic);
  ByteData.sublistView(bytes)
      .setFloat64(4, thumbnail.aspectRatio, Endian.little);
  bytes.setRange(_thumbnailHeaderLength, bytes.length, thumbnail.pngBytes);
  return bytes;
}

RecentThumbnail? _decodeThumbnail(Uint8List bytes) {
  if (bytes.length <= _thumbnailHeaderLength) return null;
  for (var i = 0; i < _thumbnailMagic.length; i++) {
    if (bytes[i] != _thumbnailMagic[i]) return null;
  }
  final aspect = ByteData.sublistView(bytes).getFloat64(4, Endian.little);
  if (!aspect.isFinite || aspect <= 0) return null;
  final png = Uint8List.sublistView(bytes, _thumbnailHeaderLength);
  if (png.length < 4 ||
      png[0] != 0x89 ||
      png[1] != 0x50 ||
      png[2] != 0x4E ||
      png[3] != 0x47) {
    return null;
  }
  return RecentThumbnail(pngBytes: png, aspectRatio: aspect);
}
