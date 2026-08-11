import 'dart:typed_data';

import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';

import 'budgeted_cache.dart';
import 'render_trace.dart';

// The worker fills its half of the unified [PdfRenderTrace]; re-exported so
// callers importing this file keep seeing [PdfWorkerPhaseTimings] (now an alias
// of that record).
export 'render_trace.dart' show PdfRenderTrace, PdfWorkerPhaseTimings;

/// One immutable, document-backed page interpretation retained by a render
/// worker. [sourceCommands] keep image COS objects for later decode variants;
/// [wireCommands] carry the float32 geometry used by strip planning.
class PdfWorkerTranscript {
  PdfWorkerTranscript(this.sourceCommands, this.wireCommands)
      : retainedCommandWeight =
            retainedCommandGraphsWeight(sourceCommands, wireCommands);

  final List<PdfRenderCommand> sourceCommands;
  final List<PdfRenderCommand> wireCommands;

  /// Command slots retained by this transcript, including commands nested
  /// inside soft-mask groups and both lists when they are distinct.
  final int retainedCommandWeight;
}

/// Counts commands in a retained graph, including nested soft-mask commands.
///
/// This is intentionally a command-slot weight rather than a byte estimate:
/// command shapes vary, but the count is stable, cheap, and catches the dense
/// lists whose references and object graphs dominate worker heap and GC.
int retainedCommandGraphWeight(List<PdfRenderCommand> commands) {
  var count = 0;
  for (final command in commands) {
    count++;
    if (command is PdfEndSoftMaskedCommand) {
      count += retainedCommandGraphWeight(command.maskCommands);
    } else if (command is PdfDrawTiledCellCommand) {
      // The nested cell is retained once regardless of tile count.
      count += retainedCommandGraphWeight(command.cellCommands);
    }
  }
  return count;
}

/// Counts retained command slots across two transcript views.
int retainedCommandGraphsWeight(
  List<PdfRenderCommand> first,
  List<PdfRenderCommand> second,
) =>
    retainedCommandGraphWeight(first) +
    (identical(first, second) ? 0 : retainedCommandGraphWeight(second));

/// Reuses the compact wire graph while restoring document-backed images.
///
/// The wire codec rounds geometry to the exact float32 values consumed by the
/// UI and removes redundant state scopes. Its reconstructed indirect images
/// carry compact object references but use placeholder streams; later detail
/// decoding still needs the worker document's actual COS stream. Replace only
/// those streams while sharing every other command object and retaining the
/// wire transform.
List<PdfRenderCommand>? compactTranscriptSourceCommands(
  List<PdfRenderCommand> wireCommands,
  List<PdfImageRequest> originalImages,
) {
  if (originalImages.isEmpty) return wireCommands;
  var imageIndex = 0;

  List<PdfRenderCommand> patch(List<PdfRenderCommand> commands) {
    List<PdfRenderCommand>? changed;
    for (var i = 0; i < commands.length; i++) {
      final command = commands[i];
      PdfRenderCommand replacement = command;
      if (command is PdfDrawImageCommand) {
        if (imageIndex >= originalImages.length) {
          throw StateError('wire transcript has more images than its source');
        }
        final original = originalImages[imageIndex++];
        final wire = command.request;
        replacement = PdfDrawImageCommand(PdfImageRequest(
          stream: original.stream,
          transform: wire.transform,
          alpha: wire.alpha,
          isStencil: wire.isStencil,
          stencilColor: wire.stencilColor,
          isInline: original.isInline,
          decoded: original.decoded,
          sourceReference: original.sourceReference,
        ));
      } else if (command is PdfEndSoftMaskedCommand) {
        final maskCommands = patch(command.maskCommands);
        if (!identical(maskCommands, command.maskCommands)) {
          replacement = PdfEndSoftMaskedCommand(
            luminosity: command.luminosity,
            backdrop: command.backdrop,
            maskCommands: maskCommands,
            backdropLuminance: command.backdropLuminance,
            transferScale: command.transferScale,
            transferOffset: command.transferOffset,
          );
        }
      } else if (command is PdfDrawTiledCellCommand) {
        // Cell images are serialized once (depth-first), matching the
        // recorder's imageRequests order - patch them once here too.
        final cellCommands = patch(command.cellCommands);
        if (!identical(cellCommands, command.cellCommands)) {
          replacement = PdfDrawTiledCellCommand(
              cellCommands, command.originsX, command.originsY);
        }
      }
      if (!identical(replacement, command)) {
        changed ??= List<PdfRenderCommand>.of(commands);
        changed[i] = replacement;
      }
    }
    return changed == null
        ? commands
        : List<PdfRenderCommand>.unmodifiable(changed);
  }

  try {
    final patched = patch(wireCommands);
    return imageIndex == originalImages.length ? patched : null;
  } on StateError {
    return null;
  }
}

/// Bounded per-worker LRU of page command transcripts.
///
/// A worker owns one immutable document revision, so `(page, annotations)` is
/// also the revision-safe identity. A replacement worker starts with an empty
/// cache. Both entry count and retained command weight are bounded; one
/// oversize hot entry is always kept so a dense page still benefits from reuse.
/// Operations per [PdfPageContentWalk.advance] chunk on the resumable record
/// path (#530, mirrors the isolate worker's constant of the same value). Bounds
/// the post-cancel overshoot before the walk suspends; the walk still yields
/// internally so the worker keeps servicing the cancel message within a chunk.
// A dense CAD operation is tiny (usually one path coordinate append). At 4096
// operations a 670k-op page crossed the worker event loop ~165 times; browser
// task handoffs became a material part of its wall time. 64k cuts that to about
// 11 turns while keeping the measured worst chunk near 50ms on the CAD corpus.
const int _resumeRecordChunkOperations = 65536;

// Progressive visible-page records start with one small chunk so medium-dense
// pages expose useful ink before a 64k throughput chunk finishes the walk.
// Non-streaming records and every later chunk retain the measured 64k policy.
const int _initialProgressiveRecordChunkOperations = 4096;

/// A page transcript record cancelled mid-walk, held so the next
/// [PdfWorkerTranscriptCache.transcriptFor] of the same page resumes it instead
/// of re-interpreting the prefix (#530). Bundles everything the resumed walk
/// needs: the walk cursor, the interpreter holding the graphics state, the
/// recorder holding the commands so far, and the page for the annotation pass.
class _SuspendedTranscriptWalk {
  _SuspendedTranscriptWalk(this.pageIndex, this.annotations, this.page,
      this.recorder, this.interpreter, this.walk);
  final int pageIndex;
  final bool annotations;
  final PdfPage page;
  final RecordingPdfDevice recorder;
  final PdfInterpreter interpreter;
  final PdfPageContentWalk walk;

  // Progressive-partial schedule (#564), carried across a preempt/resume so the
  // doubling cadence continues rather than restarting: chunks advanced so far
  // and the chunk count at which the next partial is emitted (1, 2, 4, ...).
  int chunksAdvanced = 0;
  int nextEmitAtChunk = 1;
}

class PdfWorkerTranscriptCache {
  PdfWorkerTranscriptCache({
    this.capacity = 4,
    this.maxRetainedCommands = 250000,
    this.deduplicateCommands = true,
    int? resumeChunkOperations,
  })  : assert(capacity > 0),
        assert(maxRetainedCommands > 0),
        assert(resumeChunkOperations == null || resumeChunkOperations > 0),
        _resumeChunk = resumeChunkOperations ?? _resumeRecordChunkOperations;

  final int capacity;
  final int maxRetainedCommands;

  /// Operations per resumable-record chunk. Defaults to
  /// [_resumeRecordChunkOperations]; a small value is a test seam to force a
  /// multi-chunk walk (so a preemption suspends and resumes).
  final int _resumeChunk;

  /// Whether transcripts may share the compact wire graph, patching only its
  /// document-backed image requests. Exposed for A/B benchmarks.
  final bool deduplicateCommands;

  // The shared budgeted LRU, bounded by both entry count ([capacity]) and
  // retained command weight ([maxRetainedCommands]); the weight bound keeps one
  // oversize hot entry (the most-recently-used is never evicted) so a dense
  // page still benefits from reuse.
  late final PdfBudgetedCache<(int, bool), PdfWorkerTranscript> _entries =
      PdfBudgetedCache<(int, bool), PdfWorkerTranscript>(
    weigher: (t) => t.retainedCommandWeight,
    maxWeight: maxRetainedCommands,
    maxEntries: capacity,
    debugLabel: 'worker-transcript',
  );

  // One suspended (partial) record, held across a preemption so the requeued
  // record resumes rather than restarting (#530). Only the most-recent page's
  // partial is kept; a second preemption evicts the first (bounded memory).
  _SuspendedTranscriptWalk? _suspended;

  int get hits => _entries.hits;
  int get misses => _entries.misses;
  int get evictions => _entries.evictions;

  int get length => _entries.length;
  int get retainedCommandCount => _entries.values.fold(
        0,
        (total, entry) => total + entry.sourceCommands.length,
      );
  int get retainedCommandWeight => _entries.weight;

  Future<PdfWorkerTranscript?> transcriptFor(
    PdfDocument document,
    int pageIndex,
    bool annotations,
    PdfCancellationToken token, {
    int? yieldInterval,
    PdfWorkerPhaseTimings? timings,
    void Function(Uint8List)? onPartial,
  }) async {
    if (token.cancelled) throw const PdfCancelledException();
    final key = (pageIndex, annotations);
    final hit = _entries.take(key);
    if (hit != null) {
      timings?.transcriptHit = true;
      return hit;
    }
    if (pageIndex < 0 || pageIndex >= document.pageCount) return null;

    // Resume a walk suspended by an earlier preemption of this same page, or
    // start a fresh one. The interpreter carries no cancellation token: a token
    // makes advance throw mid-chunk, which finishes the walk and restores the
    // device (discarding the partial). Driving bounded chunks and checking the
    // token between them is what keeps the recording resumable (#530).
    var entry = _takeSuspended(pageIndex, annotations);
    if (entry != null && entry.walk.isFinished) {
      entry = null; // never resume a finished walk
    }
    if (entry == null) {
      final page = document.page(pageIndex);
      final recorder = RecordingPdfDevice();
      final interpreter = PdfInterpreter(cos: document.cos, device: recorder);
      final walk = interpreter.beginPageContent(page, page.contentBytes());
      entry = _SuspendedTranscriptWalk(
          pageIndex, annotations, page, recorder, interpreter, walk);
    }

    final streamClock = timings == null ? null : (Stopwatch()..start());
    final walk = entry.walk;
    while (true) {
      final chunkOperations = onPartial != null &&
              entry.chunksAdvanced == 0 &&
              _resumeChunk > _initialProgressiveRecordChunkOperations
          ? _initialProgressiveRecordChunkOperations
          : _resumeChunk;
      final complete = await walk.advance(
        operations: chunkOperations,
        // The caller checks cancellation immediately after every bounded
        // chunk. When it has no tighter platform requirement, one task yield
        // at that boundary is sufficient; falling back to the interpreter's
        // 512-op default over-yields the same chunk dozens of times.
        yieldInterval: yieldInterval ?? chunkOperations,
      );
      if (complete) break;
      if (token.cancelled) {
        // Keep the partial recording so the requeued record resumes here.
        _keepSuspended(entry);
        throw const PdfCancelledException();
      }
      // Progressive linework partials (#564), on a doubling chunk schedule so
      // the serialize cost stays O(commands) across the page (see the isolate
      // twin). A chunk boundary is page-level graphics state, so the prefix is a
      // valid replayable buffer; images ride as placeholders like the final
      // transcript below.
      entry.chunksAdvanced++;
      if (onPartial == null || entry.chunksAdvanced < entry.nextEmitAtChunk) {
        continue;
      }
      // Re-base the next threshold off CURRENT progress rather than doubling a
      // possibly-stale value. The suspended walk is shared by (page, annotations)
      // with the non-streaming bin/detail paths, which advance chunksAdvanced
      // without emitting; deriving from chunksAdvanced keeps the doubling cadence
      // (1, 2, 4, 8 ... for a fresh walk) yet never fires a catch-up burst when a
      // record resumes streaming after such a path jumped the counter ahead.
      entry.nextEmitAtChunk = entry.chunksAdvanced * 2;
      final partial = serializeCommands(
        entry.recorder.commands,
        cos: document.cos,
        decodeImages: false,
        imagePlaceholders: true,
        compactStateScopes: true,
      );
      if (partial != null) onPartial(partial);
    }
    if (streamClock != null) {
      streamClock.stop();
      timings!.streamUs += streamClock.elapsedMicroseconds;
    }
    final interpretClock = timings == null ? null : (Stopwatch()..start());
    if (annotations) entry.interpreter.drawAnnotations(entry.page);
    if (interpretClock != null) {
      interpretClock.stop();
      timings!.interpretUs += interpretClock.elapsedMicroseconds;
    }
    final recorder = entry.recorder;
    final serializeClock = timings == null ? null : (Stopwatch()..start());
    final buffer = serializeCommands(
      recorder.commands,
      cos: document.cos,
      decodeImages: false,
      imagePlaceholders: true,
      compactStateScopes: true,
    );
    if (serializeClock != null) {
      serializeClock.stop();
      timings!.serializeUs += serializeClock.elapsedMicroseconds;
    }
    if (buffer == null) return null;
    // Once the wire buffer exists, compact mode only needs the original image
    // requests. Drop the much larger source-command list before decoding the
    // wire graph so a GC during decode can reclaim it instead of overlapping
    // both complete graphs at peak.
    if (deduplicateCommands) recorder.commands.clear();
    final wireCommands =
        List<PdfRenderCommand>.unmodifiable(deserializeCommands(buffer));
    final compactSource = deduplicateCommands
        ? compactTranscriptSourceCommands(
            wireCommands,
            recorder.imageRequests,
          )
        : null;
    if (deduplicateCommands && compactSource == null) return null;
    final sourceCommands =
        compactSource ?? List<PdfRenderCommand>.unmodifiable(recorder.commands);
    final transcript = PdfWorkerTranscript(
      sourceCommands,
      wireCommands,
    );
    _entries.put(key, transcript);
    return transcript;
  }

  void clear() {
    _entries.clear();
    _evictSuspended(null);
  }

  /// Evicts the transcripts for [pages] only, or every transcript when [pages]
  /// is null (a structural / all-pages revision). A worker calls this when an
  /// incremental revision changes those pages: their transcripts are stale, but
  /// every other page's stays warm across the edit boundary. A suspended record
  /// walks the old document too, so it follows the same eviction (#530).
  void evictPages(Set<int>? pages) {
    if (pages == null) {
      _entries.clear();
    } else {
      _entries.evictWhere((key) => pages.contains(key.$1));
    }
    _evictSuspended(pages);
  }

  /// Removes and returns the suspended record for ([pageIndex], [annotations]),
  /// or null when the slot holds a different page (left in place, so a fresh
  /// record of an urgent neighbour does not evict the page waiting to resume).
  _SuspendedTranscriptWalk? _takeSuspended(int pageIndex, bool annotations) {
    final entry = _suspended;
    if (entry != null &&
        entry.pageIndex == pageIndex &&
        entry.annotations == annotations) {
      _suspended = null;
      return entry;
    }
    return null;
  }

  /// Stashes [entry] to resume on the next record of its page, abandoning any
  /// previously stashed walk so its balancing device restore runs.
  void _keepSuspended(_SuspendedTranscriptWalk entry) {
    final previous = _suspended;
    if (previous != null && !identical(previous, entry)) {
      previous.walk.abandon();
    }
    _suspended = entry;
  }

  /// Drops the stashed walk after a revision update (or shutdown). [pages] limits
  /// eviction to the changed pages; null clears it unconditionally.
  void _evictSuspended(Set<int>? pages) {
    final entry = _suspended;
    if (entry == null) return;
    if (pages == null || pages.contains(entry.pageIndex)) {
      entry.walk.abandon();
      _suspended = null;
    }
  }
}
