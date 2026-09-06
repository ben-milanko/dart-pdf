import 'dart:typed_data';

import 'fonts/encodings.dart';

/// Internal font-program subsetting. Kept below the graphics layer because
/// this rewrites binary tables without interpreting or rasterizing outlines.
class PdfSubsetFontProgram {
  PdfSubsetFontProgram._(this._sfnt, this._cff);

  factory PdfSubsetFontProgram.parse(Uint8List bytes) {
    if (bytes.length < 4) throw const FormatException('short font program');
    final signature = ByteData.sublistView(bytes).getUint32(0);
    if (signature == 0x00010000 ||
        signature == 0x74727565 ||
        signature == 0x4f54544f) {
      final sfnt = _Sfnt(bytes);
      final os2 = sfnt.tables['OS/2'];
      if (os2 != null &&
          os2.length >= 10 &&
          (ByteData.sublistView(os2).getUint16(8) & 0x0100) != 0) {
        throw const FormatException(
            'font embedding rights prohibit subsetting');
      }
      if (sfnt.tables.keys.any(const {
        'CFF2',
        'COLR',
        'SVG ',
        'fvar',
        'gvar',
        'VARC',
      }.contains)) {
        throw const FormatException('color and variable fonts are not subset');
      }
      final cff = sfnt.tables['CFF '];
      return PdfSubsetFontProgram._(sfnt, cff == null ? null : _Cff(cff));
    }
    if (bytes[0] == 1) return PdfSubsetFontProgram._(null, _Cff(bytes));
    throw const FormatException('unsupported font format');
  }

  final _Sfnt? _sfnt;
  final _Cff? _cff;

  int glyphForCid(int cid) => _cff?.glyphForCid(cid) ?? cid;

  Uint8List? subset(Set<int> glyphs) {
    final cff = _cff;
    final sfnt = _sfnt;
    if (cff != null) {
      final subset = cff.subset(glyphs);
      if (subset == null) return null;
      if (sfnt == null) return subset;
      sfnt.tables['CFF '] = subset;
      return sfnt.build();
    }
    return sfnt!.subsetTrueType(glyphs);
  }
}

class _Sfnt {
  _Sfnt(this.bytes) {
    final data = ByteData.sublistView(bytes);
    final count = data.getUint16(4);
    if (count == 0 || count > 4096 || 12 + count * 16 > bytes.length) {
      throw const FormatException('invalid sfnt directory');
    }
    final ranges = <(int, int)>[];
    for (var i = 0; i < count; i++) {
      final record = 12 + i * 16;
      final tag = String.fromCharCodes(bytes, record, record + 4);
      final offset = data.getUint32(record + 8);
      final length = data.getUint32(record + 12);
      if (offset < 12 + count * 16 ||
          offset + length > bytes.length ||
          tables.containsKey(tag)) {
        throw const FormatException('invalid sfnt table');
      }
      if (length > 0) ranges.add((offset, offset + length));
      tables[tag] = Uint8List.fromList(bytes.sublist(offset, offset + length));
    }
    ranges.sort((a, b) => a.$1.compareTo(b.$1));
    for (var i = 1; i < ranges.length; i++) {
      if (ranges[i].$1 < ranges[i - 1].$2) {
        throw const FormatException('overlapping sfnt tables');
      }
    }
  }

  final Uint8List bytes;
  final tables = <String, Uint8List>{};

  Uint8List? subsetTrueType(Set<int> glyphs) {
    final head = tables['head'];
    final maxp = tables['maxp'];
    final glyf = tables['glyf'];
    final loca = tables['loca'];
    if (head == null ||
        head.length < 54 ||
        maxp == null ||
        maxp.length < 6 ||
        glyf == null ||
        loca == null) {
      throw const FormatException('missing TrueType outline tables');
    }
    final headData = ByteData.sublistView(head);
    final format = headData.getInt16(50);
    if (format != 0 && format != 1) {
      throw const FormatException('invalid TrueType location format');
    }
    final count = ByteData.sublistView(maxp).getUint16(4);
    final stride = format == 0 ? 2 : 4;
    if (loca.length < (count + 1) * stride) {
      throw const FormatException('short TrueType location table');
    }
    final offsets = <int>[];
    final data = ByteData.sublistView(loca);
    for (var i = 0; i <= count; i++) {
      final offset =
          format == 0 ? data.getUint16(i * 2) * 2 : data.getUint32(i * 4);
      if (offset > glyf.length || (i > 0 && offset < offsets.last)) {
        throw const FormatException('invalid TrueType glyph range');
      }
      offsets.add(offset);
    }
    final keep = <int>{0, ...glyphs.where((gid) => gid >= 0 && gid < count)};
    final pending = keep.toList();
    while (pending.isNotEmpty) {
      final gid = pending.removeLast();
      final start = offsets[gid];
      final end = offsets[gid + 1];
      if (start == end) continue;
      if (end - start < 10) {
        throw const FormatException('short TrueType glyph');
      }
      final glyph = ByteData.sublistView(glyf, start, end);
      if (glyph.getInt16(0) >= 0) continue;
      var at = 10;
      var more = true;
      while (more) {
        if (at + 4 > glyph.lengthInBytes) {
          throw const FormatException('short composite glyph');
        }
        final flags = glyph.getUint16(at);
        final component = glyph.getUint16(at + 2);
        if (component >= count) {
          throw const FormatException('invalid composite glyph dependency');
        }
        if (keep.add(component)) pending.add(component);
        at += 4 + ((flags & 1) != 0 ? 4 : 2);
        if ((flags & 8) != 0) at += 2;
        if ((flags & 64) != 0) at += 4;
        if ((flags & 128) != 0) at += 8;
        if (at > glyph.lengthInBytes) {
          throw const FormatException('short composite glyph transform');
        }
        more = (flags & 32) != 0;
      }
    }
    final output = BytesBuilder(copy: false);
    final newLoca = Uint8List((count + 1) * stride);
    final locations = ByteData.sublistView(newLoca);
    for (var gid = 0; gid <= count; gid++) {
      if (format == 0) {
        locations.setUint16(gid * 2, output.length ~/ 2);
      } else {
        locations.setUint32(gid * 4, output.length);
      }
      if (gid < count && keep.contains(gid)) {
        output.add(Uint8List.sublistView(glyf, offsets[gid], offsets[gid + 1]));
        if (output.length.isOdd) output.addByte(0);
      }
    }
    if (output.length >= glyf.length) return null;
    tables['glyf'] = output.takeBytes();
    tables['loca'] = newLoca;
    return build();
  }

  Uint8List build() {
    // A font-level digital signature would no longer describe this program.
    tables.remove('DSIG');
    final head = tables['head'];
    if (head != null && head.length >= 12) {
      ByteData.sublistView(head).setUint32(8, 0);
    }
    final tags = tables.keys.toList()..sort();
    final count = tags.length;
    final directoryLength = 12 + count * 16;
    final total = directoryLength +
        tags.fold<int>(
            0, (length, tag) => length + ((tables[tag]!.length + 3) & ~3));
    final bytesOut = Uint8List(total);
    final data = ByteData.sublistView(bytesOut);
    data.setUint32(0, ByteData.sublistView(bytes).getUint32(0));
    data.setUint16(4, count);
    var power = 1;
    var log = 0;
    while (power * 2 <= count) {
      power *= 2;
      log++;
    }
    data.setUint16(6, power * 16);
    data.setUint16(8, log);
    data.setUint16(10, count * 16 - power * 16);
    var offset = directoryLength;
    int? headOffset;
    for (var i = 0; i < tags.length; i++) {
      final tag = tags[i];
      final table = tables[tag]!;
      final record = 12 + i * 16;
      bytesOut.setRange(record, record + 4, tag.codeUnits);
      data.setUint32(record + 4, _checksum(table));
      data.setUint32(record + 8, offset);
      data.setUint32(record + 12, table.length);
      bytesOut.setRange(offset, offset + table.length, table);
      if (tag == 'head') headOffset = offset;
      offset += (table.length + 3) & ~3;
    }
    if (headOffset != null && head!.length >= 12) {
      data.setUint32(
          headOffset + 8, (0xb1b0afba - _checksum(bytesOut)) & 0xffffffff);
    }
    return bytesOut;
  }

  static int _checksum(Uint8List bytes) {
    var sum = 0;
    for (var at = 0; at < bytes.length; at += 4) {
      var word = 0;
      for (var j = 0; j < 4; j++) {
        word = word * 256 + (at + j < bytes.length ? bytes[at + j] : 0);
      }
      sum = (sum + word) & 0xffffffff;
    }
    return sum;
  }
}

class _Cff {
  _Cff(this.bytes) {
    if (bytes.length < 4 ||
        bytes[0] != 1 ||
        bytes[2] < 4 ||
        bytes[2] > bytes.length) {
      throw const FormatException('unsupported CFF version');
    }
    final names = _index(bytes[2]);
    final tops = _index(names.end);
    if (names.ranges.length != 1 || tops.ranges.length != 1) {
      throw const FormatException('CFF font collections are not subset');
    }
    top = _dict(tops.ranges.single);
    final strings = _index(tops.end);
    final globals = _index(strings.end); // Kept verbatim.
    final offset = _value(top, 17);
    if (offset == null) throw const FormatException('CFF has no CharStrings');
    charStrings = _index(offset);
    if (charStrings.start < globals.end) {
      throw const FormatException(
          'CFF CharStrings overlaps the header indexes');
    }
    if (charStrings.ranges.isEmpty) {
      throw const FormatException('empty CFF CharStrings');
    }
    if (_value(top, 0x0c06) != null && _value(top, 0x0c06) != 2) {
      throw const FormatException('CFF Type 1 charstrings are not subset');
    }
    cidKeyed = top.containsKey(0x0c1e);
    final charsetOffset = _value(top, 15) ?? 0;
    charset = _charset(charsetOffset, charStrings.ranges.length);
    if (cidKeyed) {
      for (var gid = 0; gid < charset.length; gid++) {
        cidToGid[charset[gid]] = gid;
      }
    }
  }

  final Uint8List bytes;
  late final Map<int, List<_CffOperand>> top;
  late final _CffIndex charStrings;
  late final bool cidKeyed;
  late final List<int> charset;
  final cidToGid = <int, int>{};

  int glyphForCid(int cid) => cidKeyed ? (cidToGid[cid] ?? 0) : cid;

  Uint8List? subset(Set<int> glyphs) {
    final keep = <int>{0, ...glyphs};
    if (!cidKeyed) {
      // Deprecated seac endchar composites may occur inside subroutines.
      // Retaining every StandardEncoding glyph covers their base/accent
      // dependencies without guessing at a Type 2 program's operand stack.
      final sids = <int>{for (var sid = 1; sid <= 95; sid++) sid};
      for (var code = 0; code < 256; code++) {
        final name = standardGlyphName(code);
        if (name != null) {
          final sid = cffStandardStrings.indexOf(name);
          if (sid >= 0) sids.add(sid);
        }
      }
      for (var gid = 0; gid < charset.length; gid++) {
        if (sids.contains(charset[gid])) keep.add(gid);
      }
    }
    final entries = <Uint8List>[];
    for (var gid = 0; gid < charStrings.ranges.length; gid++) {
      final range = charStrings.ranges[gid];
      entries.add(keep.contains(gid)
          ? Uint8List.sublistView(bytes, range.$1, range.$2)
          : Uint8List.fromList([14])); // endchar, same glyph ID
    }
    final rebuilt = _buildIndex(entries);
    final saved = charStrings.end - charStrings.start - rebuilt.length;
    if (saved <= 0) return null;
    final patched = Uint8List.fromList(bytes);
    int relocate(int value) {
      if (value > charStrings.start && value < charStrings.end) {
        throw const FormatException('CFF table overlaps CharStrings');
      }
      return value >= charStrings.end ? value - saved : value;
    }

    void absolute(Map<int, List<_CffOperand>> dict, int op,
        {int operand = 0, int predefined = -1}) {
      final values = dict[op];
      if (values == null) return;
      if (values.length <= operand) {
        throw const FormatException('short CFF DICT');
      }
      final value = values[operand];
      if (value.value <= predefined) return;
      _patchNumber(patched, value, relocate(value.value));
    }

    void private(Map<int, List<_CffOperand>> dict) {
      final values = dict[18];
      if (values == null) return;
      if (values.length != 2) {
        throw const FormatException('invalid CFF Private');
      }
      final size = values[0].value;
      final offset = values[1].value;
      if (size < 0 ||
          offset < 0 ||
          offset + size > bytes.length ||
          (size > 0 &&
              (offset < charStrings.end &&
                  offset + size > charStrings.start))) {
        throw const FormatException('invalid CFF Private range');
      }
      final dictionary = _dict((offset, offset + size));
      final subrs = dictionary[19];
      if (subrs != null) {
        if (subrs.length != 1) throw const FormatException('invalid CFF Subrs');
        _index(offset + subrs.single.value);
        _patchNumber(patched, subrs.single,
            relocate(offset + subrs.single.value) - relocate(offset));
      }
      absolute(dict, 18, operand: 1);
    }

    absolute(top, 15, predefined: 2); // predefined charsets are not offsets
    absolute(top, 16, predefined: 1); // predefined encodings are not offsets
    absolute(top, 17);
    absolute(top, 0x0c24); // FDArray
    absolute(top, 0x0c25); // FDSelect
    private(top);
    final fdArray = _value(top, 0x0c24);
    if (fdArray != null) {
      final index = _index(fdArray);
      if (index.start < charStrings.end && index.end > charStrings.start) {
        throw const FormatException('CFF FDArray overlaps CharStrings');
      }
      for (final range in index.ranges) {
        private(_dict(range));
      }
    }
    // SyntheticBase and embedded PostScript can refer to another font or
    // program data outside the ordinary offset-bearing fields.
    if (top.containsKey(0x0c14) || top.containsKey(0x0c15)) {
      throw const FormatException('synthetic or PostScript CFF is not subset');
    }
    return (BytesBuilder(copy: false)
          ..add(Uint8List.sublistView(patched, 0, charStrings.start))
          ..add(rebuilt)
          ..add(Uint8List.sublistView(patched, charStrings.end)))
        .takeBytes();
  }

  _CffIndex _index(int start) {
    final data = ByteData.sublistView(bytes);
    if (start < 0 || start + 2 > bytes.length) {
      throw const FormatException('invalid CFF INDEX offset');
    }
    final count = data.getUint16(start);
    if (count == 0) return _CffIndex(start, start + 2, []);
    if (start + 3 > bytes.length) {
      throw const FormatException('short CFF INDEX');
    }
    final size = bytes[start + 2];
    if (size < 1 || size > 4) {
      throw const FormatException('invalid CFF offSize');
    }
    final base = start + 3 + (count + 1) * size;
    if (base > bytes.length) throw const FormatException('short CFF offsets');
    final offsets = <int>[];
    for (var i = 0; i <= count; i++) {
      var offset = 0;
      for (var j = 0; j < size; j++) {
        offset = offset * 256 + bytes[start + 3 + i * size + j];
      }
      if (offset < 1 ||
          base + offset - 1 > bytes.length ||
          (i == 0 && offset != 1) ||
          (i > 0 && offset < offsets.last)) {
        throw const FormatException('invalid CFF INDEX range');
      }
      offsets.add(offset);
    }
    return _CffIndex(start, base + offsets.last - 1, [
      for (var i = 0; i < count; i++)
        (base + offsets[i] - 1, base + offsets[i + 1] - 1),
    ]);
  }

  Map<int, List<_CffOperand>> _dict((int, int) range) {
    final result = <int, List<_CffOperand>>{};
    var operands = <_CffOperand>[];
    var at = range.$1;
    final data = ByteData.sublistView(bytes);
    while (at < range.$2) {
      final start = at;
      final first = bytes[at++];
      int value;
      if (first >= 32 && first <= 246) {
        value = first - 139;
      } else if (first >= 247 && first <= 254) {
        final next = bytes[at++];
        value = first <= 250
            ? (first - 247) * 256 + next + 108
            : -(first - 251) * 256 - next - 108;
      } else if (first == 28 || first == 29) {
        value = first == 28 ? data.getInt16(at) : data.getInt32(at);
        at += first == 28 ? 2 : 4;
      } else if (first == 30) {
        // Real operands are irrelevant to offsets, but preserve their source
        // spans. A sentinel makes using one as an offset fail safely.
        var finished = false;
        while (at < range.$2 && !finished) {
          final nibbles = bytes[at++];
          finished = (nibbles & 15) == 15 || (nibbles >> 4) == 15;
        }
        if (!finished) throw const FormatException('unterminated CFF real');
        value = -0x7fffffff;
      } else if (first <= 21) {
        final op = first == 12 ? 0x0c00 | bytes[at++] : first;
        result[op] = operands;
        operands = [];
        continue;
      } else {
        throw const FormatException('invalid CFF DICT byte');
      }
      if (at > range.$2) throw const FormatException('short CFF DICT');
      operands.add(_CffOperand(value, start, at));
    }
    if (operands.isNotEmpty) {
      throw const FormatException('trailing CFF operands');
    }
    return result;
  }

  List<int> _charset(int offset, int count) {
    if (offset == 0) {
      if (count > 229 || cidKeyed) {
        throw const FormatException('invalid predefined CFF charset');
      }
      return [for (var gid = 0; gid < count; gid++) gid];
    }
    if (offset == 1 || offset == 2) {
      throw const FormatException(
          'predefined Expert CFF charset is not subset');
    }
    final data = ByteData.sublistView(bytes);
    var at = offset;
    final format = bytes[at++];
    final result = <int>[0];
    while (result.length < count) {
      final first = data.getUint16(at);
      at += 2;
      final left = switch (format) {
        0 => 0,
        1 => bytes[at++],
        2 => data.getUint16((at += 2) - 2),
        _ => throw const FormatException('invalid CFF charset'),
      };
      if (result.length + left + 1 > count || first + left > 65535) {
        throw const FormatException('invalid CFF charset range');
      }
      for (var value = first; value <= first + left; value++) {
        result.add(value);
      }
    }
    return result;
  }

  static int? _value(Map<int, List<_CffOperand>> dict, int op) =>
      dict[op]?.firstOrNull?.value;

  static void _patchNumber(Uint8List bytes, _CffOperand operand, int value) {
    if (value == operand.value) return;
    final first = bytes[operand.start];
    final data = ByteData.sublistView(bytes);
    if (first >= 32 && first <= 246 && value >= -107 && value <= 107) {
      bytes[operand.start] = value + 139;
    } else if (first >= 247 &&
        first <= 254 &&
        value.abs() >= 108 &&
        value.abs() <= 1131) {
      final adjusted = value.abs() - 108;
      bytes[operand.start] = (value > 0 ? 247 : 251) + adjusted ~/ 256;
      bytes[operand.start + 1] = adjusted & 255;
    } else if (first == 28 && value >= -32768 && value <= 32767) {
      data.setInt16(operand.start + 1, value);
    } else if (first == 29 && value >= -0x80000000 && value <= 0x7fffffff) {
      data.setInt32(operand.start + 1, value);
    } else {
      throw const FormatException('CFF offset cannot retain its operand width');
    }
  }

  static Uint8List _buildIndex(List<Uint8List> entries) {
    final length = entries.fold<int>(1, (sum, entry) => sum + entry.length);
    final size = length <= 255
        ? 1
        : length <= 65535
            ? 2
            : length <= 0xffffff
                ? 3
                : 4;
    final bytes = Uint8List(3 + (entries.length + 1) * size + length - 1);
    ByteData.sublistView(bytes).setUint16(0, entries.length);
    bytes[2] = size;
    var offset = 1;
    final base = 3 + (entries.length + 1) * size;
    for (var i = 0; i <= entries.length; i++) {
      for (var j = 0; j < size; j++) {
        bytes[3 + i * size + j] = (offset ~/ (1 << (8 * (size - j - 1)))) & 255;
      }
      if (i < entries.length) {
        bytes.setRange(base + offset - 1, base + offset - 1 + entries[i].length,
            entries[i]);
        offset += entries[i].length;
      }
    }
    return bytes;
  }
}

class _CffIndex {
  _CffIndex(this.start, this.end, this.ranges);
  final int start;
  final int end;
  final List<(int, int)> ranges;
}

class _CffOperand {
  _CffOperand(this.value, this.start, this.end);
  final int value;
  final int start;
  final int end;
}
