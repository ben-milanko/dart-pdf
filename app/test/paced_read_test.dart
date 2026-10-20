// PacedWholeRead, the whole-file read behind the desktop direct open: it reads
// every byte exactly once, in a small first chunk and then bigger windows,
// and signals `behind` as soon as a chunk misses its share of the budget -
// before the chunk lands when its timer fires, or as it lands when the timer
// could not run - while the read itself carries on to the end.
import 'dart:async';
import 'dart:typed_data';

import 'package:dart_pdf_editor_app/paced_read.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_cos/pdf_cos.dart';

/// Serves [data], recording every range asked for. [delay] runs before each
/// read is answered. With [overAnswer], every read runs to the end of [data]
/// whatever was asked for.
class _Source implements PdfByteSource {
  _Source(this.data, {this.delay, this.overAnswer = false});

  final Uint8List data;
  final Future<void> Function(int start, int end)? delay;
  final bool overAnswer;
  final ranges = <(int, int)>[];
  int answered = 0;

  @override
  Future<int?> get length async => data.length;

  @override
  Future<Uint8List> readRange(int start, int endExclusive) async {
    ranges.add((start, endExclusive));
    await delay?.call(start, endExclusive);
    answered++;
    final end =
        !overAnswer && endExclusive < data.length ? endExclusive : data.length;
    if (start >= end) return Uint8List(0);
    return Uint8List.sublistView(data, start, end);
  }

  @override
  Future<void> close() async {}
}

Uint8List _data(int length) =>
    Uint8List.fromList([for (var i = 0; i < length; i++) (i * 31 + 7) & 0xff]);

/// Blocks the isolate - no timer can fire meanwhile - for [duration].
void _busy(Duration duration) {
  final clock = Stopwatch()..start();
  while (clock.elapsed < duration) {}
}

/// The ranges tile `[0, length)` exactly once, in order.
Matcher _tiles(int length) => predicate<List<(int, int)>>((ranges) {
      var pos = 0;
      for (final (start, end) in ranges) {
        if (start != pos || end <= start) return false;
        pos = end < length ? end : length;
      }
      return pos == length;
    }, 'tiles [0, $length) once');

void main() {
  test('a fast read stays on pace and reads each byte once', () async {
    final data = _data(50 * 1024);
    final source = _Source(data);
    final progress = <int>[];
    final read = PacedWholeRead.start(
      source,
      length: data.length,
      budget: const Duration(seconds: 5),
      firstChunk: 1024,
      chunk: 8192,
      onProgress: (received, total) {
        expect(total, data.length);
        progress.add(received);
      },
    );

    expect(await read.bytes, data);
    expect(read.isBehind, isFalse);
    expect(read.behindAtBytes, isNull);
    // A small first read, then reads doubling up to the chunk size.
    expect(source.ranges.take(5), [
      (0, 1024),
      (1024, 3072),
      (3072, 7168),
      (7168, 15360),
      (15360, 23552),
    ]);
    expect(source.ranges, _tiles(data.length));
    expect(progress.last, data.length);
  });

  test('a file no bigger than the first chunk is one read', () async {
    final data = _data(700);
    final source = _Source(data);
    final read = PacedWholeRead.start(source,
        length: data.length,
        budget: const Duration(seconds: 5),
        firstChunk: 1024);

    expect(await read.bytes, data);
    expect(source.ranges, [(0, 700)]);
    expect(read.isBehind, isFalse);
  });

  test('slow throughput falls behind the pace line before the chunk lands',
      () async {
    // Every read is fast to start and slow to finish: 100 ms per KB, where
    // the budget allows 50 ms per KB. The whole read can't make it, and
    // the first chunk's due time on the pace line (6 ms slack + 200 ms * 1/4)
    // says so before that chunk is in. The first-chunk cap is out of the
    // way here, so this is the pace line alone.
    final data = _data(4 * 1024);
    final source = _Source(data,
        delay: (start, end) => Future<void>.delayed(
            Duration(microseconds: (end - start) * 100000 ~/ 1024)));
    var answeredWhenBehind = -1;
    final read = PacedWholeRead.start(
      source,
      length: data.length,
      budget: const Duration(milliseconds: 200),
      firstChunk: 1024,
      firstChunkDue: const Duration(seconds: 10),
      chunk: 1024,
    );
    unawaited(read.behind.then((_) => answeredWhenBehind = source.answered));

    await read.behind;
    expect(answeredWhenBehind, 0);
    expect(read.behindAtBytes, 0);
    expect(read.behindAtDeadline, isFalse);

    // The read carries on behind the caller's fallback, once over the file.
    expect(await read.bytes, data);
    expect(source.ranges, _tiles(data.length));
  });

  test('the first chunk is due within firstChunkDue, whatever the budget',
      () async {
    // Fast to answer, slow to stream: a budget this generous would allow it
    // a whole second for the first chunk, but a local disk would have
    // delivered it long before 20 ms.
    final data = _data(4 * 1024);
    final source = _Source(data,
        delay: (start, end) =>
            Future<void>.delayed(const Duration(milliseconds: 200)));
    var answeredWhenBehind = -1;
    final read = PacedWholeRead.start(
      source,
      length: data.length,
      budget: const Duration(seconds: 4),
      firstChunk: 1024,
      firstChunkDue: const Duration(milliseconds: 20),
      chunk: 3 * 1024,
    );
    unawaited(read.behind.then((_) => answeredWhenBehind = source.answered));

    await read.behind;
    expect(answeredWhenBehind, 0);
    expect(read.behindAtBytes, 0);
    expect(read.behindAtDeadline, isFalse);
    expect(await read.bytes, data);
    expect(read.firstChunkTime,
        greaterThanOrEqualTo(const Duration(milliseconds: 150)));
    // Once behind, the rest goes in one full-size read, not the ramp.
    expect(source.ranges, [(0, 1024), (1024, 4096)]);
  });

  test('a file read in one go is only held to the budget', () async {
    // No first-chunk rule when the first read is the whole file: it is
    // either in within the budget or not.
    final data = _data(700);
    final source = _Source(data,
        delay: (start, end) =>
            Future<void>.delayed(const Duration(milliseconds: 40)));
    final read = PacedWholeRead.start(source,
        length: data.length,
        budget: const Duration(seconds: 2),
        firstChunk: 1024,
        firstChunkDue: const Duration(milliseconds: 5));

    expect(await read.bytes, data);
    expect(read.isBehind, isFalse);
  });

  test('a chunk that lands late counts even if its timer never ran', () async {
    // The first read holds the isolate past its due time, so the timer armed
    // for it can't fire before the read returns; the landing check catches it.
    final data = _data(4 * 1024);
    var first = true;
    final source = _Source(data, delay: (start, end) {
      if (first) {
        first = false;
        _busy(const Duration(milliseconds: 80));
      }
      return Future<void>.value();
    });
    final read = PacedWholeRead.start(
      source,
      length: data.length,
      budget: const Duration(milliseconds: 100),
      firstChunk: 1024,
      chunk: 1024,
    );

    expect(await read.bytes, data);
    expect(read.isBehind, isTrue);
    expect(read.behindAtBytes, 0);
    expect(read.behindAtDeadline, isFalse);
  });

  test('a mid-read chunk that drops off the pace falls behind then', () async {
    // The first chunk is quick, the rest crawl: the second chunk (to 3 KB of
    // 8) is due 6 + 200 * 3/8 = 81 ms in and takes 200.
    final data = _data(8 * 1024);
    final source = _Source(data,
        delay: (start, end) => start == 0
            ? Future<void>.value()
            : Future<void>.delayed(
                Duration(microseconds: (end - start) * 100000 ~/ 1024)));
    var answeredWhenBehind = -1;
    final read = PacedWholeRead.start(
      source,
      length: data.length,
      budget: const Duration(milliseconds: 200),
      firstChunk: 1024,
      chunk: 8 * 1024,
    );
    unawaited(read.behind.then((_) => answeredWhenBehind = source.answered));

    await read.behind;
    expect(answeredWhenBehind, 1);
    expect(read.behindAtBytes, 1024);
    expect(read.behindAtDeadline, isFalse);
    expect(await read.bytes, data);
    // Ramping while on pace (1 KB, 2 KB), then the rest at full size.
    expect(source.ranges, [(0, 1024), (1024, 3072), (3072, 8192)]);
  });

  test('a stalled last chunk falls behind at the deadline', () async {
    final data = _data(3 * 1024);
    final release = Completer<void>();
    final source = _Source(data,
        delay: (start, end) =>
            start == 0 ? Future<void>.value() : release.future);
    final read = PacedWholeRead.start(
      source,
      length: data.length,
      budget: const Duration(milliseconds: 60),
      firstChunk: 1024,
      chunk: 2 * 1024,
    );

    await read.behind;
    expect(read.behindAtBytes, 1024);
    expect(read.behindAtDeadline, isTrue);
    expect(read.behindAfter!,
        greaterThanOrEqualTo(const Duration(milliseconds: 50)));
    release.complete();
    expect(await read.bytes, data);
    expect(source.ranges, [(0, 1024), (1024, 3072)]);
  });

  test('a last chunk that is in, however late, is not behind', () async {
    // The last read overruns the whole budget without yielding, so its
    // deadline timer can't fire; the bytes are complete, so they are used.
    final data = _data(2 * 1024);
    final source = _Source(data, delay: (start, end) {
      if (start > 0) _busy(const Duration(milliseconds: 80));
      return Future<void>.value();
    });
    final read = PacedWholeRead.start(
      source,
      length: data.length,
      budget: const Duration(milliseconds: 50),
      firstChunk: 1024,
      chunk: 1024,
    );

    expect(await read.bytes, data);
    expect(read.isBehind, isFalse);
  });

  test('a failed read fails the bytes without falling behind', () async {
    final data = _data(4 * 1024);
    final source = _Source(data, delay: (start, end) async {
      if (start > 0) throw StateError('gone');
    });
    final read = PacedWholeRead.start(
      source,
      length: data.length,
      budget: const Duration(seconds: 5),
      firstChunk: 1024,
      chunk: 1024,
    );

    await expectLater(read.bytes, throwsStateError);
    expect(read.isBehind, isFalse);
  });

  test('a source that answers with too much is clamped to the file', () async {
    final data = _data(3000);
    final padded = Uint8List(5000)..setRange(0, 3000, data);
    final source = _Source(padded, overAnswer: true);
    final read = PacedWholeRead.start(source,
        length: data.length,
        budget: const Duration(seconds: 5),
        firstChunk: 1024,
        chunk: 4096);

    expect(await read.bytes, data);
  });
}
