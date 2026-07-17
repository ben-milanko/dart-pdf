import 'dart:typed_data';

import 'byte_source.dart';
import 'crypto/standard_security_handler.dart';
import 'exceptions.dart';
import 'filters/filters.dart';
import 'lexer.dart';
import 'objects.dart';
import 'parser.dart';
import 'token.dart';
import 'xref.dart';

/// A parsed PDF file at the COS level: header, cross-reference machinery, and
/// on-demand object loading. Page-level semantics live in `pdf_document`.
class CosDocument {
  CosDocument._(
      this.bytes, this._offsetShift, this._xref, this.trailer, this.startXref);

  /// The document image the xref offsets refer to. Grows in place when an
  /// append-only incremental revision is fed through [applyIncrementalUpdate];
  /// the prefix is always byte-identical, so objects cached against the old
  /// buffer stay valid.
  Uint8List bytes;

  /// Offset of the `%PDF-` header. Some files carry junk before the header;
  /// xref offsets are then relative to the header, not the file start.
  final int _offsetShift;

  final Map<int, CosXrefEntry> _xref;
  CosDictionary trailer;

  /// The newest cross-reference section's offset, as declared after the
  /// `startxref` keyword. An incremental update points /Prev here.
  int startXref;

  final Map<CosReference, CosObject> _cache = {};
  final Map<int, _ObjectStream> _objectStreams = {};

  StandardSecurityHandler? _encryption;
  int? _encryptObjectNumber;

  /// Object numbers currently mid-parse, guarding against definitions
  /// that reference their own object (fuzzed and corrupt files).
  final Set<int> _loadingObjects = {};

  /// `N G obj` headers found by scanning the file, built only when an
  /// xref offset turns out to point at the wrong object.
  Map<int, CosXrefEntry>? _scannedHeaders;

  /// The active security handler, or null for unencrypted documents.
  StandardSecurityHandler? get encryption => _encryption;

  bool get isEncrypted => _encryption != null;

  /// Object number of the /Encrypt dictionary, whose strings stay raw.
  int? get encryptObjectNumber => _encryptObjectNumber;

  /// Opens a document. For encrypted files [password] is tried first as
  /// the user and then as the owner password; the default empty password
  /// is what most "owner-locked" business documents expect. Throws
  /// [CosPasswordException] when it opens neither.
  ///
  /// When the cross-reference machinery is broken (missing `startxref`,
  /// corrupt offsets, truncated tables), falls back to rebuilding the xref
  /// by scanning the file for object headers - see [_recover].
  static CosDocument open(Uint8List bytes, {String password = ''}) {
    final shift = _findHeader(bytes);
    try {
      final document = _openFromXref(bytes, shift);
      document._initEncryption(password);
      final root = document.resolve(document.trailer['Root']);
      if (root is! CosDictionary) {
        throw CosParseException('trailer /Root does not resolve');
      }
      return document;
    } on CosPasswordException {
      rethrow;
    } on UnsupportedEncryptionException {
      rethrow;
    } on Exception {
      // broken xref chain or trailer - fall through to recovery
    } on RangeError {
      // ditto: an xref offset pointing outside the file
    }
    return _recover(bytes, shift, password);
  }

  /// Feeds an append-only incremental revision into this already-parsed
  /// document in place, so a caller holding an open document (a render worker)
  /// need not re-open and re-parse the whole xref chain to see one page's edit.
  ///
  /// [newBytes] must begin with this document's current [bytes] (a strict
  /// prefix) and carry one or more appended incremental-update sections. Only
  /// the cross-reference sections newer than the current [startXref] are
  /// parsed; their entries replace the matching ones (newest wins), the trailer
  /// is refreshed (keeping keys the newest section omits, like /Root), and the
  /// cached state of every object the update redefined is evicted so the next
  /// resolve re-reads it from the appended bytes. Returns the set of redefined
  /// object numbers.
  ///
  /// Throws when the update cannot be applied incrementally (this document was
  /// opened through xref recovery, [newBytes] is not an append, or the appended
  /// xref chain is malformed); the caller should re-open from scratch instead.
  Set<int> applyIncrementalUpdate(Uint8List newBytes) {
    if (startXref <= 0) {
      // A recovered document has no trustworthy xref chain to hang a /Prev off.
      throw CosParseException('cannot incrementally update a recovered document');
    }
    if (newBytes.length <= bytes.length) {
      throw CosParseException('incremental update is not an append');
    }
    final newStartXref = _findStartXref(newBytes);
    final oldStartOffset = startXref + _offsetShift;
    final changed = <int>{};
    CosDictionary? newestTrailer;
    final pending = <int>[newStartXref + _offsetShift];
    final visited = <int>{};
    while (pending.isNotEmpty) {
      final offset = pending.removeAt(0);
      // Everything at or below the previous newest section is already loaded.
      if (offset == oldStartOffset) continue;
      if (!visited.add(offset)) continue;
      final section = _parseXrefSection(newBytes, offset);
      newestTrailer ??= section.trailer;
      for (final entry in section.entries.entries) {
        // First occurrence among the appended sections wins, and it overrides
        // whatever the old chain held for that object.
        if (changed.add(entry.key)) _xref[entry.key] = entry.value;
      }
      final hybrid = section.trailer['XRefStm'];
      if (hybrid is CosInteger) pending.add(hybrid.value + _offsetShift);
      final prev = section.trailer['Prev'];
      if (prev is CosInteger) pending.add(prev.value + _offsetShift);
    }

    bytes = newBytes;
    startXref = newStartXref;
    if (newestTrailer != null) {
      // The newest trailer wins, but an incremental trailer may omit doc-level
      // keys (/Root, /Encrypt, /ID) that still carry over from the base.
      final merged = CosDictionary();
      trailer.entries.forEach((key, value) => merged.entries[key] = value);
      newestTrailer.entries.forEach((key, value) => merged.entries[key] = value);
      trailer = merged;
    }

    // Drop cached state for every redefined object so the next resolve re-reads
    // it from the appended bytes; untouched objects keep their warm cache.
    _cache.removeWhere((ref, _) => changed.contains(ref.objectNumber));
    _objectStreams.removeWhere((number, _) => changed.contains(number));
    _scannedHeaders = null;
    return changed;
  }

  /// Opens a document from an asynchronous, random-access [source], fetching
  /// only the byte ranges it needs (header, cross-reference chain, and the
  /// live objects) instead of requiring the whole file up front. Falls back
  /// to a full sequential download when the source cannot serve useful
  /// ranges or the cross-reference machinery is broken. See [PdfByteSource]
  /// and [openCosDocumentFromSource].
  static Future<CosDocument> openSource(
    PdfByteSource source, {
    String password = '',
    PdfSourceLoadOptions options = const PdfSourceLoadOptions(),
  }) =>
      openCosDocumentFromSource(source, password: password, options: options);

  static CosDocument _openFromXref(Uint8List bytes, int shift) {
    final startXref = _findStartXref(bytes);
    final entries = <int, CosXrefEntry>{};
    CosDictionary trailer = CosDictionary();
    var isNewest = true;

    // Walk the xref chain newest-to-oldest; the first entry seen for an
    // object number wins. Hybrid files queue /XRefStm before /Prev.
    final pending = <int>[startXref + shift];
    final visited = <int>{};
    while (pending.isNotEmpty) {
      final offset = pending.removeAt(0);
      if (!visited.add(offset)) continue;
      final section = _parseXrefSection(bytes, offset);
      for (final entry in section.entries.entries) {
        entries.putIfAbsent(entry.key, () => entry.value);
      }
      if (isNewest) {
        trailer = section.trailer;
        isNewest = false;
      }
      final hybrid = section.trailer['XRefStm'];
      if (hybrid is CosInteger) pending.add(hybrid.value + shift);
      final prev = section.trailer['Prev'];
      if (prev is CosInteger) pending.add(prev.value + shift);
    }
    return CosDocument._(bytes, shift, entries, trailer, startXref);
  }

  /// Last-resort open for files whose cross-reference machinery is broken:
  /// rebuilds the xref by scanning the whole file for `N G obj` headers
  /// (the last definition of each object number wins, matching
  /// incremental-update semantics), recovers the trailer from `trailer`
  /// dictionaries and cross-reference stream dictionaries, indexes any
  /// object streams so compressed objects stay reachable, and - failing a
  /// recovered /Root - locates the catalog by its /Type.
  static CosDocument _recover(Uint8List bytes, int shift, String password) {
    final entries = _scanObjectHeaders(bytes, shift);
    if (entries.isEmpty) {
      throw CosParseException(
          'cross-reference recovery found no objects in the file');
    }

    // Recover the trailer: merge every `trailer` dictionary in file order
    // (later revisions win), then doc-level keys from any xref stream
    // dictionaries (files without the trailer keyword).
    final trailer = CosDictionary();
    var t = shift;
    while (true) {
      t = _indexOf(bytes, 'trailer', t);
      if (t < 0) break;
      try {
        final candidate =
            CosParser(bytes, offset: t + 'trailer'.length).parseObject();
        if (candidate is CosDictionary) {
          candidate.entries.forEach((key, value) {
            trailer.entries[key] = value;
          });
        }
      } on Exception {
        // junk that happens to contain the keyword
      }
      t += 'trailer'.length;
    }

    final document = CosDocument._(bytes, shift, entries, trailer, 0);

    // Doc-level keys from xref stream dictionaries. This pass runs before
    // encryption is initialized (it has to: it may recover /Encrypt), so
    // every loaded object is dropped from the cache afterwards.
    const docKeys = ['Root', 'Info', 'Encrypt', 'ID'];
    for (final number in List.of(entries.keys)) {
      try {
        final object = document.getObject(number, entries[number]!.generation);
        if (object is! CosStream) continue;
        final type = object.dictionary['Type'];
        if (type is! CosName || type.value != 'XRef') continue;
        for (final key in docKeys) {
          final value = object.dictionary[key];
          if (value != null) trailer.entries[key] = value;
        }
      } on Exception {
        continue;
      }
    }
    document._cache.clear();
    document._objectStreams.clear();

    document._initEncryption(password);

    // Index object streams so compressed objects resolve. Direct
    // definitions found by the scan win over compressed ones. The
    // "/N pairs, /First offset" wire format is parsed by the object-stream
    // decoder itself ([_objectStream]) so a lenience fix there reaches
    // recovery too - recovery only decides which streams to index.
    for (final number in List.of(entries.keys)) {
      final entry = entries[number]!;
      if (entry.type != CosXrefEntryType.inUse) continue;
      try {
        final object = document.getObject(number, entry.generation);
        if (object is! CosStream) continue;
        final type = object.dictionary['Type'];
        if (type is! CosName || type.value != 'ObjStm') continue;
        final stream = document._objectStream(number);
        for (var index = 0; index < stream.index.length; index++) {
          final objectNumber = stream.index[index].$1;
          entries.putIfAbsent(
              objectNumber, () => CosXrefEntry.compressed(number, index));
        }
      } on Exception {
        // a stream that fails to decode loses only its compressed objects
      }
    }

    // No /Root recovered? Find the catalog by type.
    if (document.resolve(trailer['Root']) is! CosDictionary) {
      trailer.entries.remove('Root');
      for (final number in List.of(entries.keys)) {
        try {
          final entry = entries[number]!;
          final object = document.getObject(number, entry.generation);
          if (object is CosDictionary) {
            final type = document.resolve(object['Type']);
            if (type is CosName && type.value == 'Catalog') {
              trailer.entries['Root'] =
                  CosReference(number, entry.generation);
              break;
            }
          }
        } on Exception {
          continue;
        }
      }
    }

    var maxNumber = 0;
    for (final number in entries.keys) {
      if (number > maxNumber) maxNumber = number;
    }
    trailer.entries.putIfAbsent('Size', () => CosInteger(maxNumber + 1));
    return document;
  }

  /// Scans the whole file for `N G obj` headers; the last definition of
  /// each object number wins, matching incremental-update semantics.
  static Map<int, CosXrefEntry> _scanObjectHeaders(Uint8List bytes, int shift) {
    final entries = <int, CosXrefEntry>{};
    for (var i = shift; i + 3 <= bytes.length; i++) {
      if (bytes[i] != 0x6F /* o */ ||
          bytes[i + 1] != 0x62 /* b */ ||
          bytes[i + 2] != 0x6A /* j */) {
        continue;
      }
      if (i + 3 < bytes.length && CosLexer.isRegular(bytes[i + 3])) continue;
      final header = _objectHeaderBefore(bytes, i, shift);
      if (header == null) continue;
      final (start, objectNumber, generation) = header;
      entries[objectNumber] = CosXrefEntry.inUse(start - shift, generation);
    }
    return entries;
  }

  /// Walks backwards from an `obj` keyword over `N G `, returning the
  /// offset of the object number and the parsed numbers, or null when the
  /// bytes before the keyword are not an object header.
  static (int, int, int)? _objectHeaderBefore(
      Uint8List bytes, int at, int shift) {
    var p = at - 1;
    var end = p;
    while (p >= shift && CosLexer.isWhitespace(bytes[p])) {
      p--;
    }
    if (p == end) return null;
    final genEnd = p;
    while (p >= shift && bytes[p] >= 0x30 && bytes[p] <= 0x39) {
      p--;
    }
    if (p == genEnd || genEnd - p > 5) return null;
    final genStart = p + 1;
    end = p;
    while (p >= shift && CosLexer.isWhitespace(bytes[p])) {
      p--;
    }
    if (p == end) return null;
    final numEnd = p;
    while (p >= shift && bytes[p] >= 0x30 && bytes[p] <= 0x39) {
      p--;
    }
    if (p == numEnd || numEnd - p > 10) return null;
    final numStart = p + 1;
    if (p >= shift && CosLexer.isRegular(bytes[p])) return null;
    var objectNumber = 0;
    for (var d = numStart; d <= numEnd; d++) {
      objectNumber = objectNumber * 10 + (bytes[d] - 0x30);
    }
    if (objectNumber == 0) return null;
    var generation = 0;
    for (var d = genStart; d <= genEnd; d++) {
      generation = generation * 10 + (bytes[d] - 0x30);
    }
    return (numStart, objectNumber, generation);
  }

  /// Installs the security handler when the trailer carries /Encrypt.
  /// Runs before any other object loads, so only the /Encrypt dictionary
  /// itself (whose strings stay raw by design) is parsed undecrypted.
  void _initEncryption(String password) {
    final encryptRef = trailer['Encrypt'];
    final encrypt = resolve(encryptRef);
    if (encrypt is! CosDictionary) return;
    if (encryptRef is CosReference) {
      _encryptObjectNumber = encryptRef.objectNumber;
    }
    Uint8List? firstId;
    final id = resolve(trailer['ID']);
    if (id is CosArray && id.length > 0) {
      final first = resolve(id[0]);
      if (first is CosString) firstId = first.bytes;
    }
    _encryption =
        StandardSecurityHandler.fromEncrypt(encrypt, firstId, password, resolve);
  }

  /// The version from the file header, e.g. `1.7`. The catalog's /Version
  /// entry, when present and newer, overrides this (not yet considered).
  String get version {
    var p = _offsetShift + '%PDF-'.length;
    final sb = StringBuffer();
    while (p < bytes.length && !CosLexer.isWhitespace(bytes[p])) {
      sb.writeCharCode(bytes[p++]);
    }
    return sb.toString();
  }

  CosDictionary get catalog {
    final root = resolve(trailer['Root']);
    if (root is! CosDictionary) {
      throw CosParseException('document has no /Root catalog');
    }
    return root;
  }

  /// Object numbers known to the cross-reference machinery.
  Iterable<int> get objectNumbers => _xref.keys;

  /// Offset of the `%PDF-` header; xref offsets are relative to it.
  int get headerOffset => _offsetShift;

  CosXrefEntry? xrefEntry(int objectNumber) => _xref[objectNumber];

  /// The trailer's declared /Size (one past the highest object number).
  int get declaredSize {
    final size = resolve(trailer['Size']);
    return size is CosInteger ? size.value : 0;
  }

  /// Finds the reference under which [object] was loaded, or null if it is
  /// not an already-loaded indirect object. Identity-based; used by editing
  /// code to map a mutated object back to its number.
  CosReference? referenceTo(CosObject object) {
    for (final entry in _cache.entries) {
      if (identical(entry.value, object)) return entry.key;
    }
    return null;
  }

  /// Registers an in-memory [object] under [ref] as if it had been loaded
  /// from the file, so it resolves (and [referenceTo] finds it) before the
  /// pending update is saved. [CosIncrementalUpdater.addObject] calls this
  /// for every object it allocates.
  void adoptObject(CosReference ref, CosObject object) {
    _cache[ref] = object;
  }

  /// Loads an object by number, parsing it on first access.
  CosObject getObject(int objectNumber, int generation) {
    final ref = CosReference(objectNumber, generation);
    final cached = _cache[ref];
    if (cached != null) return cached;

    final entry = _xref[objectNumber];
    if (entry == null) return CosNull.instance;

    // A re-entrant request means the object's own definition references
    // itself (a stream whose /Length is `N 0 R` for object N). Answer
    // null without caching: the parser treats the junk length leniently
    // and scans for "endstream" instead.
    if (!_loadingObjects.add(objectNumber)) return CosNull.instance;
    final CosObject result;
    try {
      switch (entry.type) {
        case CosXrefEntryType.free:
          result = CosNull.instance;
        case CosXrefEntryType.inUse:
          // A junk target or one holding a different object means the
          // xref offsets are off (shifted, or regenerated wrong) - fall
          // back to a one-time scan for `N G obj` headers, and failing
          // that treat the reference as dangling.
          final indirect = _parseIndirectAt(entry.offset, objectNumber) ??
              _parseScannedHeader(objectNumber);
          if (indirect == null) {
            result = CosNull.instance;
          } else {
            result = indirect.object;
            // strings decrypt with the owning object's key the moment it
            // loads; stream payloads wait for decodeStreamData
            if (_encryption != null && objectNumber != _encryptObjectNumber) {
              _encryption!
                  .decryptObjectGraph(result, objectNumber, indirect.generation);
            }
          }
        case CosXrefEntryType.compressed:
          // objects inside an object stream were decrypted wholesale with
          // the stream itself - never again individually (§7.6.3)
          result = _objectStream(entry.streamObjectNumber)
              .objectByNumber(objectNumber, entry.indexInStream);
      }
    } finally {
      _loadingObjects.remove(objectNumber);
    }
    // Record the ref every loaded stream was parsed from: its encryption
    // key derives from it, and its presence marks the payload as still the
    // file's original bytes (see [CosStream.sourceRef]).
    if (result is CosStream) result.sourceRef = ref;
    _cache[ref] = result;
    return result;
  }

  /// Parses the indirect object at xref [offset], or null when the bytes
  /// there are junk or define a different object number.
  CosIndirectObject? _parseIndirectAt(int offset, int objectNumber) {
    try {
      final parser = CosParser(bytes,
          offset: offset + _offsetShift, resolver: _resolveRef);
      final indirect = parser.parseIndirectObject();
      return indirect.objectNumber == objectNumber ? indirect : null;
    } on Exception {
      return null;
    } on RangeError {
      return null;
    }
  }

  /// Looks [objectNumber] up in the lazily built header scan (the same
  /// scan full recovery uses) - the rescue for xrefs whose offsets lie.
  CosIndirectObject? _parseScannedHeader(int objectNumber) {
    final headers =
        _scannedHeaders ??= _scanObjectHeaders(bytes, _offsetShift);
    final entry = headers[objectNumber];
    if (entry == null || entry.type != CosXrefEntryType.inUse) return null;
    return _parseIndirectAt(entry.offset, objectNumber);
  }

  /// Follows references until reaching a direct object. Null input and
  /// dangling references resolve to [CosNull.instance].
  CosObject resolve(CosObject? object) {
    var current = object ?? CosNull.instance;
    var guard = 0;
    while (current is CosReference) {
      if (guard++ > 1000) throw CosParseException('reference cycle');
      current = getObject(current.objectNumber, current.generation);
    }
    return current;
  }

  /// Decodes a stream's payload, resolving indirect /Length and /Filter
  /// entries against this document. Encrypted streams decrypt with their
  /// owning object's key before the filters run. See [decodeStream] for
  /// [stopBeforeFilter].
  Uint8List decodeStreamData(CosStream stream, {String? stopBeforeFilter}) {
    var source = stream;
    final handler = _encryption;
    if (handler != null) {
      final owner = stream.sourceRef;
      if (owner != null && handler.streamPayloadIsEncrypted(stream, resolve)) {
        source = CosStream(
            stream.dictionary,
            handler.decryptStream(
                stream.rawBytes, owner.objectNumber, owner.generation));
      }
    }
    return decodeStream(source,
        resolve: _resolveRef, stopBeforeFilter: stopBeforeFilter);
  }

  CosObject _resolveRef(CosReference ref) =>
      getObject(ref.objectNumber, ref.generation);

  _ObjectStream _objectStream(int streamObjectNumber) {
    return _objectStreams.putIfAbsent(streamObjectNumber, () {
      final object = getObject(streamObjectNumber, 0);
      if (object is! CosStream) {
        throw CosParseException(
            'object stream $streamObjectNumber is not a stream');
      }
      final data = decodeStreamData(object);
      final count = resolve(object.dictionary['N']);
      final first = resolve(object.dictionary['First']);
      if (count is! CosInteger || first is! CosInteger) {
        throw CosParseException(
            'object stream $streamObjectNumber has invalid /N or /First');
      }
      return _ObjectStream(data, count.value, first.value);
    });
  }

  static int _findHeader(Uint8List bytes) {
    final limit = bytes.length < 1024 ? bytes.length : 1024;
    final index = _indexOf(bytes, '%PDF-', 0, limit);
    if (index < 0) {
      throw CosParseException('not a PDF: missing %PDF- header');
    }
    return index;
  }

  static int _findStartXref(Uint8List bytes) {
    final from = bytes.length > 2048 ? bytes.length - 2048 : 0;
    final index = _lastIndexOf(bytes, 'startxref', from);
    if (index < 0) {
      // open() catches this and falls back to scan recovery
      throw CosParseException('missing startxref');
    }
    return CosParser(bytes, offset: index + 'startxref'.length)
        .expectInteger();
  }

  static CosXrefSection _parseXrefSection(Uint8List bytes, int offset) {
    if (offset < 0 || offset >= bytes.length) {
      throw CosParseException('cross-reference offset out of range', offset);
    }
    final parser = CosParser(bytes, offset: offset);
    if (parser.peekToken().isKeyword('xref')) {
      return _parseXrefTable(parser);
    }
    return _parseXrefStream(parser);
  }

  static CosXrefSection _parseXrefTable(CosParser parser) {
    parser.expectKeyword('xref');
    final entries = <int, CosXrefEntry>{};
    while (parser.peekToken().type == CosTokenType.integer) {
      final start = parser.expectInteger();
      final count = parser.expectInteger();
      for (var i = 0; i < count; i++) {
        final first = parser.expectInteger();
        final second = parser.expectInteger();
        final kind = parser.nextToken();
        final objectNumber = start + i;
        if (kind.isKeyword('n')) {
          entries.putIfAbsent(
              objectNumber, () => CosXrefEntry.inUse(first, second));
        } else if (kind.isKeyword('f')) {
          entries.putIfAbsent(objectNumber, () => const CosXrefEntry.free());
        } else {
          throw CosParseException('invalid xref entry type', kind.offset);
        }
      }
    }
    parser.expectKeyword('trailer');
    final trailer = parser.parseObject();
    if (trailer is! CosDictionary) {
      throw CosParseException('trailer is not a dictionary');
    }
    return CosXrefSection(entries, trailer);
  }

  static CosXrefSection _parseXrefStream(CosParser parser) {
    final indirect = parser.parseIndirectObject();
    final object = indirect.object;
    if (object is! CosStream) {
      throw CosParseException('expected a cross-reference stream');
    }
    final dict = object.dictionary;
    // xref stream dictionary entries must be direct (no resolver available
    // before the xref itself is loaded)
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

    final entries = <int, CosXrefEntry>{};
    final rowLength = widths.fold(0, (a, b) => a + b);
    var pos = 0;
    for (var r = 0; r + 1 < ranges.length; r += 2) {
      final start = ranges[r];
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
        // a zero-width type field defaults to "in use" (§7.5.8.3)
        final type = widths[0] == 0 ? 1 : fields[0];
        final objectNumber = start + i;
        switch (type) {
          case 0:
            entries.putIfAbsent(objectNumber, () => const CosXrefEntry.free());
          case 1:
            entries.putIfAbsent(objectNumber,
                () => CosXrefEntry.inUse(fields[1], fields[2]));
          case 2:
            entries.putIfAbsent(objectNumber,
                () => CosXrefEntry.compressed(fields[1], fields[2]));
        }
      }
    }
    return CosXrefSection(entries, dict);
  }
}

/// A decoded /Type /ObjStm: many small objects packed into one stream.
class _ObjectStream {
  _ObjectStream(this.data, int count, this.first) {
    final parser = CosParser(data);
    for (var i = 0; i < count; i++) {
      try {
        _index.add((parser.expectInteger(), parser.expectInteger()));
      } on CosParseException {
        // A truncated or malformed header stops the index here; the pairs
        // parsed so far stay usable (real-world files are lenient on
        // input). Recovery keeps the leading compressed objects, and
        // objectByNumber only fails to find the ones that never parsed.
        break;
      }
    }
  }

  final Uint8List data;

  /// Offset of the first object, relative to the decoded data.
  final int first;

  /// (object number, relative offset) pairs from the stream header.
  final List<(int, int)> _index = [];

  /// The parsed (object number, relative offset) pairs, in stream order.
  /// Recovery reuses this so the header wire-format is parsed in exactly
  /// one place (see [CosDocument._recover]).
  List<(int, int)> get index => List.unmodifiable(_index);

  CosObject objectByNumber(int objectNumber, int hintIndex) {
    var entry = hintIndex >= 0 &&
            hintIndex < _index.length &&
            _index[hintIndex].$1 == objectNumber
        ? _index[hintIndex]
        : null;
    if (entry == null) {
      // the xref's index hint was wrong; fall back to a number lookup
      for (final candidate in _index) {
        if (candidate.$1 == objectNumber) {
          entry = candidate;
          break;
        }
      }
    }
    if (entry == null) {
      throw CosParseException(
          'object $objectNumber not found in its object stream');
    }
    return CosParser(data, offset: first + entry.$2).parseObject();
  }
}

int _indexOf(Uint8List bytes, String pattern, int from, [int? limit]) {
  final end = (limit ?? bytes.length) - pattern.length;
  for (var p = from; p <= end; p++) {
    var match = true;
    for (var i = 0; i < pattern.length; i++) {
      if (bytes[p + i] != pattern.codeUnitAt(i)) {
        match = false;
        break;
      }
    }
    if (match) return p;
  }
  return -1;
}

int _lastIndexOf(Uint8List bytes, String pattern, int from) {
  for (var p = bytes.length - pattern.length; p >= from; p--) {
    var match = true;
    for (var i = 0; i < pattern.length; i++) {
      if (bytes[p + i] != pattern.codeUnitAt(i)) {
        match = false;
        break;
      }
    }
    if (match) return p;
  }
  return -1;
}
