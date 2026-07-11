import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';

/// One immutable, document-backed page interpretation retained by a render
/// worker. [sourceCommands] keep image COS objects for later decode variants;
/// [wireCommands] carry the float32 geometry used by strip planning.
class PdfWorkerTranscript {
  const PdfWorkerTranscript(this.sourceCommands, this.wireCommands);

  final List<PdfRenderCommand> sourceCommands;
  final List<PdfRenderCommand> wireCommands;
}

/// Optional worker-side phase accumulator used by the web performance trace.
///
/// Callers create this only while performance logging is enabled, so ordinary
/// rendering pays no stopwatch or allocation cost. Times are cumulative
/// because a detail request can serialize both a transcript and its final
/// image-bearing command buffer.
class PdfWorkerPhaseTimings {
  int parseUs = 0;
  int interpretUs = 0;
  /// Combined parse + interpret time for incremental content streaming.
  int streamUs = 0;
  int serializeUs = 0;
  int decodeUs = 0;
  int binUs = 0;
  bool transcriptHit = false;
}

/// Bounded per-worker LRU of image-free page command transcripts.
///
/// A worker owns one immutable document revision, so `(page, annotations)` is
/// also the revision-safe identity. A replacement worker starts with an empty
/// cache. Entry-count bounding is deliberate: source command graphs have no
/// reliable byte weight, while a small hot-page window is enough for viewer
/// progressive phases and repeated zoom settles.
class PdfWorkerTranscriptCache {
  PdfWorkerTranscriptCache({this.capacity = 4}) : assert(capacity > 0);

  final int capacity;
  final _entries = <(int, bool), PdfWorkerTranscript>{};

  int hits = 0;
  int misses = 0;
  int evictions = 0;

  int get length => _entries.length;
  int get retainedCommandCount => _entries.values.fold(
    0,
    (total, entry) => total + entry.sourceCommands.length,
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
    final transcript = PdfWorkerTranscript(
      List<PdfRenderCommand>.unmodifiable(recorder.commands),
      List<PdfRenderCommand>.unmodifiable(deserializeCommands(buffer)),
    );
    _entries[key] = transcript;
    while (_entries.length > capacity) {
      _entries.remove(_entries.keys.first);
      evictions++;
    }
    return transcript;
  }

  void clear() => _entries.clear();
}
