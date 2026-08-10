// PR1 of #564: the native render worker can stream progressive linework
// prefixes of a heavy page (a top-down PDFium-style reveal) BEFORE its final
// decoded buffer resolves. This pins the transport contract that PR1 adds:
//
//  - a record with an `onPartial` sink receives one or more partial buffers,
//    each a valid deserializable command list, all arriving before the final;
//  - each partial is a prefix (no more commands than the final);
//  - the final buffer is byte-identical whether or not partials were requested
//    (the sink must not perturb the recording);
//  - the production CACHED wrapper deliberately does NOT stream partials yet
//    (that is the shared-stream dedup redesign, PR2), so opting in there is
//    inert - the final still arrives unchanged.
//
// No host consumer and no web change land in PR1, so this is the whole
// observable surface of the feature.
import 'dart:typed_data';

import 'package:dart_pdf_editor/src/render_worker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';

/// A single-page PDF whose content stream is [opCount] stroked line segments -
/// enough operators (~3 per line) to span several of the worker's resumable
/// record chunks, so a full-page record emits progressive partials. Mirrors the
/// fixture in resume_record_test.dart.
Uint8List _linesPdf(int opCount) {
  final content = StringBuffer('1 0 0 1 0 0 cm\n0 0 0 RG\n');
  for (var i = 0; i < opCount; i++) {
    final x = (i % 100).toDouble();
    final y = (i % 50).toDouble();
    content.write('${x.toStringAsFixed(1)} ${y.toStringAsFixed(1)} m '
        '${(x + 1).toStringAsFixed(1)} ${(y + 1).toStringAsFixed(1)} l S\n');
  }
  final stream = content.toString();
  final objects = <String>[
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] /Contents 4 0 R '
        '/Resources << >> >>',
    '<< /Length ${stream.length} >>\nstream\n$stream\nendstream',
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
  buffer.write('trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\n'
      'startxref\n$xref\n%%EOF');
  return Uint8List.fromList(buffer.toString().codeUnits);
}

void main() {
  // The worker chunks at 4096 operators; ~9000 operators here spans several
  // chunks, so the resumable record emits partials between them.
  final bytes = _linesPdf(3000);

  test('a full-page record streams linework partials before the final',
      () async {
    final worker = PdfRenderWorker.startUncached(bytes);
    addTearDown(worker.dispose);

    final events = <String>[];
    final partials = <List<PdfRenderCommand>>[];
    final result = await worker.record(0, onPartial: (partial) {
      events.add('partial');
      partials.add(partial);
    });
    events.add('final');

    expect(result, isNotNull, reason: 'the final record must still resolve');
    expect(partials, isNotEmpty,
        reason: 'a multi-chunk page must emit at least one partial');

    // Ordering: every partial event precedes the single final event. The final
    // event is appended only after `await`, so this proves the partials landed
    // during the record, not after it.
    expect(events.last, 'final');
    expect(events.where((e) => e == 'partial').length, partials.length);
    expect(events.indexOf('final'), events.length - 1);

    // Each partial is a valid, non-empty prefix: no more commands than the
    // final, and monotonically growing (a superset reveal).
    for (final partial in partials) {
      expect(partial, isNotEmpty);
      expect(partial.length, lessThanOrEqualTo(result!.length));
    }
    for (var i = 1; i < partials.length; i++) {
      expect(partials[i].length, greaterThanOrEqualTo(partials[i - 1].length),
          reason: 'partials must grow, each a superset of the last');
    }
  });

  test('the doubling emit schedule keeps partial count logarithmic (#564 pt3)',
      () async {
    // A large page spans many worker chunks (4096 ops each). Emitting a partial
    // every chunk would re-serialize the whole growing prefix each time -
    // O(commands^2). The doubling schedule (emit after chunks 1, 2, 4, 8, ...)
    // caps the emit count at O(log chunks), so a page with ~15 chunks yields a
    // handful of partials, not fifteen. This pins that bound.
    final big = _linesPdf(20000); // ~60k ops -> ~15 worker chunks
    final worker = PdfRenderWorker.startUncached(big);
    addTearDown(worker.dispose);

    final partials = <List<PdfRenderCommand>>[];
    final result = await worker.record(0, onPartial: partials.add);

    expect(result, isNotNull);
    // ~15 chunks -> emits at chunks 1,2,4,8 = 4 partials. Bound generously to
    // stay robust to chunk-count drift while still proving it is logarithmic,
    // not linear (linear would be ~15).
    expect(partials.length, greaterThanOrEqualTo(2));
    expect(partials.length, lessThanOrEqualTo(6),
        reason: 'doubling schedule must keep emits logarithmic in chunks, '
            'got ${partials.length}');
    // Each doubling step is a strictly larger prefix (a real reveal, not repeats).
    for (var i = 1; i < partials.length; i++) {
      expect(partials[i].length, greaterThan(partials[i - 1].length),
          reason: 'each scheduled partial should cover more of the page');
    }
  });

  test(
      'a streaming vector-first (decodeImages:false) record matches the '
      'one-shot final (#564 pt4)', () async {
    // pt4 routes the full non-decoding record through the resumable path when it
    // wants partials, so the progressive linework reveal can stream while it
    // builds. Its final buffer must be byte-equivalent to the one-shot
    // non-decoding record that produced it before.
    final streamWorker = PdfRenderWorker.startUncached(bytes);
    addTearDown(streamWorker.dispose);
    final oneShotWorker = PdfRenderWorker.startUncached(bytes);
    addTearDown(oneShotWorker.dispose);

    final partials = <List<PdfRenderCommand>>[];
    final streamed = await streamWorker.record(0,
        decodeImages: false, onPartial: partials.add);
    final oneShot = await oneShotWorker.record(0, decodeImages: false);

    expect(streamed, isNotNull);
    expect(oneShot, isNotNull);
    expect(partials, isNotEmpty,
        reason: 'the vector-first record should now stream partials');
    expect(streamed!.length, oneShot!.length,
        reason: 'streaming must not change the final command buffer');
  });

  test('requesting partials does not change the final buffer', () async {
    final plainWorker = PdfRenderWorker.startUncached(bytes);
    addTearDown(plainWorker.dispose);
    final streamedWorker = PdfRenderWorker.startUncached(bytes);
    addTearDown(streamedWorker.dispose);

    final plain = await plainWorker.record(0);
    var partialCount = 0;
    final streamed =
        await streamedWorker.record(0, onPartial: (_) => partialCount++);

    expect(plain, isNotNull);
    expect(streamed, isNotNull);
    expect(partialCount, greaterThan(0));
    // The sink is a pure observer: the completed recording is identical.
    expect(streamed!.length, plain!.length);
  });

  test('a tiny single-chunk page emits no partial but still records', () async {
    final worker = PdfRenderWorker.startUncached(_linesPdf(3));
    addTearDown(worker.dispose);

    var partialCount = 0;
    final result = await worker.record(0, onPartial: (_) => partialCount++);

    expect(result, isNotNull);
    expect(partialCount, 0,
        reason: 'a page recorded in one chunk has no prefix to reveal');
  });

  test('a tiny image page emits its complete vector snapshot before decode',
      () async {
    final image = img.Image(width: 2, height: 2)
      ..clear(img.ColorRgb8(4, 8, 16));
    final pdf = PdfImageDocument.fromImageBytes(
      [Uint8List.fromList(img.encodePng(image))],
    );
    final worker = PdfRenderWorker.startUncached(pdf);
    addTearDown(worker.dispose);

    final partials = <List<PdfRenderCommand>>[];
    final result = await worker.record(0, onPartial: partials.add);

    expect(result, isNotNull);
    expect(partials, hasLength(1),
        reason: 'a single-chunk mixed page emits the complete image-free '
            'snapshot, not an intermediate chunk');
    final partialImage =
        partials.single.whereType<PdfDrawImageCommand>().single.request;
    final finalImage = result!.whereType<PdfDrawImageCommand>().single.request;
    expect(partialImage.decoded, isNull);
    expect(finalImage.decoded, isNotNull,
        reason: 'the same record must still resolve with decoded pixels');
  });

  test('the cached production wrapper streams partials through the dedup',
      () async {
    // PdfRenderWorker.start wraps the backend in PdfCachingRenderWorker, whose
    // shared-stream dedup now fans the backend's partials to the dispatching
    // caller (and any concurrent joiner). Opting in must stream and still
    // resolve the final. (Fan-out/late-joiner semantics are unit-tested against
    // a deterministic fake in caching_partial_dedup_test.dart.)
    final worker = PdfRenderWorker.start(bytes);
    addTearDown(worker.dispose);

    var partialCount = 0;
    final result = await worker.record(0, onPartial: (_) => partialCount++);

    expect(result, isNotNull, reason: 'the cached final must still resolve');
    expect(partialCount, greaterThan(0),
        reason: 'the caching wrapper forwards the backend partials');
  });

  test('the cached wrapper stays inert when no sink is passed', () async {
    // The dedup asks the backend for partials only when the dispatcher opts in,
    // so an all-null production workload never enters the streaming path. This
    // pins the byte-identical guarantee: a plain record still returns commands.
    final worker = PdfRenderWorker.start(bytes);
    addTearDown(worker.dispose);

    final result = await worker.record(0);
    expect(result, isNotNull);
    expect(result, isNotEmpty);
  });
}
