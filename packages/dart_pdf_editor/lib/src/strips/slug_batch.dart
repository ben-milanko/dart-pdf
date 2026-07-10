// Slug glyph batching (B3): per-outline curve streams (built once, cached
// by outline identity) assembled per flush into a slot-directory curve
// atlas, drawn as glyph quads through shaders/pdf_slug.frag.
//
// Per-glyph data reaches the shader through the two texcoord floats alone
// (vertex colors only modulate). A slot is one (outline, quantized px/em
// scale) pair per batch; every occurrence of that glyph at that scale
// shares the slot. Slots stack along v in cells of a per-batch constant
// height (cellHeight, texcoord units == record-time device pixels):
//   u = 2 + (emX - minX) * S      S = quantized px/em (the slot key)
//   v = slot * cellHeight + 2 + (emY - minY) * S
// (minX/minY are the slot's fixed-point-quantized band bbox, exactly what
// the shader decodes from the directory, so the inversion is exact).
//
// Texcoord units MUST be device-pixel-scaled: Impeller evaluates
// drawVertices runtime effects on an integer-aligned texcoord-unit grid
// (it snapshots the effect at ~1 texel per unit and samples that with the
// vertex UVs - measured, see the 2026-07-10 slug dev-log), so em-unit
// texcoords would collapse a glyph to a single evaluated sample. The
// 2-texel cell inset keeps Impeller's bilinear snapshot resampling from
// bleeding across slot cells. Skia evaluates per fragment directly; both
// backends see the same GLSL.
//
// The atlas starts with a 4-texel directory entry per slot (stream base as
// a u16 pair, band geometry and AA scale - see pdf_slug.frag), followed by
// the glyphs' relocatable texel streams verbatim (their internal offsets
// are stream-relative by design, curve_quads.dart).
//
// The atlas is rebuilt per flush (streams are memcpys of cached bytes;
// noted cost - a persistent cross-flush atlas is a later optimization).
import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:pdf_graphics/pdf_graphics.dart';
import 'package:pdf_graphics/raster.dart';

/// Curve atlas width in texels.
const int slugAtlasWidth = 512;

/// Per-outline Slug data: the relocatable texel stream + band geometry,
/// built once per outline identity ([of] memoizes via Expando, the same
/// lifetime pattern as [FlattenedOutline]). [overflow] marks glyphs that
/// exceed the band cap (or failed to encode) - callers use outline strips.
class SlugGlyphData {
  SlugGlyphData._(this.stream, this.texelCount, this.bandCount, this.minX,
      this.minY, this.maxX, this.maxY, this.overflow)
      : qMinX = stream == null ? 0 : fixedToEm(emToFixed(minX)),
        qMinY = stream == null ? 0 : fixedToEm(emToFixed(minY));

  final Uint8List? stream;
  final int texelCount;
  final int bandCount;
  final double minX, minY, maxX, maxY;

  /// [minX]/[minY] through the directory's fixed-point quantization - the
  /// exact values the shader decodes, used for the texcoord mapping so the
  /// em recovery inverts exactly.
  final double qMinX, qMinY;

  final bool overflow;

  static final Expando<SlugGlyphData> _cache = Expando('SlugGlyphData');

  /// One-time build cost accounting (microseconds / outlines built).
  static int totalBuildMicros = 0;
  static int totalBuilds = 0;

  static final SlugGlyphData _overflow =
      SlugGlyphData._(null, 0, 0, 0, 0, 0, 0, true);

  static SlugGlyphData of(PdfPath outline) {
    final cached = _cache[outline];
    if (cached != null) return cached;
    final sw = Stopwatch()..start();
    SlugGlyphData result;
    try {
      final quads = outlineToQuads(outline);
      final bands = buildBands(quads, bandCount: 8);
      if (quads.isEmpty || bands.overflow) {
        result = _overflow;
      } else {
        final stream = encodeGlyphStream(quads, bands);
        result = SlugGlyphData._(stream, stream.length ~/ 4, bands.bandCount,
            bands.minX, bands.minY, bands.maxX, bands.maxY, false);
      }
    } on ArgumentError {
      result = _overflow; // stream too large
    }
    totalBuildMicros += sw.elapsedMicroseconds;
    totalBuilds++;
    _cache[outline] = result;
    return result;
  }
}

/// One flushed batch of Slug glyph quads sharing one curve atlas.
class SlugBatch {
  SlugBatch._(this.chunks, this.atlasPixels, this.atlasWidth,
      this.atlasHeight, this.quadCount, this.cellHeight);

  final List<ui.Vertices> chunks;
  final Uint8List atlasPixels;
  final int atlasWidth;
  final int atlasHeight;
  final int quadCount;

  /// Slot cell stride along v, in texcoord units (integer-valued); the
  /// shader's uCellH uniform.
  final double cellHeight;

  ui.Image? atlas;

  Future<void> decodeAtlas() {
    final completer = Completer<void>();
    ui.decodeImageFromPixels(
        atlasPixels, atlasWidth, atlasHeight, ui.PixelFormat.rgba8888,
        (image) {
      atlas = image;
      completer.complete();
    });
    return completer.future;
  }

  void dispose() {
    atlas?.dispose();
    atlas = null;
    for (final v in chunks) {
      v.dispose();
    }
  }
}

/// Accumulates one flush window's Slug quads and assembles the [SlugBatch].
class SlugBatchBuilder {
  final Map<(PdfPath, int, int), int> _slots = {};
  final List<SlugGlyphData> _slotData = [];
  final List<int> _slotQsx = [];
  final List<int> _slotQsy = [];

  final FloatBuilder _positions = FloatBuilder(256);
  final FloatBuilder _texs = FloatBuilder(256);
  final List<int> _colors = [];
  final List<int> _quadSlot = [];
  double _maxCellH = 0;
  int _quadCount = 0;
  double _minPX = double.infinity, _minPY = double.infinity;
  double _maxPX = double.negativeInfinity, _maxPY = double.negativeInfinity;

  bool get isEmpty => _quadCount == 0;
  int get quadCount => _quadCount;
  int get slotCount => _slotData.length;

  /// Page-space bbox of the pending quads - lets the device keep batching
  /// when later vector paints don't overlap any pending glyph (painter's
  /// order only matters where pixels overlap).
  bool overlaps(double minX, double minY, double maxX, double maxY) =>
      _quadCount != 0 &&
      minX <= _maxPX &&
      maxX >= _minPX &&
      minY <= _maxPY &&
      maxY >= _minPY;

  /// Upper bound on the built batch's texcoord v extent
  /// (slots x cell height). Impeller snapshots the runtime effect over the
  /// texcoord bounds at ~1 texel per unit, so callers should flush before
  /// this approaches the max texture size (see StripPdfDevice).
  double get estimatedVExtent => _slotData.length * (_maxCellH + 4);

  /// Adds one glyph occurrence: [emToPage] places the em-space quad in
  /// page space; [pxPerEmX]/[pxPerEmY] are the record-time device scales
  /// (they set the shader's AA ramp width, the texcoord scale - texcoord
  /// units are record-time device pixels - and quantize into the slot key
  /// at 1/16 px/em).
  void addGlyph(PdfPath outline, SlugGlyphData data, PdfMatrix emToPage,
      double pxPerEmX, double pxPerEmY, int argb) {
    final qsx = (pxPerEmX * 16).round().clamp(1, 0xFFFF);
    final qsy = (pxPerEmY * 16).round().clamp(1, 0xFFFF);
    final slot = _slots.putIfAbsent((outline, qsx, qsy), () {
      _slotData.add(data);
      _slotQsx.add(qsx);
      _slotQsy.add(qsy);
      return _slotData.length - 1;
    });
    final sx = qsx / 16.0, sy = qsy / 16.0;

    // em bbox padded by exactly one device pixel so the AA ramp fits
    final padX = 16.0 / qsx, padY = 16.0 / qsy;
    final x0 = data.minX - padX, x1 = data.maxX + padX;
    final y0 = data.minY - padY, y1 = data.maxY + padY;
    // texcoords in device-pixel units, local to the slot cell (the slot's
    // v base is patched in at build() once the max cell height is known);
    // the 2-texel inset leaves a >=1-texel guard band around the cell.
    final u0 = 2.0 + (x0 - data.qMinX) * sx;
    final u1 = 2.0 + (x1 - data.qMinX) * sx;
    final lv0 = 2.0 + (y0 - data.qMinY) * sy;
    final lv1 = 2.0 + (y1 - data.qMinY) * sy;
    if (lv1 > _maxCellH) _maxCellH = lv1;
    // corners in em order (x0,y0) (x1,y0) (x0,y1) (x1,y1)
    final px0 = emToPage.transformX(x0, y0), py0 = emToPage.transformY(x0, y0);
    final px1 = emToPage.transformX(x1, y0), py1 = emToPage.transformY(x1, y0);
    final px2 = emToPage.transformX(x0, y1), py2 = emToPage.transformY(x0, y1);
    final px3 = emToPage.transformX(x1, y1), py3 = emToPage.transformY(x1, y1);
    _positions.add4(px0, py0, px1, py1);
    _positions.add4(px2, py2, px3, py3);
    _minPX = math.min(_minPX, math.min(math.min(px0, px1), math.min(px2, px3)));
    _maxPX = math.max(_maxPX, math.max(math.max(px0, px1), math.max(px2, px3)));
    _minPY = math.min(_minPY, math.min(math.min(py0, py1), math.min(py2, py3)));
    _maxPY = math.max(_maxPY, math.max(math.max(py0, py1), math.max(py2, py3)));
    _texs.add4(u0, lv0, u1, lv0);
    _texs.add4(u0, lv1, u1, lv1);
    _quadSlot.add(slot);
    _colors.add(argb);
    _colors.add(argb);
    _colors.add(argb);
    _colors.add(argb);
    _quadCount++;
  }

  /// Assembles the batch (atlas + vertices) and resets the builder.
  /// Returns null when empty.
  SlugBatch? build() {
    if (_quadCount == 0) return null;

    // ---- curve atlas: directory + concatenated streams ----
    final slotCount = _slotData.length;
    var total = 4 * slotCount;
    final bases = Int32List(slotCount);
    for (var i = 0; i < slotCount; i++) {
      bases[i] = total;
      total += _slotData[i].texelCount;
    }
    final height = math.max(1, (total + slugAtlasWidth - 1) ~/ slugAtlasWidth);
    final pixels = Uint8List(slugAtlasWidth * height * 4);
    final u16 = ByteData.sublistView(pixels);
    void put(int texel, int lo, int hi) {
      u16.setUint16(texel * 4, lo, Endian.little);
      u16.setUint16(texel * 4 + 2, hi, Endian.little);
    }

    for (var i = 0; i < slotCount; i++) {
      final d = _slotData[i];
      final base = bases[i];
      put(4 * i, base & 0xFFFF, base >> 16);
      put(4 * i + 1, emToFixed(d.minY),
          emToFixed((d.maxY - d.minY) / d.bandCount));
      put(4 * i + 2, emToFixed(d.minX),
          emToFixed((d.maxX - d.minX) / d.bandCount));
      put(4 * i + 3, _slotQsx[i], _slotQsy[i]);
      pixels.setRange(base * 4, base * 4 + d.stream!.length, d.stream!);
    }

    // ---- vertices (Uint16 indices cap quads per draw) ----
    const maxQuads = 16000;
    final chunks = <ui.Vertices>[];
    final positions = _positions.view;
    final texs = _texs.view;
    // patch each quad's v by its slot's cell base, now that the constant
    // cell height (max over slots, +2 trailing guard texels) is known
    final cellH = (_maxCellH + 2).ceilToDouble();
    for (var q = 0; q < _quadCount; q++) {
      final vBase = _quadSlot[q] * cellH;
      final t = q * 8;
      texs[t + 1] += vBase;
      texs[t + 3] += vBase;
      texs[t + 5] += vBase;
      texs[t + 7] += vBase;
    }
    for (var start = 0; start < _quadCount; start += maxQuads) {
      final count = math.min(maxQuads, _quadCount - start);
      final pos = Float32List.sublistView(
          positions, start * 8, (start + count) * 8);
      final tex = Float32List.sublistView(texs, start * 8, (start + count) * 8);
      final colors = Int32List(count * 4);
      for (var i = 0; i < count * 4; i++) {
        colors[i] = _colors[start * 4 + i];
      }
      final indices = Uint16List(count * 6);
      for (var q = 0; q < count; q++) {
        final v = q * 4, ix = q * 6;
        indices[ix] = v;
        indices[ix + 1] = v + 1;
        indices[ix + 2] = v + 2;
        indices[ix + 3] = v + 1;
        indices[ix + 4] = v + 3;
        indices[ix + 5] = v + 2;
      }
      chunks.add(ui.Vertices.raw(ui.VertexMode.triangles,
          Float32List.fromList(pos),
          textureCoordinates: Float32List.fromList(tex),
          colors: colors,
          indices: indices));
    }

    final batch = SlugBatch._(
        chunks, pixels, slugAtlasWidth, height, _quadCount, cellH);
    _slots.clear();
    _slotData.clear();
    _slotQsx.clear();
    _slotQsy.clear();
    _positions.clear();
    _texs.clear();
    _colors.clear();
    _quadSlot.clear();
    _maxCellH = 0;
    _quadCount = 0;
    _minPX = _minPY = double.infinity;
    _maxPX = _maxPY = double.negativeInfinity;
    return batch;
  }
}
