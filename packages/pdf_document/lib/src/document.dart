import 'dart:typed_data';

import 'package:pdf_cos/pdf_cos.dart';

import 'page.dart';

/// A PDF document with page-level semantics on top of the COS layer.
class PdfDocument {
  PdfDocument._(this.cos);

  /// The underlying COS-level document, for anything not surfaced here yet.
  final CosDocument cos;

  /// Opens a document. For encrypted files [password] is tried first as
  /// the user and then as the owner password (the empty default is what
  /// most owner-locked business documents expect); a wrong password
  /// throws [CosPasswordException].
  static PdfDocument open(Uint8List bytes, {String password = ''}) =>
      PdfDocument._(CosDocument.open(bytes, password: password));

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
  }) async =>
      PdfDocument._(await CosDocument.openSource(source,
          password: password, options: options));

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
  int get pageCount => _leaves.length;

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
    if (index < 0) {
      throw RangeError.range(index, 0, null, 'index');
    }
    // The fast walk trusts /Count on intermediate nodes to skip whole
    // subtrees. Real-world files lie about /Count, so a miss falls back
    // to walking every leaf before giving up.
    final fast = _findPage(_pagesRoot, _Counter(index), const _Inherited(),
        <CosDictionary>{});
    if (fast != null) return fast;
    final counter = _Counter(index);
    final found = _findPage(
        _pagesRoot, counter, const _Inherited(), <CosDictionary>{},
        useCounts: false);
    if (found == null) {
      throw RangeError('page index $index out of range: document has only '
          '${index - counter.value} reachable pages');
    }
    return found;
  }

  List<CosDictionary>? _leafCache;

  List<CosDictionary> get _leaves => _leafCache ??= () {
        final out = <CosDictionary>[];
        _collectLeaves(_pagesRoot, out, <CosDictionary>{});
        return out;
      }();

  /// Drops cached page-tree state. Editing code calls this after structural
  /// changes (reorder, removal, insertion) so lookups re-walk the tree.
  void invalidatePageCache() => _leafCache = null;

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

  /// Zero-based index of a page dictionary, or -1 if it isn't a leaf of
  /// this document's page tree. Resolved objects are cached by reference,
  /// so identity comparison is sound. Used to resolve link destinations.
  int pageIndexOf(CosDictionary pageDict) {
    final leaves = _leaves;
    for (var i = 0; i < leaves.length; i++) {
      if (identical(leaves[i], pageDict)) return i;
    }
    return -1;
  }

  void _collectLeaves(CosDictionary node, List<CosDictionary> out,
      Set<CosDictionary> visited) {
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

  bool _isLeaf(CosDictionary node) =>
      node.typeName == 'Page' || !node.containsKey('Kids');

  PdfPage? _findPage(CosDictionary node, _Counter remaining,
      _Inherited inherited, Set<CosDictionary> visited,
      {bool useCounts = true}) {
    if (!visited.add(node)) return null;
    final merged = inherited.mergedWith(node, cos);
    if (_isLeaf(node)) {
      if (remaining.value == 0) {
        return PdfPage(
          document: this,
          dict: node,
          resources: merged.resources,
          mediaBoxArray: merged.mediaBox,
          cropBoxArray: merged.cropBox,
          rotate: merged.rotate,
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
