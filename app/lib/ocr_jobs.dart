import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:pdf_document/pdf_document.dart';
import 'ocr_status.dart';

/// Job data is private, local app data, not a reference to a possibly revoked
/// picker URL. Pages commit independently; the source PDF is never overwritten.
abstract interface class OcrJobStorage {
  Future<List<String>> keys();
  Future<Uint8List?> read(String key);
  Future<void> write(String key, Uint8List bytes);
  Future<void> remove(String key);
  Future<OcrJobLease?> claim(String id);
}

abstract interface class OcrJobLease {
  Future<void> release();
}

enum OcrJobState { pending, running, complete, cancelled, failed }

/// Delivery is owned separately from recognition. Two editor windows/tabs can
/// observe one job, but only one may adopt its output. The output is removed
/// only after the caller confirms that its replacement snapshot is durable.
class OcrResultDelivery {
  OcrResultDelivery(this.jobs);
  final OcrJobs jobs;
  final Map<Uint8List, (String, OcrJobLease)> _pending = Map.identity();

  Future<Uint8List?> take(OcrSavedJob job) async {
    final lease = await jobs.storage.claim('${job.id}_delivery');
    if (lease == null) return null;
    try {
      if ((await jobs.read(job.id))?.state != OcrJobState.complete) {
        await lease.release();
        return null;
      }
      final result = await jobs.result(job.id);
      if (result == null) throw StateError('OCR result is missing');
      _pending[result] = (job.id, lease);
      return result;
    } catch (_) {
      await lease.release();
      rethrow;
    }
  }

  Future<void> acknowledge(Uint8List bytes) async {
    final pending = _pending.remove(bytes);
    if (pending == null) return;
    try {
      await jobs.delete(pending.$1);
    } finally {
      await pending.$2.release();
    }
  }

  Future<void> releaseUnacknowledged() async {
    final pending = _pending.values.toList();
    _pending.clear();
    await Future.wait(pending.map((p) => p.$2.release()));
  }

  void dispose() => unawaited(releaseUnacknowledged());
}

class OcrSavedJob {
  OcrSavedJob({
    required this.id,
    required this.title,
    required this.sourceHash,
    required this.pageCount,
    required this.automatic,
    this.nextPage = 0,
    this.state = OcrJobState.pending,
    this.error,
    this.workPhase = OcrPhase.preparing,
  });

  final String id;
  final String title;
  final String sourceHash;
  final int pageCount;
  final bool automatic;
  int nextPage;
  OcrJobState state;
  String? error;
  OcrPhase workPhase;

  Uint8List encode() => Uint8List.fromList(utf8.encode(jsonEncode({
        'version': 1,
        'id': id,
        'title': title,
        'sourceHash': sourceHash,
        'pageCount': pageCount,
        'automatic': automatic,
        'nextPage': nextPage,
        'state': state.name,
        'error': error,
        'workPhase': workPhase.name,
      })));

  static OcrSavedJob decode(Uint8List bytes) {
    final map = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    final id = map['id'] as String;
    if (map['version'] != 1 || !RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(id)) {
      throw const FormatException('Unsupported OCR job');
    }
    final count = map['pageCount'] as int;
    final next = map['nextPage'] as int;
    if (count < 0 || next < 0 || next > count) {
      throw const FormatException('Invalid OCR progress');
    }
    return OcrSavedJob(
      id: id,
      title: map['title'] as String,
      sourceHash: map['sourceHash'] as String,
      pageCount: count,
      automatic: map['automatic'] as bool,
      nextPage: next,
      state: OcrJobState.values.byName(map['state'] as String),
      error: map['error'] as String?,
      workPhase:
          OcrPhase.values.byName(map['workPhase'] as String? ?? 'preparing'),
    );
  }
}

class OcrJobs {
  OcrJobs(this.storage);
  final OcrJobStorage storage;

  Future<List<OcrSavedJob>> list() async {
    final jobs = <OcrSavedJob>[];
    for (final key in await storage.keys()) {
      if (!key.endsWith('_job')) continue;
      try {
        final bytes = await storage.read(key);
        if (bytes != null) jobs.add(OcrSavedJob.decode(bytes));
      } on FormatException {
        // An invalid record must not hide the other recoverable jobs.
      } on TypeError {
        // Same for an older/unrecognized record shape.
      } on ArgumentError {
        // Unknown state in a future schema.
      }
    }
    jobs.sort((a, b) => a.id.compareTo(b.id));
    return jobs;
  }

  Future<OcrSavedJob?> read(String id) async {
    final bytes = await storage.read('${id}_job');
    return bytes == null ? null : OcrSavedJob.decode(bytes);
  }

  Future<void> save(OcrSavedJob job) =>
      storage.write('${job.id}_job', job.encode());

  Future<OcrSavedJob> create(Uint8List source, String title,
      {required bool automatic}) async {
    // Repeating a failed/interrupted request for the same snapshot resumes it.
    final hash = sha256.convert(source).toString();
    for (final job in await list()) {
      if (job.sourceHash == hash &&
          job.automatic == automatic &&
          job.state != OcrJobState.cancelled &&
          job.state != OcrJobState.complete) {
        return job;
      }
    }
    final job = OcrSavedJob(
      id: '${DateTime.now().microsecondsSinceEpoch}_${Random.secure().nextInt(1 << 32)}',
      title: title,
      sourceHash: hash,
      pageCount: PdfDocument.open(source).pageCount,
      automatic: automatic,
    );
    // Manifest last: a crash while staging a large source cannot publish a
    // runnable job with incomplete bytes. Storage failures are NOT swallowed.
    await storage.write('${job.id}_source', source);
    await save(job);
    return job;
  }

  Future<Uint8List> source(OcrSavedJob job) async {
    final bytes = await storage.read('${job.id}_source');
    if (bytes == null || sha256.convert(bytes).toString() != job.sourceHash) {
      throw const FormatException('OCR source snapshot is missing or damaged');
    }
    return bytes;
  }

  Future<List<PdfOcrSpan>?> page(String id, int index) async {
    final bytes = await storage.read('${id}_page_$index');
    if (bytes == null) return null;
    final values = jsonDecode(utf8.decode(bytes)) as List;
    return [
      for (final value in values)
        PdfOcrSpan(
          text: value[0] as String,
          bounds: PdfRect(
              (value[1] as num).toDouble(),
              (value[2] as num).toDouble(),
              (value[3] as num).toDouble(),
              (value[4] as num).toDouble()),
          confidence: (value[5] as num).toDouble(),
        ),
    ];
  }

  Future<void> savePage(String id, int index, List<PdfOcrSpan> spans) =>
      storage.write(
          '${id}_page_$index',
          Uint8List.fromList(utf8.encode(jsonEncode([
            for (final s in spans)
              [
                s.text,
                s.bounds.left,
                s.bounds.bottom,
                s.bounds.right,
                s.bounds.top,
                s.confidence
              ],
          ]))));

  Future<bool> isCancelled(String id) async =>
      await storage.read('${id}_cancel') != null;
  Future<void> cancel(String id) =>
      storage.write('${id}_cancel', Uint8List.fromList([1]));

  Future<Map<int, List<PdfOcrSpan>>> recognized(OcrSavedJob job) async => {
        for (var i = 0; i < job.pageCount; i++)
          i: await page(job.id, i) ?? const [],
      };

  Future<Uint8List?> result(String id) => storage.read('${id}_result');

  /// Called only by the job's exclusive owner. Checkpoint even empty/skipped
  /// pages, and commit the page before advancing progress. A process killed
  /// at any await may repeat the in-flight page, never completed pages.
  Future<void> run(
    OcrSavedJob job, {
    required Future<List<PdfOcrSpan>> Function(int page) recognize,
    required Future<Uint8List> Function(Map<int, List<PdfOcrSpan>>) finish,
    void Function(OcrSavedJob)? onProgress,
    bool Function()? shouldPause,
  }) async {
    if (job.state == OcrJobState.complete) return;
    job
      ..state = OcrJobState.running
      ..workPhase = OcrPhase.recognising
      ..error = null;
    await save(job);
    try {
      for (var i = 0; i < job.pageCount; i++) {
        if (await isCancelled(job.id)) {
          job.state = OcrJobState.cancelled;
          await save(job);
          return;
        }
        if (shouldPause?.call() == true) {
          job.state = OcrJobState.pending;
          await save(job);
          return;
        }
        if (await page(job.id, i) == null) {
          onProgress?.call(job);
          await savePage(job.id, i, await recognize(i));
        }
        job.nextPage = i + 1;
        await save(job);
        onProgress?.call(job);
      }
      if (await isCancelled(job.id)) {
        job.state = OcrJobState.cancelled;
      } else {
        // Always assemble from the immutable source + saved spans. No double
        // text layers if termination occurs during final PDF generation.
        job.workPhase = OcrPhase.finishing;
        await save(job);
        final result = await finish(await recognized(job));
        await storage.write('${job.id}_result', result);
        job.state = await isCancelled(job.id)
            ? OcrJobState.cancelled
            : OcrJobState.complete;
      }
      await save(job);
    } catch (error) {
      job
        ..state = OcrJobState.failed
        ..error = error.toString();
      await save(job);
      rethrow;
    }
  }

  Future<void> delete(String id) async {
    await storage.remove('${id}_job');
    for (final key in await storage.keys()) {
      if (key.startsWith('${id}_')) await storage.remove(key);
    }
  }
}
