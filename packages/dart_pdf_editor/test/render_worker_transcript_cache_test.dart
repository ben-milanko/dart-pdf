import 'dart:typed_data';

import 'package:dart_pdf_editor/src/render_worker_transcript_cache.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';

import 'strip_zoom_router_test.dart' show buildVectorPdf;

PdfDrawImageCommand? _firstImage(List<PdfRenderCommand> commands) {
  for (final command in commands) {
    if (command is PdfDrawImageCommand) return command;
    if (command is PdfEndSoftMaskedCommand) {
      final nested = _firstImage(command.maskCommands);
      if (nested != null) return nested;
    }
  }
  return null;
}

void main() {
  test('transcript cache hits, bounds entries, and reports eviction', () async {
    final document = PdfDocument.open(buildVectorPdf());
    final cache = PdfWorkerTranscriptCache(capacity: 1);
    final firstTimings = PdfWorkerPhaseTimings();
    final first = await cache.transcriptFor(
      document,
      0,
      true,
      PdfCancellationToken(),
      timings: firstTimings,
    );
    expect(firstTimings.transcriptHit, isFalse);
    expect(firstTimings.parseUs, greaterThanOrEqualTo(0));
    expect(firstTimings.interpretUs, greaterThanOrEqualTo(0));
    expect(firstTimings.streamUs, greaterThanOrEqualTo(0));
    expect(firstTimings.serializeUs, greaterThanOrEqualTo(0));
    final hitTimings = PdfWorkerPhaseTimings();
    final hit = await cache.transcriptFor(
      document,
      0,
      true,
      PdfCancellationToken(),
      timings: hitTimings,
    );
    expect(identical(hit, first), isTrue);
    expect(hitTimings.transcriptHit, isTrue);
    expect(hitTimings.parseUs, 0);
    expect(hitTimings.interpretUs, 0);
    expect(hitTimings.streamUs, 0);
    expect(hitTimings.serializeUs, 0);
    expect(cache.hits, 1);
    expect(cache.misses, 1);
    expect(cache.length, 1);
    expect(cache.retainedCommandCount, greaterThan(0));
    expect(identical(first!.sourceCommands, first.wireCommands), isTrue,
        reason: 'image-free wire commands are self-contained');
    expect(first.retainedCommandWeight,
        retainedCommandGraphWeight(first.wireCommands));

    await cache.transcriptFor(document, 0, false, PdfCancellationToken());
    expect(cache.length, 1);
    expect(cache.evictions, 1);
    expect(cache.misses, 2);

    final reloaded = await cache.transcriptFor(
      document,
      0,
      true,
      PdfCancellationToken(),
    );
    expect(identical(reloaded, first), isFalse);
    expect(cache.evictions, 2);
    expect(cache.misses, 3);
  });

  test(
      'transcriptFor streams progressive partials on a doubling schedule '
      '(#564 web twin core)', () async {
    // A dense linework page spans many chunks; the transcript walk (shared by the
    // web worker record path) emits interim linework prefixes on a doubling
    // schedule (chunks 1, 2, 4, ...), so the partial count is logarithmic in the
    // chunk count, each a strictly larger prefix buffer.
    final document =
        PdfDocument.open(buildSyntheticCadStrip(ops: 20000, streams: 2));
    // Pin a multi-chunk test cadence. The production chunk is deliberately
    // much larger (64K operations) after the CAD task-turn benchmark, so this
    // schedule unit test must not depend on that performance tuning constant.
    final cache = PdfWorkerTranscriptCache(
      capacity: 2,
      resumeChunkOperations: 4096,
    );
    final partials = <Uint8List>[];
    final transcript = await cache.transcriptFor(
      document,
      0,
      false,
      PdfCancellationToken(),
      onPartial: partials.add,
    );
    expect(transcript, isNotNull);
    expect(partials.length, greaterThanOrEqualTo(2));
    expect(partials.length, lessThanOrEqualTo(8),
        reason: 'doubling schedule keeps emits logarithmic, got '
            '${partials.length}');
    for (var i = 1; i < partials.length; i++) {
      expect(partials[i].length, greaterThan(partials[i - 1].length),
          reason: 'each partial buffer should be a larger prefix');
    }

    // A cache HIT does no walk, so it must not stream.
    final hitPartials = <Uint8List>[];
    final hit = await cache.transcriptFor(
      document,
      0,
      false,
      PdfCancellationToken(),
      onPartial: hitPartials.add,
    );
    expect(identical(hit, transcript), isTrue);
    expect(hitPartials, isEmpty,
        reason: 'a transcript cache hit does no walk and streams nothing');
  });

  test('cancelled transcript construction is not cached', () async {
    final document = PdfDocument.open(buildVectorPdf());
    final cache = PdfWorkerTranscriptCache();
    final token = PdfCancellationToken()..cancelled = true;
    await expectLater(
      cache.transcriptFor(document, 0, true, token),
      throwsA(isA<PdfCancelledException>()),
    );
    expect(cache.length, 0);
  });

  test('retained command weight evicts old entries but keeps one hot oversize',
      () async {
    final document = PdfDocument.open(buildVectorPdf());
    final cache = PdfWorkerTranscriptCache(
      capacity: 4,
      maxRetainedCommands: 1,
    );
    final first = await cache.transcriptFor(
      document,
      0,
      true,
      PdfCancellationToken(),
    );
    expect(cache.length, 1);
    expect(cache.retainedCommandWeight, greaterThan(1));

    await cache.transcriptFor(document, 0, false, PdfCancellationToken());
    expect(cache.length, 1,
        reason: 'the newly used oversize entry remains reusable');
    expect(cache.evictions, 1);

    final reloaded = await cache.transcriptFor(
      document,
      0,
      true,
      PdfCancellationToken(),
    );
    expect(identical(reloaded, first), isFalse);
    expect(cache.evictions, 2);
  });

  test('detail transcripts select the visible CAD command slice', () async {
    final document =
        PdfDocument.open(buildSyntheticCadStrip(ops: 6000, streams: 2));
    final cache = PdfWorkerTranscriptCache();
    final transcript = await cache.transcriptFor(
      document,
      0,
      true,
      PdfCancellationToken(),
    );
    expect(transcript, isNotNull);

    final full = transcript!.sourceCommands;
    final detail = transcript.commandsForDetail(
      const PdfRect(0, 0, 420, 841.89),
    );
    expect(detail, isNotEmpty);
    expect(detail.length, lessThan(full.length ~/ 2),
        reason: 'a 5%-wide viewport must not serialize and bin the other '
            '${full.length} CAD commands');
    expect(detail.whereType<PdfStrokePathCommand>(), isNotEmpty);

    final again = transcript.commandsForDetail(
      const PdfRect(8000, 0, 8503.939, 841.89),
    );
    expect(again, isNotEmpty,
        reason: 'the cached index must serve a distant pan too');
    expect(again.length, lessThan(full.length ~/ 2));
  });

  test('detail transcript keeps the full fallback for overprint state', () {
    final commands = <PdfRenderCommand>[
      const PdfSetOverprintCommand(fill: true, stroke: false, mode: 1),
      const PdfFillPathCommand(
        PdfPath([
          PdfMoveTo(10, 10),
          PdfLineTo(20, 10),
          PdfLineTo(20, 20),
          PdfClosePath(),
        ]),
        PdfColor.black,
        PdfFillRule.nonzero,
        1,
      ),
    ];
    final transcript = PdfWorkerTranscript(commands, commands);
    expect(
      transcript.commandsForDetail(const PdfRect(0, 0, 30, 30)),
      same(commands),
      reason: 'state the region index cannot snapshot must never be culled',
    );
  });

  test('image-bearing transcripts keep the document-backed source graph',
      () async {
    final bytes = PdfImageDocument.fromImageBytes([buildTestJpeg()]);
    final document = PdfDocument.open(bytes);
    final cache = PdfWorkerTranscriptCache();
    final transcript = await cache.transcriptFor(
      document,
      0,
      true,
      PdfCancellationToken(),
    );
    final baseline = await PdfWorkerTranscriptCache(
      deduplicateCommands: false,
    ).transcriptFor(
      document,
      0,
      true,
      PdfCancellationToken(),
    );

    expect(transcript, isNotNull);
    expect(
        identical(transcript!.sourceCommands, transcript.wireCommands), isFalse,
        reason: 'later detail decode still needs the original COS stream');
    final sourceImage = _firstImage(transcript.sourceCommands)!;
    final wireImage = _firstImage(transcript.wireCommands)!;
    expect(sourceImage.request.isInline, isFalse,
        reason: 'the compact source keeps the original XObject identity');
    expect(wireImage.request.isInline, isFalse,
        reason: 'an indirect wire image retains XObject semantics');
    expect(
      wireImage.request.sourceReference,
      document.cos.referenceTo(sourceImage.request.stream),
      reason: 'the detached wire graph identifies the document source',
    );
    expect(wireImage.request.stream.rawBytes, isEmpty,
        reason: 'the detached wire graph must not retain the JPEG payload');
    expect(sourceImage.request.transform, wireImage.request.transform,
        reason: 'source replay keeps the exact float32 wire geometry');
    final compactBytes = serializeCommands(
      transcript.sourceCommands,
      cos: document.cos,
      decodeImages: false,
      compactStateScopes: true,
    );
    final baselineBytes = serializeCommands(
      baseline!.sourceCommands,
      cos: document.cos,
      decodeImages: false,
      compactStateScopes: true,
    );
    expect(compactBytes, baselineBytes,
        reason: 'hybrid image source must serialize byte-identically');
    expect(
      transcript.retainedCommandWeight,
      lessThanOrEqualTo(retainedCommandGraphWeight(transcript.sourceCommands) +
          retainedCommandGraphWeight(transcript.wireCommands)),
      reason: 'compact views never retain more commands than separate graphs',
    );
  });

  test('deduplication remains switchable for the benchmark A/B', () async {
    final document = PdfDocument.open(buildVectorPdf());
    final baseline = await PdfWorkerTranscriptCache(
      deduplicateCommands: false,
    ).transcriptFor(
      document,
      0,
      true,
      PdfCancellationToken(),
    );
    final optimized = await PdfWorkerTranscriptCache().transcriptFor(
      document,
      0,
      true,
      PdfCancellationToken(),
    );

    expect(identical(baseline!.sourceCommands, baseline.wireCommands), isFalse);
    expect(optimized!.retainedCommandWeight,
        lessThan(baseline.retainedCommandWeight));
  });

  test('evictPages drops the named pages and keeps the rest warm', () async {
    final document = PdfDocument.open(buildMultiPagePdf(2));
    final cache = PdfWorkerTranscriptCache(capacity: 4);
    await cache.transcriptFor(document, 0, true, PdfCancellationToken());
    await cache.transcriptFor(document, 1, true, PdfCancellationToken());
    expect(cache.length, 2);

    // Edit page 0: its transcript is stale, page 1's stays warm.
    cache.evictPages({0});
    expect(cache.length, 1);

    final keptTimings = PdfWorkerPhaseTimings();
    await cache.transcriptFor(
      document,
      1,
      true,
      PdfCancellationToken(),
      timings: keptTimings,
    );
    expect(keptTimings.transcriptHit, isTrue,
        reason: 'the unedited page survived');

    final droppedTimings = PdfWorkerPhaseTimings();
    await cache.transcriptFor(
      document,
      0,
      true,
      PdfCancellationToken(),
      timings: droppedTimings,
    );
    expect(droppedTimings.transcriptHit, isFalse,
        reason: 'the edited page was dropped');
  });

  test('evictPages(null) clears every transcript', () async {
    final document = PdfDocument.open(buildMultiPagePdf(2));
    final cache = PdfWorkerTranscriptCache(capacity: 4);
    await cache.transcriptFor(document, 0, true, PdfCancellationToken());
    await cache.transcriptFor(document, 1, true, PdfCancellationToken());
    expect(cache.length, 2);
    cache.evictPages(null);
    expect(cache.length, 0);
  });

  // A record preempted mid-walk keeps its partial and resumes on the requeue,
  // producing exactly the transcript a one-shot record would (#530, the web twin
  // of the isolate worker's resume - see resume_record_test.dart for the walk
  // composition proof).
  test('a preempted record resumes instead of restarting (#530)', () async {
    final document = PdfDocument.open(buildVectorPdf());

    // One-shot reference: a normal, un-preempted record.
    final reference = await PdfWorkerTranscriptCache(deduplicateCommands: false)
        .transcriptFor(document, 0, false, PdfCancellationToken());
    expect(reference, isNotNull);

    // A tiny chunk so buildVectorPdf's several ops span multiple chunks; the walk
    // yields at each 2-op boundary, handing control back before the between-chunk
    // cancel check so the cancel below lands deterministically.
    final cache = PdfWorkerTranscriptCache(
        deduplicateCommands: false, resumeChunkOperations: 2);
    final token = PdfCancellationToken();
    final preempted =
        cache.transcriptFor(document, 0, false, token, yieldInterval: 2);
    token.cancelled = true; // trips the first between-chunk check -> suspend
    await expectLater(preempted, throwsA(isA<PdfCancelledException>()));

    // Resume: a fresh token, same page - continues from the cursor to completion.
    final resumed =
        await cache.transcriptFor(document, 0, false, PdfCancellationToken());
    expect(resumed, isNotNull);

    Uint8List? wire(List<PdfRenderCommand> commands) => serializeCommands(
          commands,
          cos: document.cos,
          decodeImages: false,
          imagePlaceholders: true,
          compactStateScopes: true,
        );
    expect(
        wire(resumed!.sourceCommands), equals(wire(reference!.sourceCommands)),
        reason: 'resuming must reproduce the one-shot transcript exactly');

    // A resumed record is cached like any completed one: the next request hits.
    final hit =
        await cache.transcriptFor(document, 0, false, PdfCancellationToken());
    expect(identical(hit, resumed), isTrue,
        reason: 'the resumed transcript must be cached, not re-recorded');
  });

  test('a revision update evicts a suspended record (#530)', () async {
    final document = PdfDocument.open(buildVectorPdf());
    final cache = PdfWorkerTranscriptCache(
        deduplicateCommands: false, resumeChunkOperations: 2);
    final token = PdfCancellationToken();
    final preempted =
        cache.transcriptFor(document, 0, false, token, yieldInterval: 2);
    token.cancelled = true;
    await expectLater(preempted, throwsA(isA<PdfCancelledException>()));

    // The edit drops the suspended page's partial; the next record starts fresh
    // and still completes to a valid transcript.
    cache.evictPages({0});
    final fresh =
        await cache.transcriptFor(document, 0, false, PdfCancellationToken());
    expect(fresh, isNotNull);
  });
}
