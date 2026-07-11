import 'dart:io';
import 'dart:typed_data';

import 'package:dart_pdf_editor/src/render_worker_transcript_cache.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';

void main() {
  const fixtures = [
    'rotation.pdf',
    'xobject-image.pdf',
    'images_1bit_grayscale.pdf',
    'gradientfill.pdf',
    'tiling-pattern-box.pdf',
    'blendmode.pdf',
    'smask_alpha_bc.pdf',
    'knockout_smask.pdf',
  ];

  test('compact transcripts serialize byte-identically across PDF.js fixtures',
      () async {
    var strictlyReduced = 0;
    for (final name in fixtures) {
      final document = PdfDocument.open(
        File('../../test_corpora/pdfjs/$name').readAsBytesSync(),
      );
      final baseline = await PdfWorkerTranscriptCache(
        deduplicateCommands: false,
      ).transcriptFor(
        document,
        0,
        true,
        PdfCancellationToken(),
      );
      final compact = await PdfWorkerTranscriptCache().transcriptFor(
        document,
        0,
        true,
        PdfCancellationToken(),
      );
      expect(baseline, isNotNull, reason: name);
      expect(compact, isNotNull, reason: name);

      Uint8List? serialize(PdfWorkerTranscript transcript) => serializeCommands(
            transcript.sourceCommands,
            cos: document.cos,
            decodeImages: false,
            imagePlaceholders: true,
            compactStateScopes: true,
          );

      expect(serialize(compact!), serialize(baseline!), reason: name);
      expect(compact.retainedCommandWeight,
          lessThanOrEqualTo(baseline.retainedCommandWeight),
          reason: name);
      if (compact.retainedCommandWeight < baseline.retainedCommandWeight) {
        strictlyReduced++;
      }
    }
    expect(strictlyReduced, greaterThanOrEqualTo(6));
  });
}
