import 'dart:typed_data';

import 'ccitt.dart';
import 'mq.dart';

/// JBIG2 decoder for the PDF embedded profile (§7.4.7, ITU-T T.88).
///
/// Coverage: arithmetic-coded generic regions (templates 0–3, TPGDON)
/// and MMR-coded ones (via the CCITT engine), symbol dictionaries and
/// text regions (arithmetic coding), pattern dictionaries, and
/// arithmetic-coded halftone/refinement regions, with /JBIG2Globals support — which
/// spans what real-world PDF encoders (jbig2enc, Acrobat) emit. Custom
/// Huffman tables and refined symbol aggregation are not supported; such
/// files decode to null and the image is skipped.
///
/// Output is 1 bit per pixel with PDF polarity: black pixels are 0 bits
/// (matching CCITTFaxDecode's default), rows padded to byte boundaries.
class Jbig2Decoder {
  Jbig2Decoder._(this.width, this.height);

  final int width;
  final int height;

  final Map<int, List<_Bitmap>> _symbolDicts = {};
  final Map<int, List<_Bitmap>> _patternDicts = {};
  final Map<int, _Bitmap> _regionBitmaps = {};
  _Bitmap? _page;
  int _pageDefault = 0;

  static Uint8List? decode({
    required Uint8List data,
    Uint8List? globals,
    required int width,
    required int height,
  }) {
    try {
      final decoder = Jbig2Decoder._(width, height);
      if (globals != null) decoder._processSegments(globals);
      decoder._processSegments(data);
      final page = decoder._page;
      if (page == null) return null;
      // pack to PDF polarity: JBIG2 1 = black, PDF default 0 = black
      final rowBytes = (width + 7) >> 3;
      final out = Uint8List(rowBytes * height)
        ..fillRange(0, rowBytes * height, 0xFF);
      for (var y = 0; y < height && y < page.height; y++) {
        for (var x = 0; x < width && x < page.width; x++) {
          if (page.get(x, y) != 0) {
            out[y * rowBytes + (x >> 3)] &= ~(0x80 >> (x & 7));
          }
        }
      }
      return out;
    } on Object {
      return null; // unsupported feature or corrupt stream
    }
  }

  // ---------- segment layer (§7.2) ----------

  void _processSegments(Uint8List data) {
    var p = 0;
    final view = ByteData.sublistView(data);
    while (p + 11 <= data.length) {
      final number = view.getUint32(p);
      final flags = data[p + 4];
      final type = flags & 0x3F;
      final pageAssociation4 = (flags & 0x40) != 0;
      p += 5;

      var referredCount = data[p] >> 5;
      if (referredCount == 7) {
        referredCount = view.getUint32(p) & 0x1FFFFFFF;
        p += 4 + ((referredCount + 8) >> 3);
      } else {
        p += 1;
      }
      final referredSize = number <= 256 ? 1 : (number <= 65536 ? 2 : 4);
      final referred = <int>[];
      for (var i = 0; i < referredCount; i++) {
        referred.add(switch (referredSize) {
          1 => data[p],
          2 => view.getUint16(p),
          _ => view.getUint32(p),
        });
        p += referredSize;
      }
      p += pageAssociation4 ? 4 : 1;
      final length = view.getUint32(p);
      p += 4;
      if (length == 0xFFFFFFFF) {
        throw const FormatException('unknown segment length');
      }
      final end = p + length;
      if (end > data.length) break;
      final payload = Uint8List.sublistView(data, p, end);

      switch (type) {
        case 0: // symbol dictionary
          _symbolDicts[number] = _readSymbolDictionary(payload, referred);
        case 16: // pattern dictionary
          _patternDicts[number] = _readPatternDictionary(payload);
        case 20 || 22 || 23: // halftone region
          _readHalftoneRegion(payload, referred);
        case 4 || 6 || 7: // text region (intermediate/immediate/lossless)
          _readTextRegion(payload, referred);
        case 36: // intermediate generic region
          _regionBitmaps[number] = _readGenericRegionSegment(payload).$1;
        case 38 || 39: // immediate generic region
          final (region, x, y, op) = _readGenericRegionSegment(payload);
          _ensurePage().compose(region, x, y, op);
        case 40: // intermediate generic refinement region
          _regionBitmaps[number] =
              _readGenericRefinementRegionSegment(payload, referred).$1;
        case 42 || 43: // immediate generic refinement region
          final (region, x, y, op) =
              _readGenericRefinementRegionSegment(payload, referred);
          _ensurePage().compose(region, x, y, op);
        case 48: // page information
          _readPageInfo(payload);
        case 49 || 50 || 51 || 62:
          break; // end of page/stripe/file, extension: nothing to do
        default:
          throw FormatException('unsupported JBIG2 segment type $type');
      }
      p = end;
    }
  }

  void _readPageInfo(Uint8List data) {
    final view = ByteData.sublistView(data);
    var pageWidth = view.getUint32(0);
    var pageHeight = view.getUint32(4);
    final flags = data[16];
    _pageDefault = (flags >> 2) & 1;
    if (pageHeight == 0xFFFFFFFF) pageHeight = height;
    // guard absurd allocations from corrupt headers
    if (pageWidth > 1 << 16 || pageHeight > 1 << 16) {
      pageWidth = width;
      pageHeight = height;
    }
    _page = _Bitmap(pageWidth, pageHeight, fill: _pageDefault);
  }

  _Bitmap _ensurePage() => _page ??= _Bitmap(width, height, fill: 0);

  // ---------- region segment info (§7.4.1) ----------

  static (int, int, int, int, int) _regionInfo(ByteData view) => (
        view.getUint32(0), // width
        view.getUint32(4), // height
        view.getUint32(8), // x
        view.getUint32(12), // y
        view.getUint8(16) & 7, // external combination operator
      );

  (_Bitmap, int, int, int) _readGenericRegionSegment(Uint8List data) {
    final view = ByteData.sublistView(data);
    final (w, h, x, y, op) = _regionInfo(view);
    var p = 17;
    final flags = data[p++];
    final mmr = flags & 1;
    final template = (flags >> 1) & 3;
    final tpgdon = (flags >> 3) & 1;
    final at = <(int, int)>[];
    if (mmr == 0) {
      final count = template == 0 ? 4 : 1;
      for (var i = 0; i < count; i++) {
        at.add((view.getInt8(p), view.getInt8(p + 1)));
        p += 2;
      }
    }
    final payload = Uint8List.sublistView(data, p);
    final _Bitmap region;
    if (mmr == 1) {
      region = _decodeMmr(payload, w, h);
    } else {
      final decoder = MqDecoder(payload);
      final contexts = Int8List(1 << 16);
      final indexes = Uint8List(1 << 16);
      region = _decodeGeneric(
          decoder, contexts, indexes, w, h, template, at, tpgdon == 1);
    }
    return (region, x, y, op);
  }

  (_Bitmap, int, int, int) _readGenericRefinementRegionSegment(
      Uint8List data, List<int> referred) {
    if (data.length < 18) throw const FormatException('short refinement');
    final view = ByteData.sublistView(data);
    final (w, h, x, y, op) = _regionInfo(view);
    var p = 17;
    final flags = data[p++];
    final template = flags & 1;
    final tpgdon = (flags >> 1) & 1;
    if (tpgdon != 0) {
      throw const FormatException('TPGRON refinement regions');
    }
    var at0 = (-1, -1);
    var at1 = (-1, -1);
    if (template == 0) {
      if (data.length < p + 4) {
        throw const FormatException('short refinement template');
      }
      at0 = (view.getInt8(p), view.getInt8(p + 1));
      at1 = (view.getInt8(p + 2), view.getInt8(p + 3));
      p += 4;
    }
    final reference = _findReferenceBitmap(referred);
    final decoder = MqDecoder(Uint8List.sublistView(data, p));
    final contexts = Int8List(template == 0 ? 1 << 13 : 1 << 10);
    final indexes = Uint8List(contexts.length);
    final region = _decodeRefinement(
      decoder,
      contexts,
      indexes,
      w,
      h,
      reference,
      template,
      at0,
      at1,
    );
    return (region, x, y, op);
  }

  _Bitmap _findReferenceBitmap(List<int> referred) {
    for (final segment in referred) {
      final bitmap = _regionBitmaps[segment];
      if (bitmap != null) return bitmap;
    }
    final page = _page;
    if (page != null) return page;
    throw const FormatException('refinement has no reference bitmap');
  }

  // ---------- pattern dictionaries and halftone regions (§6.6, §6.7) ----------

  List<_Bitmap> _readPatternDictionary(Uint8List data) {
    if (data.length < 7) throw const FormatException('short pattern dict');
    final view = ByteData.sublistView(data);
    final flags = data[0];
    final mmr = flags & 1;
    final template = (flags >> 1) & 3;
    final patternWidth = data[1];
    final patternHeight = data[2];
    final patternCount = view.getUint32(3) + 1;
    if (patternWidth <= 0 ||
        patternHeight <= 0 ||
        patternCount <= 0 ||
        patternCount > 1 << 16) {
      throw const FormatException('invalid pattern dictionary');
    }

    final collectiveWidth = patternWidth * patternCount;
    final payload = Uint8List.sublistView(data, 7);
    final _Bitmap collective;
    if (mmr == 1) {
      collective = _decodeMmr(payload, collectiveWidth, patternHeight);
    } else {
      final decoder = MqDecoder(payload);
      final contexts = Int8List(1 << 16);
      final indexes = Uint8List(1 << 16);
      final at = template == 0
          ? [
              (-patternWidth, 0),
              (-3, -1),
              (2, -2),
              (-2, -2),
            ]
          : [(-patternWidth, 0)];
      collective = _decodeGeneric(decoder, contexts, indexes, collectiveWidth,
          patternHeight, template, at, false);
    }

    return [
      for (var i = 0; i < patternCount; i++)
        _copyBitmap(
            collective, i * patternWidth, 0, patternWidth, patternHeight),
    ];
  }

  void _readHalftoneRegion(Uint8List data, List<int> referred) {
    if (data.length < 38) throw const FormatException('short halftone');
    final view = ByteData.sublistView(data);
    final (w, h, x, y, op) = _regionInfo(view);
    var p = 17;
    final flags = data[p++];
    final mmr = flags & 1;
    final template = (flags >> 1) & 3;
    final enableSkip = (flags >> 3) & 1;
    final combOp = (flags >> 4) & 7;
    final defaultPixel = (flags >> 7) & 1;
    final gridWidth = view.getUint32(p);
    final gridHeight = view.getUint32(p + 4);
    final gridX = view.getInt32(p + 8);
    final gridY = view.getInt32(p + 12);
    p += 16;
    final stepX = view.getInt16(p);
    final stepY = view.getInt16(p + 2);
    p += 4;
    if (mmr == 1 || enableSkip == 1) {
      throw const FormatException('unsupported halftone coding');
    }
    if (gridWidth <= 0 || gridHeight <= 0) return;

    final patterns = <_Bitmap>[
      for (final segment in referred) ...?_patternDicts[segment],
    ];
    if (patterns.isEmpty) {
      throw const FormatException('halftone has no pattern dictionary');
    }

    var bitsPerPixel = 0;
    while (patterns.length > (1 << ++bitsPerPixel)) {}
    if (bitsPerPixel > 16) {
      throw const FormatException('halftone has too many patterns');
    }

    final gray = _decodeGrayScaleImage(
      Uint8List.sublistView(data, p),
      gridWidth,
      gridHeight,
      bitsPerPixel,
      template,
    );
    final region = _Bitmap(w, h, fill: defaultPixel);
    for (var mg = 0; mg < gridHeight; mg++) {
      for (var ng = 0; ng < gridWidth; ng++) {
        var index = gray[mg * gridWidth + ng];
        if (index >= patterns.length) index = patterns.length - 1;
        final px = (gridX + mg * stepY + ng * stepX) >> 8;
        final py = (gridY + mg * stepX - ng * stepY) >> 8;
        region.compose(patterns[index], px, py, combOp);
      }
    }
    _ensurePage().compose(region, x, y, op);
  }

  Uint16List _decodeGrayScaleImage(
    Uint8List data,
    int w,
    int h,
    int bitsPerPixel,
    int template,
  ) {
    final decoder = MqDecoder(data);
    final contexts = Int8List(1 << 16);
    final indexes = Uint8List(1 << 16);
    final at = template == 0
        ? [
            (3, -1),
            (-3, -1),
            (2, -2),
            (-2, -2),
          ]
        : [(template <= 1 ? 3 : 2, -1)];
    final planes = List<_Bitmap?>.filled(bitsPerPixel, null);
    for (var i = bitsPerPixel - 1; i >= 0; i--) {
      final plane =
          _decodeGeneric(decoder, contexts, indexes, w, h, template, at, false);
      if (i < bitsPerPixel - 1) {
        final higher = planes[i + 1]!;
        for (var p = 0; p < plane.data.length; p++) {
          plane.data[p] ^= higher.data[p];
        }
      }
      planes[i] = plane;
    }

    final values = Uint16List(w * h);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        var value = 0;
        for (var i = 0; i < bitsPerPixel; i++) {
          value |= planes[i]!.get(x, y) << i;
        }
        values[y * w + x] = value;
      }
    }
    return values;
  }

  static _Bitmap _copyBitmap(_Bitmap source, int x, int y, int w, int h) {
    final out = _Bitmap(w, h, fill: 0);
    for (var sy = 0; sy < h; sy++) {
      for (var sx = 0; sx < w; sx++) {
        if (source.get(x + sx, y + sy) != 0) out.set(sx, sy, 1);
      }
    }
    return out;
  }

  static _Bitmap _decodeMmr(Uint8List data, int w, int h) {
    final packed = CcittDecoder(
      data: data,
      k: -1,
      columns: w,
      rows: h,
      blackIs1: true, // JBIG2 bitmaps carry 1 = black
    ).decode();
    final bitmap = _Bitmap(w, h, fill: 0);
    final rowBytes = (w + 7) >> 3;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        if ((packed[y * rowBytes + (x >> 3)] >> (7 - (x & 7))) & 1 != 0) {
          bitmap.set(x, y, 1);
        }
      }
    }
    return bitmap;
  }

  // ---------- generic region decoding (§6.2) ----------

  /// Nominal template pixels (without the AT slots).
  static const _templates = [
    [
      (-1, -2), (0, -2), (1, -2), //
      (-2, -1), (-1, -1), (0, -1), (1, -1), (2, -1),
      (-4, 0), (-3, 0), (-2, 0), (-1, 0),
    ],
    [
      (-1, -2), (0, -2), (1, -2), (2, -2), //
      (-2, -1), (-1, -1), (0, -1), (1, -1), (2, -1),
      (-3, 0), (-2, 0), (-1, 0),
    ],
    [
      (-1, -2), (0, -2), (1, -2), //
      (-2, -1), (-1, -1), (0, -1), (1, -1),
      (-2, 0), (-1, 0),
    ],
    [
      (-3, -1), (-2, -1), (-1, -1), (0, -1), (1, -1), //
      (-4, 0), (-3, 0), (-2, 0), (-1, 0),
    ],
  ];

  static const _tpgdonContexts = [0x9B25, 0x0795, 0x00E5, 0x0195];

  static _Bitmap _decodeGeneric(
    MqDecoder decoder,
    Int8List contexts,
    Uint8List indexes,
    int w,
    int h,
    int template,
    List<(int, int)> at,
    bool tpgdon,
  ) {
    // the bit order is the combined template sorted by row then column,
    // most significant first (how every encoder builds its contexts)
    final pixels = [..._templates[template], ...at]
      ..sort((a, b) => a.$2 != b.$2 ? a.$2 - b.$2 : a.$1 - b.$1);

    final bitmap = _Bitmap(w, h, fill: 0);
    var ltp = 0;
    for (var y = 0; y < h; y++) {
      if (tpgdon) {
        final bit =
            decoder.decode(contexts, indexes, _tpgdonContexts[template]);
        ltp ^= bit;
        if (ltp == 1) {
          bitmap.copyRow(y); // duplicate the row above
          continue;
        }
      }
      for (var x = 0; x < w; x++) {
        var context = 0;
        for (final (dx, dy) in pixels) {
          context = (context << 1) | bitmap.get(x + dx, y + dy);
        }
        final bit = decoder.decode(contexts, indexes, context);
        if (bit != 0) bitmap.set(x, y, 1);
      }
    }
    return bitmap;
  }

  static _Bitmap _decodeRefinement(
    MqDecoder decoder,
    Int8List contexts,
    Uint8List indexes,
    int w,
    int h,
    _Bitmap reference,
    int template,
    (int, int) at0,
    (int, int) at1,
  ) {
    final bitmap = _Bitmap(w, h, fill: 0);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final context = template == 0
            ? _refinementContext0(bitmap, reference, x, y, at0, at1)
            : _refinementContext1(bitmap, reference, x, y);
        final bit = decoder.decode(contexts, indexes, context);
        if (bit != 0) bitmap.set(x, y, 1);
      }
    }
    return bitmap;
  }

  static int _refinementContext0(
    _Bitmap bitmap,
    _Bitmap reference,
    int x,
    int y,
    (int, int) at0,
    (int, int) at1,
  ) =>
      bitmap.get(x - 1, y) |
      (bitmap.get(x + 1, y - 1) << 1) |
      (bitmap.get(x, y - 1) << 2) |
      (bitmap.get(x + at0.$1, y + at0.$2) << 3) |
      (reference.get(x + 1, y + 1) << 4) |
      (reference.get(x, y + 1) << 5) |
      (reference.get(x - 1, y + 1) << 6) |
      (reference.get(x + 1, y) << 7) |
      (reference.get(x, y) << 8) |
      (reference.get(x - 1, y) << 9) |
      (reference.get(x + 1, y - 1) << 10) |
      (reference.get(x, y - 1) << 11) |
      (reference.get(x + at1.$1, y + at1.$2) << 12);

  static int _refinementContext1(
    _Bitmap bitmap,
    _Bitmap reference,
    int x,
    int y,
  ) =>
      bitmap.get(x - 1, y) |
      (bitmap.get(x + 1, y - 1) << 1) |
      (bitmap.get(x, y - 1) << 2) |
      (bitmap.get(x - 1, y - 1) << 3) |
      (reference.get(x + 1, y + 1) << 4) |
      (reference.get(x, y + 1) << 5) |
      (reference.get(x + 1, y) << 6) |
      (reference.get(x, y) << 7) |
      (reference.get(x - 1, y) << 8) |
      (reference.get(x, y - 1) << 9);

  // ---------- symbol dictionary (§6.5) ----------

  List<_Bitmap> _readSymbolDictionary(Uint8List data, List<int> referred) {
    final view = ByteData.sublistView(data);
    final flags = view.getUint16(0);
    final huffman = flags & 1;
    final refAgg = (flags >> 1) & 1;
    final template = (flags >> 10) & 3;
    if (huffman == 1) {
      return _readHuffmanSymbolDictionary(data, referred);
    }
    if (refAgg == 1) {
      throw const FormatException('Huffman/refinement symbol dictionaries');
    }
    var p = 2;
    final at = <(int, int)>[];
    final atCount = template == 0 ? 4 : 1;
    for (var i = 0; i < atCount; i++) {
      at.add((view.getInt8(p), view.getInt8(p + 1)));
      p += 2;
    }
    final exported = view.getUint32(p);
    final newCount = view.getUint32(p + 4);
    p += 8;

    final input = <_Bitmap>[
      for (final segment in referred) ...?_symbolDicts[segment],
    ];

    final decoder = MqDecoder(Uint8List.sublistView(data, p));
    final contexts = Int8List(1 << 16);
    final indexes = Uint8List(1 << 16);
    final iadh = MqIntContext();
    final iadw = MqIntContext();
    final iaex = MqIntContext();

    final newSymbols = <_Bitmap>[];
    var heightClass = 0;
    while (newSymbols.length < newCount) {
      final dh = decoder.decodeInt(iadh);
      if (dh == null) throw const FormatException('OOB height class');
      heightClass += dh;
      var symbolWidth = 0;
      while (true) {
        final dw = decoder.decodeInt(iadw);
        if (dw == null) break; // OOB: height class complete
        if (newSymbols.length >= newCount) {
          throw const FormatException('too many symbols');
        }
        symbolWidth += dw;
        newSymbols.add(_decodeGeneric(decoder, contexts, indexes, symbolWidth,
            heightClass, template, at, false));
      }
    }

    // export flags: alternating runs of (skip, export) over input+new
    final all = [...input, ...newSymbols];
    final result = <_Bitmap>[];
    var index = 0;
    var exporting = false;
    while (index < all.length && result.length < exported) {
      final run = decoder.decodeInt(iaex);
      if (run == null) break;
      if (exporting) {
        for (var i = 0; i < run && index < all.length; i++) {
          result.add(all[index++]);
        }
      } else {
        index += run;
      }
      exporting = !exporting;
    }
    return result;
  }

  List<_Bitmap> _readHuffmanSymbolDictionary(
      Uint8List data, List<int> referred) {
    final view = ByteData.sublistView(data);
    final flags = view.getUint16(0);
    final refAgg = (flags >> 1) & 1;
    if (refAgg == 1 ||
        (flags & 0x0100) != 0 ||
        (flags & 0x0200) != 0 ||
        (flags & 0x00CC) != 0) {
      throw const FormatException('unsupported Huffman symbol dictionary');
    }
    final dhTable = switch ((flags & 0x000C) >> 2) {
      0 => _huffmanD,
      1 => _huffmanE,
      _ => throw const FormatException('unsupported DH table'),
    };
    final dwTable = switch ((flags & 0x0030) >> 4) {
      0 => _huffmanB,
      1 => _huffmanC,
      _ => throw const FormatException('unsupported DW table'),
    };
    var p = 2; // Huffman dictionaries carry no SDAT bytes.
    final exported = view.getUint32(p);
    final newCount = view.getUint32(p + 4);
    p += 8;
    final input = <_Bitmap>[
      for (final segment in referred) ...?_symbolDicts[segment],
    ];
    if (input.isNotEmpty) {
      throw const FormatException('imported Huffman symbol dictionaries');
    }

    final reader = _BitReader(Uint8List.sublistView(data, p));
    final newSymbols = List<_Bitmap?>.filled(newCount, null);
    final widths = List<int>.filled(newCount, 0);
    var heightClass = 0;
    var decoded = 0;
    while (decoded < newCount) {
      final dh = reader.readHuffman(dhTable);
      if (dh.oob) throw const FormatException('OOB height class');
      heightClass += dh.value;
      var symbolWidth = 0;
      var totalWidth = 0;
      final first = decoded;
      while (true) {
        final dw = reader.readHuffman(dwTable);
        if (dw.oob) break;
        if (decoded >= newCount) break;
        symbolWidth += dw.value;
        widths[decoded] = symbolWidth;
        totalWidth += symbolWidth;
        decoded++;
      }
      final size = reader.readHuffman(_huffmanA);
      if (size.oob) throw const FormatException('OOB collective bitmap size');
      reader.skipToByte();
      final _Bitmap collective;
      if (size.value == 0) {
        collective = reader.readPackedBitmap(totalWidth, heightClass);
      } else {
        collective =
            _decodeMmr(reader.readBytes(size.value), totalWidth, heightClass);
      }
      var x = 0;
      for (var i = first; i < decoded; i++) {
        final glyph = _copyBitmap(collective, x, 0, widths[i], heightClass);
        newSymbols[i] = glyph;
        x += widths[i];
      }
    }

    final all = <_Bitmap>[
      for (final symbol in newSymbols) symbol!,
    ];
    final result = <_Bitmap>[];
    var index = 0;
    var exporting = false;
    while (index < all.length && result.length < exported) {
      final run = reader.readHuffman(_huffmanA);
      if (run.oob) throw const FormatException('OOB export run');
      if (exporting) {
        for (var i = 0; i < run.value && index < all.length; i++) {
          result.add(all[index++]);
        }
      } else {
        index += run.value;
      }
      exporting = !exporting;
    }
    return result;
  }

  // ---------- text region (§6.4) ----------

  void _readTextRegion(Uint8List data, List<int> referred) {
    final view = ByteData.sublistView(data);
    final (w, h, x, y, op) = _regionInfo(view);
    var p = 17;
    final flags = view.getUint16(p);
    p += 2;
    final huffman = flags & 1;
    final refine = (flags >> 1) & 1;
    final logStrips = (flags >> 2) & 3;
    final refCorner = (flags >> 4) & 3;
    final transposed = (flags >> 6) & 1;
    final combOp = (flags >> 7) & 3;
    final defaultPixel = (flags >> 9) & 1;
    var dsOffset = (flags >> 10) & 0x1F;
    if (dsOffset > 15) dsOffset -= 32;
    final rTemplate = (flags >> 15) & 1;
    if (huffman == 1) {
      _readHuffmanTextRegion(data, referred);
      return;
    }
    if (refine == 1 && rTemplate == 0) {
      p += 4; // refinement AT pixels (unused: we reject refinement below)
    }
    final instanceCount = view.getUint32(p);
    p += 4;

    final symbols = <_Bitmap>[
      for (final segment in referred) ...?_symbolDicts[segment],
    ];
    if (symbols.isEmpty) throw const FormatException('no symbols');
    var codeLength = 0;
    while ((1 << codeLength) < symbols.length) {
      codeLength++;
    }
    if (codeLength == 0) codeLength = 1;

    final strips = 1 << logStrips;
    final decoder = MqDecoder(Uint8List.sublistView(data, p));
    final iadt = MqIntContext();
    final iafs = MqIntContext();
    final iads = MqIntContext();
    final iait = MqIntContext();
    final iari = MqIntContext();
    final iaidContexts = Int8List(1 << (codeLength + 1));
    final iaidIndexes = Uint8List(1 << (codeLength + 1));

    final region = _Bitmap(w, h, fill: defaultPixel);
    var stripT = -(decoder.decodeInt(iadt) ?? 0) * strips;
    var firstS = 0;
    var decoded = 0;
    while (decoded < instanceCount) {
      final dt = decoder.decodeInt(iadt);
      if (dt == null) break;
      stripT += dt * strips;
      final dfs = decoder.decodeInt(iafs);
      if (dfs == null) break;
      firstS += dfs;
      var curS = firstS;
      var first = true;
      while (true) {
        if (!first) {
          final ds = decoder.decodeInt(iads);
          if (ds == null) break; // OOB: end of strip
          curS += ds + dsOffset;
        }
        first = false;
        final curT = strips == 1 ? 0 : (decoder.decodeInt(iait) ?? 0);
        final t = stripT + curT;
        final id = decoder.decodeId(iaidContexts, iaidIndexes, codeLength);
        if (refine == 1 && (decoder.decodeInt(iari) ?? 0) != 0) {
          throw const FormatException('refined text symbols');
        }
        if (id >= symbols.length) {
          throw const FormatException('symbol id out of range');
        }
        final symbol = symbols[id];
        _drawSymbol(region, symbol, curS, t,
            refCorner: refCorner, transposed: transposed == 1, combOp: combOp);
        curS += (transposed == 1 ? symbol.height : symbol.width) - 1;
        decoded++;
        if (decoded >= instanceCount) break;
      }
    }
    _ensurePage().compose(region, x, y, op);
  }

  void _readHuffmanTextRegion(Uint8List data, List<int> referred) {
    final view = ByteData.sublistView(data);
    final (w, h, x, y, op) = _regionInfo(view);
    var p = 17;
    final flags = view.getUint16(p);
    p += 2;
    final refine = (flags >> 1) & 1;
    final logStrips = (flags >> 2) & 3;
    final refCorner = (flags >> 4) & 3;
    final transposed = (flags >> 6) & 1;
    final combOp = (flags >> 7) & 3;
    final defaultPixel = (flags >> 9) & 1;
    var dsOffset = (flags >> 10) & 0x1F;
    if (dsOffset > 15) dsOffset -= 32;
    if (refine == 1) throw const FormatException('refined Huffman text');
    final huffmanFlags = view.getUint16(p);
    p += 2;
    if (huffmanFlags != 0) {
      throw const FormatException('custom Huffman text tables');
    }
    final instanceCount = view.getUint32(p);
    p += 4;

    final symbols = <_Bitmap>[
      for (final segment in referred) ...?_symbolDicts[segment],
    ];
    if (symbols.isEmpty) throw const FormatException('no symbols');
    final reader = _BitReader(Uint8List.sublistView(data, p));
    final symbolCodes = _readSymbolIdTable(reader, symbols.length);

    final strips = 1 << logStrips;
    final region = _Bitmap(w, h, fill: defaultPixel);
    var stripT = -reader.readHuffman(_huffmanK).value * strips;
    var firstS = 0;
    var decoded = 0;
    while (decoded < instanceCount) {
      final dt = reader.readHuffman(_huffmanK);
      if (dt.oob) throw const FormatException('OOB text DT');
      stripT += dt.value * strips;
      var curS = firstS;
      var first = true;
      while (true) {
        if (first) {
          final dfs = reader.readHuffman(_huffmanF);
          if (dfs.oob) throw const FormatException('OOB text FS');
          firstS += dfs.value;
          curS = firstS;
          first = false;
        } else {
          final ds = reader.readHuffman(_huffmanH);
          if (ds.oob) break;
          curS += ds.value + dsOffset;
        }
        final curT = strips == 1 ? 0 : reader.readBits(logStrips);
        final t = stripT + curT;
        final id = reader.readHuffman(symbolCodes);
        if (id.oob || id.value >= symbols.length) {
          throw const FormatException('symbol id out of range');
        }
        final symbol = symbols[id.value];
        _drawSymbol(region, symbol, curS, t,
            refCorner: refCorner, transposed: transposed == 1, combOp: combOp);
        if (transposed == 1) {
          if ((refCorner & 1) != 0) curS += symbol.height - 1;
        } else if (refCorner < 2) {
          curS += symbol.width - 1;
        }
        decoded++;
        if (decoded >= instanceCount) break;
      }
    }
    _ensurePage().compose(region, x, y, op);
  }

  static _HuffmanTable _readSymbolIdTable(_BitReader reader, int count) {
    final runLines = <_HuffmanLine>[
      for (var i = 0; i < 35; i++) _HuffmanLine(reader.readBits(4), 0, i),
    ];
    final runCodes = _HuffmanTable(runLines, htoob: false);
    final lengths = List<int>.filled(count, 0);
    var index = 0;
    while (index < count) {
      final code = reader.readHuffman(runCodes);
      if (code.oob || code.value < 0 || code.value >= 35) {
        throw const FormatException('bad symbol ID run code');
      }
      int length, range;
      if (code.value < 32) {
        length = code.value;
        range = 1;
      } else {
        if (code.value == 32) {
          if (index == 0) {
            throw const FormatException('symbol ID repeat without previous');
          }
          length = lengths[index - 1];
          range = reader.readBits(2) + 3;
        } else if (code.value == 33) {
          length = 0;
          range = reader.readBits(3) + 3;
        } else {
          length = 0;
          range = reader.readBits(7) + 11;
        }
      }
      for (var i = 0; i < range && index < count; i++) {
        lengths[index++] = length;
      }
    }
    reader.skipToByte();
    return _HuffmanTable([
      for (var i = 0; i < count; i++) _HuffmanLine(lengths[i], 0, i),
    ], htoob: false);
  }

  static void _drawSymbol(_Bitmap region, _Bitmap symbol, int s, int t,
      {required int refCorner, required bool transposed, required int combOp}) {
    int x, y;
    if (!transposed) {
      // refCorner: 0 bottom-left, 1 top-left, 2 bottom-right, 3 top-right
      x = s;
      y = refCorner == 1 || refCorner == 3 ? t : t - symbol.height + 1;
    } else {
      y = s;
      x = refCorner == 0 || refCorner == 1 ? t : t - symbol.width + 1;
    }
    region.compose(symbol, x, y, combOp);
  }
}

class _BitReader {
  _BitReader(this.data);

  final Uint8List data;
  var _bitOffset = 0;

  int get byteOffset => _bitOffset >> 3;

  int readBits(int count) {
    var value = 0;
    for (var i = 0; i < count; i++) {
      final byte = _bitOffset >> 3;
      if (byte >= data.length) {
        throw const FormatException('Huffman data truncated');
      }
      value = (value << 1) | ((data[byte] >> (7 - (_bitOffset & 7))) & 1);
      _bitOffset++;
    }
    return value;
  }

  void skipToByte() {
    final extra = _bitOffset & 7;
    if (extra != 0) _bitOffset += 8 - extra;
  }

  Uint8List readBytes(int count) {
    skipToByte();
    final start = byteOffset;
    final end = start + count;
    if (end > data.length) {
      throw const FormatException('Huffman data truncated');
    }
    _bitOffset += count * 8;
    return Uint8List.sublistView(data, start, end);
  }

  _Bitmap readPackedBitmap(int width, int height) {
    skipToByte();
    final rowBytes = (width + 7) >> 3;
    final bytes = readBytes(rowBytes * height);
    final bitmap = _Bitmap(width, height, fill: 0);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        if ((bytes[y * rowBytes + (x >> 3)] >> (7 - (x & 7))) & 1 != 0) {
          bitmap.set(x, y, 1);
        }
      }
    }
    return bitmap;
  }

  _HuffmanValue readHuffman(_HuffmanTable table) {
    var code = 0;
    for (var length = 1; length <= table.maxLength; length++) {
      code = (code << 1) | readBits(1);
      final entry = table.entry(length, code);
      if (entry == null) continue;
      var value = entry.rangeLow;
      if (entry.rangeLength > 0) {
        final offset = readBits(entry.rangeLength);
        value = entry.isLow ? value - offset : value + offset;
      }
      return _HuffmanValue(value, entry.isOob);
    }
    throw const FormatException('bad Huffman code');
  }
}

class _HuffmanValue {
  const _HuffmanValue(this.value, this.oob);

  final int value;
  final bool oob;
}

class _HuffmanLine {
  const _HuffmanLine(this.prefixLength, this.rangeLength, this.rangeLow);

  final int prefixLength;
  final int rangeLength;
  final int rangeLow;
}

class _HuffmanEntry {
  const _HuffmanEntry(
    this.code,
    this.prefixLength,
    this.rangeLength,
    this.rangeLow, {
    required this.isLow,
    required this.isOob,
  });

  final int code;
  final int prefixLength;
  final int rangeLength;
  final int rangeLow;
  final bool isLow;
  final bool isOob;
}

class _HuffmanTable {
  _HuffmanTable(List<_HuffmanLine> lines, {required this.htoob}) {
    final counts = <int, int>{};
    maxLength = 0;
    for (final line in lines) {
      if (line.prefixLength <= 0) continue;
      counts[line.prefixLength] = (counts[line.prefixLength] ?? 0) + 1;
      if (line.prefixLength > maxLength) maxLength = line.prefixLength;
    }
    var firstCode = 0;
    for (var length = 1; length <= maxLength; length++) {
      firstCode = (firstCode + (counts[length - 1] ?? 0)) << 1;
      var code = firstCode;
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (line.prefixLength != length) continue;
        final isLow = i == lines.length - (htoob ? 3 : 2);
        final isOob = htoob && i == lines.length - 1;
        _entries.add(_HuffmanEntry(
          code++,
          length,
          line.rangeLength,
          line.rangeLow,
          isLow: isLow,
          isOob: isOob,
        ));
      }
    }
  }

  final bool htoob;
  var maxLength = 0;
  final _entries = <_HuffmanEntry>[];

  _HuffmanEntry? entry(int length, int code) {
    for (final entry in _entries) {
      if (entry.prefixLength == length && entry.code == code) return entry;
    }
    return null;
  }
}

final _huffmanA = _HuffmanTable(const [
  _HuffmanLine(1, 4, 0),
  _HuffmanLine(2, 8, 16),
  _HuffmanLine(3, 16, 272),
  _HuffmanLine(0, 32, -1),
  _HuffmanLine(3, 32, 65808),
], htoob: false);

final _huffmanB = _HuffmanTable(const [
  _HuffmanLine(1, 0, 0),
  _HuffmanLine(2, 0, 1),
  _HuffmanLine(3, 0, 2),
  _HuffmanLine(4, 3, 3),
  _HuffmanLine(5, 6, 11),
  _HuffmanLine(0, 32, -1),
  _HuffmanLine(6, 32, 75),
  _HuffmanLine(6, 0, 0),
], htoob: true);

final _huffmanC = _HuffmanTable(const [
  _HuffmanLine(8, 8, -256),
  _HuffmanLine(1, 0, 0),
  _HuffmanLine(2, 0, 1),
  _HuffmanLine(3, 0, 2),
  _HuffmanLine(4, 3, 3),
  _HuffmanLine(5, 6, 11),
  _HuffmanLine(8, 32, -257),
  _HuffmanLine(7, 32, 75),
  _HuffmanLine(6, 0, 0),
], htoob: true);

final _huffmanD = _HuffmanTable(const [
  _HuffmanLine(1, 0, 1),
  _HuffmanLine(2, 0, 2),
  _HuffmanLine(3, 0, 3),
  _HuffmanLine(4, 3, 4),
  _HuffmanLine(5, 6, 12),
  _HuffmanLine(0, 32, -1),
  _HuffmanLine(5, 32, 76),
], htoob: false);

final _huffmanE = _HuffmanTable(const [
  _HuffmanLine(7, 8, -255),
  _HuffmanLine(1, 0, 1),
  _HuffmanLine(2, 0, 2),
  _HuffmanLine(3, 0, 3),
  _HuffmanLine(4, 3, 4),
  _HuffmanLine(5, 6, 12),
  _HuffmanLine(7, 32, -256),
  _HuffmanLine(6, 32, 76),
], htoob: false);

final _huffmanF = _HuffmanTable(const [
  _HuffmanLine(5, 10, -2048),
  _HuffmanLine(4, 9, -1024),
  _HuffmanLine(4, 8, -512),
  _HuffmanLine(4, 7, -256),
  _HuffmanLine(5, 6, -128),
  _HuffmanLine(5, 5, -64),
  _HuffmanLine(4, 5, -32),
  _HuffmanLine(2, 7, 0),
  _HuffmanLine(3, 7, 128),
  _HuffmanLine(3, 8, 256),
  _HuffmanLine(4, 9, 512),
  _HuffmanLine(4, 10, 1024),
  _HuffmanLine(6, 32, -2049),
  _HuffmanLine(6, 32, 2048),
], htoob: false);

final _huffmanH = _HuffmanTable(const [
  _HuffmanLine(8, 3, -15),
  _HuffmanLine(9, 1, -7),
  _HuffmanLine(8, 1, -5),
  _HuffmanLine(9, 0, -3),
  _HuffmanLine(7, 0, -2),
  _HuffmanLine(4, 0, -1),
  _HuffmanLine(2, 1, 0),
  _HuffmanLine(5, 0, 2),
  _HuffmanLine(6, 0, 3),
  _HuffmanLine(3, 4, 4),
  _HuffmanLine(6, 1, 20),
  _HuffmanLine(4, 4, 22),
  _HuffmanLine(4, 5, 38),
  _HuffmanLine(5, 6, 70),
  _HuffmanLine(5, 7, 134),
  _HuffmanLine(6, 7, 262),
  _HuffmanLine(7, 8, 390),
  _HuffmanLine(6, 10, 646),
  _HuffmanLine(9, 32, -16),
  _HuffmanLine(9, 32, 1670),
  _HuffmanLine(2, 0, 0),
], htoob: true);

final _huffmanK = _HuffmanTable(const [
  _HuffmanLine(1, 0, 1),
  _HuffmanLine(2, 1, 2),
  _HuffmanLine(4, 0, 4),
  _HuffmanLine(4, 1, 5),
  _HuffmanLine(5, 1, 7),
  _HuffmanLine(5, 2, 9),
  _HuffmanLine(6, 2, 13),
  _HuffmanLine(7, 2, 17),
  _HuffmanLine(7, 3, 21),
  _HuffmanLine(7, 4, 29),
  _HuffmanLine(7, 5, 45),
  _HuffmanLine(7, 6, 77),
  _HuffmanLine(0, 32, -1),
  _HuffmanLine(7, 32, 141),
], htoob: false);

/// One-byte-per-pixel bitmap; out-of-bounds reads are 0 (white).
class _Bitmap {
  _Bitmap(this.width, this.height, {required int fill})
      : data = Uint8List(width * height) {
    if (fill != 0) data.fillRange(0, data.length, 1);
  }

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

  void copyRow(int y) {
    if (y == 0) return;
    data.setRange(y * width, (y + 1) * width, data, (y - 1) * width);
  }

  /// Composites [source] at ([x], [y]) with a JBIG2 combination
  /// operator: 0 OR, 1 AND, 2 XOR, 3 XNOR, else REPLACE.
  void compose(_Bitmap source, int x, int y, int op) {
    for (var sy = 0; sy < source.height; sy++) {
      final ty = y + sy;
      if (ty < 0 || ty >= height) continue;
      for (var sx = 0; sx < source.width; sx++) {
        final tx = x + sx;
        if (tx < 0 || tx >= width) continue;
        final s = source.data[sy * source.width + sx];
        final index = ty * width + tx;
        final d = data[index];
        data[index] = switch (op) {
          0 => d | s,
          1 => d & s,
          2 => d ^ s,
          3 => 1 - (d ^ s),
          _ => s,
        };
      }
    }
  }
}
