import 'package:pdf_graphics/pdf_graphics.dart';
import 'package:pdf_graphics/raster.dart';
import 'package:test/test.dart';

const _path = PdfPath([
  PdfMoveTo(0, 0),
  PdfLineTo(10, 0),
  PdfLineTo(10, 10),
  PdfClosePath(),
]);

const _fill = PdfFillPathCommand(
  _path,
  PdfColor(1, 0, 0),
  PdfFillRule.nonzero,
  1,
);

void main() {
  test('consecutive strip paints share one estimated batch', () {
    final profile = StripReplayProfile.of(const [
      _fill,
      PdfStrokePathCommand(
        _path,
        PdfColor.black,
        PdfStroke(),
        1,
      ),
    ]);

    expect(profile.estimatedBatchCount, 1);
    expect(profile.routedPaintCount, 2);
    expect(profile.delegatedPaintCount, 0);
    expect(profile.flushPointCount, 1);
  });

  test('clip-per-shape topology estimates one batch per shape', () {
    final profile = StripReplayProfile.of(const [
      PdfSaveCommand(),
      PdfClipPathCommand(_path, PdfFillRule.nonzero),
      _fill,
      PdfRestoreCommand(),
      PdfSaveCommand(),
      PdfClipPathCommand(_path, PdfFillRule.nonzero),
      PdfStrokePathCommand(
        _path,
        PdfColor.black,
        PdfStroke(),
        1,
      ),
      PdfRestoreCommand(),
    ]);

    expect(profile.estimatedBatchCount, 2);
    expect(profile.routedPaintCount, 2);
    expect(profile.delegatedPaintCount, 0);
    expect(profile.flushPointCount, greaterThan(2));
  });

  test('delegated paints split surrounding strip batches', () {
    final profile = StripReplayProfile.of(const [
      _fill,
      PdfDrawTextCommand(PdfTextRun(
        text: 'substituted',
        transform: PdfMatrix.identity,
        color: PdfColor.black,
        width: 1,
      )),
      _fill,
    ]);

    expect(profile.estimatedBatchCount, 2);
    expect(profile.routedPaintCount, 2);
    expect(profile.delegatedPaintCount, 1);
  });

  test('delegated-only transcripts estimate no strip batches', () {
    final profile = StripReplayProfile.of(const [
      PdfDrawTextCommand(PdfTextRun(
        text: 'substituted',
        transform: PdfMatrix.identity,
        color: PdfColor.black,
        width: 1,
      )),
    ]);

    expect(profile.estimatedBatchCount, 0);
    expect(profile.routedPaintCount, 0);
    expect(profile.delegatedPaintCount, 1);
  });
}
