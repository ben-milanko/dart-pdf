import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_cos/perf.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:test/test.dart';

/// Runs the reference workload: open, load some objects, decode a stream,
/// incrementally save. Returns the saved bytes.
Uint8List _workload() {
  final doc = CosDocument.open(buildClassicPdf());
  doc.resolve(doc.catalog['Pages']);
  final content = doc.getObject(4, 0) as CosStream;
  doc.decodeStreamData(content);
  final updater = CosIncrementalUpdater(doc)
    ..replaceObject(5, CosDictionary({'A': const CosInteger(1)}));
  return updater.save();
}

void main() {
  // NOTE: the disabled-contract group must run before anything enables
  // PdfPerf - the accumulators are allocated once per isolate and
  // [PdfPerf.debugInitialized] can never go back to false. Groups run in
  // declaration order; keep this one first.
  group('disabled path (zero-overhead contract)', () {
    late Uint8List disabledSave;

    test('a full workload never allocates recording state', () {
      expect(PdfPerf.enabled, isFalse);
      PdfPerf.sink = (line) => fail('sink invoked while disabled: $line');
      try {
        disabledSave = _workload();
        // Recovery path too - the event() calls must all be inert.
        final smashed = buildClassicPdf();
        final text = String.fromCharCodes(smashed)
            .replaceAll('startxref', '#########');
        CosDocument.open(
            Uint8List.fromList(text.codeUnits));
      } finally {
        PdfPerf.sink = null;
      }
      // The Stopwatch and accumulator lists live behind the same lazy init,
      // so this staying false proves no allocation and no clock read
      // happened anywhere in the workload.
      expect(PdfPerf.debugInitialized, isFalse);
      expect(PdfPerf.snapshot().isEmpty, isTrue);
    });

    test('begin() is 0 and end/add are inert while disabled', () {
      final t0 = PdfPerf.begin();
      expect(t0, 0);
      PdfPerf.end(PdfPerfPhase.docOpen, t0);
      PdfPerf.add(PdfPerfCount.objectsLoaded, 42);
      PdfPerf.event(PdfPerfEvent.xrefRecoveryTriggered);
      expect(PdfPerf.debugInitialized, isFalse);
      expect(PdfPerf.snapshot().isEmpty, isTrue);
    });

    test('enabling changes no observable output (byte-identical save)', () {
      PdfPerf.enabled = true;
      addTearDown(() {
        PdfPerf.enabled = false;
        PdfPerf.reset();
      });
      expect(_workload(), disabledSave);
    });
  });

  group('enabled path', () {
    setUp(() {
      PdfPerf.enabled = true;
      PdfPerf.reset();
    });
    tearDown(() {
      PdfPerf.sink = null;
      PdfPerf.enabled = false;
      PdfPerf.reset();
    });

    test('open + save populate phases and counters', () {
      _workload();
      final stats = PdfPerf.snapshot();
      expect(stats.phaseCallCount(PdfPerfPhase.docOpen), 1,
          reason: 'the workload opens exactly one document; a higher count '
              'means something re-opens behind the API');
      expect(stats.phaseCallCount(PdfPerfPhase.xrefParse), greaterThan(0));
      expect(stats.phaseCallCount(PdfPerfPhase.saveIncremental), 1);
      expect(stats.count(PdfPerfCount.objectsLoaded), greaterThan(0));
      expect(stats.count(PdfPerfCount.savedObjects), 1);
      expect(stats.count(PdfPerfCount.savedBytes), greaterThan(0));
      expect(stats.count(PdfPerfCount.xrefRecovered), 0);
    });

    test('per-filter decode attributes time and bytes', () {
      final payload = Uint8List.fromList(List.generate(4096, (i) => i % 7));
      final deflated =
          Uint8List.fromList(const ZLibEncoder().encodeBytes(payload));
      final stream = CosStream(
        CosDictionary({
          'Filter': const CosName('FlateDecode'),
          'Length': CosInteger(deflated.length),
        }),
        deflated,
      );
      final decoded = decodeStream(stream);
      expect(decoded, payload);
      final stats = PdfPerf.snapshot();
      expect(stats.count(PdfPerfCount.streamsDecoded), 1);
      expect(stats.phaseCallCount(PdfPerfPhase.flate), 1);
      expect(stats.count(PdfPerfCount.bytesDecodedFlate), payload.length);
    });

    test('object-stream indexing is counted', () {
      final doc = CosDocument.open(buildXrefStreamPdf());
      doc.resolve(doc.catalog['Pages']);
      final stats = PdfPerf.snapshot();
      expect(stats.count(PdfPerfCount.objectStreamsLoaded), greaterThan(0));
      expect(
          stats.phaseCallCount(PdfPerfPhase.objectStreamIndex), greaterThan(0));
    });

    test('xref recovery bumps the counter and reports the event', () {
      final lines = <String>[];
      PdfPerf.sink = lines.add;
      final text = String.fromCharCodes(buildClassicPdf())
          .replaceAll('startxref', '#########');
      final doc = CosDocument.open(Uint8List.fromList(text.codeUnits));
      expect(doc.catalog.typeName, 'Catalog');
      final stats = PdfPerf.snapshot();
      expect(stats.count(PdfPerfCount.xrefRecovered), 1);
      expect(stats.eventCount(PdfPerfEvent.xrefRecoveryTriggered), 1);
      expect(stats.phaseCallCount(PdfPerfPhase.xrefRecovery), 1);
      expect(lines, anyElement(contains('xrefRecoveryTriggered')));
    });

    test('content tokenization records ops and bytes', () {
      final doc = CosDocument.open(buildClassicPdf());
      final content = doc.getObject(4, 0) as CosStream;
      final ops = ContentStreamParser.parse(doc.decodeStreamData(content));
      final stats = PdfPerf.snapshot();
      expect(stats.phaseCallCount(PdfPerfPhase.contentTokenize), 1);
      expect(stats.count(PdfPerfCount.contentOps), ops.length);
      expect(stats.count(PdfPerfCount.contentBytes), greaterThan(0));
    });

    test('ranged source open counts requests and bytes', () async {
      final bytes = buildClassicPdf();
      final doc = await CosDocument.openSource(PdfBytesByteSource(bytes));
      expect(doc.catalog.typeName, 'Catalog');
      final stats = PdfPerf.snapshot();
      expect(stats.phaseCallCount(PdfPerfPhase.sourceFetch), 1);
      expect(stats.count(PdfPerfCount.rangeRequests), greaterThan(0));
      expect(stats.count(PdfPerfCount.rangeBytesFetched), greaterThan(0));
      expect(stats.count(PdfPerfCount.rangeBytesFetched),
          lessThanOrEqualTo(2 * bytes.length));
    });

    test('reset zeroes accumulators, snapshot copies are stable', () {
      CosDocument.open(buildClassicPdf());
      final before = PdfPerf.snapshot();
      expect(before.isEmpty, isFalse);
      PdfPerf.reset();
      expect(PdfPerf.snapshot().isEmpty, isTrue);
      // The earlier snapshot is an unaffected copy.
      expect(before.isEmpty, isFalse);
    });

    test('addInto aggregates and toJson/fromJson round-trips', () {
      CosDocument.open(buildClassicPdf());
      final one = PdfPerf.snapshot();
      final acc = PdfPerfStats.empty();
      one.addInto(acc);
      one.addInto(acc);
      expect(acc.count(PdfPerfCount.objectsLoaded),
          2 * one.count(PdfPerfCount.objectsLoaded));
      expect(acc.phaseCallCount(PdfPerfPhase.docOpen),
          2 * one.phaseCallCount(PdfPerfPhase.docOpen));

      final restored = PdfPerfStats.fromJson(one.toJson());
      expect(restored.counts, one.counts);
      expect(restored.phaseCalls, one.phaseCalls);
      expect(restored.phaseUs, one.phaseUs);
    });

    test('budget tripwires report exceedances', () {
      CosDocument.open(buildClassicPdf());
      final stats = PdfPerf.snapshot();
      const clean = PdfPerfBudget(
        maxCounts: {PdfPerfCount.xrefRecovered: 0},
      );
      expect(clean.exceedances(stats), isEmpty);
      const tight = PdfPerfBudget(
        maxCounts: {PdfPerfCount.objectsLoaded: 0},
        maxPhaseUs: {PdfPerfPhase.docOpen: -1},
      );
      final violations = tight.exceedances(stats);
      expect(violations, hasLength(2));
      expect(violations, anyElement(contains('objectsLoaded')));
    });

    test('format is report-time only and mentions recorded phases', () {
      CosDocument.open(buildClassicPdf());
      final text = PdfPerf.snapshot().format();
      expect(text, contains('docOpen'));
      expect(text, contains('objectsLoaded'));
    });
  });
}
