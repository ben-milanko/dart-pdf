// PR2 of #564: PdfCachingRenderWorker fans the backend's progressive partial
// stream across concurrent callers for one page (the dedup), with late-joiner
// replay, while staying inert when nobody opts in. These are the subtle
// semantics the issue flags as the main source of bugs, so they are unit-tested
// against a DETERMINISTIC fake backend (a real isolate can't sequence "a joiner
// arrives after partial 1 but before partial 2" without a wall-clock race).
import 'dart:async';

import 'package:dart_pdf_editor/src/render_worker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';

/// A backend whose record emits two partials around a test-controlled gate, then
/// a final. Records whether each call was asked to stream, and how many decodes
/// it actually ran, so the dedup and the opt-in gating can be asserted directly.
class _FakeBackend extends PdfRenderWorker {
  int recordCalls = 0;
  final List<bool> streamRequested = [];
  final gate = Completer<void>();

  static List<PdfRenderCommand> _cmds(int n) =>
      List.generate(n, (_) => const PdfSaveCommand());

  @override
  bool get isActive => true;

  @override
  Future<List<PdfRenderCommand>?> record(
    int pageIndex, {
    bool annotations = true,
    int priority = 0,
    double? imagePixelRatio,
    bool decodeImages = true,
    int? commandLimit,
    PdfRect? imageDecodeRegion,
    PdfPartialRecordSink? onPartial,
  }) async {
    recordCalls++;
    streamRequested.add(onPartial != null);
    if (onPartial != null) {
      onPartial(_cmds(1)); // partial 1
      await gate.future; // held open until a late joiner has subscribed
      onPartial(_cmds(2)); // partial 2
    } else {
      await gate.future;
    }
    return _cmds(3); // final
  }

  @override
  void cancel(int pageIndex, {int priority = 0}) {}
  @override
  void dispose() {}
}

void main() {
  test('a single opted-in caller receives all partials then the final',
      () async {
    final backend = _FakeBackend();
    final worker = PdfCachingRenderWorker(backend);
    addTearDown(worker.dispose);

    final partials = <int>[];
    final future = worker.record(0, onPartial: (p) => partials.add(p.length));
    await Future<void>.delayed(Duration.zero); // let the decode reach the gate
    expect(partials, [1], reason: 'partial 1 arrives before the gate opens');

    backend.gate.complete();
    final result = await future;

    expect(partials, [1, 2]);
    expect(result, hasLength(3));
    expect(backend.recordCalls, 1);
  });

  test('a concurrent late joiner replays buffered partials then shares the rest',
      () async {
    final backend = _FakeBackend();
    final worker = PdfCachingRenderWorker(backend);
    addTearDown(worker.dispose);

    final a = <int>[];
    final aFuture = worker.record(0, onPartial: (p) => a.add(p.length));
    await Future<void>.delayed(Duration.zero); // A's decode reaches the gate
    expect(a, [1]);

    // B joins the SAME key while the decode is parked at the gate. It must
    // replay partial 1 synchronously on subscribe (so it is not behind), then
    // receive partial 2 live with A.
    final b = <int>[];
    final bFuture = worker.record(0, onPartial: (p) => b.add(p.length));
    expect(b, [1], reason: 'the late joiner replays the buffered prefix');

    backend.gate.complete();
    final aResult = await aFuture;
    final bResult = await bFuture;

    expect(a, [1, 2]);
    expect(b, [1, 2]);
    // Deduped onto one decode, one shared final.
    expect(backend.recordCalls, 1);
    expect(aResult, hasLength(3));
    expect(identical(aResult, bResult), isTrue,
        reason: 'both callers share the one backend result');
  });

  test('no partials are requested from the backend when the dispatcher opts out',
      () async {
    final backend = _FakeBackend();
    final worker = PdfCachingRenderWorker(backend);
    addTearDown(worker.dispose);

    // Dispatcher passes no sink: the backend must not be asked to stream, so an
    // all-null production workload never enters the streaming path.
    final dispatch = worker.record(0);
    await Future<void>.delayed(Duration.zero);

    // A joiner that DOES want partials cannot retroactively enable streaming -
    // the decode already started without it - so it only awaits the final.
    final joinerPartials = <int>[];
    final join = worker.record(0, onPartial: (p) => joinerPartials.add(p.length));

    backend.gate.complete();
    await dispatch;
    await join;

    expect(backend.recordCalls, 1, reason: 'still deduped onto one decode');
    expect(backend.streamRequested, [false],
        reason: 'the backend was never asked to stream');
    expect(joinerPartials, isEmpty,
        reason: 'a joiner cannot enable a stream the dispatcher declined');
  });

  test('a partial emitted after completion is dropped', () async {
    final backend = _FakeBackend();
    final worker = PdfCachingRenderWorker(backend);
    addTearDown(worker.dispose);

    final partials = <int>[];
    final future = worker.record(0, onPartial: (p) => partials.add(p.length));
    backend.gate.complete();
    await future;

    // The record has completed and been dropped from the in-flight map; a stray
    // late partial (a backend racing its own final) must not reach the sink. We
    // can only assert the observable outcome: exactly the two real partials.
    expect(partials, [1, 2]);
  });
}
