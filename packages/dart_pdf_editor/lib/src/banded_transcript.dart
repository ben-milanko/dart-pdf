/// X-strip band decomposition of a retained [PdfRenderCommand] transcript.
///
/// On a single flat-content-stream page the retained transcript is an
/// irreducible memory floor: ~60-100 MB on the 8504x842 CAD sheet that
/// [PdfRegionReplayIndex]'s spatial cull (#383) still keeps whole. Because such
/// pages are extreme-aspect and panning is horizontal, partitioning the page
/// into N vertical strips along the pan (X) axis and retaining only the strips
/// overlapping the viewport bounds the retained transcript to roughly
/// `visible strips / total`, at the cost of re-interpreting a strip when the
/// viewport pans back into a dropped one.
///
/// This is the retention/eviction engine. It sits on top of the same supported
/// subset [PdfRegionReplayIndex] guarantees (balanced save/restore, nestable
/// clips, no transparency/soft-mask group split), so every retained unit is an
/// independently replayable paint plus a persistent snapshot of the clips and
/// blend mode active at that point. A unit whose bounds span several bands is
/// retained by each (its shared command object, not a copy), so evicting the
/// others never drops a paint the survivor still needs; replay dedupes such a
/// unit back to a single draw in painter order.
library;

import 'package:flutter/painting.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';

import 'region_replay_index.dart';

class PdfBandedTranscript {
  PdfBandedTranscript._({
    required this.bands,
    required this.xMin,
    required this.xMax,
    required int perUnitBytes,
    required int clipNodeCount,
  })  : _perUnitBytes = perUnitBytes,
        _clipNodeCount = clipNodeCount;

  /// The fixed-count strips, low X to high X. Never resized; a strip is
  /// evicted by nulling its retained units, not by dropping the strip.
  final List<PdfTranscriptBand> bands;

  /// Page-space X span the strips partition (the drawable extent, [xMin]
  /// inclusive to [xMax] on the last strip).
  final double xMin;
  final double xMax;

  final int _perUnitBytes;
  final int _clipNodeCount;

  /// Partitions [commands] into [bandCount] equal-width X strips. Returns null
  /// when the transcript is outside the region-index's supported subset (a
  /// transparency/soft-mask group spans it, or state is unbalanced) - such a
  /// page stays on the whole-transcript path, exactly as region replay does.
  ///
  /// Pass a prebuilt [index] to avoid re-walking a transcript already indexed
  /// by the owning scene; it must have been built from the same [commands].
  static PdfBandedTranscript? build(
    List<PdfRenderCommand> commands, {
    required int bandCount,
    PdfRegionReplayIndex? index,
  }) {
    if (bandCount < 1) return null;
    final idx = index ??
        PdfRegionReplayIndex.build(commands, maxCommands: commands.length);
    if (!idx.supported) return null;

    final extent = idx.xExtent;
    // A page with no drawable units (blank, or everything clipped away) still
    // yields a valid, empty banded transcript so callers need not special-case.
    final xMin = extent?.$1 ?? 0.0;
    final xMax = extent?.$2 ?? 0.0;
    final span = xMax - xMin;
    final bandWidth = span <= 0 ? 0.0 : span / bandCount;

    final buckets = List.generate(bandCount, (_) => <_BandUnit>[]);
    for (final unit in idx.units) {
      final retained = _BandUnit(
        order: unit.commandIndex,
        command: commands[unit.commandIndex],
        bounds: unit.bounds,
        clips: unit.clips,
        blendMode: unit.blendMode,
      );
      final first = _bandOf(unit.bounds.left, xMin, bandWidth, bandCount);
      final last = _bandOf(unit.bounds.right, xMin, bandWidth, bandCount);
      // Units are visited in painter (command) order, so appending keeps each
      // strip's own list sorted; the shared unit lands at the same relative
      // position in every strip it spans.
      for (var band = first; band <= last; band++) {
        buckets[band].add(retained);
      }
    }

    final bands = <PdfTranscriptBand>[
      for (var i = 0; i < bandCount; i++)
        PdfTranscriptBand._(
          index: i,
          xStart: span <= 0 ? xMin : xMin + i * bandWidth,
          xEnd: span <= 0 ? xMax : xMin + (i + 1) * bandWidth,
          units: buckets[i],
        ),
    ];
    return PdfBandedTranscript._(
      bands: bands,
      xMin: xMin,
      xMax: xMax,
      perUnitBytes: 48,
      clipNodeCount: idx.clipNodeCount,
    );
  }

  static int _bandOf(double x, double xMin, double bandWidth, int bandCount) {
    if (bandWidth <= 0) return 0;
    var band = ((x - xMin) / bandWidth).floor();
    if (band < 0) band = 0;
    if (band >= bandCount) band = bandCount - 1;
    return band;
  }

  int get bandCount => bands.length;

  /// Strips whose units are currently retained.
  int get residentBandCount => bands.where((b) => b.resident).length;

  /// Retained-transcript estimate for the resident strips only. A unit shared
  /// across strips is counted once (identity-deduped), so this tracks the
  /// distinct paints actually held, not the summed strip lengths. The clip
  /// snapshot chain is charged whole while any strip is resident and released
  /// only when every strip is evicted - it is a shared spine, not per-strip.
  int get estimatedResidentBytes {
    // Dedupe by painter order, not object identity: a strip-spanning paint is
    // one command however many strips hold it, and after a restore the resident
    // and rebuilt strips carry distinct instances of the same paint.
    final seen = <int>{};
    for (final band in bands) {
      final units = band._units;
      if (units == null) continue;
      for (final unit in units) {
        seen.add(unit.order);
      }
    }
    if (seen.isEmpty) return 0;
    return seen.length * _perUnitBytes + _clipNodeCount * 40;
  }

  /// Retained-transcript estimate had no strip been evicted - the whole-page
  /// floor this decomposition trades against.
  int get estimatedFullBytes {
    final seen = <int>{};
    for (final band in bands) {
      for (final unit in band._retained) {
        seen.add(unit.order);
      }
    }
    if (seen.isEmpty) return 0;
    return seen.length * _perUnitBytes + _clipNodeCount * 40;
  }

  /// Strips overlapping [region]'s X span whose units have been evicted - the
  /// ones a caller must re-materialize (via [restore]) before [replayRegion]
  /// can paint [region] completely. Empty means the region is fully resident.
  List<int> missingBandsForRegion(PdfRect region) {
    final missing = <int>[];
    for (final band in bands) {
      if (band.resident || band.unitCount == 0) continue;
      if (band._overlapsX(region)) missing.add(band.index);
    }
    return missing;
  }

  /// Drops strip [index]'s retained units, freeing its exclusive paints. Units
  /// it shares with a still-resident strip stay alive through that strip. The
  /// strip's geometry and unit count survive as metadata for later [restore].
  void evict(int index) => bands[index]._evict();

  /// Evicts every strip that does not overlap [keep]'s X span - the
  /// memory-pressure and pan-driven eviction the viewport drives.
  int evictOutside(PdfRect keep) {
    var evicted = 0;
    for (final band in bands) {
      if (band.resident && !band._overlapsX(keep)) {
        band._evict();
        evicted++;
      }
    }
    return evicted;
  }

  /// Evicts every resident strip.
  void evictAll() {
    for (final band in bands) {
      band._evict();
    }
  }

  /// Re-materializes any evicted strips from a freshly recorded [commands]
  /// buffer for the same page/plan (deterministic, so the rebuilt strips are
  /// identical). Resident strips are left untouched. Returns the strips
  /// restored. The caller pays one whole-page interpret to produce [commands];
  /// this only re-partitions it, which is why re-materialization latency is
  /// dominated by the record, not this call.
  List<int> restore(
    List<PdfRenderCommand> commands, {
    PdfRegionReplayIndex? index,
  }) {
    final restored = <int>[];
    if (bands.every((b) => b.resident)) return restored;
    final rebuilt = build(commands, bandCount: bands.length, index: index);
    if (rebuilt == null) return restored;
    for (var i = 0; i < bands.length; i++) {
      if (bands[i].resident) continue;
      bands[i]._units = rebuilt.bands[i]._retained;
      restored.add(i);
    }
    return restored;
  }

  /// Replays every retained unit overlapping [region] (page space), in painter
  /// order, deduping a strip-spanning unit back to a single draw. Mirrors
  /// [PdfRegionReplayIndex.replay]: each unit restores its clip and blend
  /// snapshot around one command. Units in evicted strips overlapping [region]
  /// are silently skipped - call [missingBandsForRegion] first and [restore]
  /// if a complete paint is required. Returns the number of units drawn.
  int replayRegion(
    PdfRect region,
    PdfDevice device,
    Canvas canvas,
  ) {
    // A strip-spanning unit appears in each overlapped strip; key by painter
    // order to keep exactly one, then replay in that order.
    final picked = <int, _BandUnit>{};
    for (final band in bands) {
      if (!band._overlapsX(region)) continue;
      final units = band._units;
      if (units == null) continue;
      for (final unit in units) {
        if (!pdfRenderRectsIntersect(unit.bounds, region)) continue;
        picked[unit.order] = unit;
      }
    }
    if (picked.isEmpty) return 0;
    final orders = picked.keys.toList()..sort();
    final scratch = <PdfRenderCommand>[picked[orders.first]!.command];
    var replayed = 0;
    for (final order in orders) {
      final unit = picked[order]!;
      canvas.save();
      device.setBlendMode(unit.blendMode);
      unit.clips?.replay(device);
      scratch[0] = unit.command;
      replayCommands(scratch, device);
      canvas.restore();
      replayed++;
    }
    return replayed;
  }
}

/// One X strip: its page-space X range and the paints it retains (null once
/// evicted; [unitCount] survives eviction as metadata).
class PdfTranscriptBand {
  PdfTranscriptBand._({
    required this.index,
    required this.xStart,
    required this.xEnd,
    required List<_BandUnit> units,
  })  : _units = units,
        unitCount = units.length;

  final int index;
  final double xStart;
  final double xEnd;

  /// The paint count this strip carries, stable across eviction/restore.
  final int unitCount;

  List<_BandUnit>? _units;

  bool get resident => _units != null;

  List<_BandUnit> get _retained =>
      _units ?? (throw StateError('band $index is evicted'));

  void _evict() => _units = null;

  bool _overlapsX(PdfRect region) =>
      xEnd >= region.left && xStart <= region.right;
}

/// A retained paint: the command plus the clip/blend state to replay it in
/// isolation, and its painter order (dedupe/sort key for strip-spanning units).
class _BandUnit {
  _BandUnit({
    required this.order,
    required this.command,
    required this.bounds,
    required this.clips,
    required this.blendMode,
  });

  final int order;
  final PdfRenderCommand command;
  final PdfRect bounds;
  final PdfRegionClipState? clips;
  final PdfBlendMode blendMode;
}
