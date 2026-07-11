// Pure-Dart Slug curve-atlas planning. Worker isolates build these typed-data
// batches; dart_pdf_editor only wraps them in ui.Vertices and uploads the
// atlas. Keeping curve conversion here prevents dense web pages from putting
// the expensive outline/band walk back on the browser UI thread.
import 'dart:math' as math;
import 'dart:typed_data';

import '../matrix.dart';
import '../path.dart';
import 'curve_quads.dart';
import 'flatten.dart';

/// Curve atlas width in texels.
const int slugAtlasWidth = 512;

/// Maximum glyph quads in one drawVertices call (Uint16 indices).
const int slugMaxQuadsPerDraw = 16000;

/// Per-outline relocatable curve stream, memoized by outline identity.
class SlugGlyphData {
  SlugGlyphData._(this.stream, this.texelCount, this.bandCount, this.minX,
      this.minY, this.maxX, this.maxY, this.overflow)
      : qMinX = stream == null ? 0 : fixedToEm(emToFixed(minX)),
        qMinY = stream == null ? 0 : fixedToEm(emToFixed(minY));

  final Uint8List? stream;
  final int texelCount;
  final int bandCount;
  final double minX, minY, maxX, maxY;
  final double qMinX, qMinY;
  final bool overflow;

  static final Expando<SlugGlyphData> _cache = Expando('SlugGlyphData');
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
      result = _overflow;
    }
    totalBuildMicros += sw.elapsedMicroseconds;
    totalBuilds++;
    _cache[outline] = result;
    return result;
  }
}

/// One drawVertices-sized slice of a Slug batch.
class SlugChunkData {
  SlugChunkData(
      this.positions, this.textureCoordinates, this.colors, this.indices);

  final Float32List positions;
  final Float32List textureCoordinates;
  final Int32List colors;
  final Uint16List indices;
}

/// One painter-order Slug batch in worker-transferable form.
class SlugBatchData {
  SlugBatchData(this.flushOrdinal, this.chunks, this.atlasPixels,
      this.atlasWidth, this.atlasHeight, this.quadCount, this.cellHeight);

  /// The strip flush point immediately preceding this text run.
  final int flushOrdinal;
  final List<SlugChunkData> chunks;
  final Uint8List atlasPixels;
  final int atlasWidth;
  final int atlasHeight;
  final int quadCount;
  final double cellHeight;
}

/// Accumulates one painter-order Slug window without any dart:ui objects.
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

  bool overlaps(double minX, double minY, double maxX, double maxY) =>
      _quadCount != 0 &&
      minX <= _maxPX &&
      maxX >= _minPX &&
      minY <= _maxPY &&
      maxY >= _minPY;

  double get estimatedVExtent => _slotData.length * (_maxCellH + 4);

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
    final padX = 16.0 / qsx, padY = 16.0 / qsy;
    final x0 = data.minX - padX, x1 = data.maxX + padX;
    final y0 = data.minY - padY, y1 = data.maxY + padY;
    final u0 = 2.0 + (x0 - data.qMinX) * sx;
    final u1 = 2.0 + (x1 - data.qMinX) * sx;
    final lv0 = 2.0 + (y0 - data.qMinY) * sy;
    final lv1 = 2.0 + (y1 - data.qMinY) * sy;
    if (lv1 > _maxCellH) _maxCellH = lv1;
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
    _colors.addAll([argb, argb, argb, argb]);
    _quadCount++;
  }

  SlugBatchData? build([int flushOrdinal = 0]) {
    if (_quadCount == 0) return null;
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

    final positions = _positions.view;
    final texs = _texs.view;
    final cellH = (_maxCellH + 2).ceilToDouble();
    for (var q = 0; q < _quadCount; q++) {
      final vBase = _quadSlot[q] * cellH;
      final t = q * 8;
      texs[t + 1] += vBase;
      texs[t + 3] += vBase;
      texs[t + 5] += vBase;
      texs[t + 7] += vBase;
    }
    final chunks = <SlugChunkData>[];
    for (var start = 0; start < _quadCount; start += slugMaxQuadsPerDraw) {
      final count = math.min(slugMaxQuadsPerDraw, _quadCount - start);
      final pos = Float32List.fromList(
          Float32List.sublistView(positions, start * 8, (start + count) * 8));
      final tex = Float32List.fromList(
          Float32List.sublistView(texs, start * 8, (start + count) * 8));
      final colors =
          Int32List.fromList(_colors.sublist(start * 4, (start + count) * 4));
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
      chunks.add(SlugChunkData(pos, tex, colors, indices));
    }
    final batch = SlugBatchData(flushOrdinal, chunks, pixels, slugAtlasWidth,
        height, _quadCount, cellH);
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
