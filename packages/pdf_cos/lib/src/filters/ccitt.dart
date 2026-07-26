import 'dart:typed_data';

import '../objects.dart';
import 'filters.dart';

/// CCITTFaxDecode (§7.4.6): ITU-T T.4 (Group 3, 1-D and 2-D) and T.6
/// (Group 4) fax compression, the workhorse of scanned monochrome PDFs.
///
/// Output is 1 bit per pixel, rows padded to byte boundaries. Per the PDF
/// default (/BlackIs1 false) black pixels decode to 0 bits.
class CcittFaxFilter extends CosFilter {
  const CcittFaxFilter();

  @override
  Uint8List decode(Uint8List data, CosDictionary? params) {
    int intOf(String key, int fallback) {
      final v = params?[key];
      return v is CosInteger ? v.value : fallback;
    }

    bool boolOf(String key) => params?[key] == const CosBoolean(true);

    return CcittDecoder(
      data: data,
      k: intOf('K', 0),
      columns: intOf('Columns', 1728),
      rows: intOf('Rows', 0),
      blackIs1: boolOf('BlackIs1'),
      byteAlign: boolOf('EncodedByteAlign'),
    ).decode();
  }
}

/// The decoder itself, usable directly (the JBIG2 MMR path reuses it).
class CcittDecoder {
  CcittDecoder({
    required Uint8List data,
    required this.k,
    required this.columns,
    required this.rows,
    this.blackIs1 = false,
    this.byteAlign = false,
  }) : _reader = _Bits(data);

  /// /K: negative = Group 4, zero = Group 3 1-D, positive = Group 3 with
  /// per-line 1-D/2-D selection.
  final int k;
  final int columns;

  /// Expected row count; 0 decodes until the data runs out.
  final int rows;
  final bool blackIs1;
  final bool byteAlign;

  final _Bits _reader;

  /// Decodes all rows. Lenient: a coding error ends decoding and the
  /// rows produced so far are returned (padded to [rows] when set).
  Uint8List decode() {
    final rowBytes = (columns + 7) >> 3;
    final out = BytesBuilder();
    // changing-element positions of the reference row; an imaginary
    // all-white row precedes the first one
    var reference = <int>[columns, columns];
    var decoded = 0;

    while (rows == 0 || decoded < rows) {
      if (byteAlign) _reader.alignToByte();
      _skipEolAndFill();
      if (_reader.atEnd) break;

      bool useTwoD;
      if (k < 0) {
        useTwoD = true;
      } else if (k == 0) {
        useTwoD = false;
      } else {
        // the bit after each EOL selects the next line's coding
        final bit = _reader.tryRead(1);
        if (bit == null) break;
        useTwoD = bit == 0;
      }

      final List<int>? current;
      try {
        current =
            useTwoD ? _decodeTwoDRow(reference) : _decodeOneDRow();
      } on _CodingError {
        break;
      }
      if (current == null) break;
      out.add(_renderRow(current, rowBytes));
      decoded++;
      reference = [...current, columns, columns];
    }

    // honor a declared height even if the data fell short
    final result = out.toBytes();
    if (rows > 0 && decoded < rows) {
      final padded = Uint8List(rows * rowBytes)
        ..fillRange(0, rows * rowBytes, blackIs1 ? 0x00 : 0xFF)
        ..setRange(0, result.length, result);
      return padded;
    }
    return result;
  }

  /// Renders transition positions (color changes, starting white) to
  /// packed bits. White is 1 under the default polarity (/BlackIs1 false
  /// means 0 bits are black).
  Uint8List _renderRow(List<int> transitions, int rowBytes) {
    final row = Uint8List(rowBytes);
    if (!blackIs1) row.fillRange(0, rowBytes, 0xFF);
    var position = 0;
    var white = true;
    for (final transition in transitions) {
      final end = transition.clamp(0, columns);
      if (!white) _fillSpan(row, position, end, set: blackIs1);
      position = end;
      white = !white;
    }
    if (!blackIs1) {
      // clear pad bits beyond the last column so they stay deterministic
      final pad = rowBytes * 8 - columns;
      if (pad > 0) row[rowBytes - 1] &= 0xFF << pad;
    }
    return row;
  }

  /// Sets (or clears) bits `[start, end)` of a packed row. Whole interior
  /// bytes go through [Uint8List.fillRange]; only the two partial edge
  /// bytes are masked. A solid 1728-column run costs ~3 writes instead of
  /// 1728 read-modify-writes.
  static void _fillSpan(Uint8List row, int start, int end,
      {required bool set}) {
    if (start >= end) return;
    final firstByte = start >> 3;
    final lastByte = (end - 1) >> 3;
    // bits at or right of `start` within its byte
    final head = 0xFF >> (start & 7);
    // bits at or left of `end - 1` within its byte
    final tail = (0xFF << (7 - ((end - 1) & 7))) & 0xFF;
    if (firstByte == lastByte) {
      final mask = head & tail;
      row[firstByte] = set ? row[firstByte] | mask : row[firstByte] & ~mask;
      return;
    }
    row[firstByte] = set ? row[firstByte] | head : row[firstByte] & ~head;
    if (lastByte > firstByte + 1) {
      row.fillRange(firstByte + 1, lastByte, set ? 0xFF : 0x00);
    }
    row[lastByte] = set ? row[lastByte] | tail : row[lastByte] & ~tail;
  }

  /// Consumes EOL codes (000000000001) and the zero fill bits that may
  /// precede them.
  void _skipEolAndFill() {
    while (true) {
      final peeked = _reader.peek(12);
      if (peeked == null) {
        // trailing zero fill at the very end of the data
        if (_reader.remainingAllZero) _reader.skipToEnd();
        return;
      }
      if (peeked == 1) {
        _reader.skip(12);
        continue;
      }
      if ((peeked >> 1) == 0) {
        // eleven+ zeros that are not yet an EOL: drop one fill bit
        _reader.skip(1);
        continue;
      }
      return;
    }
  }

  List<int>? _decodeOneDRow() {
    final transitions = <int>[];
    var position = 0;
    var white = true;
    while (position < columns) {
      final run = _readRun(white: white);
      if (run == null) {
        if (transitions.isEmpty && position == 0) return null; // clean EOF
        throw const _CodingError();
      }
      position += run;
      transitions.add(position);
      white = !white;
    }
    return transitions;
  }

  List<int>? _decodeTwoDRow(List<int> reference) {
    final transitions = <int>[];
    var a0 = -1;
    var white = true;

    // A well-formed row's a0 never decreases, and `reference` is sorted,
    // so the scan for b1 can resume where the last one stopped instead of
    // restarting at 0 - the difference between O(transitions) and O(1)
    // amortized per mode code. Broken input can violate either premise, so
    // the cursor is only trusted when the row is actually sorted, and it
    // rewinds if a0 moves backwards (a VL code can do that on bad data).
    var sorted = true;
    for (var i = 1; i < reference.length; i++) {
      if (reference[i] < reference[i - 1]) {
        sorted = false;
        break;
      }
    }
    var cursor = 0;

    // b1: first reference transition right of a0 with opposite color of
    // a0; reference holds alternating white→black, black→white changes
    int b1Index() {
      int index;
      if (sorted) {
        if (cursor > 0 && reference[cursor - 1] > a0) cursor = 0;
        while (cursor < reference.length && reference[cursor] <= a0) {
          cursor++;
        }
        index = cursor;
      } else {
        index = 0;
        while (index < reference.length && reference[index] <= a0) {
          index++;
        }
      }
      // transitions at even indices flip white→black - those are the
      // "opposite of white" changes
      if (white) {
        if (index.isOdd) index++;
      } else {
        if (index.isEven) index++;
      }
      return index;
    }

    while (a0 < columns) {
      final mode = _readMode();
      if (mode == null) {
        if (transitions.isEmpty && a0 <= 0) return null; // clean EOF
        throw const _CodingError();
      }
      final index = b1Index();
      final b1 = index < reference.length ? reference[index] : columns;
      final b2 =
          index + 1 < reference.length ? reference[index + 1] : columns;

      switch (mode) {
        case _Mode.pass:
          a0 = b2;
        case _Mode.horizontal:
          final run1 = _readRun(white: white);
          final run2 = _readRun(white: !white);
          if (run1 == null || run2 == null) throw const _CodingError();
          final start = a0 < 0 ? 0 : a0;
          final a1 = start + run1;
          final a2 = a1 + run2;
          transitions
            ..add(a1)
            ..add(a2);
          a0 = a2;
        case _Mode.v0:
        case _Mode.vr1:
        case _Mode.vr2:
        case _Mode.vr3:
        case _Mode.vl1:
        case _Mode.vl2:
        case _Mode.vl3:
          final a1 = b1 + mode.verticalOffset;
          transitions.add(a1);
          a0 = a1;
          white = !white;
        case _Mode.eol:
          if (transitions.isEmpty) return null;
          return transitions;
      }
    }
    return transitions;
  }

  _Mode? _readMode() {
    final eol = _reader.peek(12);
    if (eol == 1) {
      _reader.skip(12);
      return _Mode.eol;
    }
    final available = _reader.remainingBits;
    if (available <= 0) return null;
    // one peek of the longest mode code (7 bits), zero-padded at the very
    // end of the data, then a single table hit - see [_modeLookup]
    final prefix = available >= _modeCodeMaxBits
        ? _reader.peek(_modeCodeMaxBits)!
        : _reader.peek(available)! << (_modeCodeMaxBits - available);
    final entry = _modeLookup[prefix];
    if (entry == 0) return null;
    final length = entry & 0xF;
    // a code the padding completed isn't really present
    if (length > available) return null;
    _reader.skip(length);
    return _Mode.values[(entry >> 4) - 1];
  }

  static const _modeCodeMaxBits = 7;

  /// Prefix-indexed mode table: `_modeLookup[next 7 bits]` is
  /// `((mode.index + 1) << 4) | codeLength`, or 0 for no match. Codes are
  /// prefix-free, so each fills the block of longer prefixes beneath it;
  /// shorter codes are laid down first and never overwritten, preserving
  /// the old "first match wins" order exactly.
  static final Int32List _modeLookup = () {
    final table = Int32List(1 << _modeCodeMaxBits);
    final byLength = [..._modeCodes]..sort((a, b) => a.$2.compareTo(b.$2));
    for (final (bits, length, mode) in byLength) {
      final shift = _modeCodeMaxBits - length;
      final start = bits << shift;
      for (var i = start; i < start + (1 << shift); i++) {
        if (table[i] == 0) table[i] = ((mode.index + 1) << 4) | length;
      }
    }
    return table;
  }();

  /// 2-D mode codes (T.4 table 4): V0 `1`, VR1 `011`, VL1 `010`,
  /// H `001`, P `0001`, VR2 `000011`, VL2 `000010`, VR3 `0000011`,
  /// VL3 `0000010`.
  static const List<(int, int, _Mode)> _modeCodes = [
    (0x1, 1, _Mode.v0),
    (0x3, 3, _Mode.vr1),
    (0x2, 3, _Mode.vl1),
    (0x1, 3, _Mode.horizontal),
    (0x1, 4, _Mode.pass),
    (0x3, 6, _Mode.vr2),
    (0x2, 6, _Mode.vl2),
    (0x3, 7, _Mode.vr3),
    (0x2, 7, _Mode.vl3),
  ];

  /// Reads one complete run: zero or more make-up codes (multiples of
  /// 64) followed by a terminating code (0–63). Null on end of data or
  /// an unknown code.
  int? _readRun({required bool white}) {
    var total = 0;
    while (true) {
      final run = _readRunCode(white: white);
      if (run == null) return null;
      total += run;
      if (run < 64) return total;
    }
  }

  int? _readRunCode({required bool white}) {
    final table = white ? _whiteLookup : _blackLookup;
    final available = _reader.remainingBits;
    if (available <= 0) return null;
    // one peek of the longest run code (13 bits) instead of re-peeking
    // once per candidate length; zero-padded at the end of the data
    final prefix = available >= _runCodeMaxBits
        ? _reader.peek(_runCodeMaxBits)!
        : _reader.peek(available)! << (_runCodeMaxBits - available);
    final entry = table[prefix];
    if (entry == 0) return null;
    final length = entry & 0xF;
    // a code the padding completed isn't really present
    if (length > available) return null;
    _reader.skip(length);
    return entry >> 4;
  }

  static const _runCodeMaxBits = 13;

  /// Prefix-indexed run tables built from [_whiteCodes]/[_blackCodes]:
  /// `table[next 13 bits]` is `(runLength << 4) | codeLength`, 0 for no
  /// match. A run length of 0 is representable because `codeLength` is
  /// never 0. Same shortest-code-wins ordering as [_modeLookup].
  static final Int32List _whiteLookup = _buildRunLookup(_whiteCodes);
  static final Int32List _blackLookup = _buildRunLookup(_blackCodes);

  static Int32List _buildRunLookup(Map<int, int> codes) {
    final table = Int32List(1 << _runCodeMaxBits);
    final keys = codes.keys.toList()
      ..sort((a, b) => (a >> 16).compareTo(b >> 16));
    for (final key in keys) {
      final length = key >> 16;
      final shift = _runCodeMaxBits - length;
      final start = (key & 0xFFFF) << shift;
      final entry = (codes[key]! << 4) | length;
      for (var i = start; i < start + (1 << shift); i++) {
        if (table[i] == 0) table[i] = entry;
      }
    }
    return table;
  }

  // ---------- code tables (ITU-T T.4) ----------

  static final Map<int, int> _whiteCodes = _parseTable('''
00110101 0|000111 1|0111 2|1000 3|1011 4|1100 5|1110 6|1111 7
10011 8|10100 9|00111 10|01000 11|001000 12|000011 13|110100 14
110101 15|101010 16|101011 17|0100111 18|0001100 19|0001000 20
0010111 21|0000011 22|0000100 23|0101000 24|0101011 25|0010011 26
0100100 27|0011000 28|00000010 29|00000011 30|00011010 31|00011011 32
00010010 33|00010011 34|00010100 35|00010101 36|00010110 37|00010111 38
00101000 39|00101001 40|00101010 41|00101011 42|00101100 43|00101101 44
00000100 45|00000101 46|00001010 47|00001011 48|01010010 49|01010011 50
01010100 51|01010101 52|00100100 53|00100101 54|01011000 55|01011001 56
01011010 57|01011011 58|01001010 59|01001011 60|00110010 61|00110011 62
00110100 63|11011 64|10010 128|010111 192|0110111 256|00110110 320
00110111 384|01100100 448|01100101 512|01101000 576|01100111 640
011001100 704|011001101 768|011010010 832|011010011 896|011010100 960
011010101 1024|011010110 1088|011010111 1152|011011000 1216
011011001 1280|011011010 1344|011011011 1408|010011000 1472
010011001 1536|010011010 1600|011000 1664|010011011 1728
$_extendedMakeup''');

  static final Map<int, int> _blackCodes = _parseTable('''
0000110111 0|010 1|11 2|10 3|011 4|0011 5|0010 6|00011 7|000101 8
000100 9|0000100 10|0000101 11|0000111 12|00000100 13|00000111 14
000011000 15|0000010111 16|0000011000 17|0000001000 18|00001100111 19
00001101000 20|00001101100 21|00000110111 22|00000101000 23
00000010111 24|00000011000 25|000011001010 26|000011001011 27
000011001100 28|000011001101 29|000001101000 30|000001101001 31
000001101010 32|000001101011 33|000011010010 34|000011010011 35
000011010100 36|000011010101 37|000011010110 38|000011010111 39
000001101100 40|000001101101 41|000011011010 42|000011011011 43
000001010100 44|000001010101 45|000001010110 46|000001010111 47
000001100100 48|000001100101 49|000001010010 50|000001010011 51
000000100100 52|000000110111 53|000000111000 54|000000100111 55
000000101000 56|000001011000 57|000001011001 58|000000101011 59
000000101100 60|000001011010 61|000001100110 62|000001100111 63
0000001111 64|000011001000 128|000011001001 192|000001011011 256
000000110011 320|000000110100 384|000000110101 448|0000001101100 512
0000001101101 576|0000001001010 640|0000001001011 704|0000001001100 768
0000001001101 832|0000001110010 896|0000001110011 960|0000001110100 1024
0000001110101 1088|0000001110110 1152|0000001110111 1216
0000001010010 1280|0000001010011 1344|0000001010100 1408
0000001010101 1472|0000001011010 1536|0000001011011 1600
0000001100100 1664|0000001100101 1728
$_extendedMakeup''');

  /// Extended make-up codes (T.4 table 3), shared by both colors.
  static const _extendedMakeup = '''
00000001000 1792|00000001100 1856|00000001101 1920|000000010010 1984
000000010011 2048|000000010100 2112|000000010101 2176|000000010110 2240
000000010111 2304|000000011100 2368|000000011101 2432|000000011110 2496
000000011111 2560''';

  static Map<int, int> _parseTable(String source) {
    final out = <int, int>{};
    for (final entry in source.split(RegExp(r'[|\n]'))) {
      final pair = entry.trim().split(' ');
      if (pair.length != 2) continue;
      final bits = pair[0];
      out[(bits.length << 16) | int.parse(bits, radix: 2)] =
          int.parse(pair[1]);
    }
    return out;
  }
}

enum _Mode {
  pass,
  horizontal,
  v0,
  vr1,
  vr2,
  vr3,
  vl1,
  vl2,
  vl3,
  eol;

  int get verticalOffset => switch (this) {
        _Mode.v0 => 0,
        _Mode.vr1 => 1,
        _Mode.vr2 => 2,
        _Mode.vr3 => 3,
        _Mode.vl1 => -1,
        _Mode.vl2 => -2,
        _Mode.vl3 => -3,
        _ => 0,
      };
}

class _CodingError implements Exception {
  const _CodingError();
}

class _Bits {
  _Bits(this.data);

  final Uint8List data;
  int _byte = 0;
  int _bit = 0;

  bool get atEnd => _byte >= data.length;

  void alignToByte() {
    if (_bit != 0) {
      _bit = 0;
      _byte++;
    }
  }

  void skipToEnd() {
    _byte = data.length;
    _bit = 0;
  }

  bool get remainingAllZero {
    if (atEnd) return true;
    if ((data[_byte] & (0xFF >> _bit)) != 0) return false;
    for (var i = _byte + 1; i < data.length; i++) {
      if (data[i] != 0) return false;
    }
    return true;
  }

  /// Bits left before the end of the data.
  int get remainingBits {
    if (atEnd) return 0;
    return (data.length - _byte) * 8 - _bit;
  }

  /// Peeks [count] bits, or null when fewer remain. Callers ask for at
  /// most 13 bits, so with a bit offset below 8 this touches at most three
  /// bytes - accumulated whole rather than one bit at a time.
  int? peek(int count) {
    if (count <= 0) return 0;
    if (count > remainingBits) return null;
    final need = _bit + count;
    final byteCount = (need + 7) >> 3;
    var accumulator = 0;
    for (var i = 0; i < byteCount; i++) {
      accumulator = (accumulator << 8) | data[_byte + i];
    }
    return (accumulator >> (byteCount * 8 - need)) & ((1 << count) - 1);
  }

  int? tryRead(int count) {
    final value = peek(count);
    if (value != null) skip(count);
    return value;
  }

  void skip(int count) {
    _bit += count;
    _byte += _bit >> 3;
    _bit &= 7;
  }
}
