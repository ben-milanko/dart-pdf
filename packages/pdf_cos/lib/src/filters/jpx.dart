import 'dart:math' as math;
import 'dart:typed_data';

import 'mq.dart';

/// A decoded JPEG 2000 image: 8-bit samples, components interleaved.
class JpxImage {
  const JpxImage(this.width, this.height, this.components, this.samples);

  final int width;
  final int height;
  final int components;
  final Uint8List samples;
}

/// JPEG 2000 decoder (ITU-T T.800) for PDF JPXDecode streams.
///
/// Coverage: raw codestreams and JP2 containers; 5/3 reversible and 9/7
/// irreversible wavelets; RCT and ICT component transforms; LRCP, RLCP,
/// and RPCL progressions; multiple layers, tiles, and resolution levels;
/// no-quantization, scalar-derived, and scalar-expounded quantization.
/// Out of scope (decode → null, image skipped): component subsampling,
/// PCRL/CPRL progressions, code-block style options (bypass, reset,
/// vertical causal, segmentation symbols), region of interest, and
/// depths above 16 bits.
class JpxDecoder {
  static JpxImage? decode(Uint8List bytes) {
    try {
      return _JpxParser(_codestreamOf(bytes)).decode();
    } on Object {
      return null;
    }
  }

  /// Unwraps a JP2 container down to its contiguous codestream, or
  /// returns [bytes] unchanged when they already start with SOC.
  static Uint8List _codestreamOf(Uint8List bytes) {
    if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0x4F) {
      return bytes;
    }
    final view = ByteData.sublistView(bytes);
    var p = 0;
    while (p + 8 <= bytes.length) {
      var length = view.getUint32(p);
      final type = String.fromCharCodes(bytes, p + 4, p + 8);
      var headerSize = 8;
      if (length == 1) {
        // 64-bit extended length
        length = view.getUint32(p + 12); // high half assumed zero
        headerSize = 16;
      } else if (length == 0) {
        length = bytes.length - p;
      }
      if (type == 'jp2c') {
        return Uint8List.sublistView(
            bytes, p + headerSize, p + length.clamp(headerSize, bytes.length - p));
      }
      p += length;
    }
    throw const FormatException('no codestream in JP2 container');
  }
}

// ---------------------------------------------------------------------
// codestream structures
// ---------------------------------------------------------------------

class _Component {
  _Component(this.depth, this.signed);
  final int depth;
  final bool signed;
}

class _CodingStyle {
  int progression = 0;
  int layers = 1;
  int mct = 0;
  int levels = 5;
  int cbWidthExp = 6;
  int cbHeightExp = 6;
  int cbStyle = 0;
  int transform = 0; // 0 = 9/7 irreversible, 1 = 5/3 reversible
  bool sop = false;
  bool eph = false;
  List<int> precinctWidths = const [];
  List<int> precinctHeights = const [];

  int precinctWidth(int r) =>
      precinctWidths.isEmpty ? 15 : precinctWidths[r];
  int precinctHeight(int r) =>
      precinctHeights.isEmpty ? 15 : precinctHeights[r];
}

class _Quantization {
  int style = 0; // 0 none, 1 scalar derived, 2 scalar expounded
  int guardBits = 2;
  List<int> exponents = const [];
  List<int> mantissas = const [];
}

class _JpxParser {
  _JpxParser(this.data) : view = ByteData.sublistView(data);

  final Uint8List data;
  final ByteData view;

  late int width, height, x0, y0;
  late int tileWidth, tileHeight, tileX0, tileY0;
  final components = <_Component>[];
  final _CodingStyle cod = _CodingStyle();
  final Map<int, _CodingStyle> codPerComponent = {};
  final _Quantization qcd = _Quantization();
  final Map<int, _Quantization> qcdPerComponent = {};

  JpxImage decode() {
    var p = 0;
    if (view.getUint16(p) != 0xFF4F) {
      throw const FormatException('missing SOC');
    }
    p += 2;

    // (tile index → list of bitstream chunks)
    final tileData = <int, List<Uint8List>>{};
    while (p + 4 <= data.length) {
      final marker = view.getUint16(p);
      if (marker == 0xFFD9) break; // EOC
      final length = view.getUint16(p + 2);
      switch (marker) {
        case 0xFF51: // SIZ
          _readSiz(p + 4);
        case 0xFF52: // COD
          _readCod(p + 4, cod);
        case 0xFF53: // COC
          final c = data[p + 4];
          final style = _CodingStyle()
            ..progression = cod.progression
            ..layers = cod.layers
            ..mct = cod.mct;
          _readCodingParameters(p + 5, style, data[p + 4 + 1]);
          codPerComponent[c] = style;
        case 0xFF5C: // QCD
          _readQuant(p + 4, length - 2, qcd);
        case 0xFF5D: // QCC
          final c = data[p + 4];
          final quant = _Quantization();
          _readQuant(p + 5, length - 3, quant);
          qcdPerComponent[c] = quant;
        case 0xFF90: // SOT
          // SOT fields from the marker (T.800 A.4.2): Lsot @+2, Isot @+4,
          // Psot @+6. Reading Psot at +8 (off by two) only ever read "rest of
          // codestream" for single tile-part files — which is the right chunk
          // there — but on a multi-tile-part tile it swallowed every later
          // tile-part's SOT/SOD markers into the packet bitstream, desyncing
          // tier-2 into garbage coefficients (issue3371.pdf: 6 tile-parts).
          final tileIndex = view.getUint16(p + 4);
          var tileLength = view.getUint32(p + 6);
          if (tileLength == 0) tileLength = data.length - p;
          // the tile part runs from SOT to SOT+Psot; data follows SOD
          var q = p + 2 + length;
          if (view.getUint16(q) != 0xFF93) {
            throw const FormatException('expected SOD');
          }
          q += 2;
          final end = math.min(p + tileLength, data.length);
          (tileData[tileIndex] ??= []).add(
              Uint8List.sublistView(data, q, end));
          p = end;
          continue;
        default:
          break; // COM and friends: skip
      }
      p += 2 + length;
    }

    if (components.isEmpty) throw const FormatException('missing SIZ');
    for (final c in components) {
      if (c.depth > 16) throw const FormatException('depth > 16');
    }

    // decode every tile into the full-image component planes
    final planes = [
      for (var c = 0; c < components.length; c++)
        Float32List((width - x0) * (height - y0)),
    ];
    final tilesX = ((width - tileX0) / tileWidth).ceil();
    final tilesY = ((height - tileY0) / tileHeight).ceil();
    for (var t = 0; t < tilesX * tilesY; t++) {
      final chunks = tileData[t];
      if (chunks == null) continue;
      _decodeTile(t, _concat(chunks), planes);
    }

    // DC level shift, clamp, interleave to 8 bits
    final outWidth = width - x0;
    final outHeight = height - y0;
    final out = Uint8List(outWidth * outHeight * components.length);
    for (var c = 0; c < components.length; c++) {
      final depth = components[c].depth;
      final shift = components[c].signed ? 0 : 1 << (depth - 1);
      final scale = depth >= 8 ? depth - 8 : 0;
      final upscale = depth < 8 ? 8 - depth : 0;
      final plane = planes[c];
      for (var i = 0; i < plane.length; i++) {
        var v = (plane[i] + shift).round();
        v = v >> scale << upscale;
        out[i * components.length + c] = v.clamp(0, 255);
      }
    }
    return JpxImage(outWidth, outHeight, components.length, out);
  }

  static Uint8List _concat(List<Uint8List> chunks) {
    if (chunks.length == 1) return chunks[0];
    final builder = BytesBuilder(copy: false);
    for (final chunk in chunks) {
      builder.add(chunk);
    }
    return builder.takeBytes();
  }

  void _readSiz(int p) {
    width = view.getUint32(p + 2);
    height = view.getUint32(p + 6);
    x0 = view.getUint32(p + 10);
    y0 = view.getUint32(p + 14);
    tileWidth = view.getUint32(p + 18);
    tileHeight = view.getUint32(p + 22);
    tileX0 = view.getUint32(p + 26);
    tileY0 = view.getUint32(p + 30);
    final count = view.getUint16(p + 34);
    for (var c = 0; c < count; c++) {
      final ssiz = data[p + 36 + c * 3];
      final dx = data[p + 37 + c * 3];
      final dy = data[p + 38 + c * 3];
      if (dx != 1 || dy != 1) {
        throw const FormatException('component subsampling');
      }
      components.add(_Component((ssiz & 0x7F) + 1, ssiz & 0x80 != 0));
    }
  }

  void _readCod(int p, _CodingStyle style) {
    final scod = data[p];
    style.sop = scod & 2 != 0;
    style.eph = scod & 4 != 0;
    style.progression = data[p + 1];
    style.layers = view.getUint16(p + 2);
    style.mct = data[p + 4];
    _readCodingParameters(p + 5, style, scod);
  }

  void _readCodingParameters(int p, _CodingStyle style, int scod) {
    style.levels = data[p];
    style.cbWidthExp = (data[p + 1] & 0xF) + 2;
    style.cbHeightExp = (data[p + 2] & 0xF) + 2;
    style.cbStyle = data[p + 3];
    style.transform = data[p + 4];
    // Bit 1 (0x02) = reset the MQ context probabilities at each coding-pass
    // boundary (Table A.19); supported below. The remaining style bits
    // (arithmetic bypass, per-pass termination, vertically-causal contexts,
    // predictable termination, segmentation symbols) are not — reject them so
    // the image is skipped rather than mis-decoded.
    const supportedCbStyle = 0x02;
    if (style.cbStyle & ~supportedCbStyle != 0) {
      throw const FormatException('code-block style options');
    }
    if (scod & 1 != 0) {
      final widths = <int>[];
      final heights = <int>[];
      for (var r = 0; r <= style.levels; r++) {
        final pp = data[p + 5 + r];
        widths.add(pp & 0xF);
        heights.add(pp >> 4);
      }
      style.precinctWidths = widths;
      style.precinctHeights = heights;
    }
  }

  void _readQuant(int p, int length, _Quantization quant) {
    final sqcd = data[p];
    quant.style = sqcd & 0x1F;
    quant.guardBits = sqcd >> 5;
    final exponents = <int>[];
    final mantissas = <int>[];
    if (quant.style == 0) {
      for (var q = p + 1; q < p + length; q++) {
        exponents.add(data[q] >> 3);
        mantissas.add(0);
      }
    } else {
      quant.style = quant.style == 1 ? 1 : 2;
      for (var q = p + 1; q + 1 < p + length; q += 2) {
        final v = view.getUint16(q);
        exponents.add(v >> 11);
        mantissas.add(v & 0x7FF);
      }
    }
    quant.exponents = exponents;
    quant.mantissas = mantissas;
  }

  _CodingStyle _styleFor(int c) => codPerComponent[c] ?? cod;
  _Quantization _quantFor(int c) => qcdPerComponent[c] ?? qcd;

  // ---------- tile decoding ----------

  void _decodeTile(int index, Uint8List bitstream, List<Float32List> planes) {
    final tilesX = ((width - tileX0) / tileWidth).ceil();
    final tp = index % tilesX;
    final tq = index ~/ tilesX;
    final tx0 = math.max(tileX0 + tp * tileWidth, x0);
    final ty0 = math.max(tileY0 + tq * tileHeight, y0);
    final tx1 = math.min(tileX0 + (tp + 1) * tileWidth, width);
    final ty1 = math.min(tileY0 + (tq + 1) * tileHeight, height);

    final tileComponents = [
      for (var c = 0; c < components.length; c++)
        _TileComponent(tx0, ty0, tx1, ty1, _styleFor(c), _quantFor(c),
            components[c].depth),
    ];

    _decodePackets(bitstream, tileComponents);
    final results = [
      for (final tc in tileComponents) tc.reconstruct(),
    ];

    // multiple component transform over the first three components
    final w = tx1 - tx0;
    final h = ty1 - ty0;
    if (cod.mct == 1 && results.length >= 3) {
      final a = results[0], b = results[1], c = results[2];
      if (tileComponents[0].style.transform == 1) {
        for (var i = 0; i < w * h; i++) {
          final y = a[i], cb = b[i], cr = c[i];
          final g = y - ((cb + cr) / 4).floorToDouble();
          a[i] = cr + g; // red
          b[i] = g;
          c[i] = cb + g; // blue
        }
      } else {
        for (var i = 0; i < w * h; i++) {
          final y = a[i], cb = b[i], cr = c[i];
          a[i] = y + 1.402 * cr;
          b[i] = y - 0.344136 * cb - 0.714136 * cr;
          c[i] = y + 1.772 * cb;
        }
      }
    }

    for (var c = 0; c < results.length; c++) {
      final plane = planes[c];
      final rowOffset = (ty0 - y0) * (width - x0) + (tx0 - x0);
      for (var yy = 0; yy < h; yy++) {
        plane.setRange(rowOffset + yy * (width - x0),
            rowOffset + yy * (width - x0) + w, results[c], yy * w);
      }
    }
  }

  void _decodePackets(Uint8List bitstream, List<_TileComponent> tcs) {
    final reader = _PacketReader(bitstream, sop: cod.sop, eph: cod.eph);
    final layers = cod.layers;
    final maxLevels =
        tcs.fold(0, (m, tc) => math.max(m, tc.style.levels));

    void packet(int c, int r, int p, int layer) {
      final tc = tcs[c];
      if (r > tc.style.levels) return;
      final resolution = tc.resolutions[r];
      if (p >= resolution.precinctCount) return;
      reader.readPacket(resolution, p, layer);
    }

    switch (cod.progression) {
      case 0: // LRCP
        for (var l = 0; l < layers; l++) {
          for (var r = 0; r <= maxLevels; r++) {
            for (var c = 0; c < tcs.length; c++) {
              final count = r <= tcs[c].style.levels
                  ? tcs[c].resolutions[r].precinctCount
                  : 0;
              for (var p = 0; p < count; p++) {
                packet(c, r, p, l);
              }
            }
          }
        }
      case 1: // RLCP
        for (var r = 0; r <= maxLevels; r++) {
          for (var l = 0; l < layers; l++) {
            for (var c = 0; c < tcs.length; c++) {
              final count = r <= tcs[c].style.levels
                  ? tcs[c].resolutions[r].precinctCount
                  : 0;
              for (var p = 0; p < count; p++) {
                packet(c, r, p, l);
              }
            }
          }
        }
      case 2: // RPCL
        for (var r = 0; r <= maxLevels; r++) {
          final count = tcs.fold(
              0,
              (m, tc) => math.max(
                  m,
                  r <= tc.style.levels
                      ? tc.resolutions[r].precinctCount
                      : 0));
          for (var p = 0; p < count; p++) {
            for (var c = 0; c < tcs.length; c++) {
              for (var l = 0; l < layers; l++) {
                packet(c, r, p, l);
              }
            }
          }
        }
      default:
        throw const FormatException('unsupported progression order');
    }
  }
}

// ---------------------------------------------------------------------
// tile component: geometry, packets, tier-1, reconstruction
// ---------------------------------------------------------------------

class _TileComponent {
  _TileComponent(this.tcx0, this.tcy0, this.tcx1, this.tcy1, this.style,
      this.quant, this.depth) {
    for (var r = 0; r <= style.levels; r++) {
      resolutions.add(_Resolution(this, r));
    }
  }

  final int tcx0, tcy0, tcx1, tcy1;
  final _CodingStyle style;
  final _Quantization quant;
  final int depth;
  final resolutions = <_Resolution>[];

  /// Tier-1 decodes every code-block, dequantizes, and runs the inverse
  /// wavelet. Returns the tile-component samples (still centered around
  /// zero — the DC shift happens later).
  Float32List reconstruct() {
    for (final resolution in resolutions) {
      for (final band in resolution.bands) {
        for (final block in band.blocks) {
          block.decode(band.mb, band.family, style.cbStyle);
        }
      }
    }

    final reversible = style.transform == 1;
    // start with the r0 LL band and synthesize upwards
    var current = resolutions[0].bands[0].dequantize(this, reversible);
    var x0 = resolutions[0].x0, y0 = resolutions[0].y0;
    var x1 = resolutions[0].x1, y1 = resolutions[0].y1;
    for (var r = 1; r < resolutions.length; r++) {
      final resolution = resolutions[r];
      current = _inverseDwt(
        ll: current,
        llX0: x0, llY0: y0, llX1: x1, llY1: y1,
        hl: resolution.bands[0].dequantize(this, reversible),
        lh: resolution.bands[1].dequantize(this, reversible),
        hh: resolution.bands[2].dequantize(this, reversible),
        bands: resolution.bands,
        x0: resolution.x0, y0: resolution.y0,
        x1: resolution.x1, y1: resolution.y1,
        reversible: reversible,
      );
      x0 = resolution.x0;
      y0 = resolution.y0;
      x1 = resolution.x1;
      y1 = resolution.y1;
    }
    return current;
  }
}

class _Resolution {
  _Resolution(_TileComponent tc, this.r) {
    final shift = tc.style.levels - r;
    x0 = _ceilDiv(tc.tcx0, 1 << shift);
    y0 = _ceilDiv(tc.tcy0, 1 << shift);
    x1 = _ceilDiv(tc.tcx1, 1 << shift);
    y1 = _ceilDiv(tc.tcy1, 1 << shift);

    final ppx = tc.style.precinctWidth(r);
    final ppy = tc.style.precinctHeight(r);
    precinctsX = x1 > x0
        ? _ceilDiv(x1, 1 << ppx) - (x0 >> ppx)
        : 0;
    precinctsY = y1 > y0
        ? _ceilDiv(y1, 1 << ppy) - (y0 >> ppy)
        : 0;

    if (r == 0) {
      bands.add(_Band(this, tc, 0, 0, 0, shift));
    } else {
      bands.add(_Band(this, tc, 1, 0, 1, shift)); // HL
      bands.add(_Band(this, tc, 0, 1, 1, shift)); // LH
      bands.add(_Band(this, tc, 1, 1, 2, shift)); // HH
    }
  }

  final int r;
  late final int x0, y0, x1, y1;
  late final int precinctsX, precinctsY;
  final bands = <_Band>[];

  int get precinctCount => math.max(precinctsX * precinctsY, 0);
}

class _Band {
  _Band(this.resolution, _TileComponent tc, int xob, int yob, this.gain,
      int shift) {
    // quantization parameters for this band (T.800 E.1)
    final r = resolution.r;
    family = r == 0 ? 0 : (xob == 1 && yob == 0 ? 1 : (xob == 1 ? 2 : 0));
    final subbandIndex = r == 0 ? 0 : (r - 1) * 3 + (family == 1 ? 0 : (family == 0 ? 1 : 2)) + 1;
    final quant = tc.quant;
    final int eps;
    final int mu;
    if (quant.style == 1) {
      eps = quant.exponents[0] - (tc.style.levels - r);
      mu = quant.mantissas[0];
    } else {
      final i = math.min(subbandIndex, quant.exponents.length - 1);
      eps = quant.exponents[i];
      mu = quant.mantissas[i];
    }
    mb = quant.guardBits + eps - 1;
    delta = tc.style.transform == 1
        ? 1.0
        : math.pow(2, tc.depth + gain - eps).toDouble() * (1 + mu / 2048);
    _buildGeometry(tc, xob, yob, shift);
  }

  void _buildGeometry(_TileComponent tc, int xob, int yob, int shift) {
    // band rectangle (T.800 B.5); for r=0 the band equals the resolution
    final r = resolution.r;
    if (r == 0) {
      x0 = resolution.x0;
      y0 = resolution.y0;
      x1 = resolution.x1;
      y1 = resolution.y1;
    } else {
      final denominator = 1 << (shift + 1);
      final half = 1 << shift;
      x0 = _ceilDiv(tc.tcx0 - half * xob, denominator);
      y0 = _ceilDiv(tc.tcy0 - half * yob, denominator);
      x1 = _ceilDiv(tc.tcx1 - half * xob, denominator);
      y1 = _ceilDiv(tc.tcy1 - half * yob, denominator);
    }

    // code-block grid; blocks are also bounded by precincts, which at
    // the default size (2^15) never split them
    final ppx = tc.style.precinctWidth(r) - (r == 0 ? 0 : 1);
    final ppy = tc.style.precinctHeight(r) - (r == 0 ? 0 : 1);
    final cbw = math.min(tc.style.cbWidthExp, ppx);
    final cbh = math.min(tc.style.cbHeightExp, ppy);
    cbWidthExp = cbw;
    cbHeightExp = cbh;

    if (x1 <= x0 || y1 <= y0) return;
    final gx0 = x0 >> cbw, gx1 = _ceilDiv(x1, 1 << cbw);
    final gy0 = y0 >> cbh, gy1 = _ceilDiv(y1, 1 << cbh);
    for (var gy = gy0; gy < gy1; gy++) {
      for (var gx = gx0; gx < gx1; gx++) {
        final bx0 = math.max(gx << cbw, x0);
        final by0 = math.max(gy << cbh, y0);
        final bx1 = math.min((gx + 1) << cbw, x1);
        final by1 = math.min((gy + 1) << cbh, y1);
        blocks.add(_CodeBlock(bx0, by0, bx1, by1));
      }
    }
    // assign blocks to precincts by position (raster order per precinct)
    final precinctWidth = 1 << (tc.style.precinctWidth(r) - (r == 0 ? 0 : 1));
    final precinctHeight =
        1 << (tc.style.precinctHeight(r) - (r == 0 ? 0 : 1));
    for (final block in blocks) {
      final px = (block.x0 ~/ precinctWidth) - (x0 ~/ precinctWidth);
      final py = (block.y0 ~/ precinctHeight) - (y0 ~/ precinctHeight);
      block.precinct = py * math.max(resolution.precinctsX, 1).toInt() + px;
    }
    final precinctTotal = resolution.precinctCount;
    inclusionTrees = List.generate(precinctTotal, (p) {
      final inPrecinct = blocks.where((b) => b.precinct == p).length;
      return _precinctTrees(p, inPrecinct);
    });
  }

  final _Resolution resolution;
  final int gain;
  late final int family; // 0: LL/LH, 1: HL, 2: HH (context tables)
  late final int mb; // magnitude bit-planes
  late final double delta; // quantization step (1.0 when reversible)
  late final int x0, y0, x1, y1;
  late int cbWidthExp, cbHeightExp;
  final blocks = <_CodeBlock>[];
  List<(_TagTree, _TagTree)> inclusionTrees = const [];

  (_TagTree, _TagTree) _precinctTrees(int p, int count) {
    final list = blocksOf(p);
    var w = 0, h = 0;
    if (list.isNotEmpty) {
      final xs = list.map((b) => b.x0 >> cbWidthExp);
      final ys = list.map((b) => b.y0 >> cbHeightExp);
      w = xs.reduce(math.max) - xs.reduce(math.min) + 1;
      h = ys.reduce(math.max) - ys.reduce(math.min) + 1;
    }
    return (_TagTree(w, h), _TagTree(w, h));
  }

  List<_CodeBlock> blocksOf(int precinct) =>
      [for (final b in blocks) if (b.precinct == precinct) b];
}

int _ceilDiv(int a, int b) => (a / b).ceil();

// ---------------------------------------------------------------------
// packets
// ---------------------------------------------------------------------

class _CodeBlock {
  _CodeBlock(this.x0, this.y0, this.x1, this.y1);

  final int x0, y0, x1, y1;
  int precinct = 0;

  bool included = false;
  int zeroBitPlanes = 0;
  int lBlock = 3;
  int passCount = 0;
  final segments = <Uint8List>[];

  // decoded coefficients
  Int32List? magnitudes;
  Uint8List? signs;

  /// Per coefficient: the lowest bit-plane that was actually coded for
  /// it. > 0 means the tail was truncated (lossy) and the mid-point of
  /// the remaining interval is added at reconstruction.
  Int8List? lowPlanes;

  int get width => x1 - x0;
  int get height => y1 - y0;

  void decode(int mb, int family, int cbStyle) {
    final planes = mb - zeroBitPlanes;
    if (segments.isEmpty || width <= 0 || height <= 0 || planes <= 0) {
      magnitudes = Int32List(math.max(width * height, 0));
      signs = Uint8List(math.max(width * height, 0));
      return;
    }
    final data = _JpxParser._concat(segments);
    final model = _BitModel(width, height, planes, family, MqDecoder(data))
      ..resetOnPass = cbStyle & 0x02 != 0;
    model.decodePasses(passCount);
    magnitudes = model.magnitudes;
    signs = model.signs;
    lowPlanes = model.lowPlanes;
  }
}

/// Reads packet headers (with bit stuffing, SOP/EPH markers) and slices
/// out the code-block contributions.
class _PacketReader {
  _PacketReader(this.data, {required this.sop, required this.eph});

  final Uint8List data;
  final bool sop;
  final bool eph;
  int _p = 0;
  int _buffer = 0;
  int _bits = 0;

  int _readBit() {
    if (_bits == 0) {
      if (_p >= data.length) return 0;
      final previous = _p > 0 ? data[_p - 1] : 0;
      _buffer = data[_p++];
      _bits = previous == 0xFF ? 7 : 8;
    }
    _bits--;
    return (_buffer >> _bits) & 1;
  }

  int _readBits(int count) {
    var v = 0;
    for (var i = 0; i < count; i++) {
      v = (v << 1) | _readBit();
    }
    return v;
  }

  void _alignToByte() {
    _bits = 0;
    // a stuffed 0xFF consumes the following 0 bit with the next byte
    if (_p > 0 && _p < data.length && data[_p - 1] == 0xFF) {
      _p++;
    }
  }

  void readPacket(_Resolution resolution, int precinct, int layer) {
    if (sop && _p + 6 <= data.length && data[_p] == 0xFF && data[_p + 1] == 0x91) {
      _p += 6;
    }
    final contributions = <(_CodeBlock, int)>[];
    final nonEmpty = _readBit();
    if (nonEmpty == 1) {
      for (var bandIndex = 0; bandIndex < resolution.bands.length; bandIndex++) {
        final band = resolution.bands[bandIndex];
        if (band.x1 <= band.x0 || band.y1 <= band.y0) continue;
        final blocks = band.blocksOf(precinct);
        if (blocks.isEmpty) continue;
        final (inclusionTree, zeroTree) = band.inclusionTrees[precinct];
        final originX = blocks.map((b) => b.x0 >> band.cbWidthExp).reduce(math.min);
        final originY = blocks.map((b) => b.y0 >> band.cbHeightExp).reduce(math.min);
        for (final block in blocks) {
          final i = (block.x0 >> band.cbWidthExp) - originX;
          final j = (block.y0 >> band.cbHeightExp) - originY;
          bool includedNow;
          if (!block.included) {
            includedNow = inclusionTree.decode(this, i, j, layer + 1);
          } else {
            includedNow = _readBit() == 1;
          }
          if (!includedNow) continue;
          if (!block.included) {
            block.included = true;
            block.zeroBitPlanes = zeroTree.decodeValue(this, i, j);
          }
          final passes = _readPassCount();
          var lBlock = block.lBlock;
          while (_readBit() == 1) {
            lBlock++;
          }
          block.lBlock = lBlock;
          final lengthBits = lBlock + (math.log(passes) / math.ln2).floor();
          final length = _readBits(lengthBits);
          block.passCount += passes;
          contributions.add((block, length));
        }
      }
    }
    _alignToByte();
    if (eph && _p + 2 <= data.length && data[_p] == 0xFF && data[_p + 1] == 0x92) {
      _p += 2;
    }
    for (final (block, length) in contributions) {
      final end = math.min(_p + length, data.length);
      block.segments.add(Uint8List.sublistView(data, _p, end));
      _p = end;
    }
  }

  int _readPassCount() {
    if (_readBit() == 0) return 1;
    if (_readBit() == 0) return 2;
    final two = _readBits(2);
    if (two < 3) return 3 + two;
    final five = _readBits(5);
    if (five < 31) return 6 + five;
    return 37 + _readBits(7);
  }
}

/// Tag tree (T.800 B.10.2).
class _TagTree {
  _TagTree(int width, int height) {
    var w = math.max(width, 1);
    var h = math.max(height, 1);
    while (true) {
      _widths.add(w);
      _values.add(Int32List(w * h));
      _known.add(Uint8List(w * h));
      if (w == 1 && h == 1) break;
      w = _ceilDiv(w, 2);
      h = _ceilDiv(h, 2);
    }
  }

  final _widths = <int>[];
  final _values = <Int32List>[];
  final _known = <Uint8List>[];

  /// Returns whether the value at (i, j) is < [threshold], consuming
  /// exactly the bits the encoder emitted for this query.
  bool decode(_PacketReader reader, int i, int j, int threshold) {
    final levels = _values.length;
    var low = 0;
    for (var level = levels - 1; level >= 0; level--) {
      final x = i >> level;
      final y = j >> level;
      final index = y * _widths[level] + x;
      if (_values[level][index] < low) _values[level][index] = low;
      while (_known[level][index] == 0 &&
          _values[level][index] < threshold) {
        if (reader._readBit() == 1) {
          _known[level][index] = 1;
        } else {
          _values[level][index]++;
        }
      }
      if (_known[level][index] == 0) return false;
      low = _values[level][index];
    }
    return _values[0][j * _widths[0] + i] < threshold;
  }

  /// Fully resolves the value at (i, j) (used for zero bit-planes).
  int decodeValue(_PacketReader reader, int i, int j) {
    var threshold = 1;
    while (!decode(reader, i, j, threshold)) {
      threshold++;
    }
    return _values[0][j * _widths[0] + i];
  }
}

// ---------------------------------------------------------------------
// tier-1: EBCOT bit-plane decoding
// ---------------------------------------------------------------------

class _BitModel {
  _BitModel(this.width, this.height, this.planes, this.family, this.decoder)
      : magnitudes = Int32List(width * height),
        signs = Uint8List(width * height),
        lowPlanes = Int8List(width * height),
        _significant = Uint8List(width * height),
        _refined = Uint8List(width * height),
        _visited = Uint8List(width * height) {
    _mps = Int8List(19);
    _index = Uint8List(19);
    _index[0] = 4; // first ZC context
    _index[17] = 3; // run-length
    _index[18] = 46; // uniform
  }

  final int width, height, planes;
  final int family;
  final MqDecoder decoder;
  final Int32List magnitudes;
  final Uint8List signs;
  final Int8List lowPlanes;
  final Uint8List _significant;
  final Uint8List _refined;
  final Uint8List _visited;
  late final Int8List _mps;
  late final Uint8List _index;
  int planesDecoded = 0;

  /// Code-block style bit 1 (0x02): reset the MQ context states to their
  /// initial values at the start of every coding pass (Table A.19).
  bool resetOnPass = false;

  void _resetContexts() {
    _mps.fillRange(0, _mps.length, 0);
    _index.fillRange(0, _index.length, 0);
    _index[0] = 4; // first ZC context
    _index[17] = 3; // run-length
    _index[18] = 46; // uniform
  }

  // zero-coding context lookup: neighbors (h, v, d) → context, per band
  // family (0: LL/LH, 1: HL, 2: HH)
  int _zcContext(int x, int y) {
    var h = 0, v = 0, d = 0;
    if (x > 0 && _significant[y * width + x - 1] != 0) h++;
    if (x + 1 < width && _significant[y * width + x + 1] != 0) h++;
    if (y > 0 && _significant[(y - 1) * width + x] != 0) v++;
    if (y + 1 < height && _significant[(y + 1) * width + x] != 0) v++;
    if (x > 0 && y > 0 && _significant[(y - 1) * width + x - 1] != 0) d++;
    if (x + 1 < width && y > 0 && _significant[(y - 1) * width + x + 1] != 0) {
      d++;
    }
    if (x > 0 && y + 1 < height && _significant[(y + 1) * width + x - 1] != 0) {
      d++;
    }
    if (x + 1 < width &&
        y + 1 < height &&
        _significant[(y + 1) * width + x + 1] != 0) {
      d++;
    }
    if (family == 1) {
      // HL: horizontal and vertical swap roles
      final t = h;
      h = v;
      v = t;
    }
    if (family == 2) {
      // HH: diagonal-dominated table
      if (d >= 3) return 8;
      if (d == 2) return h + v > 0 ? 7 : 6;
      if (d == 1) return h + v >= 2 ? 5 : (h + v == 1 ? 4 : 3);
      return h + v >= 2 ? 2 : (h + v == 1 ? 1 : 0);
    }
    if (h == 2) return 8;
    if (h == 1) {
      if (v >= 1) return 7;
      return d >= 1 ? 6 : 5;
    }
    if (v == 2) return 4;
    if (v == 1) return 3;
    if (d >= 2) return 2;
    return d == 1 ? 1 : 0;
  }

  /// Sign coding: context 9–13 plus an XOR bit, from the H/V neighbor
  /// significance/sign contributions.
  (int, int) _scContext(int x, int y) {
    int contribution(int nx, int ny) {
      if (nx < 0 || nx >= width || ny < 0 || ny >= height) return 0;
      final index = ny * width + nx;
      if (_significant[index] == 0) return 0;
      return signs[index] == 0 ? 1 : -1;
    }

    var h = contribution(x - 1, y) + contribution(x + 1, y);
    var v = contribution(x, y - 1) + contribution(x, y + 1);
    h = h.clamp(-1, 1);
    v = v.clamp(-1, 1);
    if (h == 1) return (v == 1 ? 13 : (v == 0 ? 12 : 11), 0);
    if (h == 0) return (v == 1 ? 10 : (v == 0 ? 9 : 10), v == -1 ? 1 : 0);
    return (v == 1 ? 11 : (v == 0 ? 12 : 13), 1);
  }

  bool _hasSignificantNeighbor(int x, int y) {
    for (var dy = -1; dy <= 1; dy++) {
      for (var dx = -1; dx <= 1; dx++) {
        if (dx == 0 && dy == 0) continue;
        final nx = x + dx, ny = y + dy;
        if (nx < 0 || nx >= width || ny < 0 || ny >= height) continue;
        if (_significant[ny * width + nx] != 0) return true;
      }
    }
    return false;
  }

  void decodePasses(int passCount) {
    var plane = planes - 1;
    var pass = 0;
    // the first pass is always a cleanup pass on the top plane
    var passType = 2;
    while (pass < passCount && plane >= 0) {
      // Reset the context states (but not the arithmetic decoder register) at
      // each coding-pass boundary when the reset flag is set. The first reset
      // matches the constructor's initial state, so it is a harmless no-op.
      if (resetOnPass) _resetContexts();
      switch (passType) {
        case 0:
          _significancePass(plane);
        case 1:
          _refinementPass(plane);
        case 2:
          _cleanupPass(plane);
      }
      pass++;
      if (passType == 2) {
        plane--;
        passType = 0;
      } else {
        passType++;
      }
    }
    planesDecoded = plane + 1;
  }

  void _significancePass(int plane) {
    final bit = 1 << plane;
    for (var y0 = 0; y0 < height; y0 += 4) {
      for (var x = 0; x < width; x++) {
        for (var y = y0; y < math.min(y0 + 4, height); y++) {
          final index = y * width + x;
          if (_significant[index] != 0 || !_hasSignificantNeighbor(x, y)) {
            continue;
          }
          _visited[index] = 1;
          final d = decoder.decode(_mps, _index, _zcContext(x, y));
          if (d == 1) {
            final (sc, xorBit) = _scContext(x, y);
            final sign = decoder.decode(_mps, _index, sc) ^ xorBit;
            _significant[index] = 1;
            signs[index] = sign;
            magnitudes[index] = bit;
            lowPlanes[index] = plane;
          }
        }
      }
    }
  }

  void _refinementPass(int plane) {
    final bit = 1 << plane;
    for (var y0 = 0; y0 < height; y0 += 4) {
      for (var x = 0; x < width; x++) {
        for (var y = y0; y < math.min(y0 + 4, height); y++) {
          final index = y * width + x;
          if (_significant[index] == 0 || _visited[index] != 0) continue;
          int context;
          if (_refined[index] == 0) {
            context = _hasSignificantNeighbor(x, y) ? 15 : 14;
            _refined[index] = 1;
          } else {
            context = 16;
          }
          final d = decoder.decode(_mps, _index, context);
          if (d == 1) magnitudes[index] |= bit;
          lowPlanes[index] = plane;
        }
      }
    }
  }

  void _cleanupPass(int plane) {
    final bit = 1 << plane;
    for (var y0 = 0; y0 < height; y0 += 4) {
      for (var x = 0; x < width; x++) {
        var y = y0;
        final columnHeight = math.min(4, height - y0);
        // run-length mode: the whole 4-column is insignificant with no
        // significant neighbors and nothing visited
        var runLength = false;
        if (columnHeight == 4) {
          runLength = true;
          for (var k = 0; k < 4; k++) {
            final index = (y0 + k) * width + x;
            if (_significant[index] != 0 ||
                _visited[index] != 0 ||
                _hasSignificantNeighbor(x, y0 + k)) {
              runLength = false;
              break;
            }
          }
        }
        if (runLength) {
          final any = decoder.decode(_mps, _index, 17);
          if (any == 0) {
            _clearVisited(x, y0, columnHeight);
            continue; // all four stay insignificant
          }
          final position = (decoder.decode(_mps, _index, 18) << 1) |
              decoder.decode(_mps, _index, 18);
          y = y0 + position;
          // the coefficient at `position` is significant by definition
          final index = y * width + x;
          final (sc, xorBit) = _scContext(x, y);
          final sign = decoder.decode(_mps, _index, sc) ^ xorBit;
          _significant[index] = 1;
          signs[index] = sign;
          magnitudes[index] = bit;
          lowPlanes[index] = plane;
          y++;
        }
        for (; y < y0 + columnHeight; y++) {
          final index = y * width + x;
          if (_significant[index] != 0 || _visited[index] != 0) continue;
          final d = decoder.decode(_mps, _index, _zcContext(x, y));
          if (d == 1) {
            final (sc, xorBit) = _scContext(x, y);
            final sign = decoder.decode(_mps, _index, sc) ^ xorBit;
            _significant[index] = 1;
            signs[index] = sign;
            magnitudes[index] = bit;
            lowPlanes[index] = plane;
          }
        }
        _clearVisited(x, y0, columnHeight);
      }
    }
  }

  void _clearVisited(int x, int y0, int count) {
    for (var k = 0; k < count; k++) {
      _visited[(y0 + k) * width + x] = 0;
    }
  }
}

// ---------------------------------------------------------------------
// dequantization and inverse wavelet
// ---------------------------------------------------------------------

extension on _Band {
  /// Decoded coefficients of this band as floats (already dequantized).
  Float32List dequantize(_TileComponent tc, bool reversible) {
    final w = x1 - x0, h = y1 - y0;
    final out = Float32List(math.max(w * h, 0));
    if (w <= 0 || h <= 0) return out;

    for (final block in blocks) {
      final mags = block.magnitudes;
      final blockSigns = block.signs;
      final lows = block.lowPlanes;
      if (mags == null || blockSigns == null || lows == null) continue;
      for (var by = 0; by < block.height; by++) {
        final row = (block.y0 - y0 + by) * w + (block.x0 - x0);
        for (var bx = 0; bx < block.width; bx++) {
          final i = by * block.width + bx;
          final magnitude = mags[i];
          if (magnitude == 0) continue;
          // add the mid-point of this coefficient's undecoded tail
          var value = magnitude.toDouble();
          final low = lows[i];
          if (low > 0) value += 1 << (low - 1);
          if (blockSigns[i] != 0) value = -value;
          out[row + bx] = reversible ? value : value * delta;
        }
      }
    }
    return out;
  }
}

Float32List _inverseDwt({
  required Float32List ll,
  required int llX0,
  required int llY0,
  required int llX1,
  required int llY1,
  required Float32List hl,
  required Float32List lh,
  required Float32List hh,
  required List<_Band> bands,
  required int x0,
  required int y0,
  required int x1,
  required int y1,
  required bool reversible,
}) {
  final w = x1 - x0, h = y1 - y0;
  final out = Float32List(w * h);

  // 2D interleave (T.800 F.3.2): LL at (even, even), HL at (odd, even),
  // LH at (even, odd), HH at (odd, odd) in the resolution grid
  final hlBand = bands[0], lhBand = bands[1], hhBand = bands[2];
  void scatter(Float32List source, int sx0, int sy0, int sx1, int sy1,
      int parityX, int parityY) {
    final sw = sx1 - sx0;
    for (var sy = sy0; sy < sy1; sy++) {
      final ty = 2 * sy + parityY - y0;
      if (ty < 0 || ty >= h) continue;
      for (var sx = sx0; sx < sx1; sx++) {
        final tx = 2 * sx + parityX - x0;
        if (tx < 0 || tx >= w) continue;
        out[ty * w + tx] = source[(sy - sy0) * sw + (sx - sx0)];
      }
    }
  }

  scatter(ll, llX0, llY0, llX1, llY1, 0, 0);
  scatter(hl, hlBand.x0, hlBand.y0, hlBand.x1, hlBand.y1, 1, 0);
  scatter(lh, lhBand.x0, lhBand.y0, lhBand.x1, lhBand.y1, 0, 1);
  scatter(hh, hhBand.x0, hhBand.y0, hhBand.x1, hhBand.y1, 1, 1);

  // horizontal then vertical 1D synthesis
  final row = Float32List(w);
  for (var yy = 0; yy < h; yy++) {
    row.setRange(0, w, out, yy * w);
    _synthesize1d(row, x0, reversible);
    out.setRange(yy * w, (yy + 1) * w, row);
  }
  final column = Float32List(h);
  for (var xx = 0; xx < w; xx++) {
    for (var yy = 0; yy < h; yy++) {
      column[yy] = out[yy * w + xx];
    }
    _synthesize1d(column, y0, reversible);
    for (var yy = 0; yy < h; yy++) {
      out[yy * w + xx] = column[yy];
    }
  }
  return out;
}

/// In-place 1D inverse wavelet over [signal], whose first sample sits at
/// global index [i0] (parity decides low/high classification).
void _synthesize1d(Float32List signal, int i0, bool reversible) {
  final n = signal.length;
  if (n == 1) {
    // a single sample at odd parity is a pure high-pass sample
    if (reversible && i0.isOdd) signal[0] /= 2;
    if (!reversible && i0.isOdd) signal[0] *= 0.5;
    return;
  }

  // extend with symmetric boundary handling via index mirroring
  double at(int i) {
    var index = i;
    if (index < 0) index = -index;
    if (index >= n) index = 2 * (n - 1) - index;
    return signal[index.clamp(0, n - 1)];
  }

  final result = Float32List(n);
  if (reversible) {
    // 5/3 (T.800 F.3.8.2): even samples first, then odd
    for (var i = 0; i < n; i++) {
      final global = i0 + i;
      if (global.isEven) {
        result[i] =
            signal[i] - ((at(i - 1) + at(i + 1) + 2) / 4).floorToDouble();
      }
    }
    double even(int i) {
      var index = i;
      if (index < 0) index = -index;
      if (index >= n) index = 2 * (n - 1) - index;
      index = index.clamp(0, n - 1);
      return (i0 + index).isEven ? result[index] : signal[index];
    }

    for (var i = 0; i < n; i++) {
      final global = i0 + i;
      if (global.isOdd) {
        result[i] =
            signal[i] + ((even(i - 1) + even(i + 1)) / 2).floorToDouble();
      }
    }
  } else {
    // 9/7 (T.800 F.4.8.2)
    const k = 1.230174104914;
    const alpha = -1.586134342059924;
    const beta = -0.052980118572961;
    const gamma = 0.882911075530934;
    const delta = 0.443506852043971;
    for (var i = 0; i < n; i++) {
      result[i] = (i0 + i).isEven ? signal[i] * k : signal[i] / k;
    }
    Float32List current = result;
    double cat(int i) {
      var index = i;
      if (index < 0) index = -index;
      if (index >= n) index = 2 * (n - 1) - index;
      return current[index.clamp(0, n - 1)];
    }

    void lift(double coefficient, bool evenTargets) {
      final next = Float32List.fromList(current);
      for (var i = 0; i < n; i++) {
        final isEven = (i0 + i).isEven;
        if (isEven == evenTargets) {
          next[i] = current[i] - coefficient * (cat(i - 1) + cat(i + 1));
        }
      }
      current = next;
    }

    lift(delta, true);
    lift(gamma, false);
    lift(beta, true);
    lift(alpha, false);
    result.setRange(0, n, current);
  }
  signal.setRange(0, n, result);
}
