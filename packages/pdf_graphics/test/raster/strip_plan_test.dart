// StripPlanBinner + strip-plan codec:
//
//  - flush-ordinal semantics of the shared binning core on synthetic
//    command sequences (delegated paints, clips incl. restore-pops-clip,
//    nested/knockout groups, soft masks with the mask drawn between the
//    composite halves, blend-mode switches, empty flushes) - the parity
//    invariant precomputed plans ride on;
//  - cooperative cancellation of the chunked replay;
//  - encodeStripPlan/decodeStripPlan round-trip fidelity.
import 'dart:typed_data';

import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart' show PdfRect;
import 'package:pdf_graphics/pdf_graphics.dart';
import 'package:pdf_graphics/raster.dart';
import 'package:test/test.dart';

PdfPath rect(double l, double t, double r, double b) => PdfPath([
      PdfMoveTo(l, t),
      PdfLineTo(r, t),
      PdfLineTo(r, b),
      PdfLineTo(l, b),
      const PdfClosePath(),
    ]);

StripPlanBinner binner({int w = 64, int h = 64}) => StripPlanBinner(
      pageToDevice: PdfMatrix.identity,
      deviceWidth: w,
      deviceHeight: h,
      pixelRatio: 1,
    );

void fill(PdfDevice d, PdfPath path) =>
    d.fillPath(path, PdfColor.black, PdfFillRule.nonzero, 1);

PdfImageRequest dummyImage() => PdfImageRequest(
      stream: CosStream(CosDictionary(), Uint8List(0)),
      transform: PdfMatrix.identity,
    );

void main() {
  test('delegated paints are flush points; trailing strips flush at finish',
      () {
    final b = binner();
    fill(b, rect(2, 2, 10, 10));
    fill(b, rect(12, 2, 20, 10));
    b.drawImage(dummyImage()); // delegated paint -> flush ordinal 0
    fill(b, rect(2, 12, 10, 20));
    final plan = b.finish(); // final flush -> ordinal 1

    expect(plan.totalFlushPoints, 2);
    expect(plan.batches.map((x) => x.flushOrdinal), [0, 1]);
    expect(b.delegatedPaintCount, 1);
    expect(plan.batches[0].stripCount, greaterThan(0));
    expect(plan.batches[1].stripCount, greaterThan(0));
  });

  test('clip flushes before it applies; restore pops the clip with a flush',
      () {
    final b = binner();
    fill(b, rect(2, 2, 10, 10));
    b.save();
    b.clipPath(rect(0, 0, 32, 32), PdfFillRule.nonzero); // flush 0 (batch)
    fill(b, rect(4, 4, 8, 8));
    b.restore(); // pops the clip -> flush 1 (batch)
    fill(b, rect(20, 20, 30, 30));
    final plan = b.finish(); // flush 2 (batch)

    expect(plan.totalFlushPoints, 3);
    expect(plan.batches.map((x) => x.flushOrdinal), [0, 1, 2]);
  });

  test('empty flush points still count ordinals but emit no batch', () {
    final b = binner();
    b.save();
    b.clipPath(rect(0, 0, 32, 32), PdfFillRule.nonzero); // flush 0, empty
    fill(b, rect(4, 4, 8, 8));
    b.restore(); // flush 1 (batch)
    final plan = b.finish(); // flush 2, empty

    expect(plan.totalFlushPoints, 3);
    expect(plan.batches.map((x) => x.flushOrdinal), [1]);
  });

  test('knockout group delegates its fills; ordinary group re-enables', () {
    final b = binner();
    b.beginGroup(1, knockout: true); // flush 0 (empty)
    fill(b, rect(2, 2, 10, 10)); // knockout -> delegated -> flush 1 (empty)
    b.beginGroup(0.5); // nested non-knockout -> flush 2 (empty)
    fill(b, rect(4, 4, 8, 8)); // strips active again (top of stack wins)
    b.endGroup(); // flush 3 (batch)
    fill(b, rect(2, 2, 10, 10)); // directly in knockout -> delegated, flush 4
    b.endGroup(); // flush 5 (empty)
    fill(b, rect(20, 20, 30, 30)); // binned
    final plan = b.finish(); // flush 6 (batch)

    expect(plan.totalFlushPoints, 7);
    expect(plan.batches.map((x) => x.flushOrdinal), [3, 6]);
    expect(b.delegatedPaintCount, 2);
  });

  test('non-normal blend modes delegate until normal returns', () {
    final b = binner();
    b.setBlendMode(PdfBlendMode.multiply); // state, not a flush point
    fill(b, rect(2, 2, 10, 10)); // delegated -> flush 0 (empty)
    b.setBlendMode(PdfBlendMode.normal);
    fill(b, rect(12, 2, 20, 10)); // binned
    final plan = b.finish(); // flush 1 (batch)

    expect(plan.totalFlushPoints, 2);
    expect(plan.batches.map((x) => x.flushOrdinal), [1]);
    expect(b.delegatedPaintCount, 1);
  });

  test('soft mask: content flushes at the boundary, mask strips land between '
      'the composite halves', () {
    final b = binner();
    b.beginSoftMasked(); // flush 0 (empty)
    fill(b, rect(2, 2, 10, 10)); // masked content
    b.endSoftMasked(
      luminosity: true,
      backdrop: const PdfRect(0, 0, 64, 64),
      drawMask: () => fill(b, rect(0, 0, 32, 32)), // mask group strips
    ); // flush 1 (content batch), mask draw, flush 2 (mask batch)
    final plan = b.finish(); // flush 3 (empty)

    expect(plan.totalFlushPoints, 4);
    expect(plan.batches.map((x) => x.flushOrdinal), [1, 2]);
  });

  test('substituted text delegates, outline text bins', () {
    final glyph = PdfGlyphPlacement(offset: 0, outline: rect(0, 0, 0.5, 0.6));
    final b = binner();
    b.drawText(PdfTextRun(
      text: 'x',
      transform: const PdfMatrix(16, 0, 0, 16, 4, 20),
      color: PdfColor.black,
      width: 0.5,
      glyphs: [glyph],
    )); // binned
    b.drawText(PdfTextRun(
      text: 'y',
      transform: const PdfMatrix(16, 0, 0, 16, 4, 40),
      color: PdfColor.black,
      width: 0.5,
    )); // no glyphs -> delegated -> flush 0 (batch: the outline glyph)
    final plan = b.finish(); // flush 1 (empty)

    expect(plan.totalFlushPoints, 2);
    expect(plan.batches.map((x) => x.flushOrdinal), [0]);
    expect(b.delegatedPaintCount, 1);
  });

  test('two binners over one command list produce identical plans', () async {
    final commands = <PdfRenderCommand>[
      PdfFillPathCommand(rect(2, 2, 30, 30), PdfColor.black,
          PdfFillRule.nonzero, 1),
      PdfStrokePathCommand(rect(8, 8, 24, 24), const PdfColor(1, 0, 0),
          const PdfStroke(width: 2), 0.8),
      PdfDrawImageCommand(dummyImage()),
      PdfFillPathCommand(rect(40, 40, 60, 60), const PdfColor(0, 0, 1),
          PdfFillRule.evenOdd, 0.5),
    ];
    Future<Uint8List> run() async {
      final b = binner();
      await b.bin(commands);
      return encodeStripPlan(b.finish());
    }

    expect(await run(), await run());
  });

  test('cancellation token aborts the chunked replay', () async {
    final commands = <PdfRenderCommand>[
      for (var i = 0; i < 4000; i++)
        PdfFillPathCommand(
            rect(2, 2, 10, 10), PdfColor.black, PdfFillRule.nonzero, 1),
    ];
    final b = binner();
    final token = PdfCancellationToken();
    // Flip the token from the event loop: the replay yields between chunks,
    // so the cancel lands mid-walk exactly like a worker's cancel port.
    Future<void>.delayed(Duration.zero, () => token.cancelled = true);
    await expectLater(
        b.bin(commands, cancellation: token),
        throwsA(isA<PdfCancelledException>()));
  });

  test('codec round-trips a real plan bit-exactly', () async {
    final b = StripPlanBinner(
      pageToDevice: const PdfMatrix(2.5, 0, 0, -2.5, 3.25, 170.125),
      deviceWidth: 160,
      deviceHeight: 176,
      pixelRatio: 2.5,
    );
    // Fractional edges force mixed-coverage strips (atlas bytes) alongside
    // solid runs; a delegated paint splits the plan into two batches.
    fill(b, rect(1.25, 1.5, 30.75, 12.25));
    b.strokePath(rect(4, 20, 40, 40), const PdfColor(0, 0.5, 1),
        const PdfStroke(width: 1.3), 0.7);
    b.drawImage(dummyImage());
    fill(b, rect(10.1, 50.2, 55.9, 60.8));
    final plan = b.finish();
    expect(plan.batches.length, 2);

    final decoded = decodeStripPlan(encodeStripPlan(plan));
    expect(decoded.totalFlushPoints, plan.totalFlushPoints);
    expect(decoded.deviceWidth, plan.deviceWidth);
    expect(decoded.deviceHeight, plan.deviceHeight);
    expect(decoded.tolerance, plan.tolerance);
    expect(decoded.pageToDevice.a, plan.pageToDevice.a);
    expect(decoded.pageToDevice.b, plan.pageToDevice.b);
    expect(decoded.pageToDevice.c, plan.pageToDevice.c);
    expect(decoded.pageToDevice.d, plan.pageToDevice.d);
    expect(decoded.pageToDevice.e, plan.pageToDevice.e);
    expect(decoded.pageToDevice.f, plan.pageToDevice.f);
    expect(decoded.batches.length, plan.batches.length);
    for (var i = 0; i < plan.batches.length; i++) {
      final a = plan.batches[i], d = decoded.batches[i];
      expect(d.flushOrdinal, a.flushOrdinal);
      expect(d.stripCount, a.stripCount);
      expect(d.atlasWidth, a.atlasWidth);
      expect(d.atlasHeight, a.atlasHeight);
      expect(d.atlasPixels, a.atlasPixels);
      expect(d.chunks.length, a.chunks.length);
      for (var c = 0; c < a.chunks.length; c++) {
        expect(d.chunks[c].positions, a.chunks[c].positions);
        expect(d.chunks[c].textureCoordinates,
            a.chunks[c].textureCoordinates);
        expect(d.chunks[c].colors, a.chunks[c].colors);
        expect(d.chunks[c].indices, a.chunks[c].indices);
      }
    }
    // And the re-encode of the decode is byte-identical.
    expect(encodeStripPlan(decoded), encodeStripPlan(plan));
  });
}
