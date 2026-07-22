import 'dart:math' as math;
import 'dart:typed_data';

import 'document.dart';
import 'exceptions.dart';
import 'filters/filters.dart';
import 'objects.dart';
import 'parser.dart';
import 'perf/perf.dart';
import 'token.dart';
import 'xref.dart';

/// A random-access, possibly asynchronous source of PDF bytes.
///
/// The core parser is network-agnostic: it asks a source for the byte ranges
/// it needs rather than requiring the whole file in one buffer. An HTTP
/// implementation (Range requests, headers, auth, cancellation, progress)
/// lives outside the core - see `PdfHttpByteSource` in `dart_pdf_editor`.
///
/// Implementations must be safe to call [readRange] on concurrently.
abstract interface class PdfByteSource {
  /// The total number of bytes, or null when the length is not known ahead
  /// of time (e.g. a server that answers neither HEAD nor a ranged GET with
  /// a total). A null length makes progressive loading fall back to a plain
  /// sequential download.
  Future<int?> get length;

  /// Returns the bytes in `[start, endExclusive)`. Implementations clamp the
  /// range to the available data: a request past the end returns fewer bytes
  /// (a short read), and a request wholly past the end returns an empty list.
  /// `start` is clamped to be non-negative; `endExclusive <= start` yields an
  /// empty list.
  Future<Uint8List> readRange(int start, int endExclusive);

  /// Releases any resources (open connections, buffers). Optional; the
  /// default does nothing. Sources are single-use unless documented
  /// otherwise.
  Future<void> close() async {}
}

/// A [PdfByteSource] backed by a complete in-memory buffer. Handy for tests
/// and for adapting already-downloaded bytes to the source-based API.
class PdfBytesByteSource implements PdfByteSource {
  PdfBytesByteSource(this._bytes);

  final Uint8List _bytes;

  @override
  Future<int?> get length async => _bytes.length;

  @override
  Future<Uint8List> readRange(int start, int endExclusive) async {
    final s = start < 0 ? 0 : (start > _bytes.length ? _bytes.length : start);
    final e = endExclusive < s
        ? s
        : (endExclusive > _bytes.length ? _bytes.length : endExclusive);
    return Uint8List.sublistView(_bytes, s, e);
  }

  @override
  Future<void> close() async {}
}

/// Reports progressive-load progress. [fetched] is the running total of bytes
/// pulled from the source; [total] is the document length when known.
typedef PdfSourceProgress = void Function(int fetched, int? total);

/// Tuning knobs for [openCosDocumentFromSource]. The defaults suit HTTP Range
/// loading: a few KB probes for the header, ~64 KB windows for the tail and
/// each xref section, and coalescing of nearby object ranges so densely
/// packed bodies fetch in one request instead of thousands.
class PdfSourceLoadOptions {
  const PdfSourceLoadOptions({
    this.headWindow = 4096,
    this.tailWindow = 65536,
    this.xrefWindow = 65536,
    this.coalesceGap = 65536,
    this.downloadChunk = 1 << 20,
    this.firstPaintPages,
    this.onProgress,
  })  : assert(headWindow > 0),
        assert(tailWindow > 0),
        assert(xrefWindow > 0),
        assert(coalesceGap >= 0),
        assert(downloadChunk > 0),
        assert(firstPaintPages == null || firstPaintPages > 0);

  /// Bytes fetched from the start of the file to locate the `%PDF-` header.
  final int headWindow;

  /// Bytes fetched from the end of the file to locate `startxref` and the
  /// newest cross-reference section.
  final int tailWindow;

  /// Initial window fetched for each cross-reference section; grown
  /// geometrically when a section (a large xref table or stream) overruns it.
  final int xrefWindow;

  /// Object byte ranges separated by at most this many bytes are fetched in a
  /// single request. Larger values mean fewer, bigger requests.
  final int coalesceGap;

  /// Chunk size used by the sequential-download fallback (unknown length or
  /// a source that cannot serve useful ranges).
  final int downloadChunk;

  /// When set, fetch only the bytes needed to render the first [firstPaintPages]
  /// page(s) - the whole page tree (so page navigation and count work) plus
  /// those pages' content streams, resources, fonts and image XObjects - instead
  /// of every live object. For an image-heavy document (a scan, a CAD sheet) the
  /// live objects *are* the page images, so the default whole-object fetch is
  /// essentially the whole file; this makes first paint a few pages' worth of
  /// bytes. The returned buffer is deliberately incomplete (later pages' bytes
  /// are still zero), so it is only good for rendering the covered pages - do
  /// NOT edit or sign from it; complete the buffer first (e.g. a background
  /// sequential read). Null keeps the original fetch-every-object behaviour.
  ///
  /// Falls back to fetching every object if the page tree can't be walked from
  /// ranged reads, so a first-paint open never fails where a full one would.
  final int? firstPaintPages;

  /// Optional progress callback, invoked after each fetch.
  final PdfSourceProgress? onProgress;
}

/// Opens a [CosDocument] from an asynchronous [source], fetching only the
/// bytes it needs.
///
/// The loader reads the header probe, walks the cross-reference chain with
/// ranged reads, and then fetches the byte ranges of the live objects
/// (skipping free space and superseded incremental-update revisions) into a
/// sparse buffer that the ordinary synchronous [CosDocument.open] consumes.
///
/// When the length is unknown, the cross-reference machinery is broken, or a
/// ranged read fails, it falls back to a plain sequential download and opens
/// that - so a non-range-capable server still works, just without the
/// bandwidth savings. [password] is forwarded to [CosDocument.open].
Future<CosDocument> openCosDocumentFromSource(
  PdfByteSource source, {
  String password = '',
  PdfSourceLoadOptions options = const PdfSourceLoadOptions(),
}) async {
  Uint8List buffer;
  final t0 = PdfPerf.begin();
  try {
    buffer = await _ProgressiveLoader(source, options).load();
  } on _FallbackToFullDownload {
    PdfPerf.add(PdfPerfCount.fullDownloadFallback);
    PdfPerf.event(PdfPerfEvent.rangedSourceFellBack);
    buffer = await _downloadFully(source, options);
  }
  PdfPerf.end(PdfPerfPhase.sourceFetch, t0);
  return CosDocument.open(buffer, password: password);
}

/// Sentinel that unwinds the progressive path to the full-download fallback.
class _FallbackToFullDownload implements Exception {
  const _FallbackToFullDownload();
}

/// A half-open byte interval `[start, end)`.
class _Range {
  _Range(this.start, this.end);
  int start;
  int end;
}

/// Fetches the whole document sequentially. Used when ranged loading is not
/// viable. Reads one range for a known length, otherwise chunks until a short
/// read signals EOF.
Future<Uint8List> _downloadFully(
    PdfByteSource source, PdfSourceLoadOptions options) async {
  final len = await source.length;
  if (len != null && len >= 0) {
    final data = await source.readRange(0, len);
    PdfPerf.add(PdfPerfCount.rangeRequests);
    PdfPerf.add(PdfPerfCount.rangeBytesFetched, data.length);
    options.onProgress?.call(data.length, len);
    return data;
  }
  final builder = BytesBuilder(copy: false);
  var pos = 0;
  while (true) {
    final chunk = await source.readRange(pos, pos + options.downloadChunk);
    PdfPerf.add(PdfPerfCount.rangeRequests);
    PdfPerf.add(PdfPerfCount.rangeBytesFetched, chunk.length);
    if (chunk.isEmpty) break;
    builder.add(chunk);
    pos += chunk.length;
    options.onProgress?.call(pos, null);
    if (chunk.length < options.downloadChunk) break;
  }
  return builder.toBytes();
}

/// Drives a [PdfByteSource] to assemble a sparse buffer good enough for the
/// synchronous parser: header, cross-reference sections, and the live
/// objects' byte ranges are populated; free space and dead revisions are
/// left as zeros the parser never reads.
class _ProgressiveLoader {
  _ProgressiveLoader(this.source, this.options);

  final PdfByteSource source;
  final PdfSourceLoadOptions options;

  late final int _length;
  late final Uint8List _buffer;

  /// Fetched (merged, sorted) byte ranges, so overlapping windows are not
  /// pulled twice.
  final List<_Range> _present = [];
  int _fetched = 0;

  Future<Uint8List> load() async {
    final len = await source.length;
    if (len == null || len <= 0) throw const _FallbackToFullDownload();
    _length = len;
    _buffer = Uint8List(len);

    // Header probe: also settles the offset shift for junk-before-header.
    await _fetch(0, math.min(len, options.headWindow));
    final shift = _indexOf(_buffer, _pdfHeader, 0, math.min(len, 1024));
    if (shift < 0) throw const _FallbackToFullDownload();

    // Tail: startxref + the newest cross-reference section usually live here.
    await _fetch(math.max(0, len - options.tailWindow), len);

    final startXref = _findStartXref(shift);
    if (startXref == null) throw const _FallbackToFullDownload();

    final offsets = await _walkXref(startXref + shift, shift);
    if (offsets.isEmpty) throw const _FallbackToFullDownload();

    // Page-scoped first paint: fetch just the page tree + the first few pages'
    // render closure. Falls through to fetching every object when the page tree
    // can't be walked from ranged reads - so a first-paint open never fails
    // where a whole-object open would.
    if (options.firstPaintPages != null &&
        await _fetchFirstPaintClosure(startXref, shift, offsets)) {
      return _buffer;
    }

    await _fetchObjects(offsets);
    return _buffer;
  }

  /// Absolute offsets of the cross-reference sections visited by [_walkXref].
  /// Object bodies never cross into an xref section, so these bound how far an
  /// object range may extend.
  final List<int> _xrefOffsets = [];

  /// Walks the cross-reference chain newest-to-oldest, collecting the absolute
  /// file offsets of every in-use object. Compressed objects need no offset -
  /// their container object stream is itself an in-use object in the chain.
  Future<List<int>> _walkXref(int firstOffset, int shift) async {
    final offsets = <int>{};
    final pending = <int>[firstOffset];
    final visited = <int>{};
    var sections = 0;
    while (pending.isNotEmpty) {
      final offset = pending.removeAt(0);
      if (!visited.add(offset)) continue;
      if (++sections > 4096) throw const _FallbackToFullDownload();
      _xrefOffsets.add(offset);
      final section = await _readXrefSection(offset);
      for (final raw in section.inUseOffsets) {
        offsets.add(raw + shift);
      }
      final xrefStm = section.trailer['XRefStm'];
      if (xrefStm is CosInteger) pending.add(xrefStm.value + shift);
      final prev = section.trailer['Prev'];
      if (prev is CosInteger) pending.add(prev.value + shift);
    }
    _xrefOffsets.sort();
    return offsets.toList()..sort();
  }

  /// The smallest boundary strictly greater than [start] - the next object
  /// offset, the next xref section, or end of file - which is where the object
  /// at [start] can safely be assumed to end.
  int _objectEnd(List<int> sortedOffsets, int index) {
    final start = sortedOffsets[index];
    var end = index + 1 < sortedOffsets.length
        ? sortedOffsets[index + 1]
        : _length;
    for (final xref in _xrefOffsets) {
      if (xref > start && xref < end) end = xref;
    }
    return end;
  }

  /// Reads and parses the cross-reference section at [offset], growing the
  /// fetched window geometrically until the section fits.
  ///
  /// A section parse only succeeds when its terminator (`trailer` for a
  /// table, `endstream`/`endobj` for a stream) is reached over real bytes:
  /// beyond the fetched window the buffer is zero-filled, which the lexer
  /// treats as whitespace and runs into an EOF, so truncation always throws
  /// rather than yielding a short read. That makes any successful parse
  /// authoritative, so we simply widen the window and retry on failure,
  /// giving up (to the full-download fallback) only once the whole remaining
  /// file has been fetched.
  Future<_XrefSection> _readXrefSection(int offset) async {
    if (offset < 0 || offset >= _length) {
      throw const _FallbackToFullDownload();
    }
    var window = options.xrefWindow;
    while (true) {
      final end = math.min(_length, offset + window);
      await _fetch(offset, end);
      try {
        return _parseXrefSection(offset, end);
      } on _FallbackToFullDownload {
        rethrow;
      } on Exception {
        // Truncated window (_NeedMoreBytes), malformed syntax, or a filter
        // error on a partial stream - widen and retry.
        _growOrFail(end);
        window *= 2;
      } on RangeError {
        _growOrFail(end);
        window *= 2;
      }
    }
  }

  void _growOrFail(int end) {
    if (end >= _length) throw const _FallbackToFullDownload();
  }

  _XrefSection _parseXrefSection(int offset, int limit) {
    final parser = CosParser(_buffer, offset: offset);
    if (parser.peekToken().isKeyword('xref')) {
      return _parseXrefTable(parser, limit);
    }
    return _parseXrefStream(parser, limit);
  }

  _XrefSection _parseXrefTable(CosParser parser, int limit) {
    parser.expectKeyword('xref');
    final inUse = <int>[];
    while (parser.peekToken().type == CosTokenType.integer) {
      parser.expectInteger(); // subsection start object number
      final count = parser.expectInteger();
      for (var i = 0; i < count; i++) {
        final offset = parser.expectInteger();
        parser.expectInteger(); // generation
        final kind = parser.nextToken();
        if (kind.offset >= limit) throw const _NeedMoreBytes();
        if (kind.isKeyword('n')) {
          inUse.add(offset);
        } else if (!kind.isKeyword('f')) {
          throw CosParseException('invalid xref entry type', kind.offset);
        }
        // free entries carry no live object
      }
    }
    final trailerToken = parser.expectKeyword('trailer');
    if (trailerToken.offset >= limit) throw const _NeedMoreBytes();
    final trailer = parser.parseObject();
    if (trailer is! CosDictionary) {
      throw CosParseException('trailer is not a dictionary');
    }
    return _XrefSection(inUse, trailer);
  }

  _XrefSection _parseXrefStream(CosParser parser, int limit) {
    final indirect = parser.parseIndirectObject();
    final object = indirect.object;
    if (object is! CosStream) {
      throw CosParseException('expected a cross-reference stream');
    }
    final dict = object.dictionary;
    // The stream body slices the shared buffer; its absolute end must fall
    // within the fetched window, otherwise part of it is still zero-filled.
    final bodyEnd = object.rawBytes.offsetInBytes + object.rawBytes.length;
    if (bodyEnd > limit) throw const _NeedMoreBytes();
    final data = decodeStream(object);

    final w = dict['W'];
    final size = dict['Size'];
    if (w is! CosArray || w.length < 3 || size is! CosInteger) {
      throw CosParseException('invalid /W or /Size in cross-reference stream');
    }
    final widths = [
      for (final field in w.items)
        field is CosInteger
            ? field.value
            : throw CosParseException('invalid /W entry'),
    ];
    final index = dict['Index'];
    final ranges = index is CosArray
        ? [
            for (final v in index.items)
              v is CosInteger
                  ? v.value
                  : throw CosParseException('invalid /Index entry'),
          ]
        : [0, size.value];

    final inUse = <int>[];
    final rowLength = widths.fold(0, (a, b) => a + b);
    var pos = 0;
    for (var r = 0; r + 1 < ranges.length; r += 2) {
      final count = ranges[r + 1];
      for (var i = 0; i < count && pos + rowLength <= data.length; i++) {
        final fields = <int>[];
        for (final width in widths) {
          var value = 0;
          for (var k = 0; k < width; k++) {
            value = (value << 8) | data[pos++];
          }
          fields.add(value);
        }
        final type = widths[0] == 0 ? 1 : fields[0];
        if (type == 1) inUse.add(fields[1]);
      }
    }
    return _XrefSection(inUse, dict);
  }

  /// Fetches the byte ranges of the live objects. Each object spans from its
  /// offset up to the next object's offset (a safe upper bound); the highest
  /// object runs to end of file. Nearby ranges coalesce into one request.
  Future<void> _fetchObjects(List<int> offsets) async {
    if (offsets.isEmpty) return;
    _Range? pending;
    for (var i = 0; i < offsets.length; i++) {
      final start = offsets[i];
      final end = _objectEnd(offsets, i);
      if (start < 0 || end > _length || start >= end) continue;
      if (pending == null) {
        pending = _Range(start, end);
      } else if (start - pending.end <= options.coalesceGap) {
        pending.end = end;
      } else {
        await _fetch(pending.start, pending.end);
        pending = _Range(start, end);
      }
    }
    if (pending != null) await _fetch(pending.start, pending.end);
  }

  int? _findStartXref(int shift) {
    final from = _length > 2048 ? _length - 2048 : shift;
    final at = _lastIndexOf(_buffer, _startXref, from);
    if (at < 0) return null;
    try {
      return CosParser(_buffer, offset: at + _startXref.length).expectInteger();
    } on CosParseException {
      return null;
    } on RangeError {
      return null;
    }
  }

  /// Reads `[start, end)` from the source into the buffer, skipping any bytes
  /// already present. Reports progress for the bytes actually pulled.
  Future<void> _fetch(int start, int end) async {
    if (end <= start) return;
    for (final gap in _missing(start, end)) {
      final data = await source.readRange(gap.start, gap.end);
      PdfPerf.add(PdfPerfCount.rangeRequests);
      PdfPerf.add(PdfPerfCount.rangeBytesFetched, data.length);
      if (data.isEmpty) continue;
      // Never trust a source to honour the requested length: a misbehaving
      // server can answer a ranged read with more bytes than asked for
      // (a 206 carrying the whole file, a padding CDN). Clamp so setRange
      // can't run past the gap - and the buffer's end - which would abort
      // the whole open instead of letting it fall back.
      final count = math.min(data.length, gap.end - gap.start);
      _buffer.setRange(gap.start, gap.start + count, data);
      _addPresent(gap.start, gap.start + count);
      _fetched += count;
      options.onProgress?.call(_fetched, _length);
    }
  }

  /// The sub-ranges of `[start, end)` not yet fetched.
  List<_Range> _missing(int start, int end) {
    final gaps = <_Range>[];
    var cursor = start;
    for (final r in _present) {
      if (r.end <= cursor) continue;
      if (r.start >= end) break;
      if (r.start > cursor) gaps.add(_Range(cursor, math.min(r.start, end)));
      cursor = math.max(cursor, r.end);
      if (cursor >= end) break;
    }
    if (cursor < end) gaps.add(_Range(cursor, end));
    return gaps;
  }

  void _addPresent(int start, int end) {
    _present.add(_Range(start, end));
    _present.sort((a, b) => a.start.compareTo(b.start));
    final merged = <_Range>[];
    for (final r in _present) {
      if (merged.isNotEmpty && r.start <= merged.last.end) {
        if (r.end > merged.last.end) merged.last.end = r.end;
      } else {
        merged.add(_Range(r.start, r.end));
      }
    }
    _present
      ..clear()
      ..addAll(merged);
  }

  // --- page-scoped first paint --------------------------------------------

  /// Object-number → cross-reference entry, built (via [CosXrefReader]) once the
  /// xref sections are fetched. Drives the targeted object fetches below.
  Map<int, CosXrefEntry> _entries = const {};

  /// Absolute (post-shift) offsets of every in-use object, sorted - the upper
  /// bound for a single object's byte range is the next one.
  List<int> _sortedInUseOffsets = const [];

  /// Objects parsed during the closure walk, so a shared font/resource is
  /// fetched and parsed once.
  final Map<int, CosObject> _loaded = {};

  /// Decoded object streams, so a /ObjStm holding several page dicts is fetched
  /// and inflated once.
  final Map<int, _DecodedObjStm> _objStmCache = {};

  /// Fetches only the bytes needed to render the first [PdfSourceLoadOptions.
  /// firstPaintPages] pages: the whole page tree (so navigation and page count
  /// work) plus those pages' content, resources, fonts and image XObjects.
  /// Returns true on success, false to fall back to fetching every object.
  Future<bool> _fetchFirstPaintClosure(
      int rawStartXref, int shift, List<int> sortedOffsets) async {
    try {
      _sortedInUseOffsets = sortedOffsets;
      final chain = CosXrefReader(_buffer, shift: shift).walkFrom(rawStartXref);
      _entries = chain.entries;

      // CosDocument.open validates /Root (and /Encrypt) resolve, so fetch them
      // up front or the open would trip the whole-file recovery scan.
      final rootRef = chain.trailer['Root'];
      if (rootRef is! CosReference) return false;
      final catalog = await _loadObject(rootRef.objectNumber, shift);
      if (catalog is! CosDictionary) return false;
      final encrypt = chain.trailer['Encrypt'];
      if (encrypt is CosReference) {
        await _loadObject(encrypt.objectNumber, shift);
      }

      final pagesRef = catalog['Pages'];
      if (pagesRef is! CosReference) return false;
      final leaves = <CosDictionary>[];
      if (!await _walkPageTree(pagesRef.objectNumber, shift, leaves, <int>{})) {
        return false;
      }
      if (leaves.isEmpty) return false;

      final wanted = options.firstPaintPages!;
      final visited = <int>{};
      for (var i = 0; i < leaves.length && i < wanted; i++) {
        await _fetchLeafRenderClosure(leaves[i], shift, visited);
      }
      return true;
    } on _FallbackToFullDownload {
      return false;
    } on Object {
      // Any surprise (odd tree, malformed object, filter error on a partial
      // stream) just means we fetch everything instead - still correct.
      return false;
    }
  }

  /// Walks the page tree depth-first in reading order, fetching every node and
  /// leaf dictionary (small) and collecting the page leaves into [leaves].
  /// Returns false on a shape it can't follow, so the caller falls back.
  Future<bool> _walkPageTree(int nodeNumber, int shift,
      List<CosDictionary> leaves, Set<int> visited) async {
    if (!visited.add(nodeNumber)) return true;
    if (visited.length > 1000000) return false;
    final node = await _loadObject(nodeNumber, shift);
    if (node is! CosDictionary) return false;
    final kids = node['Kids'];
    if (node.typeName == 'Page' || kids is! CosArray) {
      leaves.add(node);
      return true;
    }
    for (final kid in kids.items) {
      if (kid is! CosReference) return false; // inline kid: bail to fetch-all
      if (!await _walkPageTree(kid.objectNumber, shift, leaves, visited)) {
        return false;
      }
    }
    return true;
  }

  /// Fetches a page leaf's render dependencies: its content stream(s), its own
  /// /Resources graph (fonts, image XObjects, and everything they reference),
  /// and the /Resources inherited from ancestor page-tree nodes (followed via
  /// /Parent, never /Kids - so it never pulls other pages' content).
  Future<void> _fetchLeafRenderClosure(
      CosDictionary leaf, int shift, Set<int> visited) async {
    await _fetchGraph(leaf['Contents'], shift, visited);
    var node = leaf;
    final seenNodes = <int>{};
    while (true) {
      await _fetchGraph(node['Resources'], shift, visited);
      final parent = node['Parent'];
      if (parent is! CosReference || !seenNodes.add(parent.objectNumber)) break;
      final p = await _loadObject(parent.objectNumber, shift);
      if (p is! CosDictionary) break;
      node = p;
    }
  }

  /// Fetches the transitive closure of indirect objects reachable from [root]
  /// (a resources dict, a /Contents ref/array, ...). Bounded: a page's resource
  /// graph never reaches other pages.
  Future<void> _fetchGraph(
      CosObject? root, int shift, Set<int> visited) async {
    if (root == null) return;
    final queue = <CosReference>[..._enumerateRefs(root)];
    while (queue.isNotEmpty) {
      final ref = queue.removeLast();
      if (!visited.add(ref.objectNumber)) continue;
      final obj = await _loadObject(ref.objectNumber, shift);
      if (obj != null) queue.addAll(_enumerateRefs(obj));
    }
  }

  /// Every indirect reference contained (recursively) in [object].
  Iterable<CosReference> _enumerateRefs(CosObject object) sync* {
    if (object is CosReference) {
      yield object;
    } else if (object is CosArray) {
      for (final item in object.items) {
        yield* _enumerateRefs(item);
      }
    } else if (object is CosDictionary) {
      for (final value in object.entries.values) {
        yield* _enumerateRefs(value);
      }
    } else if (object is CosStream) {
      yield* _enumerateRefs(object.dictionary);
    }
  }

  /// Fetches and parses the object numbered [objectNumber] (following an
  /// /ObjStm for a compressed object), memoized in [_loaded]. Returns null when
  /// the object is free, missing, or can't be parsed from the fetched bytes.
  Future<CosObject?> _loadObject(int objectNumber, int shift) async {
    final cached = _loaded[objectNumber];
    if (cached != null) return cached;
    final entry = _entries[objectNumber];
    if (entry == null) return null;
    CosObject? result;
    switch (entry.type) {
      case CosXrefEntryType.inUse:
        final start = entry.offset + shift;
        if (start < 0 || start >= _length) return null;
        await _fetch(start, _boundedEnd(start));
        try {
          final indirect = CosParser(_buffer, offset: start).parseIndirectObject();
          if (indirect.objectNumber == objectNumber) result = indirect.object;
        } on Object {
          result = null;
        }
      case CosXrefEntryType.compressed:
        final stream = await _loadObjStm(entry.streamObjectNumber, shift);
        result = stream?.object(objectNumber);
      case CosXrefEntryType.free:
        result = null;
    }
    if (result != null) _loaded[objectNumber] = result;
    return result;
  }

  /// Fetches, parses and inflates the object stream numbered [streamNumber],
  /// memoized in [_objStmCache].
  Future<_DecodedObjStm?> _loadObjStm(int streamNumber, int shift) async {
    final cached = _objStmCache[streamNumber];
    if (cached != null) return cached;
    final entry = _entries[streamNumber];
    if (entry == null || entry.type != CosXrefEntryType.inUse) return null;
    final start = entry.offset + shift;
    if (start < 0 || start >= _length) return null;
    await _fetch(start, _boundedEnd(start));
    try {
      final indirect = CosParser(_buffer, offset: start).parseIndirectObject();
      final object = indirect.object;
      if (object is! CosStream) return null;
      final data = decodeStream(object);
      final n = object.dictionary['N'];
      final first = object.dictionary['First'];
      if (n is! CosInteger || first is! CosInteger) return null;
      final decoded = _DecodedObjStm(data, n.value, first.value);
      _objStmCache[streamNumber] = decoded;
      return decoded;
    } on Object {
      return null;
    }
  }

  /// The end of the object at absolute offset [start]: the next in-use object,
  /// the next xref section, or end of file - a safe upper bound to fetch, since
  /// the exact end is unknown until the bytes (with `endstream`/`endobj`) are
  /// present. Mirrors [_objectEnd] but keyed by offset (binary search).
  int _boundedEnd(int start) {
    var end = _length;
    final offsets = _sortedInUseOffsets;
    var lo = 0, hi = offsets.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (offsets[mid] <= start) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    if (lo < offsets.length) end = offsets[lo];
    for (final xref in _xrefOffsets) {
      if (xref > start && xref < end) end = xref;
    }
    return end;
  }
}

/// A decoded /ObjStm: the inflated body plus the object-number → in-body offset
/// index, so a compressed object can be parsed on demand.
class _DecodedObjStm {
  _DecodedObjStm(this._data, int count, this._first) {
    final parser = CosParser(_data);
    for (var i = 0; i < count; i++) {
      final number = parser.expectInteger();
      final offset = parser.expectInteger();
      _index[number] = offset;
    }
  }

  final Uint8List _data;
  final int _first;
  final Map<int, int> _index = {};

  CosObject? object(int objectNumber) {
    final offset = _index[objectNumber];
    if (offset == null) return null;
    try {
      return CosParser(_data, offset: _first + offset).parseObject();
    } on Object {
      return null;
    }
  }
}

/// Parsed cross-reference section: the raw (pre-shift) file offsets of its
/// in-use objects and its trailer/xref-stream dictionary (for /Prev chasing).
class _XrefSection {
  _XrefSection(this.inUseOffsets, this.trailer);
  final List<int> inUseOffsets;
  final CosDictionary trailer;
}

/// Raised inside section parsing when the fetched window is too small; the
/// caller widens the window and retries.
class _NeedMoreBytes implements Exception {
  const _NeedMoreBytes();
}

final Uint8List _pdfHeader = _ascii('%PDF-');
final Uint8List _startXref = _ascii('startxref');

Uint8List _ascii(String s) => Uint8List.fromList(s.codeUnits);

int _indexOf(Uint8List bytes, Uint8List pattern, int from, int limit) {
  final end = limit - pattern.length;
  for (var p = from; p <= end; p++) {
    var match = true;
    for (var i = 0; i < pattern.length; i++) {
      if (bytes[p + i] != pattern[i]) {
        match = false;
        break;
      }
    }
    if (match) return p;
  }
  return -1;
}

int _lastIndexOf(Uint8List bytes, Uint8List pattern, int from) {
  for (var p = bytes.length - pattern.length; p >= from; p--) {
    var match = true;
    for (var i = 0; i < pattern.length; i++) {
      if (bytes[p + i] != pattern[i]) {
        match = false;
        break;
      }
    }
    if (match) return p;
  }
  return -1;
}
