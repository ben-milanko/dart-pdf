// A precomputed strip-binning result and its wire codec: everything a
// StripPdfDevice needs to skip the flatten/stroke-expansion/coverage work
// of a zoom re-bin because a worker isolate already did it. Pure Dart -
// the plan crosses the isolate boundary as one Uint8List (a single
// TransferableTypedData on native, postMessage-transferable on the web).
import 'dart:math' as math;
import 'dart:typed_data';

import '../device.dart';
import '../interpreter.dart' show PdfCancellationToken;
import '../matrix.dart';
import '../render_command.dart';
import 'slug_batch_data.dart';
import 'strip_batch_data.dart';
import 'strip_binning_device.dart';

/// The strip batches of one full binning walk, tagged with the geometry
/// they were binned for. Only valid for a device with the exact same
/// [pageToDevice] matrix, viewport, and [tolerance]; the consuming device
/// verifies [totalFlushPoints] and full batch consumption at finish and
/// falls back to local binning on any mismatch.
class StripPlan {
  StripPlan({
    required this.totalFlushPoints,
    required this.deviceWidth,
    required this.deviceHeight,
    required this.pageToDevice,
    required this.tolerance,
    required this.batches,
    this.slugGlyphs = false,
    this.slugBatches = const [],
    this.slugQuadCount = 0,
    this.slugFallbackOutlineRuns = 0,
    this.slugFallbackOrdinals = const [],
  });

  /// Flush points the binning walk counted (empty ones included) - must
  /// equal the consuming device's own count for the plan to be valid.
  final int totalFlushPoints;

  final int deviceWidth;
  final int deviceHeight;

  /// Page space -> device pixels, exactly as the consuming device will be
  /// constructed (the six coefficients round-trip bit-exactly).
  final PdfMatrix pageToDevice;

  /// The flatten tolerance the strips were binned at
  /// ([stripFlattenTolerance] everywhere today; carried for the guard).
  final double tolerance;

  /// Non-empty batches ordered by [StripBatchData.flushOrdinal].
  final List<StripBatchData> batches;

  /// Whether outline text was routed into worker-built Slug batches.
  final bool slugGlyphs;
  final List<SlugBatchData> slugBatches;
  final int slugQuadCount;
  final int slugFallbackOutlineRuns;
  final List<int> slugFallbackOrdinals;
}

/// Thrown when a [StripPlan] does not match the device consuming it
/// (stale geometry, or a flush-ordinal/batch-count desync). Callers catch
/// it, discard the picture, and re-run with local binning.
class StripPlanMismatchError extends Error {
  StripPlanMismatchError(this.message);
  final String message;

  @override
  String toString() => 'StripPlanMismatchError: $message';
}

/// Headless subclass of the binning core: collects the [StripBatchData]
/// emitted at each flush point (delegated ops are no-ops) into a
/// [StripPlan]. Feed it the page's command list with [bin] - which honors
/// a [PdfCancellationToken] cooperatively - then take [finish]'s plan.
class StripPlanBinner extends StripBinningDevice {
  StripPlanBinner({
    required super.pageToDevice,
    required super.deviceWidth,
    required super.deviceHeight,
    required super.pixelRatio,
    this.slugGlyphs = false,
    this.slugMinGlyphPx = 4,
  });

  final List<StripBatchData> batches = [];
  final bool slugGlyphs;
  final double slugMinGlyphPx;
  final List<SlugBatchData> slugBatches = [];
  SlugBatchBuilder? _slugBuilder;
  int slugQuadCount = 0;
  int slugFallbackOutlineRuns = 0;
  final List<int> slugFallbackOrdinals = [];
  bool _finished = false;

  @override
  void emitBatch(int ordinal, StripBatchData? data) {
    if (data != null) batches.add(data);
  }

  /// Replays [commands] through the binning core, yielding to the event
  /// loop (and checking [cancellation]) every ~1024 commands so a worker's
  /// cancel message can preempt a long walk - the same cooperative scheme
  /// as the worker's record path.
  Future<void> bin(List<PdfRenderCommand> commands,
          {PdfCancellationToken? cancellation}) =>
      replayCommandsCancellable(commands, this, cancellation: cancellation);

  /// Runs the final flush point and packages the plan. Call exactly once,
  /// after every command has been replayed.
  StripPlan finish() {
    assert(!_finished, 'StripPlanBinner.finish() called twice');
    _finished = true;
    flushPending();
    return StripPlan(
      totalFlushPoints: flushPointCount,
      deviceWidth: deviceWidth,
      deviceHeight: deviceHeight,
      pageToDevice: pageToDevice,
      tolerance: stripFlattenTolerance,
      batches: batches,
      slugGlyphs: slugGlyphs,
      slugBatches: slugBatches,
      slugQuadCount: slugQuadCount,
      slugFallbackOutlineRuns: slugFallbackOutlineRuns,
      slugFallbackOrdinals: slugFallbackOrdinals,
    );
  }

  @override
  void drawText(PdfTextRun run) {
    final glyphs = run.glyphs;
    if (!slugGlyphs ||
        run.invisible ||
        !stripsActive ||
        delegateText ||
        glyphs == null ||
        !run.fill ||
        run.strokeColor != null ||
        run.gradient != null) {
      super.drawText(run);
      return;
    }
    flushPending();
    if (!_addSlugRun(glyphs, run, stripArgbColor(run.color, 1))) {
      slugFallbackOutlineRuns++;
      slugFallbackOrdinals.add(flushPointCount - 1);
      super.drawText(run);
      return;
    }
    _flushSlug(flushPointCount - 1);
  }

  static const double _slugMaxVExtent = 8192;

  bool _addSlugRun(List<PdfGlyphPlacement> glyphs, PdfTextRun run, int color) {
    final deviceTransform = run.transform.concat(pageToDevice);
    final sx = math.sqrt(deviceTransform.a * deviceTransform.a +
        deviceTransform.b * deviceTransform.b);
    final sy = math.sqrt(deviceTransform.c * deviceTransform.c +
        deviceTransform.d * deviceTransform.d);
    if (math.max(sx, sy) < slugMinGlyphPx) return false;
    for (final glyph in glyphs) {
      final outline = glyph.outline;
      if (outline != null && SlugGlyphData.of(outline).overflow) return false;
    }
    final builder = _slugBuilder ??= SlugBatchBuilder();
    for (final glyph in glyphs) {
      final outline = glyph.outline;
      if (outline == null) continue;
      builder.addGlyph(
          outline,
          SlugGlyphData.of(outline),
          PdfMatrix.translation(glyph.offset, glyph.offsetY)
              .concat(run.transform),
          sx,
          sy,
          color);
    }
    if (builder.estimatedVExtent > _slugMaxVExtent) {
      _flushSlug(flushPointCount - 1);
    }
    return true;
  }

  void _flushSlug(int ordinal) {
    final batch = _slugBuilder?.build(ordinal);
    if (batch == null) return;
    slugBatches.add(batch);
    slugQuadCount += batch.quadCount;
  }

  // Delegated ops paint nothing here - the live device replays them from
  // its own retained scene; the plan only carries strips.
  @override
  void delegateSave() {}
  @override
  void delegateRestore() {}
  @override
  void delegateClipPath(path, rule) {}
  @override
  void delegateSetBlendMode(mode) {}
  @override
  void delegateSetOverprint({required fill, required stroke, required mode}) {}
  @override
  void delegateBeginGroup(double alpha, {required bool knockout}) {}
  @override
  void delegateEndGroup() {}
  @override
  void delegateBeginSoftMasked() {}
  @override
  void delegateBeginSoftMaskComposite(
      {required luminosity,
      required backdrop,
      required double backdropLuminance,
      required double transferScale,
      required double transferOffset}) {}
  @override
  void delegateFinishSoftMaskComposite() {}
  @override
  void delegateFillPath(path, color, rule, double alpha) {}
  @override
  void delegateStrokePath(path, color, stroke, double alpha) {}
  @override
  void delegateFillPathGradient(path, rule, gradient, double alpha) {}
  @override
  void delegateFillMesh(mesh, double alpha) {}
  @override
  void delegateDrawText(run) {}
  @override
  void delegateDrawImage(request) {}
}

// ---- codec ----------------------------------------------------------------
//
// Layout (version byte first, scalars big-endian like render_command_codec;
// the bulk vertex/atlas arrays are written as raw host-order bytes - both
// ends of the wire are the same build on the same architecture, and every
// supported platform is little-endian):
//
//   u8  version
//   u32 totalFlushPoints, u32 deviceWidth, u32 deviceHeight
//   f64 x6 pageToDevice, f64 tolerance
//   u8 slugGlyphs, u32 slugQuadCount, u32 slugFallbackOutlineRuns
//   u32 slugFallbackOrdinalCount + ordinals
//   u32 batchCount, then per batch:
//     u32 flushOrdinal, u32 stripCount, u32 atlasWidth, u32 atlasHeight
//     u32 atlasByteLength + raw atlas bytes
//     u32 chunkCount, then per chunk:
//       u32 quadCount, u32 alphaBase
//       raw positions (quadCount*8 f32), texcoords (quadCount*8 f32),
//           colors (quadCount*4 i32), indices (quadCount*6 u16)
//   u32 slugBatchCount, then per batch:
//     u32 flushOrdinal, u32 quadCount, u32 atlasWidth, u32 atlasHeight,
//     f64 cellHeight, u32 atlasByteLength + raw atlas bytes
//     u32 chunkCount, then per chunk: u32 quadCount + the same four arrays

const int _planFormatVersion = 2;

/// Telemetry: microseconds spent in [decodeStripPlan] (accumulated) - this
/// runs on the consuming (UI) isolate, so it counts toward the residual
/// UI-thread cost of a worker-binned settle.
int decodeStripPlanMicros = 0;

/// Serializes [plan] into one compact buffer (see the layout above).
Uint8List encodeStripPlan(StripPlan plan) {
  final w = _PlanWriter();
  w.u8(_planFormatVersion);
  w.u32(plan.totalFlushPoints);
  w.u32(plan.deviceWidth);
  w.u32(plan.deviceHeight);
  final m = plan.pageToDevice;
  w.f64(m.a);
  w.f64(m.b);
  w.f64(m.c);
  w.f64(m.d);
  w.f64(m.e);
  w.f64(m.f);
  w.f64(plan.tolerance);
  w.u8(plan.slugGlyphs ? 1 : 0);
  w.u32(plan.slugQuadCount);
  w.u32(plan.slugFallbackOutlineRuns);
  w.u32(plan.slugFallbackOrdinals.length);
  for (final ordinal in plan.slugFallbackOrdinals) {
    w.u32(ordinal);
  }
  w.u32(plan.batches.length);
  for (final batch in plan.batches) {
    w.u32(batch.flushOrdinal);
    w.u32(batch.stripCount);
    w.u32(batch.atlasWidth);
    w.u32(batch.atlasHeight);
    w.raw(batch.atlasPixels);
    w.u32(batch.chunks.length);
    for (final chunk in batch.chunks) {
      final quads = chunk.positions.length ~/ 8;
      w.u32(quads);
      w.u32(chunk.alphaBase);
      w.rawView(chunk.positions.buffer, chunk.positions.offsetInBytes,
          chunk.positions.lengthInBytes);
      w.rawView(
          chunk.textureCoordinates.buffer,
          chunk.textureCoordinates.offsetInBytes,
          chunk.textureCoordinates.lengthInBytes);
      w.rawView(chunk.colors.buffer, chunk.colors.offsetInBytes,
          chunk.colors.lengthInBytes);
      w.rawView(chunk.indices.buffer, chunk.indices.offsetInBytes,
          chunk.indices.lengthInBytes);
    }
  }
  w.u32(plan.slugBatches.length);
  for (final batch in plan.slugBatches) {
    w.u32(batch.flushOrdinal);
    w.u32(batch.quadCount);
    w.u32(batch.atlasWidth);
    w.u32(batch.atlasHeight);
    w.f64(batch.cellHeight);
    w.raw(batch.atlasPixels);
    w.u32(batch.chunks.length);
    for (final chunk in batch.chunks) {
      final quads = chunk.positions.length ~/ 8;
      w.u32(quads);
      w.rawView(chunk.positions.buffer, chunk.positions.offsetInBytes,
          chunk.positions.lengthInBytes);
      w.rawView(
          chunk.textureCoordinates.buffer,
          chunk.textureCoordinates.offsetInBytes,
          chunk.textureCoordinates.lengthInBytes);
      w.rawView(chunk.colors.buffer, chunk.colors.offsetInBytes,
          chunk.colors.lengthInBytes);
      w.rawView(chunk.indices.buffer, chunk.indices.offsetInBytes,
          chunk.indices.lengthInBytes);
    }
  }
  return w.takeBytes();
}

/// Decodes a buffer produced by [encodeStripPlan]. Throws on a version or
/// structure mismatch (producer and consumer ship together; a mismatch is
/// a programming error, and callers treat any throw as "no plan").
StripPlan decodeStripPlan(Uint8List bytes) {
  final sw = Stopwatch()..start();
  final r = _PlanReader(bytes);
  final version = r.u8();
  if (version != _planFormatVersion) {
    throw StateError('strip plan version $version != $_planFormatVersion');
  }
  final totalFlushPoints = r.u32();
  final deviceWidth = r.u32();
  final deviceHeight = r.u32();
  final matrix =
      PdfMatrix(r.f64(), r.f64(), r.f64(), r.f64(), r.f64(), r.f64());
  final tolerance = r.f64();
  final slugGlyphs = r.u8() != 0;
  final slugQuadCount = r.u32();
  final slugFallbackOutlineRuns = r.u32();
  final slugFallbackOrdinalCount = r.u32();
  final slugFallbackOrdinals = <int>[
    for (var i = 0; i < slugFallbackOrdinalCount; i++) r.u32(),
  ];
  final batchCount = r.u32();
  final batches = <StripBatchData>[];
  for (var i = 0; i < batchCount; i++) {
    final flushOrdinal = r.u32();
    final stripCount = r.u32();
    final atlasWidth = r.u32();
    final atlasHeight = r.u32();
    final atlasPixels = r.rawBytes();
    final chunkCount = r.u32();
    final chunks = <StripChunkData>[];
    for (var c = 0; c < chunkCount; c++) {
      final quads = r.u32();
      chunks.add(StripChunkData(
        r.u32(),
        r.f32List(quads * 8),
        r.f32List(quads * 8),
        r.i32List(quads * 4),
        r.u16List(quads * 6),
      ));
    }
    batches.add(StripBatchData.raw(flushOrdinal, chunks, atlasPixels,
        atlasWidth, atlasHeight, stripCount));
  }
  final slugBatchCount = r.u32();
  final slugBatches = <SlugBatchData>[];
  for (var i = 0; i < slugBatchCount; i++) {
    final flushOrdinal = r.u32();
    final quadCount = r.u32();
    final atlasWidth = r.u32();
    final atlasHeight = r.u32();
    final cellHeight = r.f64();
    final atlasPixels = r.rawBytes();
    final chunkCount = r.u32();
    final chunks = <SlugChunkData>[];
    for (var c = 0; c < chunkCount; c++) {
      final quads = r.u32();
      chunks.add(SlugChunkData(
        r.f32List(quads * 8),
        r.f32List(quads * 8),
        r.i32List(quads * 4),
        r.u16List(quads * 6),
      ));
    }
    slugBatches.add(SlugBatchData(flushOrdinal, chunks, atlasPixels, atlasWidth,
        atlasHeight, quadCount, cellHeight));
  }
  final plan = StripPlan(
    totalFlushPoints: totalFlushPoints,
    deviceWidth: deviceWidth,
    deviceHeight: deviceHeight,
    pageToDevice: matrix,
    tolerance: tolerance,
    batches: batches,
    slugGlyphs: slugGlyphs,
    slugBatches: slugBatches,
    slugQuadCount: slugQuadCount,
    slugFallbackOutlineRuns: slugFallbackOutlineRuns,
    slugFallbackOrdinals: slugFallbackOrdinals,
  );
  decodeStripPlanMicros += sw.elapsedMicroseconds;
  return plan;
}

class _PlanWriter {
  Uint8List _buf = Uint8List(1 << 16);
  late ByteData _view = ByteData.view(_buf.buffer);
  int _len = 0;

  void _ensure(int extra) {
    final need = _len + extra;
    if (need <= _buf.length) return;
    var cap = _buf.length * 2;
    while (cap < need) {
      cap *= 2;
    }
    final grown = Uint8List(cap)..setRange(0, _len, _buf);
    _buf = grown;
    _view = ByteData.view(grown.buffer);
  }

  void u8(int v) {
    _ensure(1);
    _buf[_len++] = v & 0xff;
  }

  void u32(int v) {
    _ensure(4);
    _view.setUint32(_len, v);
    _len += 4;
  }

  void f64(double v) {
    _ensure(8);
    _view.setFloat64(_len, v);
    _len += 8;
  }

  /// A length-prefixed raw byte run.
  void raw(Uint8List xs) {
    u32(xs.length);
    _ensure(xs.length);
    _buf.setRange(_len, _len + xs.length, xs);
    _len += xs.length;
  }

  /// Raw bytes of a typed-data view, unprefixed (the element count travels
  /// separately).
  void rawView(ByteBuffer buffer, int offsetInBytes, int lengthInBytes) {
    _ensure(lengthInBytes);
    _buf.setRange(_len, _len + lengthInBytes,
        Uint8List.view(buffer, offsetInBytes, lengthInBytes));
    _len += lengthInBytes;
  }

  Uint8List takeBytes() =>
      Uint8List.fromList(Uint8List.sublistView(_buf, 0, _len));
}

class _PlanReader {
  _PlanReader(this._bytes) : _data = ByteData.sublistView(_bytes);

  final Uint8List _bytes;
  final ByteData _data;
  int _o = 0;

  int u8() => _data.getUint8(_o++);

  int u32() {
    final v = _data.getUint32(_o);
    _o += 4;
    return v;
  }

  double f64() {
    final v = _data.getFloat64(_o);
    _o += 8;
    return v;
  }

  Uint8List rawBytes() {
    final n = u32();
    final out = Uint8List.fromList(Uint8List.sublistView(_bytes, _o, _o + n));
    _o += n;
    return out;
  }

  // The bulk reads copy into freshly-allocated (aligned) typed arrays; a
  // view over the transferred buffer could be misaligned and would pin the
  // whole buffer alive.
  Float32List f32List(int n) {
    final out = Float32List(n);
    out.buffer
        .asUint8List()
        .setRange(0, n * 4, Uint8List.sublistView(_bytes, _o, _o + n * 4));
    _o += n * 4;
    return out;
  }

  Int32List i32List(int n) {
    final out = Int32List(n);
    out.buffer
        .asUint8List()
        .setRange(0, n * 4, Uint8List.sublistView(_bytes, _o, _o + n * 4));
    _o += n * 4;
    return out;
  }

  Uint16List u16List(int n) {
    final out = Uint16List(n);
    out.buffer
        .asUint8List()
        .setRange(0, n * 2, Uint8List.sublistView(_bytes, _o, _o + n * 2));
    _o += n * 2;
    return out;
  }
}
