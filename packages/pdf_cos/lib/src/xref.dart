import 'dart:typed_data';

import 'exceptions.dart';
import 'filters/filters.dart';
import 'objects.dart';
import 'parser.dart';
import 'token.dart';

enum CosXrefEntryType { free, inUse, compressed }

/// One cross-reference entry: where to find an object.
class CosXrefEntry {
  const CosXrefEntry.free()
      : type = CosXrefEntryType.free,
        offset = 0,
        generation = 0,
        streamObjectNumber = 0,
        indexInStream = 0;

  const CosXrefEntry.inUse(this.offset, this.generation)
      : type = CosXrefEntryType.inUse,
        streamObjectNumber = 0,
        indexInStream = 0;

  const CosXrefEntry.compressed(this.streamObjectNumber, this.indexInStream)
      : type = CosXrefEntryType.compressed,
        offset = 0,
        generation = 0;

  final CosXrefEntryType type;

  /// Byte offset of the object, for [CosXrefEntryType.inUse] entries.
  final int offset;
  final int generation;

  /// Object number of the containing object stream, for
  /// [CosXrefEntryType.compressed] entries.
  final int streamObjectNumber;
  final int indexInStream;
}

/// One parsed cross-reference section (a table or stream) and its trailer.
class CosXrefSection {
  CosXrefSection(this.entries, this.trailer);

  final Map<int, CosXrefEntry> entries;
  final CosDictionary trailer;
}

/// The merged view of a walked cross-reference chain: every object number
/// mapped to the entry from the newest section that defines it, plus the
/// newest section's trailer and the `startxref` the walk began at.
class CosXref {
  CosXref(this.entries, this.trailer, this.startXref);

  final Map<int, CosXrefEntry> entries;
  final CosDictionary trailer;

  /// The `startxref` value the walk began at, relative to the header.
  final int startXref;
}

/// Reads a document's cross-reference machinery over a byte buffer: locating
/// `startxref`, parsing a single section (classic `xref` table or a `/XRef`
/// stream, with `/W` widths and `/Index` ranges), and walking the
/// `/Prev`+`/XRefStm` chain newest-to-oldest into one merged
/// [CosXref] view.
///
/// It is deliberately pure over [bytes] - no object cache, encryption, or
/// scan recovery - so a `/W`-width, `/Index`-range, hybrid-ordering, or
/// `/Prev`-cycle bug is provokable from a bare section plus trailer, without
/// hand-crafting a whole valid document.
class CosXrefReader {
  CosXrefReader(this.bytes, {this.shift = 0});

  /// The document image the cross-reference offsets refer to.
  final Uint8List bytes;

  /// Offset of the `%PDF-` header. Some files carry junk before the header;
  /// xref offsets are then relative to the header, not the file start.
  final int shift;

  /// Locates the `startxref` value declared near the tail of the file
  /// (relative to the header). Throws [CosParseException] when the keyword is
  /// missing - the caller falls back to scan recovery.
  int findStartXref() {
    final from = bytes.length > 2048 ? bytes.length - 2048 : 0;
    final index = _lastIndexOf(bytes, 'startxref', from);
    if (index < 0) {
      throw CosParseException('missing startxref');
    }
    return CosParser(bytes, offset: index + 'startxref'.length).expectInteger();
  }

  /// Reads the whole chain declared by the file's `startxref`. Convenience for
  /// [findStartXref] followed by [walkFrom].
  CosXref read() => walkFrom(findStartXref());

  /// Walks the cross-reference chain from [startXref] (a value relative to the
  /// header), newest-to-oldest. The first entry seen for an object number wins;
  /// hybrid files queue `/XRefStm` before `/Prev`; a visited-offset set guards
  /// against `/Prev` cycles.
  ///
  /// [stopAt] (also relative to the header, when given) is a section already
  /// known to the caller: the walk never descends into it, pruning the
  /// already-loaded tail of the chain for incremental updates. The returned
  /// [CosXref.entries] then holds only the sections newer than [stopAt].
  CosXref walkFrom(int startXref, {int? stopAt}) {
    final entries = <int, CosXrefEntry>{};
    var trailer = CosDictionary();
    var isNewest = true;
    final stopOffset = stopAt == null ? null : stopAt + shift;

    final pending = <int>[startXref + shift];
    final visited = <int>{};
    while (pending.isNotEmpty) {
      final offset = pending.removeAt(0);
      // A section the caller already loaded; everything reachable through it
      // is loaded too, so stop the descent here.
      if (offset == stopOffset) continue;
      if (!visited.add(offset)) continue;
      final section = parseSection(offset);
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
    return CosXref(entries, trailer, startXref);
  }

  /// Parses one section at absolute file [offset]: a classic `xref` table or a
  /// cross-reference stream, dispatched on the leading keyword.
  CosXrefSection parseSection(int offset) {
    if (offset < 0 || offset >= bytes.length) {
      throw CosParseException('cross-reference offset out of range', offset);
    }
    final parser = CosParser(bytes, offset: offset);
    if (parser.peekToken().isKeyword('xref')) {
      return _parseTable(parser);
    }
    return _parseStream(parser);
  }

  static CosXrefSection _parseTable(CosParser parser) {
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

  static CosXrefSection _parseStream(CosParser parser) {
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
