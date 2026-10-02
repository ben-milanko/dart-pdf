import 'dart:typed_data';

import 'package:dart_pdf_editor/src/render_worker_transcript_cache.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_cos/pdf_cos.dart';
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

List<PdfDrawTiledCellCommand> _stamps(List<PdfRenderCommand> commands) =>
    commands.whereType<PdfDrawTiledCellCommand>().toList();

/// A page of five occurrences of one Type3 bitmap glyph - a 1-bit inline
/// ImageMask, the TeX PK font shape - which the interpreter stamps as five
/// tiled cells sharing one recorded list.
Uint8List _type3BitmapPdf() {
  const glyph = '600 0 0 0 600 700 d1 600 0 0 700 0 0 cm '
      'BI /W 4 /H 4 /IM true /BPC 1 /F /AHx ID\nf0f0f0f0 >\nEI';
  const content = 'BT /T3 10 Tf 20 100 Td (XXXXX) Tj ET';
  final objects = <String>[
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] '
        '/Resources << /Font << /T3 5 0 R >> >> /Contents 4 0 R >>',
    '<< /Length ${content.length} >>\nstream\n$content\nendstream',
    '<< /Type /Font /Subtype /Type3 /FontBBox [0 0 600 700] '
        '/FontMatrix [0.001 0 0 0.001 0 0] /FirstChar 88 /LastChar 88 '
        '/Widths [600] /Encoding << /Differences [88 /X] >> '
        '/CharProcs << /X 6 0 R >> >>',
    '<< /Length ${glyph.length} >>\nstream\n$glyph\nendstream',
  ];
  final buffer = StringBuffer('%PDF-1.4\n');
  final offsets = <int>[];
  for (var i = 0; i < objects.length; i++) {
    offsets.add(buffer.length);
    buffer.write('${i + 1} 0 obj\n${objects[i]}\nendobj\n');
  }
  final xref = buffer.length;
  buffer.write('xref\n0 ${objects.length + 1}\n0000000000 65535 f \n');
  for (final offset in offsets) {
    buffer.write('${offset.toString().padLeft(10, '0')} 00000 n \n');
  }
  buffer.write('trailer << /Size ${objects.length + 1} /Root 1 0 R >>\n'
      'startxref\n$xref\n%%EOF\n');
  return Uint8List.fromList(buffer.toString().codeUnits);
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

  test('a shared tiled cell patches once and keeps its image alignment', () {
    // The recorder lists a cell's images again for every stamp, the codec
    // (v11) keeps one wire list per cell. Patching must hand every stamp the
    // one patched list and still step through the per-stamp image entries.
    CosStream stream(int id) => CosStream(
        CosDictionary({'Id': CosInteger(id)}), Uint8List.fromList([id]));
    PdfImageRequest request(CosStream s, [double x = 0]) => PdfImageRequest(
        stream: s,
        transform: PdfMatrix(4, 0, 0, 4, x, 0),
        isInline: true,
        isStencil: true);
    final top = request(stream(1));
    final glyphA = request(stream(2));
    final glyphB = request(stream(3));
    final last = request(stream(4));
    PdfDrawImageCommand wire(PdfImageRequest r) => PdfDrawImageCommand(
        request(CosStream(CosDictionary(), Uint8List(0)), r.transform.e));
    final wireCell = <PdfRenderCommand>[
      wire(glyphA),
      const PdfSaveCommand(),
      wire(glyphB),
      const PdfRestoreCommand(),
    ];
    PdfDrawTiledCellCommand stamp(double x) => PdfDrawTiledCellCommand(
        wireCell, Float64List.fromList([x]), Float64List.fromList([0]));
    final wireCommands = <PdfRenderCommand>[
      wire(top),
      stamp(0),
      stamp(6),
      stamp(12),
      wire(last),
    ];
    final originals = [
      top,
      glyphA, glyphB, //
      glyphA, glyphB, //
      glyphA, glyphB, //
      last,
    ];

    final patched = compactTranscriptSourceCommands(wireCommands, originals)!;
    final stamps = _stamps(patched);
    expect(stamps, hasLength(3));
    final cell = stamps.first.cellCommands;
    expect(identical(cell, wireCell), isFalse, reason: 'its images patched');
    for (final s in stamps) {
      expect(identical(s.cellCommands, cell), isTrue,
          reason: 'every stamp shares the one patched cell');
    }
    expect(stamps.map((s) => s.originsX.single), [0, 6, 12]);
    final cellImages = cell.whereType<PdfDrawImageCommand>().toList();
    expect(identical(cellImages[0].request.stream, glyphA.stream), isTrue);
    expect(identical(cellImages[1].request.stream, glyphB.stream), isTrue);
    expect(
        identical(
            (patched.first as PdfDrawImageCommand).request.stream, top.stream),
        isTrue);
    expect(
        identical(
            (patched.last as PdfDrawImageCommand).request.stream, last.stream),
        isTrue,
        reason: 'the images after the stamps still line up');

    // A later stamp whose recorded images are not the first stamp's cannot
    // share its patched list; the caller falls back to the source graph.
    final diverged = [...originals]..[5] = request(stream(2));
    expect(compactTranscriptSourceCommands(wireCommands, diverged), isNull);
  });

  test('a Type3 bitmap glyph keeps one cell through the worker transcript',
      () async {
    // The web worker (and a native detail record) serializes from the
    // transcript's source commands, not from the recording: the cell's
    // identity has to survive the image patch or every stamp ships its own
    // copy of the glyph again.
    final document = PdfDocument.open(_type3BitmapPdf());
    final transcript = await PdfWorkerTranscriptCache()
        .transcriptFor(document, 0, false, PdfCancellationToken());
    expect(transcript, isNotNull);
    final stamps = _stamps(transcript!.sourceCommands);
    expect(stamps, hasLength(5));
    for (final s in stamps) {
      expect(identical(s.cellCommands, stamps.first.cellCommands), isTrue,
          reason: 'the image-bearing glyph cell stays shared');
    }
    final glyph = _firstImage(stamps.first.cellCommands)!.request;
    expect(glyph.isStencil, isTrue);
    expect(glyph.stream.rawBytes, isNotEmpty,
        reason: 'the source graph holds the real inline image, not the '
            'wire placeholder');
    expect(_stamps(transcript.wireCommands).first.cellCommands,
        isNot(same(stamps.first.cellCommands)));

    // Serialized as the web worker does, it is the same record the native
    // worker makes straight from the recording.
    final recorder = RecordingPdfDevice();
    PdfInterpreter(
            cos: document.cos, device: recorder, collectCharOffsets: true)
        .drawPage(document.page(0));
    Uint8List record(List<PdfRenderCommand> commands) =>
        serializeCommands(commands,
            cos: document.cos,
            decodeImages: true,
            maxImagePixelRatio: 2,
            compactStateScopes: true)!;
    final bytes = record(transcript.sourceCommands);
    expect(bytes, record(recorder.commands));
    final restored = _stamps(deserializeCommands(bytes));
    expect(restored.map((s) => s.cellCommands).toSet(), hasLength(1));
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

  test('trimRetained drops the command graphs and keeps the text cache',
      () async {
    final document = PdfDocument.open(buildMultiPagePdf(2));
    final cache = PdfWorkerTranscriptCache(capacity: 4);
    await cache.transcriptFor(document, 0, true, PdfCancellationToken());
    await cache.transcriptFor(document, 1, true, PdfCancellationToken());
    expect(cache.length, 2);
    final text = cache.textCache.length;
    expect(text, greaterThan(0));

    // The web worker's memory-pressure trim.
    cache.trimRetained();
    expect(cache.length, 0);
    expect(cache.retainedCommandWeight, 0);
    expect(cache.textCache.length, text,
        reason: 'search and selection keep their extracted text');

    final timings = PdfWorkerPhaseTimings();
    final again = await cache.transcriptFor(
        document, 0, true, PdfCancellationToken(),
        timings: timings);
    expect(timings.transcriptHit, isFalse);
    expect(again, isNotNull, reason: 'a trimmed page records again');
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
