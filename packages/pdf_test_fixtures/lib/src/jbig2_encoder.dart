/// A minimal pure-Dart JBIG2 *encoder* for the PDF embedded profile
/// (ITU-T T.88), enough to build the one shape no in-repo corpus has: a
/// separate `/JBIG2Globals` stream carrying a multi-symbol arithmetic symbol
/// dictionary, referenced by many per-page `JBIG2Decode` images - the scanned
/// book (issue #557).
///
/// Scope is deliberately narrow, matching what `jbig2enc -s` emits and what
/// [Jbig2Decoder] reads back:
///
/// * MQ arithmetic coding (Annex E), no Huffman tables;
/// * generic region template 0 with the nominal AT pixels, TPGDON off;
/// * one symbol dictionary segment (SDHUFF=0, REFAGG=0) per globals stream;
/// * one page-info + one immediate text region segment (SBHUFF=0, REFINE=0,
///   SBSTRIPS=1, TOPLEFT reference corner) per page stream.
///
/// Real-world *encoding* quality (symbol clustering, refinement, generic-region
/// tuning) is out of scope - the goal is a decodable, representative workload,
/// not a competitive encoder. The round-trip is asserted against the shipping
/// decoder in `pdf_cos/test/jbig2_roundtrip_test.dart`.
library;

import 'dart:typed_data';

/// A 1-bit-per-pixel bitmap in JBIG2 polarity: 1 is black.
class Jbig2Bitmap {
  Jbig2Bitmap(this.width, this.height) : data = Uint8List(width * height);

  final int width;
  final int height;
  final Uint8List data;

  int get(int x, int y) {
    if (x < 0 || x >= width || y < 0 || y >= height) return 0;
    return data[y * width + x];
  }

  void set(int x, int y, int value) {
    if (x < 0 || x >= width || y < 0 || y >= height) return;
    data[y * width + x] = value;
  }

  /// Fills the axis-aligned rectangle at ([x], [y]) with black.
  void fillRect(int x, int y, int w, int h) {
    for (var dy = 0; dy < h; dy++) {
      for (var dx = 0; dx < w; dx++) {
        set(x + dx, y + dy, 1);
      }
    }
  }
}

/// One symbol instance on a page: [symbol] drawn with its top-left corner at
/// ([x], [y]) in image pixels.
class Jbig2Placement {
  const Jbig2Placement(this.symbol, this.x, this.y);

  final int symbol;
  final int x;
  final int y;
}

/// Encodes [symbols] as a standalone `/JBIG2Globals` stream: a single
/// arithmetic symbol dictionary segment (number 0) exporting every symbol.
///
/// Symbols are coded in height classes, so [symbols] must be ordered by
/// non-decreasing height - run it through [sortSymbolsForDictionary] first.
/// Symbol ids are positions in that list; pass the same list to
/// [encodeJbig2TextPage].
Uint8List encodeJbig2Globals(List<Jbig2Bitmap> symbols) {
  if (symbols.isEmpty) throw ArgumentError('a dictionary needs symbols');
  for (var i = 1; i < symbols.length; i++) {
    if (symbols[i].height < symbols[i - 1].height) {
      throw ArgumentError('symbols must be sorted by non-decreasing height');
    }
  }
  final sorted = symbols;
  final payload = BytesBuilder()
    ..add(_u16(0)) // SDHUFF=0, REFAGG=0, SDTEMPLATE=0, no retained contexts
    ..add(_atBytes(_nominalAt)) // SDAT: template 0 takes four AT pixels
    ..add(_u32(sorted.length)) // SDNUMEXSYMS
    ..add(_u32(sorted.length)); // SDNUMNEWSYMS

  final mq = _MqEncoder();
  final generic = _ArithContexts(1 << 16);
  final iadh = _ArithContexts(512);
  final iadw = _ArithContexts(512);
  final iaex = _ArithContexts(512);

  var heightClass = 0;
  var index = 0;
  while (index < sorted.length) {
    final height = sorted[index].height;
    mq.encodeInt(iadh, height - heightClass);
    heightClass = height;
    var symbolWidth = 0;
    while (index < sorted.length && sorted[index].height == height) {
      final symbol = sorted[index++];
      mq.encodeInt(iadw, symbol.width - symbolWidth);
      symbolWidth = symbol.width;
      _encodeGeneric(mq, generic, symbol);
    }
    mq.encodeInt(iadw, null); // OOB closes the height class
  }
  // Export flags are alternating (skip, export) runs: skip none, export all.
  mq
    ..encodeInt(iaex, 0)
    ..encodeInt(iaex, sorted.length);
  payload.add(mq.flush());

  return _segment(
    number: _globalsDictionarySegment,
    type: 0, // symbol dictionary
    referred: const [],
    page: 0,
    payload: payload.takeBytes(),
  );
}

/// [symbols] in the height-class order a symbol dictionary needs, ties broken
/// by the caller's order (Dart's [List.sort] is not stable on its own).
List<Jbig2Bitmap> sortSymbolsForDictionary(List<Jbig2Bitmap> symbols) {
  final indexed = [
    for (var i = 0; i < symbols.length; i++) (symbols[i], i),
  ]..sort((a, b) =>
      a.$1.height != b.$1.height ? a.$1.height - b.$1.height : a.$2 - b.$2);
  return [for (final (symbol, _) in indexed) symbol];
}

/// Encodes one page's `JBIG2Decode` image stream: a page-information segment
/// plus an immediate lossless text region that places [placements] (symbol ids
/// index [symbols], which must be the dictionary order) over a [width] x
/// [height] page.
///
/// The stream refers to the symbol dictionary in the globals stream produced
/// by [encodeJbig2Globals], so it only decodes when that stream is passed as
/// `/DecodeParms << /JBIG2Globals ... >>`.
Uint8List encodeJbig2TextPage({
  required int width,
  required int height,
  required List<Jbig2Bitmap> symbols,
  required List<Jbig2Placement> placements,
}) {
  if (placements.isEmpty) throw ArgumentError('a text region needs instances');

  final pageInfo = BytesBuilder()
    ..add(_u32(width))
    ..add(_u32(height))
    ..add(_u32(0)) // X resolution: unknown
    ..add(_u32(0)) // Y resolution: unknown
    ..addByte(1) // flags: lossless, default pixel 0, default OR combination
    ..add(_u16(0)); // striping information

  // Strips of instances sharing one T coordinate (SBSTRIPS = 1), in the
  // top-to-bottom, left-to-right order a text region is coded in.
  final strips = <int, List<Jbig2Placement>>{};
  for (final placement in placements) {
    (strips[placement.y] ??= []).add(placement);
  }
  final stripTs = strips.keys.toList()..sort();
  for (final t in stripTs) {
    strips[t]!.sort((a, b) => a.x - b.x);
  }

  var codeLength = 0;
  while ((1 << codeLength) < symbols.length) {
    codeLength++;
  }
  if (codeLength == 0) codeLength = 1;

  final region = BytesBuilder()
    ..add(_u32(width)) // region width
    ..add(_u32(height)) // region height
    ..add(_u32(0)) // region X
    ..add(_u32(0)) // region Y
    ..addByte(0) // external combination operator: OR
    // SBHUFF=0, REFINE=0, LOGSBSTRIPS=0, REFCORNER=TOPLEFT, TRANSPOSED=0,
    // SBCOMBOP=OR, SBDEFPIXEL=0, SBDSOFFSET=0, SBRTEMPLATE=0
    ..add(_u16(1 << 4))
    ..add(_u32(placements.length));

  final mq = _MqEncoder();
  final iadt = _ArithContexts(512);
  final iafs = _ArithContexts(512);
  final iads = _ArithContexts(512);
  final iaid = _ArithContexts(1 << (codeLength + 1));

  mq.encodeInt(iadt, 0); // STRIPT: the first strip's T is absolute
  var stripT = 0;
  var firstS = 0;
  var placed = 0;
  outer:
  for (final t in stripTs) {
    mq.encodeInt(iadt, t - stripT);
    stripT = t;
    final strip = strips[t]!;
    mq.encodeInt(iafs, strip.first.x - firstS);
    firstS = strip.first.x;
    var curS = firstS;
    for (var i = 0; i < strip.length; i++) {
      if (i > 0) {
        mq.encodeInt(iads, strip[i].x - curS);
        curS = strip[i].x;
      }
      mq.encodeId(iaid, codeLength, strip[i].symbol);
      curS += symbols[strip[i].symbol].width - 1;
      placed++;
      // The decoder stops on the instance count without reading a closing
      // OOB, so the last strip must not emit one.
      if (placed >= placements.length) break outer;
    }
    mq.encodeInt(iads, null); // OOB closes the strip
  }
  region.add(mq.flush());

  return Uint8List.fromList([
    ..._segment(
      number: 1,
      type: 48, // page information
      referred: const [],
      page: 1,
      payload: pageInfo.takeBytes(),
    ),
    ..._segment(
      number: 2,
      type: 6, // immediate text region
      referred: const [_globalsDictionarySegment],
      page: 1,
      payload: region.takeBytes(),
    ),
  ]);
}

// The symbol dictionary lives in the globals stream as segment 0; every page's
// text region refers to it by that number.
const _globalsDictionarySegment = 0;

/// Nominal AT pixels for generic region template 0 (what every encoder emits).
const _nominalAt = [(3, -1), (-3, -1), (2, -2), (-2, -2)];

/// Template 0's fixed pixels (T.88 figure 4), without the AT slots.
const _template0 = [
  (-1, -2), (0, -2), (1, -2), //
  (-2, -1), (-1, -1), (0, -1), (1, -1), (2, -1),
  (-4, 0), (-3, 0), (-2, 0), (-1, 0),
];

/// Encodes [bitmap] with the generic region procedure (§6.2), template 0.
///
/// The context is the combined template sorted by row then column, most
/// significant bit first - the same order the decoder builds it in, which is
/// all that has to agree.
void _encodeGeneric(_MqEncoder mq, _ArithContexts cx, Jbig2Bitmap bitmap) {
  final pixels = [..._template0, ..._nominalAt]
    ..sort((a, b) => a.$2 != b.$2 ? a.$2 - b.$2 : a.$1 - b.$1);
  for (var y = 0; y < bitmap.height; y++) {
    for (var x = 0; x < bitmap.width; x++) {
      var context = 0;
      for (final (dx, dy) in pixels) {
        context = (context << 1) | bitmap.get(x + dx, y + dy);
      }
      mq.encode(cx, context, bitmap.get(x, y));
    }
  }
}

/// Wraps [payload] in a segment header (§7.2). Segment and referred-to numbers
/// stay under 257 so the referred-to fields are one byte each, and the page
/// association is the one-byte form.
Uint8List _segment({
  required int number,
  required int type,
  required List<int> referred,
  required int page,
  required Uint8List payload,
}) {
  if (referred.length > 4) {
    throw ArgumentError('the short referred-to form holds at most 4 entries');
  }
  return Uint8List.fromList([
    ..._u32(number),
    type, // segment header flags: type, one-byte page association
    referred.length << 5, // referred-to count, no retain bits
    ...referred,
    page,
    ..._u32(payload.length),
    ...payload,
  ]);
}

List<int> _u16(int v) => [(v >> 8) & 0xFF, v & 0xFF];

List<int> _u32(int v) =>
    [(v >> 24) & 0xFF, (v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF];

List<int> _atBytes(List<(int, int)> at) =>
    [for (final (x, y) in at) ...[x & 0xFF, y & 0xFF]];

/// Adaptive probability state for one arithmetic context set.
class _ArithContexts {
  _ArithContexts(int size)
      : mps = Int8List(size),
        index = Uint8List(size);

  final Int8List mps;
  final Uint8List index;
}

/// The MQ arithmetic *encoder* (T.88 Annex E.3) - the inverse of pdf_cos's
/// `MqDecoder`, in the standard software formulation (the one OpenJPEG and
/// jbig2enc share): CODEMPS/CODELPS, RENORME, BYTEOUT with carry propagation
/// into the previous byte, and the SETBITS flush.
class _MqEncoder {
  // Index 0 is the "byte before the buffer" the spec's BYTEOUT reads and
  // carries into; the real output is [1..bp]. Dropped by flush().
  final List<int> _out = [0];
  int _bp = 0;
  int _a = 0x8000;
  int _c = 0;
  int _ct = 12;

  static const _qe = [
    (0x5601, 1, 1, 1), (0x3401, 2, 6, 0), (0x1801, 3, 9, 0), //
    (0x0AC1, 4, 12, 0), (0x0521, 5, 29, 0), (0x0221, 38, 33, 0),
    (0x5601, 7, 6, 1), (0x5401, 8, 14, 0), (0x4801, 9, 14, 0),
    (0x3801, 10, 14, 0), (0x3001, 11, 17, 0), (0x2401, 12, 18, 0),
    (0x1C01, 13, 20, 0), (0x1601, 29, 21, 0), (0x5601, 15, 14, 1),
    (0x5401, 16, 14, 0), (0x5101, 17, 15, 0), (0x4801, 18, 16, 0),
    (0x3801, 19, 17, 0), (0x3401, 20, 18, 0), (0x3001, 21, 19, 0),
    (0x2801, 22, 19, 0), (0x2401, 23, 20, 0), (0x2201, 24, 21, 0),
    (0x1C01, 25, 22, 0), (0x1801, 26, 23, 0), (0x1601, 27, 24, 0),
    (0x1401, 28, 25, 0), (0x1201, 29, 26, 0), (0x1101, 30, 27, 0),
    (0x0AC1, 31, 28, 0), (0x09C1, 32, 29, 0), (0x08A1, 33, 30, 0),
    (0x0521, 34, 31, 0), (0x0441, 35, 32, 0), (0x02A1, 36, 33, 0),
    (0x0221, 37, 34, 0), (0x0141, 38, 35, 0), (0x0111, 39, 36, 0),
    (0x0085, 40, 37, 0), (0x0049, 41, 38, 0), (0x0025, 42, 39, 0),
    (0x0015, 43, 40, 0), (0x0009, 44, 41, 0), (0x0005, 45, 42, 0),
    (0x0001, 45, 43, 0), (0x5601, 46, 46, 0),
  ];

  /// Codes decision [d] in context [context] of [cx].
  void encode(_ArithContexts cx, int context, int d) {
    final i = cx.index[context];
    final mps = cx.mps[context];
    final (qe, nmps, nlps, sw) = _qe[i];

    if (d == mps) {
      _a -= qe;
      if (_a & 0x8000 == 0) {
        if (_a < qe) {
          _a = qe;
        } else {
          _c += qe;
        }
        cx.index[context] = nmps;
        _renorm();
      } else {
        _c += qe;
      }
    } else {
      _a -= qe;
      if (_a < qe) {
        _c += qe;
      } else {
        _a = qe;
      }
      if (sw == 1) cx.mps[context] = 1 - mps;
      cx.index[context] = nlps;
      _renorm();
    }
  }

  void _renorm() {
    do {
      _a = (_a << 1) & 0xFFFF;
      _c = (_c << 1) & 0xFFFFFFFF;
      _ct--;
      if (_ct == 0) _byteOut();
    } while (_a & 0x8000 == 0);
  }

  void _byteOut() {
    if (_out[_bp] == 0xFF) {
      _emit((_c >> 20) & 0xFF);
      _c &= 0xFFFFF;
      _ct = 7;
    } else if (_c & 0x8000000 == 0) {
      _emit((_c >> 19) & 0xFF);
      _c &= 0x7FFFF;
      _ct = 8;
    } else {
      // Carry out of C propagates into the byte already written.
      _out[_bp]++;
      if (_out[_bp] == 0xFF) {
        _c &= 0x7FFFFFF;
        _emit((_c >> 20) & 0xFF);
        _c &= 0xFFFFF;
        _ct = 7;
      } else {
        _emit((_c >> 19) & 0xFF);
        _c &= 0x7FFFF;
        _ct = 8;
      }
    }
  }

  void _emit(int byte) {
    _bp++;
    _out.add(byte);
  }

  /// Codes an integer with the Annex A.2 procedure; null is OOB.
  void encodeInt(_ArithContexts cx, int? value) {
    var prev = 1;
    void bit(int b) {
      encode(cx, prev, b);
      prev = prev < 256 ? (prev << 1) | b : ((((prev << 1) | b) & 511) | 256);
    }

    void bits(int v, int count) {
      for (var i = count - 1; i >= 0; i--) {
        bit((v >> i) & 1);
      }
    }

    // OOB is the otherwise-unrepresentable "negative zero".
    final magnitude = value == null ? 0 : value.abs();
    bit(value == null || value < 0 ? 1 : 0);
    if (magnitude < 4) {
      bit(0);
      bits(magnitude, 2);
    } else if (magnitude < 20) {
      bit(1);
      bit(0);
      bits(magnitude - 4, 4);
    } else if (magnitude < 84) {
      bit(1);
      bit(1);
      bit(0);
      bits(magnitude - 20, 6);
    } else if (magnitude < 340) {
      bit(1);
      bit(1);
      bit(1);
      bit(0);
      bits(magnitude - 84, 8);
    } else if (magnitude < 4436) {
      bit(1);
      bit(1);
      bit(1);
      bit(1);
      bit(0);
      bits(magnitude - 340, 12);
    } else {
      bit(1);
      bit(1);
      bit(1);
      bit(1);
      bit(1);
      bits(magnitude - 4436, 32);
    }
  }

  /// Codes a symbol id with the IAID procedure: [codeLength] bits, most
  /// significant first, each in the context of the bits already coded.
  void encodeId(_ArithContexts cx, int codeLength, int id) {
    var prev = 1;
    for (var i = codeLength - 1; i >= 0; i--) {
      final b = (id >> i) & 1;
      encode(cx, prev, b);
      prev = (prev << 1) | b;
    }
  }

  /// Terminates the codestream and returns its bytes (T.88 E.3.8).
  Uint8List flush() {
    // SETBITS: push as many 1 bits into C as the interval allows.
    final tempc = _c + _a;
    _c |= 0xFFFF;
    if (_c >= tempc) _c -= 0x8000;
    _c = (_c << _ct) & 0xFFFFFFFF;
    _byteOut();
    _c = (_c << _ct) & 0xFFFFFFFF;
    _byteOut();
    // A trailing 0xFF carries no information - it is the marker prefix.
    final length = _out[_bp] == 0xFF ? _bp - 1 : _bp;
    return Uint8List.fromList([
      ..._out.sublist(1, 1 + length),
      0xFF, 0xAC, // the end-of-codestream marker
    ]);
  }
}
