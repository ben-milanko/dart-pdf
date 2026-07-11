import 'package:dart_pdf_editor/src/render_worker_transcript_cache.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';

import 'strip_zoom_router_test.dart' show buildVectorPdf;

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
}
