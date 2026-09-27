import 'dart:async';
import 'dart:typed_data';

import 'package:pdf_cos/pdf_cos.dart';

/// Reads a [PdfByteSource] of known length whole while checking its own pace
/// against a time budget. This is the whole-file read behind the desktop
/// direct open (`_openProgressive` in editor_screen.dart).
///
/// A file is only worth reading straight into an edit session if the whole
/// read lands within the budget. How fast the storage answered the first-paint
/// open's many small reads shows its latency, not its throughput: a network
/// share, a USB stick or a spinning disk answers a 2 KB read in well under a
/// millisecond and then moves 30-150 MB a second. So the read checks its pace
/// as it goes, and completes [behind] as soon as a chunk misses its due time.
/// The caller can then hand over to the preview at once.
///
/// - Every chunk keeps pace with a straight line from the read's start to the
///   end of the budget, at most [slack] behind it: the chunk ending at byte `e`
///   is due `min(budget, slack + budget * e / length)` after the start. The
///   last chunk is due at the budget itself, so [behind] doubles as the
///   deadline.
/// - The first read is a small [firstChunk]. When there is more to come, it is
///   also due within [firstChunkDue], however generous the budget: a local
///   disk delivers 1 MB in a millisecond or two, the slow storage classes
///   above in 7-35. That catches them within about [firstChunkDue] even for a
///   file only a little too big to read over them within the budget.
/// - Reads then double in size up to [chunk] (the window `readSourceFully`
///   uses), so the pace is checked often while there is still a decision to
///   make, and big reads carry the bulk of the file. Once behind, the read
///   goes straight to [chunk]: it is now the preview's background read, and
///   each extra read boundary costs it a hop through a busy isolate.
///
/// Each due time is checked twice: by a timer while the chunk is in flight,
/// and as it lands, in case the isolate was too busy for the timer to run.
///
/// Falling behind does not stop the read. [bytes] still completes with the
/// whole file, so a caller that falls back to the preview reads the file only
/// once.
class PacedWholeRead {
  PacedWholeRead._(this._source, this.length, this.budget, this.slack,
      this.firstChunk, this.firstChunkDue, this.chunk, this._onProgress);

  /// Starts reading [length] bytes of [source] from offset 0. [onProgress]
  /// is called after each chunk with the running total.
  factory PacedWholeRead.start(
    PdfByteSource source, {
    required int length,
    required Duration budget,
    Duration slack = const Duration(milliseconds: 6),
    int firstChunk = 1 << 20,
    Duration firstChunkDue = const Duration(milliseconds: 10),
    int chunk = 8 << 20,
    void Function(int received, int total)? onProgress,
  }) {
    assert(length > 0 && firstChunk > 0 && chunk > 0);
    final read = PacedWholeRead._(source, length, budget, slack, firstChunk,
        firstChunkDue, chunk, onProgress);
    read._bytes = read._run();
    return read;
  }

  final PdfByteSource _source;

  /// The length of the file being read.
  final int length;

  /// How long the whole read may take before it counts as too slow.
  final Duration budget;

  /// How far behind the straight-line pace a chunk may land.
  final Duration slack;

  /// The size of the first read.
  final int firstChunk;

  /// The most time the first read may take when it isn't the whole file.
  final Duration firstChunkDue;

  /// The size reads grow to after the first.
  final int chunk;

  final void Function(int received, int total)? _onProgress;
  final _clock = Stopwatch()..start();
  final _behind = Completer<void>();
  late final Future<Uint8List> _bytes;

  /// The whole file. Also completes after [behind], with the same bytes.
  Future<Uint8List> get bytes => _bytes;

  /// Completes, once, when a chunk misses its due time.
  Future<void> get behind => _behind.future;

  /// Whether the read has fallen behind its pace.
  bool get isBehind => _behind.isCompleted;

  /// How many bytes were in hand when the read fell behind, or null while it
  /// is on pace.
  int? get behindAtBytes => _behindAtBytes;
  int? _behindAtBytes;

  /// How far into the read it fell behind, or null while it is on pace.
  Duration? get behindAfter => _behindAfter;
  Duration? _behindAfter;

  /// Whether the chunk that fell behind was due at the end of the [budget]
  /// (the last chunk always is). If so, the caller waited out the whole
  /// budget. If not, it learned early that the read could not make it.
  bool get behindAtDeadline => _behindAtDeadline;
  bool _behindAtDeadline = false;

  /// How long the first read took, once it is in.
  Duration? get firstChunkTime => _firstChunkTime;
  Duration? _firstChunkTime;

  /// Microseconds after the start by which the chunk ending at byte [end] is
  /// due; [first] if it is the first read.
  int _dueUs(int end, {required bool first}) {
    final budgetUs = budget.inMicroseconds;
    var dueUs = slack.inMicroseconds + budgetUs * end ~/ length;
    if (dueUs > budgetUs) dueUs = budgetUs;
    if (first && end < length) {
      final firstUs = firstChunkDue.inMicroseconds;
      if (firstUs < dueUs) dueUs = firstUs;
    }
    return dueUs;
  }

  void _fallBehind(int inHand, int dueUs) {
    if (_behind.isCompleted) return;
    _behindAtBytes = inHand;
    _behindAfter = _clock.elapsed;
    _behindAtDeadline = dueUs >= budget.inMicroseconds;
    _behind.complete();
  }

  Future<Uint8List> _run() async {
    final out = Uint8List(length);
    var pos = 0;
    var size = firstChunk;
    Timer? due;
    try {
      for (var first = true; pos < length; first = false) {
        // Small reads only while there is a decision to make: once behind,
        // every read boundary is a hop through a busy isolate that the
        // storage sits idle for, so go straight to the big reads.
        if (!first) size = isBehind || size * 2 >= chunk ? chunk : size * 2;
        final end = pos + size < length ? pos + size : length;
        final dueUs = _dueUs(end, first: first);
        final inHand = pos;
        if (!isBehind) {
          final leftUs = dueUs - _clock.elapsedMicroseconds;
          due = Timer(Duration(microseconds: leftUs < 0 ? 0 : leftUs),
              () => _fallBehind(inHand, dueUs));
        }
        final data = await _source.readRange(pos, end);
        due?.cancel();
        due = null;
        if (first) _firstChunkTime = _clock.elapsed;
        if (data.isEmpty) break;
        // Late, and more is still to come: the timer's callback may simply
        // not have run yet. A last chunk that is already in is not late in
        // any way that matters - the bytes are here.
        if (end < length && _clock.elapsedMicroseconds > dueUs) {
          _fallBehind(inHand, dueUs);
        }
        // A source may answer with more than was asked for; never let it run
        // past the buffer.
        final count = data.length < length - pos ? data.length : length - pos;
        out.setRange(pos, pos + count, data);
        pos += count;
        _onProgress?.call(pos, length);
      }
    } finally {
      due?.cancel();
    }
    return pos == length ? out : Uint8List.sublistView(out, 0, pos);
  }
}
