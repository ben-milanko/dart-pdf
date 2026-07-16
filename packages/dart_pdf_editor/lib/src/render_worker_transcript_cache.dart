import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';

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
/// UI and removes redundant state scopes. Its reconstructed image streams are
/// detached from the document, so later detail serialization cannot resolve
/// every dependency. Replace only those streams while sharing every other
/// command object and retaining the wire transform.
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
class PdfWorkerTranscriptCache {
  PdfWorkerTranscriptCache({
    this.capacity = 4,
    this.maxRetainedCommands = 250000,
    this.deduplicateCommands = true,
  })  : assert(capacity > 0),
        assert(maxRetainedCommands > 0);

  final int capacity;
  final int maxRetainedCommands;

  /// Whether transcripts may share the compact wire graph, patching only its
  /// document-backed image requests. Exposed for A/B benchmarks.
  final bool deduplicateCommands;
  final _entries = <(int, bool), PdfWorkerTranscript>{};

  int hits = 0;
  int misses = 0;
  int evictions = 0;

  int get length => _entries.length;
  int get retainedCommandCount => _entries.values.fold(
        0,
        (total, entry) => total + entry.sourceCommands.length,
      );
  int get retainedCommandWeight => _entries.values.fold(
        0,
        (total, entry) => total + entry.retainedCommandWeight,
      );

  Future<PdfWorkerTranscript?> transcriptFor(
    PdfDocument document,
    int pageIndex,
    bool annotations,
    PdfCancellationToken token, {
    int? yieldInterval,
    PdfWorkerPhaseTimings? timings,
  }) async {
    if (token.cancelled) throw const PdfCancelledException();
    final key = (pageIndex, annotations);
    final hit = _entries.remove(key);
    if (hit != null) {
      hits++;
      timings?.transcriptHit = true;
      _entries[key] = hit;
      return hit;
    }
    misses++;
    if (pageIndex < 0 || pageIndex >= document.pageCount) return null;
    final page = document.page(pageIndex);
    final recorder = RecordingPdfDevice();
    final interpreter = PdfInterpreter(
      cos: document.cos,
      device: recorder,
      cancellation: token,
    );
    final streamClock = timings == null ? null : (Stopwatch()..start());
    if (yieldInterval == null) {
      await interpreter.drawPageContentAsync(page, page.contentBytes());
    } else {
      await interpreter.drawPageContentAsync(
        page,
        page.contentBytes(),
        yieldInterval: yieldInterval,
      );
    }
    if (streamClock != null) {
      streamClock.stop();
      timings!.streamUs += streamClock.elapsedMicroseconds;
    }
    final interpretClock = timings == null ? null : (Stopwatch()..start());
    if (annotations) interpreter.drawAnnotations(page);
    if (interpretClock != null) {
      interpretClock.stop();
      timings!.interpretUs += interpretClock.elapsedMicroseconds;
    }
    if (token.cancelled) throw const PdfCancelledException();
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
    _entries[key] = transcript;
    while (_entries.length > 1 &&
        (_entries.length > capacity ||
            retainedCommandWeight > maxRetainedCommands)) {
      _entries.remove(_entries.keys.first);
      evictions++;
    }
    return transcript;
  }

  void clear() => _entries.clear();
}
