import 'package:pdf_graphics/pdf_graphics.dart';

import 'budgeted_cache.dart';

/// Text metadata from complete page recordings, local to one render worker.
///
/// Capture before drawing annotations and before the render codec drops exact
/// advances and marked-content ids. A miss still uses ordinary extraction: a
/// pool can assign extraction to a different worker, and large entries may be
/// declined or evicted. No command graph, glyph outline or document is retained.
class PdfWorkerTextCache {
  PdfWorkerTextCache({int maxBytes = 16 * 1024 * 1024, int maxPages = 32})
      : _entries = PdfBudgetedCache<int, PdfRecordedText>(
          weigher: (text) => text.estimatedBytes,
          maxWeight: maxBytes,
          maxEntries: maxPages,
          rejectOversize: true,
          debugLabel: 'worker-recorded-text',
        );

  final PdfBudgetedCache<int, PdfRecordedText> _entries;

  int get hits => _entries.hits;
  int get retainedBytes => _entries.weight;
  int get length => _entries.length;

  /// [commands] must contain the complete page content, recorded with
  /// `collectCharOffsets: true`, and must exclude annotation appearances.
  /// Call [evictPages] when the worker receives a document revision.
  void record(int pageIndex, List<PdfRenderCommand> commands) {
    // Image resolutions and annotation visibility can trigger another full
    // recording without changing searchable page content.
    if (_entries.containsKey(pageIndex)) return;
    _entries.put(pageIndex, PdfRecordedText.capture(commands));
  }

  PdfPageText? extract(int pageIndex) {
    final recorded = _entries.take(pageIndex);
    return recorded == null
        ? null
        : PdfTextExtractor.fromRecordedText(recorded, pageIndex);
  }

  void evictPages(Set<int>? pages) {
    if (pages == null) {
      _entries.clear();
    } else {
      _entries.evictWhere(pages.contains);
    }
  }
}
