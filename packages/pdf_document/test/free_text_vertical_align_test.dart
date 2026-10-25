import 'dart:convert';

import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:test/test.dart';

List<double> _baselines(PdfDocument document, PdfAnnotation annotation) {
  final content = latin1
      .decode(document.cos.decodeStreamData(annotation.normalAppearance!));
  var y = 0.0;
  return [
    for (final match in RegExp(r'(-?[\d.]+) (-?[\d.]+) Td').allMatches(content))
      y += double.parse(match.group(2)!),
  ];
}

void main() {
  const box = PdfRect(100, 500, 300, 650);
  for (final rich in [false, true]) {
    for (final align in PdfTextVerticalAlign.values) {
      test('${rich ? 'rich' : 'plain'} wrapped block aligns ${align.name}', () {
        final editor = PdfEditor(PdfDocument.open(buildMultiPagePdf(1)));
        if (rich) {
          editor.addFreeTextRich(
              0,
              box,
              [
                const PdfFreeTextRun('First\nSecond', fontSize: 20),
              ],
              verticalAlign: align);
        } else {
          editor.addFreeText(0, box, 'First\nSecond',
              fontSize: 20, verticalAlign: align);
        }
        final saved = PdfDocument.open(editor.save());
        final annotation = saved.page(0).annotations.single;
        expect(annotation.freeTextStyle!.verticalAlignment, align);
        expect(annotation.freeTextStyle!.alignment, PdfTextAlign.left);
        final offset = switch (align) {
          PdfTextVerticalAlign.top => 0,
          PdfTextVerticalAlign.center => 50,
          PdfTextVerticalAlign.bottom => 100,
        };
        final baselines = _baselines(saved, annotation);
        expect(baselines, hasLength(2));
        expect(baselines.first, closeTo(650 - 3 - 20 * .718 - offset, .001));
        expect(baselines.last, closeTo(baselines.first - 24, .001));
      });
    }
  }

  test('rich mixed sizes align the complete block', () {
    final editor = PdfEditor(PdfDocument.open(buildMultiPagePdf(1)));
    editor.addFreeTextRich(
        0,
        box,
        [
          const PdfFreeTextRun('small\n', fontSize: 10),
          const PdfFreeTextRun('large', fontSize: 30),
        ],
        verticalAlign: PdfTextVerticalAlign.bottom);
    final saved = PdfDocument.open(editor.save());
    final baselines = _baselines(saved, saved.page(0).annotations.single);
    // The block is 12pt of first-line advance plus a 30pt final em.
    expect(baselines.first, closeTo(500 + 3 + 42 - 10 * .718, .001));
    expect(baselines.last, closeTo(500 + 3 + 30 - 30 * .718, .001));
  });

  test('an overfull block stays top-anchored in every alignment', () {
    for (final align in PdfTextVerticalAlign.values) {
      final editor = PdfEditor(PdfDocument.open(buildMultiPagePdf(1)));
      editor.addFreeText(
          0, const PdfRect(100, 500, 300, 520), 'One\nTwo\nThree',
          fontSize: 20, verticalAlign: align);
      final saved = PdfDocument.open(editor.save());
      expect(_baselines(saved, saved.page(0).annotations.single).first,
          closeTo(520 - 3 - 20 * .718, .001));
    }
  });

  test('absent or unknown placement falls back to top', () {
    final editor = PdfEditor(PdfDocument.open(buildMultiPagePdf(1)))
      ..addFreeText(0, box, 'Legacy');
    final saved = PdfDocument.open(editor.save());
    final annotation = saved.page(0).annotations.single;
    expect(annotation.dict.containsKey(kPdfFreeTextVerticalAlignKey), isFalse);
    expect(
        annotation.freeTextStyle!.verticalAlignment, PdfTextVerticalAlign.top);
    annotation.dict[kPdfFreeTextVerticalAlignKey] = const CosName('unknown');
    expect(
        annotation.freeTextStyle!.verticalAlignment, PdfTextVerticalAlign.top);
  });

  test('resize and callout reshape preserve placement', () {
    final editor = PdfEditor(PdfDocument.open(buildMultiPagePdf(1)))
      ..addFreeText(0, box, 'Centered',
          verticalAlign: PdfTextVerticalAlign.center)
      ..addCallout(0, box, 'Bottom', (50, 450),
          verticalAlign: PdfTextVerticalAlign.bottom);
    var saved = PdfDocument.open(editor.save());
    final resized = PdfEditor(saved);
    resized.resizeAnnotation(
        0, saved.page(0).annotations[0], const PdfRect(100, 450, 350, 650));
    resized.reshapeCallout(0, saved.page(0).annotations[1],
        box: const PdfRect(100, 450, 350, 650));
    saved = PdfDocument.open(resized.save());
    expect(saved.page(0).annotations[0].freeTextStyle!.verticalAlignment,
        PdfTextVerticalAlign.center);
    expect(saved.page(0).annotations[1].freeTextStyle!.verticalAlignment,
        PdfTextVerticalAlign.bottom);
  });
}
