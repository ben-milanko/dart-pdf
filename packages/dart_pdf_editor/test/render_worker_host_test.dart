// The worker lifecycle state machine extracted from the shell (#396): a no-op
// when the document is unchanged, an in-place updateRevision for a byte-prefix
// append, and a full restart otherwise. Driven here with a fake worker via the
// debug spawn seam, so it exercises the logic without spawning a real isolate.
import 'dart:typed_data';

import 'package:dart_pdf_editor/src/render_worker.dart';
import 'package:dart_pdf_editor/src/render_worker_host.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';

class _FakeWorker extends PdfRenderWorker {
  _FakeWorker(this.bytesLength);
  final int bytesLength;
  bool disposed = false;
  final revisions = <(int base, int newLen, Set<int>? pages)>[];

  @override
  bool get supportsRevisionUpdate => true;

  @override
  void updateRevision(
      int baseLength, Uint8List appended, int newLength, Set<int>? changedPages) {
    revisions.add((baseLength, newLength, changedPages));
  }

  @override
  bool get isActive => !disposed;

  @override
  Future<List<PdfRenderCommand>?> record(int pageIndex,
          {bool annotations = true,
          int priority = 0,
          double? imagePixelRatio,
          bool decodeImages = true,
          int? commandLimit,
          PdfRect? imageDecodeRegion}) async =>
      null;

  @override
  void cancel(int pageIndex, {int priority = 0}) {}

  @override
  void dispose() => disposed = true;
}

void main() {
  final spawned = <_FakeWorker>[];

  setUp(() {
    spawned.clear();
    PdfRenderWorkerHost.debugSpawnOverride = (bytes,
        {required int pageCount, int? workerCount, bool copySource = false}) {
      final worker = _FakeWorker(bytes.length);
      spawned.add(worker);
      return worker;
    };
  });

  tearDown(() => PdfRenderWorkerHost.debugSpawnOverride = null);

  PdfDocument openDoc() => PdfDocument.open(buildMultiPagePdf(3));

  test('first sync starts exactly one generation', () {
    final host = PdfRenderWorkerHost();
    final doc = openDoc();
    host.sync(document: doc, bytes: doc.cos.bytes, pageCount: 3, revision: null);

    expect(host.generations, 1);
    expect(spawned, hasLength(1));
    expect(identical(host.worker, spawned.single), isTrue);
  });

  test('the same document is a no-op', () {
    final host = PdfRenderWorkerHost();
    final doc = openDoc();
    host.sync(document: doc, bytes: doc.cos.bytes, pageCount: 3, revision: null);
    host.sync(document: doc, bytes: doc.cos.bytes, pageCount: 3, revision: null);

    expect(host.generations, 1, reason: 'unchanged document must not restart');
    expect(spawned, hasLength(1));
  });

  test('a byte-prefix append updates in place, no new generation', () {
    final host = PdfRenderWorkerHost();
    final doc1 = openDoc();
    host.sync(
        document: doc1, bytes: doc1.cos.bytes, pageCount: 3, revision: null);

    // A new document object (a revision) whose bytes extend the first.
    final baseLength = doc1.cos.bytes.length;
    final appended = Uint8List(16);
    final grown = Uint8List(baseLength + appended.length)
      ..setRange(0, baseLength, doc1.cos.bytes);
    final doc2 = openDoc(); // distinct object; identity is what drives the sync
    host.sync(
      document: doc2,
      bytes: grown,
      pageCount: 3,
      revision: (baseLength: baseLength, newLength: grown.length, changedPages: {1}),
    );

    expect(host.generations, 1, reason: 'an incremental edit keeps the worker');
    expect(spawned, hasLength(1));
    expect(spawned.single.revisions, hasLength(1));
    expect(spawned.single.revisions.single.$1, baseLength);
    expect(spawned.single.revisions.single.$2, grown.length);
    expect(spawned.single.revisions.single.$3, {1});
  });

  test('a revision whose length disagrees with the buffer restarts', () {
    final host = PdfRenderWorkerHost();
    final doc1 = openDoc();
    host.sync(
        document: doc1, bytes: doc1.cos.bytes, pageCount: 3, revision: null);

    // newLength that doesn't match the passed bytes (a structural edit / buffer
    // replacement) can't be applied as a prefix append, so a fresh generation.
    final doc2 = openDoc();
    host.sync(
      document: doc2,
      bytes: doc2.cos.bytes,
      pageCount: 3,
      revision: (baseLength: 0, newLength: doc2.cos.bytes.length + 999, changedPages: null),
    );

    expect(host.generations, 2);
    expect(spawned, hasLength(2));
    expect(spawned.first.disposed, isTrue, reason: 'the old worker is disposed');
    expect(spawned.last.disposed, isFalse);
  });

  test('dispose tears down the worker and is idempotent', () {
    final host = PdfRenderWorkerHost();
    final doc = openDoc();
    host.sync(document: doc, bytes: doc.cos.bytes, pageCount: 3, revision: null);
    final worker = spawned.single;

    host.dispose();
    expect(worker.disposed, isTrue);
    expect(host.worker, isNull);
    host.dispose(); // idempotent
    expect(host.worker, isNull);
  });

  test('onGeneration fires per fresh generation, not per in-place update', () {
    var generations = 0;
    final host = PdfRenderWorkerHost(onGeneration: () => generations++);
    final doc1 = openDoc();
    host.sync(
        document: doc1, bytes: doc1.cos.bytes, pageCount: 3, revision: null);
    expect(generations, 1);

    // In-place update: no onGeneration.
    final baseLength = doc1.cos.bytes.length;
    final grown = Uint8List(baseLength + 8)..setRange(0, baseLength, doc1.cos.bytes);
    host.sync(
      document: openDoc(),
      bytes: grown,
      pageCount: 3,
      revision: (baseLength: baseLength, newLength: grown.length, changedPages: {0}),
    );
    expect(generations, 1);
  });
}
