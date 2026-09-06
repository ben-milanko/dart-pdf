import 'dart:typed_data';

import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_cos/perf.dart';

import 'page.dart';

/// A PDF document with page-level semantics on top of the COS layer.
class PdfDocument {
  PdfDocument._(this.cos, [this._sourcePageCountHint])
      : _pageCacheRevision = cos.revision;

  /// The underlying COS-level document, for anything not surfaced here yet.
  final CosDocument cos;

  // A short-lived sparse source preview may deliberately fetch only its first
  // N page leaves. Do not make pageCount resolve every intentionally absent
  // /Kids reference (which can trigger xref recovery scans over a large sparse
  // address space). The complete replacement document has no hint and keeps
  // the correctness-first full leaf walk below.
  final int? _sourcePageCountHint;

  /// Opens a document. For encrypted files [password] is tried first as
  /// the user and then as the owner password (the empty default is what
  /// most owner-locked business documents expect); a wrong password
  /// throws [CosPasswordException].
  ///
  /// [populatedRanges] carries a sparse buffer's populated `[start, end)` byte
  /// pairs when [bytes] has been copied (including across isolates). Omit it
  /// to inherit the map attached to this exact buffer, or treat an unmarked
  /// buffer as complete. See [CosDocument.populatedRanges].
  static PdfDocument open(Uint8List bytes,
          {String password = '', List<int>? populatedRanges}) =>
      PdfDocument._(CosDocument.open(bytes,
          password: password, populatedRanges: populatedRanges));

  /// Opens a document from an asynchronous, random-access [source] - a remote
  /// file over HTTP Range requests, a local file read on demand, or any other
  /// [PdfByteSource]. Only the bytes the parser needs (header, cross-reference
  /// chain, and the live objects) are fetched, falling back to a full download
  /// when the source cannot serve useful ranges or the file is malformed.
  ///
  /// [PdfDocument.open] and the byte-based widgets are unaffected; this is an
  /// additive entry point for progressive/remote loading. See [PdfByteSource]
  /// and, for the HTTP adapter, `PdfHttpByteSource` in `dart_pdf_editor`.
  static Future<PdfDocument> openSource(
    PdfByteSource source, {
    String password = '',
    PdfSourceLoadOptions options = const PdfSourceLoadOptions(),
  }) async {
    final result = await openCosDocumentFromSourceWithStatus(source,
        password: password, options: options);
    final hint = result.isFirstPaintBuffer &&
            options.firstPaintPages != null &&
            !options.completeFirstPaintPageTree
        ? options.firstPaintPages
        : null;
    return PdfDocument._(result.document, hint);
  }

  String get version => cos.version;

  CosDictionary get catalog => cos.catalog;

  CosDictionary get _pagesRoot {
    final pages = cos.resolve(catalog['Pages']);
    if (pages is! CosDictionary) {
      throw CosParseException('catalog has no /Pages tree');
    }
    return pages;
  }

  /// The number of reachable page leaves. Deliberately NOT the root
  /// /Count: real-world files lie about it (and fuzzed ones make it a
  /// reference to a stream), and an index below pageCount must never
  /// make [page] throw. The walk caches in [_leafCache]; /Count is still
  /// used as the subtree-skipping hint inside [page].
  int get pageCount {
    _refreshPageCacheRevision();
    return _sourcePageCountHint ?? _leaves.length;
  }

  /// Document information dictionary (/Title, /Author, ...) as text.
  Map<String, String> get info {
    final dict = cos.resolve(cos.trailer['Info']);
    if (dict is! CosDictionary) return const {};
    final result = <String, String>{};
    dict.entries.forEach((key, value) {
      final v = cos.resolve(value);
      if (v is CosString) result[key] = v.text;
      if (v is CosName) result[key] = v.value;
    });
    return result;
  }

  /// Returns page [index] (zero-based), with inheritable attributes
  /// (Resources, MediaBox, CropBox, Rotate) resolved along the tree path.
  PdfPage page(int index) {
    _refreshPageCacheRevision();
    if (index < 0) {
      throw RangeError.range(index, 0, null, 'index');
    }
    final sourceLimit = _sourcePageCountHint;
    if (sourceLimit != null && index >= sourceLimit) {
      throw RangeError.range(index, 0, sourceLimit - 1, 'index');
    }
    final allPages = _allPagesCache;
    if (allPages != null) {
      if (index >= allPages.length) {
        throw RangeError.range(index, 0, allPages.length - 1, 'index');
      }
      return allPages[index];
    }
    final cached = _pageCache[index];
    if (cached != null) return cached;
    // The fast walk trusts /Count on intermediate nodes to skip whole
    // subtrees. Real-world files lie about /Count, so a miss falls back
    // to walking every leaf before giving up.
    final fast = _findPage(
        _pagesRoot, _Counter(index), const _Inherited(), <CosDictionary>{});
    if (fast != null) return _pageCache[index] = fast;
    final counter = _Counter(index);
    final found = _findPage(
        _pagesRoot, counter, const _Inherited(), <CosDictionary>{},
        useCounts: false);
    if (found == null) {
      throw RangeError('page index $index out of range: document has only '
          '${index - counter.value} reachable pages');
    }
    return _pageCache[index] = found;
  }

  /// Page objects by index, so repeat access reuses one instance.
  ///
  /// Safe because [PdfPage] resolves its inheritable attributes from its live
  /// dictionary rather than snapshotting them, so an in-place [PdfEditor]
  /// mutation is visible through a cached page (#418). Only the page TREE
  /// shape is snapshotted here, and that is dropped by
  /// [invalidatePageCache] alongside the leaf index.
  ///
  /// Reusing instances is what makes [PdfPage.annotations]' cache reachable:
  /// building a fresh page per call meant every annotation read re-parsed
  /// /Annots and rebuilt every PdfAnnotation.
  final Map<int, PdfPage> _pageCache = {};

  /// Every reachable page in document order, resolved in one page-tree walk.
  ///
  /// Prefer this when a caller needs the whole document. Repeated [page]
  /// lookups are optimized for sparse random access using subtree /Count, but
  /// on a flat tree enumerating `page(0)..page(n)` revisits an ever-longer kid
  /// prefix and becomes quadratic. This traversal also resolves inherited
  /// page attributes once and seeds [page]'s cache.
  List<PdfPage> get pages {
    _refreshPageCacheRevision();
    final cached = _allPagesCache;
    if (cached != null) return cached;
    final t0 = PdfPerf.begin();
    final out = <PdfPage>[];
    final leaves = <CosDictionary>[];
    _collectPages(
      _pagesRoot,
      const _Inherited(),
      <CosDictionary>{},
      out,
      leaves,
      limit: _sourcePageCountHint,
    );
    final result = List<PdfPage>.unmodifiable(out);
    _allPagesCache = result;
    _leafCache = leaves;
    _leafIndexCache = {
      for (var i = 0; i < leaves.length; i++) leaves[i]: i,
    };
    _pageCache
      ..clear()
      ..addEntries([
        for (var i = 0; i < result.length; i++) MapEntry(i, result[i]),
      ]);
    PdfPerf.end(PdfPerfPhase.pageTreeWalk, t0);
    return result;
  }

  List<CosDictionary>? _leafCache;
  Map<CosDictionary, int>? _leafIndexCache;
  List<PdfPage>? _allPagesCache;
  int _pageCacheRevision;

  /// Invalidates a wrapper's page-tree caches when another wrapper sharing
  /// the same [CosDocument] has advanced it to a new incremental revision.
  ///
  /// Viewer page objects deliberately survive clean-page revisions. Some of
  /// them therefore retain an older [PdfDocument] wrapper over the same live
  /// COS graph; making this check lazy keeps their destination/page-index
  /// lookups correct without walking the whole page tree on every edit.
  void _refreshPageCacheRevision() {
    final revision = cos.revision;
    if (_pageCacheRevision == revision) return;
    _leafCache = null;
    _leafIndexCache = null;
    _allPagesCache = null;
    _pageCache.clear();
    _pageCacheRevision = revision;
  }

  /// Identity map from page dictionary to index, built alongside [_leaves].
  ///
  /// [CosDictionary] does not override `==`, so a plain map is identity-keyed
  /// - the same comparison the linear scan this replaces made, at O(1).
  ///
  /// Iteration order is immaterial because [_leaves] cannot hold the same
  /// dictionary twice: [_collectLeaves] guards on a `visited` set, so a node a
  /// broken file reaches from two places in the tree is collected once.
  Map<CosDictionary, int> get _leafIndex => _leafIndexCache ??= {
        for (var i = 0; i < _leaves.length; i++) _leaves[i]: i,
      };

  List<CosDictionary> get _leaves => _leafCache ??= () {
        final t0 = PdfPerf.begin();
        final out = <CosDictionary>[];
        _collectLeaves(_pagesRoot, out, <CosDictionary>{});
        PdfPerf.end(PdfPerfPhase.pageTreeWalk, t0);
        return out;
      }();

  /// Drops cached page-tree state. Editing code calls this after structural
  /// changes (reorder, removal, insertion) so lookups re-walk the tree.
  void invalidatePageCache() {
    _leafCache = null;
    _leafIndexCache = null;
    _allPagesCache = null;
    _pageCache.clear();
    _pageCacheRevision = cos.revision;
  }

  /// Feeds an append-only incremental revision into this open document in
  /// place (see [CosDocument.applyIncrementalUpdate]) and re-walks the page
  /// tree, so a render worker can reflect one page's edit without re-parsing
  /// the whole document. [newBytes] must begin with this document's current
  /// bytes (`cos.bytes`).
  /// Returns the set of redefined COS object numbers. Throws when the update
  /// cannot be applied incrementally; the caller should re-open instead.
  Set<int> applyIncrementalUpdate(Uint8List newBytes) {
    final changed = cos.applyIncrementalUpdate(newBytes);
    invalidatePageCache();
    return changed;
  }

  /// Folds an append-only revision into the COS layer (see
  /// [applyIncrementalUpdate]) and returns a *fresh* [PdfDocument] over it.
  ///
  /// The fresh wrapper is a convenience, not a contract: it skips the full
  /// re-parse (the COS object cache is shared and only the objects this
  /// revision redefined were evicted, and the new wrapper starts with an empty
  /// page-tree cache), so it is cheaper than reopening. Callers that need a
  /// "did a new revision land?" signal must NOT rely on the wrapper's identity
  /// changing - `PdfEditingController.revisionId` is that signal (#414). Once no
  /// caller depends on the identity, applying the update in place
  /// ([applyIncrementalUpdate]) is a valid drop-in that saves this allocation.
  ///
  /// Older wrappers share the now-updated [CosDocument]. Their page-tree
  /// caches notice the COS revision and invalidate lazily if they are retained.
  PdfDocument withIncrementalUpdate(Uint8List newBytes) {
    cos.applyIncrementalUpdate(newBytes);
    return PdfDocument._(cos);
  }

  /// Zero-based index of a page dictionary, or -1 if it isn't a leaf of
  /// this document's page tree. Resolved objects are cached by reference,
  /// so identity comparison is sound. Used to resolve link destinations.
  int pageIndexOf(CosDictionary pageDict) {
    _refreshPageCacheRevision();
    return _leafIndex[pageDict] ?? -1;
  }

  void _collectLeaves(
      CosDictionary node, List<CosDictionary> out, Set<CosDictionary> visited) {
    if (!visited.add(node)) return;
    if (_isLeaf(node)) {
      out.add(node);
      return;
    }
    final kids = cos.resolve(node['Kids']);
    if (kids is! CosArray) return;
    for (final kid in kids.items) {
      final child = cos.resolve(kid);
      if (child is CosDictionary) _collectLeaves(child, out, visited);
    }
  }

  bool _collectPages(
    CosDictionary node,
    _Inherited inherited,
    Set<CosDictionary> visited,
    List<PdfPage> out,
    List<CosDictionary> leaves, {
    int? limit,
  }) {
    if (limit != null && out.length >= limit) return true;
    if (!visited.add(node)) return false;
    if (_isLeaf(node)) {
      leaves.add(node);
      final existing = _pageCache[out.length];
      out.add(existing != null && identical(existing.dict, node)
          ? existing
          : PdfPage(
              document: this,
              dict: node,
              inheritedResources: inherited.resources,
              inheritedMediaBox: inherited.mediaBox,
              inheritedCropBox: inherited.cropBox,
              inheritedRotate: inherited.rotate,
            ));
      return limit != null && out.length >= limit;
    }
    final merged = inherited.mergedWith(node, cos);
    final kids = cos.resolve(node['Kids']);
    if (kids is! CosArray) return false;
    for (final kid in kids.items) {
      final child = cos.resolve(kid);
      if (child is CosDictionary &&
          _collectPages(
            child,
            merged,
            visited,
            out,
            leaves,
            limit: limit,
          )) {
        return true;
      }
    }
    return false;
  }

  bool _isLeaf(CosDictionary node) =>
      node.typeName == 'Page' || !node.containsKey('Kids');

  PdfPage? _findPage(CosDictionary node, _Counter remaining,
      _Inherited inherited, Set<CosDictionary> visited,
      {bool useCounts = true}) {
    if (!visited.add(node)) return null;
    final merged = inherited.mergedWith(node, cos);
    if (_isLeaf(node)) {
      if (remaining.value == 0) {
        // Pass what the ANCESTORS supply, not the merge including this leaf:
        // PdfPage reads its own entries from `node` live, so snapshotting the
        // merged values here would reintroduce the staleness it avoids.
        return PdfPage(
          document: this,
          dict: node,
          inheritedResources: inherited.resources,
          inheritedMediaBox: inherited.mediaBox,
          inheritedCropBox: inherited.cropBox,
          inheritedRotate: inherited.rotate,
        );
      }
      remaining.value--;
      return null;
    }
    final kids = cos.resolve(node['Kids']);
    if (kids is! CosArray) return null;
    for (final kid in kids.items) {
      final child = cos.resolve(kid);
      if (child is! CosDictionary) continue;
      if (useCounts && !_isLeaf(child)) {
        final count = cos.resolve(child['Count']);
        if (count is CosInteger &&
            count.value >= 0 &&
            remaining.value >= count.value) {
          // the page is not in this subtree; skip it wholesale
          remaining.value -= count.value;
          continue;
        }
      }
      final found =
          _findPage(child, remaining, merged, visited, useCounts: useCounts);
      if (found != null) return found;
    }
    return null;
  }
}

class _Counter {
  _Counter(this.value);
  int value;
}

/// Attributes that inherit down the page tree (§7.7.3.4).
class _Inherited {
  const _Inherited({this.resources, this.mediaBox, this.cropBox, this.rotate});

  final CosDictionary? resources;
  final CosArray? mediaBox;
  final CosArray? cropBox;
  final int? rotate;

  _Inherited mergedWith(CosDictionary node, CosDocument cos) {
    final res = cos.resolve(node['Resources']);
    final media = cos.resolve(node['MediaBox']);
    final crop = cos.resolve(node['CropBox']);
    final rot = cos.resolve(node['Rotate']);
    return _Inherited(
      resources: res is CosDictionary ? res : resources,
      mediaBox: media is CosArray ? media : mediaBox,
      cropBox: crop is CosArray ? crop : cropBox,
      rotate: rot is CosInteger ? rot.value : rotate,
    );
  }
}
