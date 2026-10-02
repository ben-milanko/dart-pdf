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
}
