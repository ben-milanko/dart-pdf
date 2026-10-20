// The web render worker takes editor revisions in place (the web twin of
// render_worker_revision_test.dart): an edit streams only the appended tail
// into the live worker instead of restarting it, and only the changed pages'
// worker-side caches drop. Build the real worker before running, as CI's
// worker-compiles job does:
// dart run dart_pdf_editor:build_web_worker --out lib/src/sparse_test_worker.js
// flutter test --platform chrome --no-cross-origin-isolation \
//   test/render_worker_revision_web_test.dart
// Delete the generated lib/src/sparse_test_worker.js after the run. CI runs
// without cross-origin isolation, so the worker is seeded with a transferred
// buffer here; the SharedArrayBuffer seed is covered by the release harness.
@TestOn('browser')
library;

import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:dart_pdf_editor/src/render_worker_host.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';
import 'package:web/web.dart' as web;

const _workerUrl = '/packages/dart_pdf_editor/src/sparse_test_worker.js';

void main() {
  late String? oldUrl;
  setUp(() {
    oldUrl = pdfRenderWorkerScriptUrl;
    pdfRenderWorkerScriptUrl = '${Uri.base.origin}$_workerUrl';
  });
  tearDown(() => pdfRenderWorkerScriptUrl = oldUrl);

  test(
      'an edit lands in place: page 6 stays warm and every step (edit, undo, '
      'an overwriting edit, redo) records like a fresh worker', () async {
    // Perf logging makes the worker report transcript hits (lastRenderTrace).
    final oldPerf = PdfPerfLog.enabled;
    PdfPerfLog.enabled = true;
    addTearDown(() => PdfPerfLog.enabled = oldPerf);
    final controller = PdfEditingController(_pages(8));
    addTearDown(controller.dispose);
    final worker = PdfRenderWorker.startUncached(controller.bytes);
    addTearDown(worker.dispose);
    const pages = [4, 5, 6];
    for (final page in pages) {
      expect(await worker.record(page), isNotNull);
    }
    expect(worker.supportsRevisionUpdate, isTrue,
        reason: 'the worker advertises revision updates once it is ready');
    expect(await _transcriptHit(worker, 6), isTrue, reason: 'warm before');
    final originalLength = controller.bytes.length;

    controller.apply((e) => e.addSquare(5, const PdfRect(20, 20, 120, 120)));
    _feed(worker, controller);
    expect(await _transcriptHit(worker, 6), isTrue,
        reason: "an edit to page 5 must keep page 6's transcript");
    expect(await _transcriptHit(worker, 5), isFalse,
        reason: 'the edited page must re-record');
    await _expectMatchesFresh(worker, controller.bytes, pages, step: 'edit A');
    final afterA = Uint8List.fromList(controller.bytes);

    controller.apply((e) => e.addCircle(6, const PdfRect(30, 30, 90, 90)));
    _feed(worker, controller);
    controller.undo();
    _feed(worker, controller);
    controller.undo();
    _feed(worker, controller);
    await _expectMatchesFresh(worker, controller.bytes, pages,
        step: 'undo back to the original');

    // Edit C is written where A's bytes were.
    controller.apply((e) => e.addCircle(5, const PdfRect(200, 200, 260, 300)));
    _feed(worker, controller);
    final overlap = afterA.length < controller.bytes.length
        ? afterA.length
        : controller.bytes.length;
    expect(Uint8List.sublistView(controller.bytes, originalLength, overlap),
        isNot(Uint8List.sublistView(afterA, originalLength, overlap)),
        reason: 'edit C must overwrite the undone bytes');
    await _expectMatchesFresh(worker, controller.bytes, pages,
        step: 'edit C over the undone revisions');

    controller.undo();
    _feed(worker, controller);
    controller.redo();
    _feed(worker, controller);
    await _expectMatchesFresh(worker, controller.bytes, pages,
        step: 'undo + redo of C');
    expect(worker.isActive, isTrue);
    expect(worker.supportsRevisionUpdate, isTrue);
  });

  test('a pool hands every lane the same tail, and every lane applies it',
      () async {
    final controller = PdfEditingController(_pages(8));
    addTearDown(controller.dispose);
    // Two web lanes. PdfPooledRenderWorker.updateRevisionTo makes one tail
    // copy and gives it to both; transferring it to the first lane would
    // leave the second an empty (detached) buffer.
    final pool = PdfPooledRenderWorker(controller.bytes, 2, copySource: false);
    addTearDown(pool.dispose);
    // Sequential records on an idle pool route page % 2: both lanes warm.
    const pages = [0, 1, 2, 3];
    for (final page in pages) {
      expect(await pool.record(page), isNotNull);
    }
    expect(pool.supportsRevisionUpdate, isTrue);

    controller.apply((e) => e.addSquare(0, const PdfRect(20, 20, 120, 120)));
    _feedWhole(pool, controller);
    controller.apply((e) => e.addSquare(1, const PdfRect(40, 40, 140, 140)));
    _feedWhole(pool, controller);
    await _expectMatchesFresh(pool, controller.bytes, pages,
        step: 'two edits through both lanes');
    controller.undo();
    _feedWhole(pool, controller);
    await _expectMatchesFresh(pool, controller.bytes, pages,
        step: 'undo through both lanes');
    expect(pool.supportsRevisionUpdate, isTrue,
        reason: 'no lane may have failed its update');
  });

  test('through the host, edits and undo keep one worker generation', () async {
    final controller = PdfEditingController(_pages(8));
    final host = PdfRenderWorkerHost(workerCount: () => 1);
    void sync() => _sync(host, controller);
    sync();
    controller.addListener(sync);
    addTearDown(() {
      controller.removeListener(sync);
      host.dispose();
      controller.dispose();
    });
    expect(await host.worker!.record(5), isNotNull); // waits for 'ready'
    expect(host.worker!.supportsRevisionUpdate, isTrue);

    controller.apply((e) => e.addSquare(5, const PdfRect(20, 20, 120, 120)));
    controller.apply((e) => e.addCircle(2, const PdfRect(30, 30, 90, 90)));
    controller.undo();
    controller.redo();
    expect(host.generations, 1, reason: 'every revision applied in place');
    await _expectMatchesFresh(host.worker!, controller.bytes, const [2, 5],
        step: 'host edits');
  });

  test('a worker whose ready lacks revisionUpdate is restarted on each edit',
      () async {
    // An older worker bundle: it opens nothing and declines every record, and
    // its 'ready' says nothing about updates.
    const stub = '''
onmessage = (event) => {
  const data = event.data;
  if (data.kind === 'init') {
    postMessage({kind: 'ready', shared: !!data.shared, imageDecodeCache: true});
  } else if (data.kind === 'record') {
    postMessage({kind: 'result', id: data.id, buffer: null});
  }
};
''';
    final url = web.URL.createObjectURL(web.Blob(
        <JSAny>[stub.toJS].toJS, web.BlobPropertyBag(type: 'text/javascript')));
    addTearDown(() => web.URL.revokeObjectURL(url));
    pdfRenderWorkerScriptUrl = url;

    final controller = PdfEditingController(_pages(3));
    final host = PdfRenderWorkerHost(workerCount: () => 1);
    void sync() => _sync(host, controller);
    sync();
    controller.addListener(sync);
    addTearDown(() {
      controller.removeListener(sync);
      host.dispose();
      controller.dispose();
    });
    final first = host.worker!;
    expect(await first.record(0), isNull); // the stub is ready once it answers
    expect(first.isActive, isTrue);
    expect(first.supportsRevisionUpdate, isFalse);

    controller.apply((e) => e.addSquare(0, const PdfRect(20, 20, 120, 120)));
    expect(host.generations, 2, reason: 'the old bundle is restarted');
    expect(identical(host.worker, first), isFalse);
    expect(first.isActive, isFalse, reason: 'the old generation is disposed');
  });
}

/// What the shell does on every session change.
void _sync(PdfRenderWorkerHost host, PdfEditingController controller) {
  final delta = controller.lastRevisionDelta;
  host.sync(
    document: controller.document,
    bytes: controller.bytes,
    pageCount: controller.document.pageCount,
    revision: delta == null
        ? null
        : (
            baseLength: delta.baseLength,
            newLength: delta.newLength,
            changedPages: delta.changedPages,
          ),
  );
}

/// Feeds [controller]'s latest revision to [worker] with a private copy of its
/// tail, as [PdfRenderWorker.updateRevision] callers must.
void _feed(PdfRenderWorker worker, PdfEditingController controller) {
  final delta = controller.lastRevisionDelta!;
  worker.updateRevision(
    delta.baseLength,
    Uint8List.fromList(Uint8List.sublistView(
        controller.bytes, delta.baseLength, delta.newLength)),
    delta.newLength,
    delta.changedPages,
  );
}

/// Feeds the revision as [PdfRenderWorkerHost] does: the whole revision view.
void _feedWhole(PdfRenderWorker worker, PdfEditingController controller) {
  final delta = controller.lastRevisionDelta!;
  worker.updateRevisionTo(
      controller.bytes, delta.baseLength, delta.changedPages);
}

/// Records [pageIndex] and says whether the worker served it from its
/// transcript cache.
Future<bool> _transcriptHit(PdfRenderWorker worker, int pageIndex) async {
  expect(await worker.record(pageIndex), isNotNull);
  return worker.lastRenderTrace!.transcriptHit;
}

/// [pageIndex]'s record from [worker] in wire form, byte-comparable across
/// workers.
Future<Uint8List?> _recorded(PdfRenderWorker worker, int pageIndex) async {
  final commands = await worker.record(pageIndex);
  return commands == null ? null : serializeCommands(commands);
}

/// Expects [worker] to record [pages] byte-identically to a fresh web worker
/// opened on a private copy of [bytes].
Future<void> _expectMatchesFresh(
  PdfRenderWorker worker,
  Uint8List bytes,
  List<int> pages, {
  required String step,
}) async {
  final fresh = PdfRenderWorker.startUncached(Uint8List.fromList(bytes));
  try {
    for (final page in pages) {
      final want = await _recorded(fresh, page);
      expect(want, isNotNull, reason: '$step: reference page $page');
      expect(await _recorded(worker, page), want, reason: '$step: page $page');
    }
  } finally {
    fresh.dispose();
  }
}

/// A [count]-page document, page N showing "Page N". Built here rather than
/// with pdf_test_fixtures, whose barrel does not compile to JS.
Uint8List _pages(int count) {
  final builder = CosDocumentBuilder();
  final pages = CosDictionary({
    'Type': CosName('Pages'),
    'Count': CosInteger(count),
  });
  final pagesRef = builder.add(pages);
  final font = builder.add(CosDictionary({
    'Type': CosName('Font'),
    'Subtype': CosName('Type1'),
    'BaseFont': CosName('Helvetica'),
  }));
  pages['Kids'] = CosArray([
    for (var i = 0; i < count; i++)
      builder.add(CosDictionary({
        'Type': CosName('Page'),
        'Parent': pagesRef,
        'MediaBox': CosArray([0, 0, 612, 792].map(CosInteger.new).toList()),
        'Resources': CosDictionary({
          'Font': CosDictionary({'F1': font})
        }),
        'Contents': builder.add(CosStream(
          CosDictionary(),
          Uint8List.fromList(
              latin1.encode('BT /F1 24 Tf 72 720 Td (Page ${i + 1}) Tj ET')),
        )),
      })),
  ]);
  return builder.build(
      root: builder.add(CosDictionary({
    'Type': CosName('Catalog'),
    'Pages': pagesRef,
  })));
}
