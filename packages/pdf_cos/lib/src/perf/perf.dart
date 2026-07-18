/// Zero-overhead performance instrumentation core, shared by every layer of
/// the workspace (`pdf_cos` is the root dependency, so `pdf_document`,
/// `pdf_graphics`, and `dart_pdf_editor` can all import it).
///
/// UNSTABLE diagnostics surface: this library is exported through
/// `package:pdf_cos/perf.dart` (deliberately *not* through
/// `package:pdf_cos/pdf_cos.dart`) and carries **no semver guarantee** -
/// phases, counters, and shapes change whenever the instrumentation needs to.
///
/// Cost contract, in order of strictness:
///
///  * `--dart-define=PDF_PERF=false` folds [kPdfPerfCompiledIn] to a
///    compile-time `false`; every guarded body becomes unreachable and both
///    dart2js and AOT tree-shake the whole facade out of the build
///    (`tool/check_perf_dce.sh` verifies this against compiled JS).
///  * Compiled in but disabled (the default): every entry point is a single
///    const-load + bool-load + branch. No allocation, no clock reads - the
///    [Stopwatch] and accumulator lists are created only inside
///    `enabled = true` ([PdfPerf.debugInitialized] proves it in tests).
///  * Enabled: recording stays allocation-free - phases and counters are
///    enum-indexed `List<int>` bumps; strings are built only at report time
///    ([PdfPerfStats.toJson]/[PdfPerfStats.format]) or for rare [event]s.
///
/// Statics are **isolate-local**: a render-worker isolate has its own
/// [PdfPerf] that must be enabled (and snapshotted) over the worker protocol.
///
/// Instrumentation convention for `lib/` code: never allocate a [Stopwatch]
/// or read a clock at a call site - always
/// `final t0 = PdfPerf.begin(); ... PdfPerf.end(phase, t0);`.
library;

/// Compile-time kill switch. Defaults to compiled-in; build with
/// `--dart-define=PDF_PERF=false` to dead-code-eliminate the entire facade.
const bool kPdfPerfCompiledIn =
    bool.fromEnvironment('PDF_PERF', defaultValue: true);

/// Timed phases. Enum-indexed so recording is string-free and alloc-free.
///
/// A phase accumulates *inclusive* wall time across all its begin/end pairs;
/// nested phases (e.g. [flate] inside [docOpen]) each count their own time,
/// so phase sums can exceed end-to-end wall time. Compare a phase with
/// itself across runs, not phases against each other as a partition.
enum PdfPerfPhase {
  /// [CosDocument.open] end to end (header scan, xref, encryption init,
  /// /Root resolve; includes [xrefRecovery] when the fallback runs).
  docOpen,

  /// Parsing the cross-reference chain (tables + streams + /Prev walk).
  xrefParse,

  /// The full-file `N G obj` recovery scan when the xref chain is broken.
  xrefRecovery,

  /// Locating + decoding + indexing an object stream (/Type /ObjStm).
  objectStreamIndex,

  /// Decrypting stream payloads (RC4/AES) inside decodeStreamData.
  streamDecrypt,

  // Per-filter decode phases (one per PDF stream filter family).
  flate,
  lzw,
  ccitt,
  jbig2,
  jpx,
  dct,
  runLength,
  asciiFilter,

  /// Content-stream tokenization (ContentStreamParser).
  contentTokenize,

  /// Incremental save (CosIncrementalUpdater.save), including xref append.
  saveIncremental,

  /// From-scratch serialization (CosDocumentBuilder.build).
  saveFull,

  /// Re-encrypting the changed-object graph on save.
  encryptGraph,

  /// Page-tree leaf walk (pdf_document).
  pageTreeWalk,

  /// Font-program parsing (TrueType/CFF/Type1) in pdf_graphics.
  fontParse,

  /// Text extraction over a page (pdf_graphics).
  textExtract,

  /// ByteRange patching during signing (pdf_document).
  byteRangePatch,

  /// Fetching bytes from a ranged/lazy byte source.
  sourceFetch,
}

/// Monotonic counters: structural facts and byte volumes that drive
/// performance, cheap enough to bump on the hottest paths.
enum PdfPerfCount {
  /// Documents that fell back to the xref recovery scan.
  xrefRecovered,

  /// Objects rescued via the scanned-header fallback (xref offset pointed
  /// at the wrong object).
  xrefOffsetRescue,

  /// Indirect objects parsed from bytes (cache misses in getObject).
  objectsLoaded,

  /// Object streams (/ObjStm) located and decoded.
  objectStreamsLoaded,

  /// Streams run through the decode-filter chain.
  streamsDecoded,

  // Decoded output bytes per filter family.
  bytesDecodedFlate,
  bytesDecodedCcitt,
  bytesDecodedJbig2,
  bytesDecodedJpx,
  bytesDecodedDct,
  bytesDecodedOther,

  /// Content-stream operators executed by the tokenizer's consumers.
  contentOps,

  /// Content-stream bytes tokenized.
  contentBytes,

  /// Font programs parsed / failed to parse.
  fontsParsed,
  fontParseFailed,

  /// Style-matched fallback fonts embedded by replaceText.
  fallbackFontEmbedded,

  /// Bytes / redefined objects written by a save.
  savedBytes,
  savedObjects,

  /// Ranged byte-source traffic.
  rangeRequests,
  rangeBytesFetched,
  fullDownloadFallback,
}

/// Rare structural events worth a [PdfPerf.sink] line, not just a counter.
enum PdfPerfEvent {
  /// The xref chain was broken and the recovery scan rebuilt it.
  xrefRecoveryTriggered,

  /// The `N G obj` header scan was built to rescue a wrong xref offset.
  objectRescueScanBuilt,

  /// A ranged source gave up and downloaded the whole file.
  rangedSourceFellBack,
}

/// The shared perf facade. All members are static; see the library docs for
/// the cost contract.
abstract final class PdfPerf {
  static bool _enabled = false;

  // All mutable state lives behind [enabled]'s lazy init so the disabled
  // path provably allocates nothing (see [debugInitialized]).
  static Stopwatch? _clock;
  static List<int>? _phaseUs;
  static List<int>? _phaseCalls;
  static List<int>? _counts;
  static List<int>? _events;

  /// Marker literal referenced only from guarded code paths;
  /// `tool/check_perf_dce.sh` greps compiled JS for it to prove that
  /// `--dart-define=PDF_PERF=false` eliminated the facade.
  static const String debugDceMarker = 'PdfPerf:compiled-in';

  /// Optional line sink for [event]s and lifecycle lines. Null (the
  /// default) drops them. The Flutter layer points this at PdfPerfLog;
  /// harnesses point it at their collectors.
  static void Function(String line)? sink;

  /// Whether recording is active. The setter lazily allocates the clock and
  /// accumulators on first enable; disabling stops recording but keeps
  /// accumulated data for [snapshot].
  static bool get enabled => kPdfPerfCompiledIn && _enabled;

  static set enabled(bool value) {
    if (!kPdfPerfCompiledIn) return;
    if (value && _phaseUs == null) {
      _clock = Stopwatch()..start();
      _phaseUs = List<int>.filled(PdfPerfPhase.values.length, 0);
      _phaseCalls = List<int>.filled(PdfPerfPhase.values.length, 0);
      _counts = List<int>.filled(PdfPerfCount.values.length, 0);
      _events = List<int>.filled(PdfPerfEvent.values.length, 0);
      sink?.call('$debugDceMarker recording on');
    }
    _enabled = value;
  }

  /// True once `enabled = true` has allocated recording state. Stays false
  /// across a fully disabled workload - the zero-allocation contract's
  /// test hook.
  static bool get debugInitialized => _phaseUs != null;

  /// Timestamp in microseconds, or 0 when disabled. Pair with [end].
  @pragma('vm:prefer-inline')
  @pragma('dart2js:tryInline')
  static int begin() {
    if (!kPdfPerfCompiledIn || !_enabled) return 0;
    return _clock!.elapsedMicroseconds;
  }

  /// Accumulates the time since [begin]'s [t0] into [phase].
  @pragma('vm:prefer-inline')
  @pragma('dart2js:tryInline')
  static void end(PdfPerfPhase phase, int t0) {
    if (!kPdfPerfCompiledIn || !_enabled) return;
    _phaseUs![phase.index] += _clock!.elapsedMicroseconds - t0;
    _phaseCalls![phase.index]++;
  }

  /// Bumps [count] by [n].
  @pragma('vm:prefer-inline')
  @pragma('dart2js:tryInline')
  static void add(PdfPerfCount count, [int n = 1]) {
    if (!kPdfPerfCompiledIn || !_enabled) return;
    _counts![count.index] += n;
  }

  /// Records a rare structural [event]; [detail] reaches [sink] verbatim.
  static void event(PdfPerfEvent event, [String detail = '']) {
    if (!kPdfPerfCompiledIn || !_enabled) return;
    _events![event.index]++;
    final s = sink;
    if (s != null) {
      s('perf event ${event.name}${detail.isEmpty ? '' : ' $detail'}');
    }
  }

  /// An immutable copy of everything recorded so far. Empty stats when
  /// recording was never enabled.
  static PdfPerfStats snapshot() {
    final phaseUs = _phaseUs;
    if (!kPdfPerfCompiledIn || phaseUs == null) return PdfPerfStats.empty();
    return PdfPerfStats._(
      List<int>.of(phaseUs),
      List<int>.of(_phaseCalls!),
      List<int>.of(_counts!),
      List<int>.of(_events!),
    );
  }

  /// Zeroes the accumulators (keeps [enabled] as-is). Corpus sweeps call
  /// this between files.
  static void reset() {
    if (!kPdfPerfCompiledIn || _phaseUs == null) return;
    _phaseUs!.fillRange(0, _phaseUs!.length, 0);
    _phaseCalls!.fillRange(0, _phaseCalls!.length, 0);
    _counts!.fillRange(0, _counts!.length, 0);
    _events!.fillRange(0, _events!.length, 0);
  }
}

/// An immutable snapshot of [PdfPerf] accumulators.
class PdfPerfStats {
  PdfPerfStats._(this.phaseUs, this.phaseCalls, this.counts, this.events);

  /// All-zero stats (what [PdfPerf.snapshot] returns before first enable).
  factory PdfPerfStats.empty() => PdfPerfStats._(
        List<int>.filled(PdfPerfPhase.values.length, 0),
        List<int>.filled(PdfPerfPhase.values.length, 0),
        List<int>.filled(PdfPerfCount.values.length, 0),
        List<int>.filled(PdfPerfEvent.values.length, 0),
      );

  /// Rebuilds a snapshot from [toJson] output (missing/unknown names are
  /// tolerated so snapshots survive enum evolution across isolates).
  factory PdfPerfStats.fromJson(Map<String, Object?> json) {
    final stats = PdfPerfStats.empty();
    void read(String key, List<String> names, List<int> into,
        [List<int>? callsInto]) {
      final section = json[key];
      if (section is! Map) return;
      section.forEach((name, value) {
        final index = names.indexOf(name as String);
        if (index < 0) return;
        if (value is int) {
          into[index] = value;
        } else if (value is Map) {
          into[index] = (value['us'] as num?)?.toInt() ?? 0;
          callsInto?[index] = (value['calls'] as num?)?.toInt() ?? 0;
        }
      });
    }

    read('phases', PdfPerfPhase.values.map((p) => p.name).toList(),
        stats.phaseUs, stats.phaseCalls);
    read('counts', PdfPerfCount.values.map((c) => c.name).toList(),
        stats.counts);
    read('events', PdfPerfEvent.values.map((e) => e.name).toList(),
        stats.events);
    return stats;
  }

  /// Accumulated microseconds per [PdfPerfPhase.index].
  final List<int> phaseUs;

  /// begin/end pair count per [PdfPerfPhase.index].
  final List<int> phaseCalls;

  /// Value per [PdfPerfCount.index].
  final List<int> counts;

  /// Occurrences per [PdfPerfEvent.index].
  final List<int> events;

  int phaseTotalUs(PdfPerfPhase phase) => phaseUs[phase.index];

  int phaseCallCount(PdfPerfPhase phase) => phaseCalls[phase.index];

  int count(PdfPerfCount c) => counts[c.index];

  int eventCount(PdfPerfEvent e) => events[e.index];

  /// True when nothing was recorded.
  bool get isEmpty =>
      !phaseCalls.any((v) => v != 0) &&
      !counts.any((v) => v != 0) &&
      !events.any((v) => v != 0);

  /// Sums this snapshot into [accumulator] (corpus-sweep aggregation).
  void addInto(PdfPerfStats accumulator) {
    for (var i = 0; i < phaseUs.length; i++) {
      accumulator.phaseUs[i] += phaseUs[i];
      accumulator.phaseCalls[i] += phaseCalls[i];
    }
    for (var i = 0; i < counts.length; i++) {
      accumulator.counts[i] += counts[i];
    }
    for (var i = 0; i < events.length; i++) {
      accumulator.events[i] += events[i];
    }
  }

  /// JSON shape: zero entries are omitted so sweep output stays compact.
  Map<String, Object> toJson() => {
        'phases': {
          for (final p in PdfPerfPhase.values)
            if (phaseCalls[p.index] != 0)
              p.name: {'us': phaseUs[p.index], 'calls': phaseCalls[p.index]},
        },
        'counts': {
          for (final c in PdfPerfCount.values)
            if (counts[c.index] != 0) c.name: counts[c.index],
        },
        'events': {
          for (final e in PdfPerfEvent.values)
            if (events[e.index] != 0) e.name: events[e.index],
        },
      };

  /// Human-readable multi-line summary (report-time only).
  String format() {
    final lines = <String>[];
    for (final p in PdfPerfPhase.values) {
      final calls = phaseCalls[p.index];
      if (calls == 0) continue;
      final ms = (phaseUs[p.index] / 1000).toStringAsFixed(1);
      lines.add('  ${p.name}: ${ms}ms over $calls call(s)');
    }
    for (final c in PdfPerfCount.values) {
      if (counts[c.index] != 0) lines.add('  ${c.name}: ${counts[c.index]}');
    }
    for (final e in PdfPerfEvent.values) {
      if (events[e.index] != 0) lines.add('  ${e.name}: ${events[e.index]}');
    }
    return lines.isEmpty ? 'PdfPerfStats(empty)' : 'PdfPerfStats:\n${lines.join('\n')}';
  }
}

/// Coarse upper-bound tripwires over a [PdfPerfStats] snapshot - same
/// philosophy as the render path's PdfRenderPhaseBudget: bounds are set with
/// generous headroom so only an order-of-magnitude regression (or a
/// structural fault like an unexpected recovery scan) trips them.
class PdfPerfBudget {
  const PdfPerfBudget({this.maxPhaseUs = const {}, this.maxCounts = const {}});

  /// Upper bound in microseconds per phase.
  final Map<PdfPerfPhase, int> maxPhaseUs;

  /// Upper bound per counter (e.g. `xrefRecovered: 0` asserts a well-formed
  /// fixture never falls back to recovery).
  final Map<PdfPerfCount, int> maxCounts;

  /// Human-readable violations; empty means within budget.
  List<String> exceedances(PdfPerfStats stats) {
    final out = <String>[];
    maxPhaseUs.forEach((phase, maxUs) {
      final us = stats.phaseTotalUs(phase);
      if (us > maxUs) {
        out.add('${phase.name}: ${us}us exceeds budget ${maxUs}us');
      }
    });
    maxCounts.forEach((count, max) {
      final value = stats.count(count);
      if (value > max) {
        out.add('${count.name}: $value exceeds budget $max');
      }
    });
    return out;
  }
}
