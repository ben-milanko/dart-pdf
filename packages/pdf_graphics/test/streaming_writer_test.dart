// PdfStreamingCommandWriter writes, as the walk runs, the exact bytes
// serializeCommands(compactStateScopes: true, imagePlaceholders: true) writes
// from a RecordingPdfDevice transcript of the same walk - for the whole page
// and for every chunk-boundary prefix - and hands back the same images and
// the same text capture.
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';
import 'package:test/test.dart';

/// Walks [pageIndex] twice in lockstep - into a recorder and into a streaming
/// writer - in chunks of [chunk] operations, comparing at every boundary.
Future<int> _expectStreamEqualsRecord(
    PdfDocument document, int pageIndex, int chunk) async {
  final page = document.page(pageIndex);
  final recorder = RecordingPdfDevice();
  final writer = PdfStreamingCommandWriter(cos: document.cos);
  final recording = PdfInterpreter(
      cos: document.cos, device: recorder, collectCharOffsets: true);
  final streaming = PdfInterpreter(
      cos: document.cos, device: writer, collectCharOffsets: true);
  final a = recording.beginPageContent(page, page.contentBytes());
  final b = streaming.beginPageContent(page, page.contentBytes());

  Uint8List expected() => serializeCommands(recorder.commands,
      cos: document.cos, imagePlaceholders: true, compactStateScopes: true)!;

  var boundaries = 0;
  while (true) {
    final doneA = await a.advance(operations: chunk);
    final doneB = await b.advance(operations: chunk);
    expect(doneB, doneA);
    if (doneA) break;
    boundaries++;
    // On the worker's doubling schedule (1, 2, 4, ... chunks), so a dense
    // page is not re-serialized per chunk.
    if (boundaries & (boundaries - 1) != 0) continue;
    expect(writer.snapshot(), expected(),
        reason: 'page $pageIndex: the prefix after $boundaries chunks');
  }
  // What the worker captures as page text: top-level text and cells, closed
  // before annotations.
  final text = writer.takeTextCommands();
  expect(
      serializePageText(PdfTextExtractor.fromRecordedText(
          PdfRecordedText.capture(text), pageIndex)),
      serializePageText(PdfTextExtractor.fromRecordedText(
          PdfRecordedText.capture(recorder.commands), pageIndex)),
      reason: 'page $pageIndex: text capture');
  recording.drawAnnotations(page);
  streaming.drawAnnotations(page);
  expect(writer.snapshot(), expected(), reason: 'page $pageIndex: full');
  expect(writer.commandCount, deserializeCommands(expected()).length);
  expect(writer.imageRequests.length, recorder.imageRequests.length);
  for (var i = 0; i < recorder.imageRequests.length; i++) {
    final want = recorder.imageRequests[i], got = writer.imageRequests[i];
    // An inline image is parsed afresh by each walk; the rest are the
    // document's own stream objects.
    expect(
        identical(got.stream, want.stream) ||
            (got.isInline &&
                want.isInline &&
                _sameBytes(got.stream.rawBytes, want.stream.rawBytes)),
        isTrue,
        reason: 'page $pageIndex: image $i in recorder order');
    expect(got.transform, want.transform);
  }
  return boundaries;
}

bool _sameBytes(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

void main() {
  // Groups, knockout, soft masks (vector, text, image), tiling patterns,
  // Type3 cells, raster underlays and dense linework.
  const files = [
    'ghent/1-CMYK/GWG160_Transp_Basic_BM_DeviceCMYK_Non-knockout_X4.pdf',
    'ghent/1-CMYK/GWG161_Transp_Basic_BM_DeviceCMYK_Knockout_X4.pdf',
    'ghent/1-CMYK/GWG1610_Softmasks_Text_part1_X4.pdf',
    'ghent/1-CMYK/GWG166_Softmasks_Images_DeviceCMYK_X4.pdf',
    'ghent/1-CMYK/GWG168_Softmasks_Vector_part1_X4.pdf',
    'ghent/1-CMYK/Ghent_PDF-Output-Test-V50_CMYK_X4.pdf',
    'pdfjs/knockout_isolated_overlap.pdf',
    'pdfjs/knockout_smask.pdf',
    'pdfjs/smask_alpha_bc.pdf',
    'pdfjs/tiling_patterns_variations.pdf',
    'pdfjs/ContentStreamNoCycleType3insideType3.pdf',
    'dartpdf/type3-text-6p.pdf',
    'dartpdf/hatch-sections-4p.pdf',
    'dartpdf/raster-underlay-1p.pdf',
    'dartpdf/diagram-dense-3p.pdf',
    'dartpdf/annotated-10p.pdf',
  ];

  var partialsCompared = 0;
  for (final name in files) {
    final file = File('../../test_corpora/$name');
    test('streamed bytes equal the compacted record: $name', () async {
      final document = PdfDocument.open(file.readAsBytesSync());
      for (var p = 0; p < math.min(3, document.pageCount); p++) {
        // Some of these pages are a single form XObject at the top level,
        // so only the full buffer is compared there.
        partialsCompared += await _expectStreamEqualsRecord(document, p, 4);
      }
    }, skip: file.existsSync() ? false : 'checked-in corpus unavailable');
  }

  test('the corpus pages compared partials too', () {
    expect(partialsCompared, greaterThan(0));
  },
      skip: File('../../test_corpora/dartpdf/diagram-dense-3p.pdf').existsSync()
          ? false
          : 'checked-in corpus unavailable');

  test('a soft mask streams into its own frame and count', () async {
    final writer = PdfStreamingCommandWriter();
    const box = PdfPath([
      PdfMoveTo(0, 0),
      PdfLineTo(1, 0),
      PdfLineTo(1, 1),
      PdfClosePath(),
    ]);
    final commands = <PdfRenderCommand>[];
    // The same calls into both a recorder and the writer.
    void drive(PdfDevice device) {
      device.save(); // pending when the mask opens: written before it
      device.beginSoftMasked();
      device.fillPath(box, PdfColor.black, PdfFillRule.nonzero, 1);
      device.endSoftMasked(
        luminosity: true,
        backdrop: const PdfRect(0, 0, 1, 1),
        drawMask: () {
          device.save(); // the mask's own frame: clip-free, dropped
          device.fillPath(box, PdfColor(1, 1, 1), PdfFillRule.nonzero, 1);
          device.restore();
          device.save(); // clipped, kept
          device.clipPath(box, PdfFillRule.evenOdd);
          device.fillPath(box, PdfColor(1, 1, 1), PdfFillRule.nonzero, 1);
          device.restore();
        },
      );
      device.restore();
    }

    final recorder = RecordingPdfDevice();
    drive(recorder);
    drive(writer);
    commands.addAll(recorder.commands);
    final expected = serializeCommands(commands, compactStateScopes: true)!;
    expect(writer.snapshot(), expected);
    final restored = deserializeCommands(expected);
    expect(restored.map((c) => c.runtimeType), [
      PdfSaveCommand,
      PdfBeginSoftMaskedCommand,
      PdfFillPathCommand,
      PdfEndSoftMaskedCommand,
      PdfRestoreCommand,
    ]);
    expect(
        (restored[3] as PdfEndSoftMaskedCommand)
            .maskCommands
            .map((c) => c.runtimeType),
        [
          PdfFillPathCommand,
          PdfSaveCommand,
          PdfClipPathCommand,
          PdfFillPathCommand,
          PdfRestoreCommand,
        ]);
    expect(writer.commandCount, 5);
  });

  // A finished writer hands its buffer to the next one, so records are
  // written into memory that still holds an earlier record's bytes. Nothing
  // of the earlier record may show through, and a writer that has given its
  // buffer away must not be able to write into it.
  group('writers reuse one buffer', () {
    PdfPath zigzag(int seed, int points) => PdfPath([
          PdfMoveTo(seed * 1.5, seed * 0.25),
          for (var i = 1; i < points; i++)
            PdfLineTo(seed * 1.5 + i * 3.25, (i * seed) % 97 + 0.125),
        ]);
    List<PdfRenderCommand> drawing(int seed, int paths) => [
          for (var i = 0; i < paths; i++) ...[
            const PdfSaveCommand(),
            PdfFillPathCommand(zigzag(seed + i, 3 + (seed + i) % 9),
                PdfColor(i % 2, seed % 2, 0.5), PdfFillRule.nonzero, 1),
            PdfDrawTextCommand(PdfTextRun(
              text: 'run $seed/$i',
              transform: PdfMatrix(9, 0, 0, 9, i * 4.0, seed * 2.0),
              color: PdfColor.black,
              width: 4.5,
              fontName: 'F$seed',
            )),
            const PdfRestoreCommand(),
          ],
        ];
    void feed(PdfDevice device, List<PdfRenderCommand> commands) =>
        replayCommands(commands, device);

    test('a record is the same bytes whatever was written before it', () {
      final small = drawing(3, 40);
      final large = drawing(11, 6000); // grows the buffer well past 64 KB
      final other = drawing(29, 900);

      final first = serializeCommands(small)!;
      expect(serializeCommands(large)!.length, greaterThan(1 << 18));
      expect(serializeCommands(small), first,
          reason: 'after a much larger record');
      serializeCommands(other, compactStateScopes: true);
      expect(serializeCommands(small), first,
          reason: 'after a different record of a different size');
      expect(_transcriptOf(deserializeCommands(serializeCommands(small)!)),
          _transcriptOf(small));
    });

    test('finish is the last snapshot, and spends the writer', () {
      final commands = drawing(5, 300);
      final expected = serializeCommands(commands,
          imagePlaceholders: true, compactStateScopes: true)!;

      final writer = PdfStreamingCommandWriter();
      feed(writer, commands);
      final partial = writer.snapshot();
      expect(writer.length, expected.length);
      final finished = writer.finish();
      expect(finished, expected);
      expect(partial, expected, reason: 'a snapshot is a copy of its own');
      expect(writer.length, 0);
      expect(writer.commandCount, greaterThan(0));
    });

    test('a spent writer cannot write into the next record', () {
      final commands = drawing(7, 200);
      final spent = PdfStreamingCommandWriter();
      feed(spent, commands);
      spent.finish();

      // The next record now owns the buffer `spent` wrote into.
      final next = PdfStreamingCommandWriter();
      feed(next, drawing(13, 150));
      final expected = serializeCommands(drawing(13, 150),
          imagePlaceholders: true, compactStateScopes: true)!;
      // A stray draw into the spent writer lands in a buffer of its own.
      feed(spent, drawing(17, 500));
      expect(next.finish(), expected);
    });

    test('two open writers do not share a buffer', () {
      final a = PdfStreamingCommandWriter();
      final b = PdfStreamingCommandWriter();
      feed(a, drawing(2, 120));
      feed(b, drawing(4, 80));
      feed(a, drawing(6, 40));
      final expectA = serializeCommands([...drawing(2, 120), ...drawing(6, 40)],
          imagePlaceholders: true, compactStateScopes: true)!;
      final expectB = serializeCommands(drawing(4, 80),
          imagePlaceholders: true, compactStateScopes: true)!;
      expect(a.finish(), expectA);
      expect(b.finish(), expectB);
    });

    test('a record larger than the kept buffer still round-trips', () {
      final huge = drawing(19, 60000);
      final bytes = serializeCommands(huge)!;
      expect(bytes.length, greaterThan(4 << 20));
      expect(deserializeCommands(bytes), hasLength(huge.length));
      // ... and what follows it is unaffected.
      final small = drawing(3, 40);
      final again = serializeCommands(small)!;
      expect(_transcriptOf(deserializeCommands(again)), _transcriptOf(small));
    });
  });

  test('a snapshot inside a soft mask throws instead of corrupting', () {
    // Release builds included: the nested list's count is still 0 and its
    // header half-written, so a prefix copy there would not replay.
    final writer = PdfStreamingCommandWriter();
    const box = PdfPath([PdfMoveTo(0, 0), PdfLineTo(1, 0), PdfClosePath()]);
    writer.beginSoftMasked();
    writer.fillPath(box, PdfColor.black, PdfFillRule.nonzero, 1);
    Object? thrown;
    writer.endSoftMasked(
      luminosity: true,
      backdrop: const PdfRect(0, 0, 1, 1),
      drawMask: () {
        writer.fillPath(box, PdfColor(1, 1, 1), PdfFillRule.nonzero, 1);
        try {
          writer.snapshot();
        } on StateError catch (e) {
          thrown = e;
        }
      },
    );
    expect(thrown, isA<StateError>());
    // Back at page level the snapshot is whole again.
    final restored = deserializeCommands(writer.snapshot());
    expect(restored.map((c) => c.runtimeType), [
      PdfBeginSoftMaskedCommand,
      PdfFillPathCommand,
      PdfEndSoftMaskedCommand,
    ]);
  });
}

/// A printable form of [commands], enough to tell two records apart.
List<String> _transcriptOf(List<PdfRenderCommand> commands) => [
      for (final c in commands)
        switch (c) {
          PdfFillPathCommand() => 'fill ${c.path.segments.length} '
              '${c.path.segments.map((s) => switch (s) {
                    PdfMoveTo() => 'm${s.x},${s.y}',
                    PdfLineTo() => 'l${s.x},${s.y}',
                    _ => '?',
                  }).join(' ')} ${c.color}',
          PdfDrawTextCommand() =>
            'text ${c.run.text} ${c.run.fontName} ${c.run.transform.e}',
          _ => c.runtimeType.toString(),
        },
    ];
