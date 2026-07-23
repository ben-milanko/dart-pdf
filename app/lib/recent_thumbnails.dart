import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';

import 'devtools.dart';
import 'file_io.dart';
import 'recents.dart';

/// Reads a recent entry's bytes from its [RecentFile.readPath]. Mirrors
/// [readPdfAtPath]'s shape so it is the production default, and is injectable
/// so widget tests can hand back fixture bytes without touching the filesystem.
typedef RecentBytesReader = Future<Uint8List> Function(String path,
    {String? bookmark});

/// Renders and memoizes small first-page thumbnails for the recent-documents
/// list on the welcome screen.
///
/// [thumbnailFor] reads an entry's bytes, opens the PDF, and rasterizes its
/// first page to PNG bytes sized to [longestSide] px, keyed by the entry's
/// [RecentFile.id] so a welcome-screen rebuild (recents changing, the list
/// scrolling) never re-renders the same page. Entries with no readable source
/// (a web pick with no snapshot) or a file that fails to open resolve to null,
/// and the list falls back to its generic document icon.
///
/// Owned by the editor screen alongside the recents store; lives for the app
/// session and is bounded to [maxEntries] retained thumbnails.
class RecentThumbnailCache {
  RecentThumbnailCache({
    this.readBytes = readPdfAtPath,
    this.longestSide = 96,
    this.maxEntries = 32,
  }) : assert(longestSide > 0);

  /// Reads an entry's bytes. Production reads from disk / the byte-snapshot
  /// store via [readPdfAtPath]; tests inject a fixture reader.
  final RecentBytesReader readBytes;

  /// Longest side of a rendered thumbnail, in pixels. The list draws it at
  /// ~40 px, so a modest raster stays crisp on high-DPI screens without paying
  /// for a full-page render.
  final double longestSide;

  /// Cap on retained thumbnails; the least-recently-requested entry is dropped
  /// past it. The welcome list shows at most ~20.
  final int maxEntries;

  // Insertion-ordered so the first key is the least-recently-touched. A cached
  // null (the entry has no readable/renderable source) is retained too, so a
  // failed render isn't retried on every rebuild.
  final Map<String, Uint8List?> _cache = {};
  final Map<String, Future<Uint8List?>> _inflight = {};
  bool _disposed = false;

  /// The first-page thumbnail for [entry] as PNG bytes, rendered once and
  /// memoized. Null when the entry has no readable source or the render fails.
  Future<Uint8List?> thumbnailFor(RecentFile entry) {
    final key = entry.id;
    if (_cache.containsKey(key)) {
      // Touch: move to the most-recently-used end.
      final value = _cache.remove(key);
      _cache[key] = value;
      return Future.value(value);
    }
    final pending = _inflight[key];
    if (pending != null) return pending;
    final future = _render(entry).then((bytes) {
      _inflight.remove(key);
      if (!_disposed) _store(key, bytes);
      return bytes;
    });
    _inflight[key] = future;
    return future;
  }

  void _store(String key, Uint8List? bytes) {
    _cache[key] = bytes;
    while (_cache.length > maxEntries) {
      _cache.remove(_cache.keys.first);
    }
  }

  Future<Uint8List?> _render(RecentFile entry) async {
    final path = entry.readPath;
    if (path == null) return null;
    try {
      final bytes = await readBytes(path, bookmark: entry.bookmark);
      final doc = PdfDocument.open(bytes);
      if (doc.pageCount == 0) return null;
      final page = doc.page(0);
      final size = PdfPageRenderer.pageSize(page);
      final longest = math.max(size.width, size.height);
      final scale = longest <= 0 ? 1.0 : longestSide / longest;
      return await PdfPageExport.exportPage(page, scale: scale);
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
