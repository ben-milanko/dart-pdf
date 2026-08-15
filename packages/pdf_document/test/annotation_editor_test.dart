import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:test/test.dart';

void main() {
  Uint8List buildMalformedAnnotsPdf() {
    final builder = CosDocumentBuilder();
    final badAnnotsRef = builder.add(CosString.fromText('not an array'));
    final pageDict = CosDictionary({
      'Type': const CosName('Page'),
      'MediaBox': CosArray(const [
        CosInteger(0),
        CosInteger(0),
        CosInteger(612),
        CosInteger(792),
      ]),
      'Resources': CosDictionary(),
      'Annots': badAnnotsRef,
    });
    final pageRef = builder.add(pageDict);
    final pagesRef = builder.add(CosDictionary({
      'Type': const CosName('Pages'),
      'Kids': CosArray([pageRef]),
      'Count': const CosInteger(1),
    }));
    pageDict['Parent'] = pagesRef;
    final catalogRef = builder.add(
        CosDictionary({'Type': const CosName('Catalog'), 'Pages': pagesRef}));
    return builder.build(root: catalogRef);
  }

  PdfDocument roundTrip(void Function(PdfEditor) edit) {
    final editor = PdfEditor(PdfDocument.open(buildClassicPdf()));
    edit(editor);
    return PdfDocument.open(editor.save());
  }

  String appearanceText(PdfDocument doc, PdfAnnotation annot) {
    final stream = annot.normalAppearance;
    expect(stream, isNotNull, reason: 'annotation must carry /AP /N');
    return latin1.decode(doc.cos.decodeStreamData(stream!));
  }

  test('highlight round-trips with quad points and a Multiply appearance', () {
    final doc = roundTrip((e) => e.addHighlight(
          0,
          const [PdfRect(72, 700, 200, 712), PdfRect(72, 686, 150, 698)],
          contents: 'important',
          author: 'Ben',
        ));
    final annots = doc.page(0).annotations;
    expect(annots, hasLength(1));
    final hl = annots.single;
    expect(hl.subtype, 'Highlight');
    expect(hl.rect, const PdfRect(72, 686, 200, 712));

    final quads = doc.cos.resolve(hl.dict['QuadPoints']) as CosArray;
    expect(quads.length, 16);

    final content = appearanceText(doc, hl);
    expect(content, contains('re'));
    expect(content, contains('f'));
    expect(content, contains('/GS0 gs'));

    final form = hl.normalAppearance!;
    final resources =
        doc.cos.resolve(form.dictionary['Resources']) as CosDictionary;
    final gstates = doc.cos.resolve(resources['ExtGState']) as CosDictionary;
    final gs0 = doc.cos.resolve(gstates['GS0']) as CosDictionary;
    expect((doc.cos.resolve(gs0['BM']) as CosName).value, 'Multiply');

    expect(
        (doc.cos.resolve(hl.dict['Contents']) as CosString).text, 'important');
    expect((doc.cos.resolve(hl.dict['T']) as CosString).text, 'Ben');
  });

  test('underline, strikeout, and squiggly carry quad points', () {
    final doc = roundTrip((e) {
      const quads = [PdfRect(72, 700, 200, 712)];
      e.addUnderline(0, quads);
      e.addStrikeOut(0, quads);
      e.addSquiggly(0, quads);
    });
    final subtypes = [for (final a in doc.page(0).annotations) a.subtype];
    expect(subtypes, ['Underline', 'StrikeOut', 'Squiggly']);
    for (final annot in doc.page(0).annotations) {
      expect(doc.cos.resolve(annot.dict['QuadPoints']), isA<CosArray>());
      expect(appearanceText(doc, annot), contains('S'));
    }
  });

  test('ink stores the stroke list and pads its rect by the line width', () {
    final doc = roundTrip((e) => e.addInk(
          0,
          [
            [(100, 100), (150, 130), (200, 100)],
            [(120, 90)],
          ],
          strokeWidth: 4,
        ));
    final ink = doc.page(0).annotations.single;
    expect(ink.subtype, 'Ink');
    // bounds (100,90)-(200,130) padded by width/2 + 1 = 3
    expect(ink.rect, const PdfRect(97, 87, 203, 133));

    final inkList = doc.cos.resolve(ink.dict['InkList']) as CosArray;
    expect(inkList.length, 2);
    expect((doc.cos.resolve(inkList[0]) as CosArray).length, 6);

    final content = appearanceText(doc, ink);
    expect(content, contains('1 J'));
    expect(content, contains('4 w'));
  });

  test('ink pressures vary the appearance width per segment', () {
    final doc = roundTrip((e) => e.addInk(
          0,
          [
            [(100, 100), (150, 130), (200, 100)],
          ],
          strokeWidth: 4,
          pressures: [
            [0.0, 0.5, 1.0],
          ],
        ));
    final ink = doc.page(0).annotations.single;

    // segment widths use the average of the endpoint pressures:
    // (0+0.5)/2 → 4×0.7 = 2.8, (0.5+1)/2 → 4×1.3 = 5.2
    final content = appearanceText(doc, ink);
    expect(content, contains('2.8 w'));
    expect(content, contains('5.2 w'));
    expect('S'.allMatches(content).length, greaterThanOrEqualTo(2),
        reason: 'one stroked segment per point pair');

    // the InkList still stores the centerline; the rect pads by the
    // widest possible point (pressure 1 → 6.4/2 + 1 = 4.2)
    final inkList = doc.cos.resolve(ink.dict['InkList']) as CosArray;
    expect((doc.cos.resolve(inkList[0]) as CosArray).length, 6);
    expect(ink.rect.left, closeTo(100 - 4.2, 1e-9));
    expect(ink.rect.top, closeTo(130 + 4.2, 1e-9));

    expect(pdfInkStrokeWidth(4, 0.5), 4);
    expect(pdfInkStrokeWidth(4, 0), closeTo(1.6, 1e-9));
    expect(pdfInkStrokeWidth(4, 1), closeTo(6.4, 1e-9));
  });

  test('reduced-opacity ink fades as one isolated transparency group', () {
    // A pressure (trackpad/stylus) stroke paints each segment separately
    // with round caps that overlap at every join. Compositing them
    // individually at partial alpha double-paints those overlaps into
    // visible dots, so the strokes are drawn opaquely inside a
    // transparency group the /N form fades as a whole.
    String innerDrawing(PdfDocument d, PdfAnnotation a) {
      final resources =
          d.cos.resolve(a.normalAppearance!.dictionary['Resources'])
              as CosDictionary;
      final xObjects = d.cos.resolve(resources['XObject']) as CosDictionary;
      final inner =
          d.cos.resolve(xObjects.entries.values.single) as CosStream;
      return latin1.decode(d.cos.decodeStreamData(inner));
    }

    final doc = roundTrip((e) => e.addInk(
          0,
          [
            [(100, 100), (150, 130), (200, 100)],
          ],
          strokeWidth: 4,
          opacity: 0.5,
          pressures: [
            [0.0, 0.5, 1.0],
          ],
        ));
    final ink = doc.page(0).annotations.single;
    final form = ink.normalAppearance!;

    // the /N form just fades and paints the group - no stroke ops leak
    // out where the constant alpha would compound them
    final outer = latin1.decode(doc.cos.decodeStreamData(form));
    expect(outer, contains('/GS0 gs'));
    expect(outer, contains('Do'));
    expect(outer, isNot(contains(' S')));

    // /GS0 carries the constant alpha; the inner form is an isolated
    // transparency group
    final resources =
        doc.cos.resolve(form.dictionary['Resources']) as CosDictionary;
    final gstates = doc.cos.resolve(resources['ExtGState']) as CosDictionary;
    final gs0 = doc.cos.resolve(gstates['GS0']) as CosDictionary;
    expect((doc.cos.resolve(gs0['ca']) as CosReal).value, closeTo(0.5, 1e-9));
    expect((doc.cos.resolve(gs0['CA']) as CosReal).value, closeTo(0.5, 1e-9));

    final xObjects = doc.cos.resolve(resources['XObject']) as CosDictionary;
    final inner = doc.cos.resolve(xObjects.entries.values.single) as CosStream;
    final group = doc.cos.resolve(inner.dictionary['Group']) as CosDictionary;
    expect((doc.cos.resolve(group['S']) as CosName).value, 'Transparency');
    expect(doc.cos.resolve(group['I']), const CosBoolean(true));

    // the per-segment stroking lives inside the group, at full alpha
    final drawing = innerDrawing(doc, ink);
    expect(drawing, contains('2.8 w'));
    expect(drawing, contains('5.2 w'));
    expect('S'.allMatches(drawing).length, greaterThanOrEqualTo(2));
    expect(drawing, isNot(contains('gs')));

    // restyling recovers the pressures through the group wrapper, so a
    // recolor stays per-segment instead of collapsing to a uniform pen
    final editor = PdfEditor(doc)
      ..restyleAnnotation(0, ink, color: 0x1E88E5);
    final out = PdfDocument.open(editor.save());
    final after = out.page(0).annotations.single;
    expect(after.color, 0x1E88E5);
    final afterDrawing = innerDrawing(out, after);
    expect(afterDrawing, contains('RG'), reason: 'recolored');
    // still per-segment: recovery inverts the group's segment widths back
    // to pressures (a lossy re-average, 2.8/5.2 → 3.4/4.6) rather than
    // flattening to a single uniform pen
    expect(afterDrawing, contains('3.4 w'),
        reason: 'pressures recovered through the group wrapper');
    expect(afterDrawing, contains('4.6 w'));
  });

  test('ink appearances smooth the polyline into Bézier curves', () {
    final doc = roundTrip((e) => e.addInk(0, [
          [(100, 100), (150, 130), (200, 100)],
        ]));
    final content = appearanceText(doc, doc.page(0).annotations.single);
    // curve segments instead of straight l segments between samples
    expect(content, contains(' c'));
    expect(content, isNot(contains(' l')));

    // the Catmull-Rom controls: endpoints clamp, interior tangents are
    // (next − previous) / 6
    final controls = pdfInkCurveControls([(100, 100), (150, 130), (200, 100)]);
    expect(controls, hasLength(2));
    expect(controls[0].$1.$1, closeTo(100 + 50 / 6, 1e-9));
    expect(controls[0].$1.$2, closeTo(105, 1e-9));
    expect(controls[0].$2.$1, closeTo(150 - 100 / 6, 1e-9));
    expect(controls[0].$2.$2, closeTo(130, 1e-9));
    expect(controls[1].$1.$1, closeTo(150 + 100 / 6, 1e-9));
    expect(controls[1].$1.$2, closeTo(130, 1e-9));
    expect(controls[1].$2.$1, closeTo(200 - 50 / 6, 1e-9));
    expect(controls[1].$2.$2, closeTo(105, 1e-9));

    // a two-point stroke degenerates to a straight segment: collinear
    // controls on the chord
    final straight = pdfInkCurveControls([(0, 0), (60, 30)]);
    expect(straight.single.$1.$1, closeTo(10, 1e-9));
    expect(straight.single.$1.$2, closeTo(5, 1e-9));
    expect(straight.single.$2.$1, closeTo(50, 1e-9));
    expect(straight.single.$2.$2, closeTo(25, 1e-9));
  });

  test('ink rect covers spline overshoot past the sampled points', () {
    // an asymmetric apex: the spline's control points poke above and
    // left of the samples, and the rect must still contain the curve
    final doc = roundTrip((e) => e.addInk(
        0,
        [
          [(50, 0), (60, 100), (150, 90)],
        ],
        strokeWidth: 2));
    final ink = doc.page(0).annotations.single;
    // seg 1's c1 = p1 + (p2 − p0)/6 = (76.67, 115); pad = w/2 + 1 = 2
    expect(ink.rect.top, closeTo(115 + 2, 1e-4));
    // seg 0's c2 = p1 − (p2 − p0)/6 = (43.33, 85) - left of every sample
    expect(ink.rect.left, closeTo(60 - 100 / 6 - 2, 1e-4));
  });

  test('mismatched ink pressures are rejected', () {
    final editor = PdfEditor(PdfDocument.open(buildClassicPdf()));
    expect(
        () => editor.addInk(0, [
              [(100, 100), (150, 130)],
            ], pressures: [
              [0.5],
            ]),
        throwsArgumentError);
  });

  test('square and circle render stroke and fill', () {
    final doc = roundTrip((e) {
      e.addSquare(0, const PdfRect(100, 100, 200, 150),
          fillColor: 0x2040FF, opacity: 0.5);
      e.addCircle(0, const PdfRect(250, 100, 350, 150), strokeWidth: 3);
    });
    final annots = doc.page(0).annotations;
    expect([for (final a in annots) a.subtype], ['Square', 'Circle']);

    final square = appearanceText(doc, annots[0]);
    expect(square, contains('B')); // fill + stroke
    expect(doc.cos.resolve(annots[0].dict['IC']), isA<CosArray>());

    final circle = appearanceText(doc, annots[1]);
    expect(circle, contains('c')); // Bézier arcs
    expect(circle, contains('S'));
  });

  test('rounded rectangle curves its corners and records /Border', () {
    final doc = roundTrip((e) => e.addSquare(
          0,
          const PdfRect(100, 100, 300, 200),
          strokeWidth: 2,
          cornerRadius: 12,
        ));
    final square = doc.page(0).annotations.single;
    expect(square.subtype, 'Square');
    expect(square.cornerRadius, 12);

    final content = appearanceText(doc, square);
    // roundedRect draws corners as Bézier curves rather than a single `re`.
    expect(content, contains('c'));
    expect(content, isNot(contains(' re')));

    // §12.5.4 /Border = [hCornerRadius vCornerRadius width].
    final border = doc.cos.resolve(square.dict['Border']) as CosArray;
    expect(border.length, 3);
    expect((doc.cos.resolve(border[0]) as CosReal).value, 12);
    expect((doc.cos.resolve(border[1]) as CosReal).value, 12);
  });

  test('a plain rectangle keeps square corners and no /Border radius', () {
    final doc = roundTrip((e) => e.addSquare(
          0,
          const PdfRect(100, 100, 300, 200),
          strokeWidth: 2,
        ));
    final square = doc.page(0).annotations.single;
    expect(square.cornerRadius, 0);
    expect(appearanceText(doc, square), contains(' re'));
  });

  test('resizing a rounded rectangle keeps its corner radius', () {
    final editor = PdfEditor(PdfDocument.open(buildClassicPdf()));
    editor.addSquare(
      0,
      const PdfRect(100, 100, 300, 200),
      strokeWidth: 2,
      cornerRadius: 12,
    );
    final doc = PdfDocument.open(editor.save());
    final editor2 = PdfEditor(doc);
    final square = doc.page(0).annotations.single;
    editor2.resizeAnnotation(0, square, const PdfRect(100, 100, 500, 400));
    final resized = PdfDocument.open(editor2.save());
    final annot = resized.page(0).annotations.single;
    expect(annot.cornerRadius, 12);
    final content = appearanceText(resized, annot);
    expect(content, contains('c'));
    expect(content, isNot(contains(' re')));
  });

  test('free text wraps to the rect and records /DA', () {
    final doc = roundTrip((e) => e.addFreeText(
          0,
          const PdfRect(72, 600, 240, 680),
          'The quick brown fox jumps over the lazy dog near the riverbank',
          fontSize: 12,
          fillColor: 0xFFFFE0,
          borderColor: 0x808080,
        ));
    final ft = doc.page(0).annotations.single;
    expect(ft.subtype, 'FreeText');

    final da = doc.cos.resolve(ft.dict['DA']) as CosString;
    expect(da.text, contains('/Helv 12 Tf'));

    final content = appearanceText(doc, ft);
    expect(content, contains('BT'));
    expect(content, contains('/Helv 12 Tf'));
    // 62 chars at 12pt Helvetica cannot fit one 168pt-wide line
    expect(' Tj'.allMatches(content).length, greaterThanOrEqualTo(2));
    expect(content, contains('W')); // clipped to the rect

    final form = ft.normalAppearance!;
    final resources =
        doc.cos.resolve(form.dictionary['Resources']) as CosDictionary;
    final fonts = doc.cos.resolve(resources['Font']) as CosDictionary;
    final helv = doc.cos.resolve(fonts['Helv']) as CosDictionary;
    expect((doc.cos.resolve(helv['BaseFont']) as CosName).value, 'Helvetica');
    expect((doc.cos.resolve(helv['Widths']) as CosArray).length, 95);
  });

  test('Bluebeam free text recovers CSS alignment and CR line breaks', () {
    final doc = PdfDocument.open(buildBluebeamFreeTextPdf());
    final box = doc.page(0).annotations.single;
    final style = box.freeTextStyle!;

    expect(style.alignment, PdfTextAlign.center);
    expect(style.lineSpacing, closeTo(1.15, 1e-9));
    expect(box.contents, 'PJ\r202/7');
    expect(pdfNormalizeLineEndings(box.contents!), 'PJ\n202/7');

    // /RC is a second Bluebeam style source when /DS is missing.
    box.dict.entries.remove('DS');
    final fromRichContent = PdfAnnotation.fromDict(doc, box.dict);
    expect(fromRichContent.freeTextStyle!.alignment, PdfTextAlign.center);
    expect(fromRichContent.freeTextStyle!.lineSpacing, closeTo(1.15, 1e-9));

    // Regeneration must measure the CR as a paragraph break, not as a glyph.
    final editor = PdfEditor(doc)
      ..restyleAnnotation(0, fromRichContent, opacity: 0.4);
    final regenerated = PdfDocument.open(editor.save());
    final after = regenerated.page(0).annotations.single;
    final content = appearanceText(regenerated, after);
    expect(' Tj'.allMatches(content), hasLength(2));
    expect(content, isNot(contains('\\r')));
    expect(after.appearanceOpacity, closeTo(0.4, 1e-9));
  });

  test('standard free text layout entries override Bluebeam CSS fallbacks', () {
    final doc = PdfDocument.open(buildBluebeamFreeTextPdf());
    final dict = doc.page(0).annotations.single.dict;
    final ds = doc.cos.resolve(dict['DS']) as CosString;
    dict
      ..['DS'] = CosString.fromText('${ds.text}; text-decoration:underline')
      ..['Q'] = const CosInteger(2)
      ..[kPdfFreeTextLineSpacingKey] = const CosReal(1.4)
      ..[kPdfFreeTextCharSpacingKey] = const CosReal(2)
      ..[kPdfFreeTextHScaleKey] = const CosReal(80)
      ..[kPdfFreeTextUnderlineKey] = const CosBoolean(false);

    final style = PdfAnnotation.fromDict(doc, dict).freeTextStyle!;
    expect(style.alignment, PdfTextAlign.right);
    expect(style.lineSpacing, 1.4);
    expect(style.charSpacing, 2);
    expect(style.horizontalScale, 80);
    expect(style.underline, isFalse);
  });

  test('free text opacity is baked into and preserved by its appearance', () {
    final doc = roundTrip((e) => e.addFreeText(
          0,
          const PdfRect(72, 600, 240, 680),
          'Translucent text',
          fillColor: 0xFFFFE0,
          opacity: 0.4,
        ));
    final box = doc.page(0).annotations.single;
    expect(box.appearanceOpacity, closeTo(0.4, 1e-9));
    expect(appearanceText(doc, box), startsWith('/GS0 gs'));

    final editor = PdfEditor(doc)
      ..resizeAnnotation(0, box, const PdfRect(72, 600, 360, 700));
    final resized = PdfDocument.open(editor.save()).page(0).annotations.single;
    expect(resized.appearanceOpacity, closeTo(0.4, 1e-9));
  });

  test('free text can lay out RTL visual order and right alignment', () {
    expect(pdfTextLooksRtl('שלום 123'), isTrue);
    expect(pdfVisualText('שלום 123', PdfTextDirection.rtl), '123 םולש');

    final doc = roundTrip((e) => e.addFreeText(
          0,
          const PdfRect(100, 600, 300, 640),
          'abc 123 def',
          textDirection: PdfTextDirection.rtl,
        ));
    final ft = doc.page(0).annotations.single;
    expect((doc.cos.resolve(ft.dict['Q']) as CosInteger).value, 2);

    final content = appearanceText(doc, ft);
    expect(content, contains('(def 123 abc) Tj'));
    expect(content, isNot(contains('(abc 123 def) Tj')));
  });

  test('free text encodes non-Latin-1 characters via Type0 Unicode font', () {
    const text = 'hello مرحبا world';
    final doc = roundTrip((e) => e.addFreeText(
          0,
          const PdfRect(72, 600, 300, 640),
          text,
        ));
    final ft = doc.page(0).annotations.single;
    // /Contents preserves the original text via UTF-16BE
    expect(ft.contents, text);
    // the appearance stream uses hex-encoded glyph IDs, not literal text
    final content = appearanceText(doc, ft);
    expect(content, isNot(contains('?')));
    expect(content, isNot(contains('(hello')));
    // hex-encoded content uses <...> Tj
    expect(content, contains('Tj'));
    // the font resource should be a Type0 font with Identity-H encoding
    final form = ft.normalAppearance!;
    final res = doc.cos.resolve(form.dictionary['Resources']) as CosDictionary;
    final fonts = doc.cos.resolve(res['Font']) as CosDictionary;
    final f1 = doc.cos.resolve(fonts['F1']) as CosDictionary;
    expect((f1['Subtype'] as CosName).value, 'Type0');
    expect((f1['Encoding'] as CosName).value, 'Identity-H');
    // /ToUnicode CMap must exist for text extraction
    expect(f1['ToUnicode'], isNotNull);
  });

  test('RTL free text uses logical order (no visual reversal)', () {
    const text = 'ـب';
    final doc = roundTrip((e) => e.addFreeText(
          0,
          const PdfRect(72, 600, 200, 640),
          text,
        ));
    final content = appearanceText(doc, doc.page(0).annotations.single);
    // PdfUnicodeFont keeps text in logical order so the renderer's BiDi
    // and shaping produce correct Arabic contextual forms; no ActualText
    // is needed because the ToUnicode CMap already maps to logical Unicode.
    expect(content, isNot(contains('ActualText')));
    // hex-encoded logical-order text
    final hex =
        text.runes.map((r) => r.toRadixString(16).padLeft(4, '0')).join();
    expect(content, contains(hex));
  });

  test('supplementary-plane characters encode correctly', () {
    // U+1F600 (😀) is above U+FFFF
    const text = '😀مرحبا';
    final doc = roundTrip((e) => e.addFreeText(
          0,
          const PdfRect(72, 600, 200, 640),
          text,
        ));
    final content = appearanceText(doc, doc.page(0).annotations.single);
    // no ActualText needed - logical order in content stream
    expect(content, isNot(contains('ActualText')));
    expect(content, contains('Tj'));
  });

  test('rich free text encodes non-Latin runs via Type0 Unicode font', () {
    final doc = roundTrip((e) => e.addFreeTextRich(
          0,
          const PdfRect(72, 600, 400, 660),
          [
            const PdfFreeTextRun('Hello '),
            const PdfFreeTextRun('مرحبا', color: 0xFF0000),
          ],
        ));
    final ft = doc.page(0).annotations.single;
    expect(ft.contents, 'Hello مرحبا');
    final content = appearanceText(doc, ft);
    // the Arabic run uses hex-encoded glyph IDs
    expect(content, isNot(contains('?')));
    expect(content, contains('Tj'));
    // the font resource dict should contain F1 (Type0 for Arabic run)
    final form = ft.normalAppearance!;
    final res = doc.cos.resolve(form.dictionary['Resources']) as CosDictionary;
    final fonts = doc.cos.resolve(res['Font']) as CosDictionary;
    final f1 = doc.cos.resolve(fonts['F1']) as CosDictionary;
    expect((f1['Subtype'] as CosName).value, 'Type0');
  });

  test('rich free text with RTL runs uses logical order', () {
    final doc = roundTrip((e) => e.addFreeTextRich(
          0,
          const PdfRect(72, 600, 400, 660),
          [
            const PdfFreeTextRun('مرحبا', color: 0xFF0000),
            const PdfFreeTextRun(' عالم'),
          ],
        ));
    final content = appearanceText(doc, doc.page(0).annotations.single);
    // PdfUnicodeFont: logical order, no ActualText
    expect(content, isNot(contains('ActualText')));
  });

  test('rich free text persists /RC and /DS for re-editing', () {
    final doc = roundTrip((e) => e.addFreeTextRich(
          0,
          const PdfRect(72, 600, 400, 660),
          [
            const PdfFreeTextRun('Bold ',
                font: PdfStandardFont.helveticaBold, fontSize: 14),
            const PdfFreeTextRun('red', color: 0xFF0000, fontSize: 14),
            const PdfFreeTextRun(' italic',
                font: PdfStandardFont.timesItalic, fontSize: 18),
          ],
        ));
    final ft = doc.page(0).annotations.single;
    expect(ft.contents, 'Bold red italic');
    final rc = ft.richContent;
    expect(rc, isNotNull);
    expect(rc, contains('<span'));

    final runs = PdfAnnotationEditing.parseFreeTextRichContent(rc!);
    expect(runs.map((r) => r.text).join(), 'Bold red italic');
    expect(runs, hasLength(3));

    expect(runs[0].text, 'Bold ');
    expect(runs[0].font, PdfStandardFont.helveticaBold);
    expect(runs[0].fontSize, 14);

    expect(runs[1].text, 'red');
    expect(runs[1].color, 0xFF0000);

    expect(runs[2].text, ' italic');
    expect(runs[2].font, PdfStandardFont.timesItalic);
    expect(runs[2].fontSize, 18);
  });

  test('rich free text /RC escapes markup and newlines', () {
    final doc = roundTrip((e) => e.addFreeTextRich(
          0,
          const PdfRect(72, 600, 400, 660),
          [
            const PdfFreeTextRun('a < b & c',
                font: PdfStandardFont.helveticaBold),
            const PdfFreeTextRun('\nline2'),
          ],
        ));
    final ft = doc.page(0).annotations.single;
    final runs = PdfAnnotationEditing.parseFreeTextRichContent(ft.richContent!);
    expect(runs.map((r) => r.text).join(), 'a < b & c\nline2');
    expect(runs.first.font, PdfStandardFont.helveticaBold);
  });

  test('parseFreeTextRichContent falls back for missing attributes', () {
    final runs = PdfAnnotationEditing.parseFreeTextRichContent(
      '<body><p><span style="font-weight:bold">x</span>'
      '<span>y</span></p></body>',
      fallbackFont: PdfStandardFont.times,
      fallbackSize: 20,
      fallbackColor: 0x00FF00,
    );
    expect(runs, hasLength(2));
    // bold refines the serif fallback into Times-Bold
    expect(runs[0].font, PdfStandardFont.timesBold);
    expect(runs[0].fontSize, 20);
    expect(runs[0].color, 0x00FF00);
    // bare span keeps the fallback wholesale
    expect(runs[1].font, PdfStandardFont.times);
    expect(runs[1].color, 0x00FF00);
  });

  test('resizing a non-Latin free text regenerates with Unicode font', () {
    final editor = PdfEditor(PdfDocument.open(buildClassicPdf()));
    editor.addFreeText(0, const PdfRect(72, 600, 300, 640), 'مرحبا');
    // round-trip so the annotation is parseable from the saved bytes
    final saved = PdfDocument.open(editor.save());
    final editor2 = PdfEditor(saved);
    final annot = saved.page(0).annotations.single;
    editor2.resizeAnnotation(0, annot, const PdfRect(72, 580, 350, 640));
    final doc = PdfDocument.open(editor2.save());
    final ft = doc.page(0).annotations.single;
    expect(ft.rect, const PdfRect(72, 580, 350, 640));
    final content = appearanceText(doc, ft);
    expect(content, isNot(contains('?')));
    expect(content, contains('Tj'));
    final form = ft.normalAppearance!;
    final res = doc.cos.resolve(form.dictionary['Resources']) as CosDictionary;
    final fonts = doc.cos.resolve(res['Font']) as CosDictionary;
    final f1 = doc.cos.resolve(fonts['F1']) as CosDictionary;
    expect((f1['Subtype'] as CosName).value, 'Type0');
  });

  test('free text takes a standard serif or monospace font', () {
    final doc = roundTrip((e) {
      e.addFreeText(0, const PdfRect(72, 600, 240, 680), 'Serif text',
          fontSize: 14, font: PdfStandardFont.times);
      e.addFreeText(0, const PdfRect(72, 500, 240, 580), 'Mono text',
          fontSize: 10, font: PdfStandardFont.courier);
    });
    final annots = doc.page(0).annotations;

    final serifDa = doc.cos.resolve(annots[0].dict['DA']) as CosString;
    expect(serifDa.text, contains('/TiRo 14 Tf'));
    expect(appearanceText(doc, annots[0]), contains('/TiRo 14 Tf'));
    final serifRes =
        doc.cos.resolve(annots[0].normalAppearance!.dictionary['Resources'])
            as CosDictionary;
    final serifFonts = doc.cos.resolve(serifRes['Font']) as CosDictionary;
    final tiro = doc.cos.resolve(serifFonts['TiRo']) as CosDictionary;
    expect((doc.cos.resolve(tiro['BaseFont']) as CosName).value, 'Times-Roman');
    final tiroWidths = doc.cos.resolve(tiro['Widths']) as CosArray;
    expect((tiroWidths.items.first as CosInteger).value, 250); // space

    final monoDa = doc.cos.resolve(annots[1].dict['DA']) as CosString;
    expect(monoDa.text, contains('/Cour 10 Tf'));
    final monoRes =
        doc.cos.resolve(annots[1].normalAppearance!.dictionary['Resources'])
            as CosDictionary;
    final monoFonts = doc.cos.resolve(monoRes['Font']) as CosDictionary;
    final cour = doc.cos.resolve(monoFonts['Cour']) as CosDictionary;
    expect((doc.cos.resolve(cour['BaseFont']) as CosName).value, 'Courier');
    final courWidths = doc.cos.resolve(cour['Widths']) as CosArray;
    expect(courWidths.length, 95);
    expect(
        courWidths.items.every((w) => (w as CosInteger).value == 600), isTrue);
  });

  test('standard-font metrics measure and map names leniently', () {
    // Courier is monospaced at 600/1000 em
    expect(measureStandardText('abc', 10, font: PdfStandardFont.courier), 18);
    // Times-Roman 'A' is 722/1000 em
    expect(measureStandardText('A', 10, font: PdfStandardFont.times), 7.22);
    // the helvetica path matches the long-standing helper
    expect(measureStandardText('Hello world', 12),
        measureHelvetica('Hello world', 12));

    expect(PdfStandardFont.fromName('TiRo'), PdfStandardFont.times);
    expect(PdfStandardFont.fromName('Times-Roman'), PdfStandardFont.times);
    expect(PdfStandardFont.fromName('Cour'), PdfStandardFont.courier);
    expect(PdfStandardFont.fromName('CourierNew'), PdfStandardFont.courier);
    expect(PdfStandardFont.fromName('Helv'), PdfStandardFont.helvetica);
    expect(PdfStandardFont.fromName('Arial'), PdfStandardFont.helvetica);
  });

  test('standard fonts cover bold and italic variants', () {
    // every (family, bold, italic) combination resolves to a distinct font
    for (final family in PdfStandardFontFamily.values) {
      for (final bold in [false, true]) {
        for (final italic in [false, true]) {
          final font =
              PdfStandardFont.styled(family, bold: bold, italic: italic);
          expect(font.family, family);
          expect(font.isBold, bold);
          expect(font.isItalic, italic);
        }
      }
    }
    expect(PdfStandardFont.values.length, 12);

    // names round-trip with their style recovered
    expect(PdfStandardFont.fromName('Helvetica-Bold'),
        PdfStandardFont.helveticaBold);
    expect(PdfStandardFont.fromName('Helvetica-BoldOblique'),
        PdfStandardFont.helveticaBoldOblique);
    expect(
        PdfStandardFont.fromName('Times-Italic'), PdfStandardFont.timesItalic);
    expect(PdfStandardFont.fromName('Times-BoldItalic'),
        PdfStandardFont.timesBoldItalic);
    expect(PdfStandardFont.fromName('Courier-Oblique'),
        PdfStandardFont.courierOblique);
    // our own short /DA resource names recover too
    expect(PdfStandardFont.fromName('TimesBoldItalic'),
        PdfStandardFont.timesBoldItalic);
    expect(PdfStandardFont.fromName('CourBoldObl'),
        PdfStandardFont.courierBoldOblique);

    // withBold/withItalic flip one axis, keep the family
    expect(PdfStandardFont.times.withBold(true), PdfStandardFont.timesBold);
    expect(PdfStandardFont.timesBold.withItalic(true),
        PdfStandardFont.timesBoldItalic);

    // bold metrics differ from the regular face (AFM Times widths)
    expect(measureStandardText('M', 1000, font: PdfStandardFont.times), 889);
    expect(
        measureStandardText('M', 1000, font: PdfStandardFont.timesBold), 944);
    expect(
        measureStandardText('M', 1000, font: PdfStandardFont.timesItalic), 833);
  });

  test('bold-italic free text writes its variant /BaseFont and /Widths', () {
    final doc = roundTrip((e) => e.addFreeText(
        0, const PdfRect(72, 600, 240, 680), 'Bold italic',
        fontSize: 12, font: PdfStandardFont.timesBoldItalic));
    final annot = doc.page(0).annotations.single;
    final da = doc.cos.resolve(annot.dict['DA']) as CosString;
    expect(da.text, contains('/TimesBoldItalic 12 Tf'));
    final res = doc.cos.resolve(annot.normalAppearance!.dictionary['Resources'])
        as CosDictionary;
    final fonts = doc.cos.resolve(res['Font']) as CosDictionary;
    final font = doc.cos.resolve(fonts['TimesBoldItalic']) as CosDictionary;
    expect((doc.cos.resolve(font['BaseFont']) as CosName).value,
        'Times-BoldItalic');
    final widths = doc.cos.resolve(font['Widths']) as CosArray;
    // 'M' is code 77; Times-BoldItalic 'M' is 889/1000 em
    expect((widths.items[77 - 32] as CosInteger).value, 889);
  });

  test('free text on a rotated page counter-rotates the appearance', () {
    // Rotate the page 90° first, then add a FreeText with pageRotation: 90.
    // The appearance content must include a cm operator for the counter-
    // rotation so the text reads upright after the page transform.
    final editor = PdfEditor(PdfDocument.open(buildClassicPdf()))
      ..rotatePages([0], 90);
    final rotated = PdfDocument.open(editor.save());
    final editor2 = PdfEditor(rotated);
    editor2.addFreeText(
      0,
      const PdfRect(72, 600, 240, 680),
      'Hello rotated',
      fontSize: 12,
      pageRotation: 90,
    );
    final doc = PdfDocument.open(editor2.save());
    final ft = doc.page(0).annotations.single;
    expect(ft.subtype, 'FreeText');
    expect(doc.page(0).rotation, 90);
    final content = appearanceText(doc, ft);
    // The counter-rotation writes a cm operator with sin/cos coefficients
    expect(content, contains('cm'));
    // For 90° the matrix is [0, 1, -1, 0, cx+cy, cy-cx]
    expect(content, contains('0 1 -1 0'));
    // The text is still there
    expect(content, contains('BT'));
    expect(content, contains('Tj'));
  });

  test('free text on a 180-rotated page counter-rotates the appearance', () {
    final editor = PdfEditor(PdfDocument.open(buildClassicPdf()))
      ..rotatePages([0], 180);
    final rotated = PdfDocument.open(editor.save());
    final editor2 = PdfEditor(rotated);
    editor2.addFreeText(
      0,
      const PdfRect(72, 600, 240, 680),
      'Hello 180',
      fontSize: 12,
      pageRotation: 180,
    );
    final doc = PdfDocument.open(editor2.save());
    final content = appearanceText(doc, doc.page(0).annotations.single);
    expect(content, contains('cm'));
    // For 180° the matrix is [-1, 0, 0, -1, 2*cx, 2*cy]
    expect(content, contains('-1 0 0 -1'));
  });

  test('free text on a 270-rotated page counter-rotates the appearance', () {
    final editor = PdfEditor(PdfDocument.open(buildClassicPdf()))
      ..rotatePages([0], 270);
    final rotated = PdfDocument.open(editor.save());
    final editor2 = PdfEditor(rotated);
    editor2.addFreeText(
      0,
      const PdfRect(72, 600, 240, 680),
      'Hello 270',
      fontSize: 12,
      pageRotation: 270,
    );
    final doc = PdfDocument.open(editor2.save());
    final content = appearanceText(doc, doc.page(0).annotations.single);
    expect(content, contains('cm'));
    // For 270° the matrix is [0, -1, 1, 0, cx-cy, cx+cy]
    expect(content, contains('0 -1 1 0'));
  });

  test('rich free text on a rotated page counter-rotates the appearance', () {
    final editor = PdfEditor(PdfDocument.open(buildClassicPdf()))
      ..rotatePages([0], 90);
    final rotated = PdfDocument.open(editor.save());
    final editor2 = PdfEditor(rotated);
    editor2.addFreeTextRich(
      0,
      const PdfRect(72, 600, 240, 680),
      [
        const PdfFreeTextRun('Bold ', font: PdfStandardFont.helveticaBold),
        const PdfFreeTextRun('normal'),
      ],
      pageRotation: 90,
    );
    final doc = PdfDocument.open(editor2.save());
    final content = appearanceText(doc, doc.page(0).annotations.single);
    expect(content, contains('cm'));
    expect(content, contains('0 1 -1 0'));
    expect(content, contains('BT'));
  });

  test('free text on an unrotated page has no counter-rotation cm', () {
    final doc = roundTrip((e) => e.addFreeText(
          0,
          const PdfRect(72, 600, 240, 680),
          'No rotation',
          fontSize: 12,
          pageRotation: 0,
        ));
    final content = appearanceText(doc, doc.page(0).annotations.single);
    // No cm operator before the fill/text ops (only q/Q/re/W/BT etc.)
    expect(content, isNot(contains('0 1 -1 0')));
    expect(content, isNot(contains('-1 0 0 -1')));
    expect(content, isNot(contains('0 -1 1 0')));
  });

  test('note builds a 20pt icon at the given top-left corner', () {
    final doc = roundTrip(
        (e) => e.addNote(0, 500, 700, 'remember this', author: 'Ben'));
    final note = doc.page(0).annotations.single;
    expect(note.subtype, 'Text');
    expect(note.rect, const PdfRect(500, 680, 520, 700));
    expect((doc.cos.resolve(note.dict['Name']) as CosName).value, 'Comment');
    expect((doc.cos.resolve(note.dict['Contents']) as CosString).text,
        'remember this');
    expect(appearanceText(doc, note), contains('c')); // rounded corners
  });

  test('stamp centers bold text that fits the rect', () {
    final doc = roundTrip(
        (e) => e.addStamp(0, const PdfRect(100, 500, 260, 540), 'APPROVED'));
    final stamp = doc.page(0).annotations.single;
    expect(stamp.subtype, 'Stamp');

    final content = appearanceText(doc, stamp);
    expect(content, contains('/HelvB'));
    expect(content, contains('(APPROVED) Tj'));

    final form = stamp.normalAppearance!;
    final resources =
        doc.cos.resolve(form.dictionary['Resources']) as CosDictionary;
    final fonts = doc.cos.resolve(resources['Font']) as CosDictionary;
    final helvB = doc.cos.resolve(fonts['HelvB']) as CosDictionary;
    expect((doc.cos.resolve(helvB['BaseFont']) as CosName).value,
        'Helvetica-Bold');
  });

  test('custom stamp metadata is readable from the annotation', () {
    final doc = roundTrip((e) => e.addStamp(
          0,
          const PdfRect(100, 500, 260, 540),
          'AUDIT',
          stampType: 'Audit',
          stampTags: const ['external', 'field'],
        ));
    final stamp = doc.page(0).annotations.single;
    expect(stamp.stampType, 'Audit');
    expect(stamp.stampTags, ['external', 'field']);
  });

  test('a template stamp carries its design, with fields left unresolved', () {
    final template = PdfStampTemplate(
      width: 200,
      height: 100,
      components: [
        PdfStampTemplateComponent.rectangle(
            x: 0, y: 0, width: 200, height: 100, color: 0x2E7D32),
        PdfStampTemplateComponent.text(
            x: 10,
            y: 30,
            width: 180,
            height: 40,
            text: 'APPROVED {{date}}',
            color: 0x2E7D32),
      ],
    );
    final doc = roundTrip((e) => e.addTemplateStamp(
          0,
          const PdfRect(100, 500, 300, 600),
          template,
          contents: 'APPROVED {{date}}',
          templateValues: const {'date': '2026-08-06'},
        ));
    final stamp = doc.page(0).annotations.single;

    // what the page shows has the date filled in...
    expect(appearanceText(doc, stamp), contains('2026-08-06'));
    expect(stamp.contents, 'APPROVED 2026-08-06');
    // ...while the recorded design keeps the live field, so putting this
    // stamp back in a collection stamps tomorrow's date tomorrow
    expect(stamp.stampTemplate, template);
    expect(stamp.stampTemplate!.components[1].text, 'APPROVED {{date}}');
  });

  test('a template too large to record leaves the stamp without one', () {
    // In practice the cap only bites on a template carrying a picture, whose
    // bytes the appearance stream already pays for; a long caption is just
    // the deterministic way to blow it.
    final caption = 'A' * PdfAnnotationEditing.maxStampTemplateMetadataBytes;
    final huge = PdfStampTemplate(
      width: 200,
      height: 100,
      components: [
        PdfStampTemplateComponent.text(
            x: 0, y: 0, width: 200, height: 100, text: caption, color: 0),
      ],
    );
    final doc = roundTrip((e) => e.addTemplateStamp(
        0, const PdfRect(100, 500, 300, 600), huge,
        contents: 'HUGE'));
    final stamp = doc.page(0).annotations.single;
    expect(stamp.stampTemplate, isNull);
    // the stamp itself is unaffected - it still draws its design
    expect(appearanceText(doc, stamp), contains('Tj'));
  });

  test('only a /Stamp reads back a template', () {
    final doc = roundTrip((e) => e.addNote(0, 500, 700, 'note'));
    expect(doc.page(0).annotations.single.stampTemplate, isNull);
  });

  test('oriented annotations on rotated pages counter-rotate appearances', () {
    final editor = PdfEditor(PdfDocument.open(buildClassicPdf()))
      ..rotatePages([0], 90);
    final rotated = PdfDocument.open(editor.save());
    final editor2 = PdfEditor(rotated)
      ..addNote(0, 500, 700, 'rotated note')
      ..addStamp(0, const PdfRect(100, 500, 140, 660), 'APPROVED')
      ..addCheckMark(0, const PdfRect(200, 500, 220, 520));

    final doc = PdfDocument.open(editor2.save());
    expect(doc.page(0).rotation, 90);
    final annotations = doc.page(0).annotations;
    expect(annotations.map((a) => a.subtype), ['Text', 'Stamp', 'Stamp']);
    for (final annotation in annotations) {
      final content = appearanceText(doc, annotation);
      expect(content, contains('cm'));
      expect(content, contains('0 1 -1 0'));
    }
    expect(appearanceText(doc, annotations[1]), contains('(APPROVED) Tj'));
    expect(annotations[2].isCheckMark, isTrue);
  });

  test('annotations append to an existing /Annots array', () {
    final first = PdfEditor(PdfDocument.open(buildAnnotatedPdf()));
    final before =
        PdfDocument.open(buildAnnotatedPdf()).page(0).annotations.length;
    first.addNote(0, 500, 700, 'appended');
    final doc = PdfDocument.open(first.save());
    final annots = doc.page(0).annotations;
    expect(annots.length, before + 1);
    expect(annots.last.subtype, 'Text');
    // existing annotations are untouched
    expect(annots.first.subtype, 'Link');
  });

  test('adding an annotation abandons a malformed indirect /Annots value', () {
    final doc = PdfDocument.open(buildMalformedAnnotsPdf());
    final badRef = doc.page(0).dict['Annots'] as CosReference;
    expect(doc.cos.resolve(badRef), isA<CosString>());

    final editor = PdfEditor(doc)
      ..addSquare(0, const PdfRect(100, 100, 200, 150));
    final reopened = PdfDocument.open(editor.save());

    final raw = reopened.page(0).dict['Annots'];
    expect(raw, isA<CosArray>());
    expect(reopened.cos.resolve(badRef), isA<CosString>(),
        reason: 'the invalid referenced object is not overwritten');
    expect(reopened.page(0).annotations.single.subtype, 'Square');
  });

  test('appearance BBox equals the annotation rect (identity mapping)', () {
    final doc =
        roundTrip((e) => e.addSquare(0, const PdfRect(10, 20, 110, 70)));
    final annot = doc.page(0).annotations.single;
    final bbox =
        pdfRectFrom(doc.cos, annot.normalAppearance!.dictionary['BBox']);
    expect(bbox, annot.rect);
  });

  test('the original bytes survive as a prefix (incremental update)', () {
    final original = buildClassicPdf();
    final editor = PdfEditor(PdfDocument.open(original))
      ..addNote(0, 500, 700, 'incremental');
    final saved = editor.save();
    expect(saved.length, greaterThan(original.length));
    expect(saved.sublist(0, original.length), original);
  });

  test('removeAnnotation deletes the annotation from /Annots', () {
    final first = PdfEditor(PdfDocument.open(buildClassicPdf()))
      ..addSquare(0, const PdfRect(100, 100, 200, 150))
      ..addNote(0, 300, 700, 'keep me');
    final doc = PdfDocument.open(first.save());
    final square = doc.page(0).annotations.first;
    expect(square.subtype, 'Square');

    final editor = PdfEditor(doc)..removeAnnotation(0, square);
    final reopened = PdfDocument.open(editor.save());
    final remaining = reopened.page(0).annotations;
    expect(remaining, hasLength(1));
    expect(remaining.single.subtype, 'Text');
  });

  test('removeAnnotation on an existing indirect /Annots array', () {
    final seeded = PdfEditor(PdfDocument.open(buildIndirectAnnotsPdf()))
      ..addSquare(0, const PdfRect(100, 100, 200, 150))
      ..addNote(0, 300, 700, 'keep me');
    final doc = PdfDocument.open(seeded.save());
    final before = doc.page(0).annotations.length;
    final editor = PdfEditor(doc)
      ..removeAnnotation(0, doc.page(0).annotations.first);
    final reopened = PdfDocument.open(editor.save());
    expect(reopened.page(0).annotations.length, before - 1);
  });

  test('remove then append composes on an indirect /Annots array', () {
    final seeded = PdfEditor(PdfDocument.open(buildIndirectAnnotsPdf()))
      ..addSquare(0, const PdfRect(100, 100, 200, 150));
    final doc = PdfDocument.open(seeded.save());
    final removed = doc.page(0).annotations.single;
    final editor = PdfEditor(doc)
      ..removeAnnotation(0, removed)
      ..addNote(0, 500, 700, 'replacement');

    final after = PdfDocument.open(editor.save()).page(0).annotations;
    expect(after, hasLength(1));
    expect(after.single.subtype, 'Text');
    expect(after.single.contents, 'replacement');
  });

  test('removeAnnotations deletes multiple annotations in one edit', () {
    final first = PdfEditor(PdfDocument.open(buildClassicPdf()))
      ..addSquare(0, const PdfRect(100, 100, 200, 150))
      ..addNote(0, 300, 700, 'remove me')
      ..addCircle(0, const PdfRect(250, 100, 350, 150))
      ..addFreeText(0, const PdfRect(120, 500, 260, 540), 'keep me');
    final doc = PdfDocument.open(first.save());
    final annotations = doc.page(0).annotations;

    final editor = PdfEditor(doc)
      ..removeAnnotations(0, [annotations[0], annotations[1], annotations[2]]);
    final reopened = PdfDocument.open(editor.save());

    final remaining = reopened.page(0).annotations;
    expect(remaining, hasLength(1));
    expect(remaining.single.subtype, 'FreeText');
    expect(remaining.single.contents, 'keep me');
  });

  test('bringAnnotationsToFront moves entries to the end of /Annots', () {
    final first = PdfEditor(PdfDocument.open(buildClassicPdf()))
      ..addSquare(0, const PdfRect(100, 100, 200, 150))
      ..addNote(0, 300, 700, 'middle')
      ..addCircle(0, const PdfRect(250, 100, 350, 150));
    final doc = PdfDocument.open(first.save());
    expect([for (final a in doc.page(0).annotations) a.subtype],
        ['Square', 'Text', 'Circle']);

    final editor = PdfEditor(doc)
      ..bringAnnotationsToFront(0, [doc.page(0).annotations.first]);
    final reopened = PdfDocument.open(editor.save());
    expect([for (final a in reopened.page(0).annotations) a.subtype],
        ['Text', 'Circle', 'Square']);
  });

  test('sendAnnotationsToBack moves entries to the start, keeping order', () {
    final first = PdfEditor(PdfDocument.open(buildClassicPdf()))
      ..addSquare(0, const PdfRect(100, 100, 200, 150))
      ..addNote(0, 300, 700, 'middle')
      ..addCircle(0, const PdfRect(250, 100, 350, 150));
    final doc = PdfDocument.open(first.save());

    // the middle and last move back together: relative order preserved
    final annots = doc.page(0).annotations;
    final editor = PdfEditor(doc)
      ..sendAnnotationsToBack(0, [annots[1], annots[2]]);
    final reopened = PdfDocument.open(editor.save());
    expect([for (final a in reopened.page(0).annotations) a.subtype],
        ['Text', 'Circle', 'Square']);
  });

  test('reordering to where an annotation already sits stages nothing', () {
    final first = PdfEditor(PdfDocument.open(buildClassicPdf()))
      ..addSquare(0, const PdfRect(100, 100, 200, 150))
      ..addNote(0, 300, 700, 'top');
    final doc = PdfDocument.open(first.save());
    final annots = doc.page(0).annotations;

    final editor = PdfEditor(doc)
      ..bringAnnotationsToFront(0, [annots.last])
      ..sendAnnotationsToBack(0, [annots.first]);
    expect(editor.hasChanges, isFalse);
  });

  test('moveAnnotation shifts rect, quad points, and ink lists', () {
    final first = PdfEditor(PdfDocument.open(buildClassicPdf()))
      ..addHighlight(0, const [PdfRect(72, 700, 200, 712)])
      ..addInk(0, [
        [(100, 100), (150, 130)],
      ]);
    final doc = PdfDocument.open(first.save());

    final editor = PdfEditor(doc)
      ..moveAnnotation(0, doc.page(0).annotations[0], 10, -20)
      ..moveAnnotation(0, doc.page(0).annotations[1], 5, 5);
    final reopened = PdfDocument.open(editor.save());

    final highlight = reopened.page(0).annotations[0];
    expect(highlight.rect, const PdfRect(82, 680, 210, 692));
    final quads =
        reopened.cos.resolve(highlight.dict['QuadPoints']) as CosArray;
    expect((reopened.cos.resolve(quads[0]) as CosReal).value, 82); // left
    expect((reopened.cos.resolve(quads[1]) as CosReal).value, 692); // top

    final ink = reopened.page(0).annotations[1];
    final inkList = reopened.cos.resolve(ink.dict['InkList']) as CosArray;
    final stroke = reopened.cos.resolve(inkList[0]) as CosArray;
    expect((reopened.cos.resolve(stroke[0]) as CosReal).value, 105);
    expect((reopened.cos.resolve(stroke[1]) as CosReal).value, 105);
  });

  test('a moved annotation still renders: BBox maps onto the new rect', () {
    // the fixture square's appearance BBox is [0 0 10 10] over rect
    // (100,100)-(200,150) - after a move the §12.5.5 mapping must land it
    // on the new rect without touching the stream
    final doc = PdfDocument.open(buildAppearanceAnnotationsPdf());
    final editor = PdfEditor(doc)
      ..moveAnnotation(0, doc.page(0).annotations.first, 50, 100);
    final reopened = PdfDocument.open(editor.save());
    final moved = reopened.page(0).annotations.first;
    expect(moved.rect, const PdfRect(150, 200, 250, 250));
    expect(moved.normalAppearance, isNotNull);
  });

  test('resizeAnnotation rewrites the rect and scales point arrays', () {
    final first = PdfEditor(PdfDocument.open(buildClassicPdf()))
      ..addSquare(0, const PdfRect(100, 100, 200, 150))
      ..addInk(0, [
        [(100, 100), (200, 150)],
      ]);
    final doc = PdfDocument.open(first.save());

    final square = doc.page(0).annotations[0];
    final ink = doc.page(0).annotations[1];
    final inkTo = PdfRect(ink.rect.left, ink.rect.bottom,
        ink.rect.left + ink.rect.width * 2, ink.rect.top);
    final editor = PdfEditor(doc)
      ..resizeAnnotation(0, square, const PdfRect(100, 100, 300, 250))
      ..resizeAnnotation(0, ink, inkTo);
    final reopened = PdfDocument.open(editor.save());

    final resized = reopened.page(0).annotations[0];
    expect(resized.rect, const PdfRect(100, 100, 300, 250));
    // shapes regenerate their appearance at the new size (ink keeps the
    // §12.5.5 stretch - its rect doubles below and the points follow)
    expect(resized.normalAppearance, isNotNull);

    // ink points scale with the rect: x doubled relative to the rect's
    // left edge, y unchanged
    final inkRect = ink.rect;
    final resizedInk = reopened.page(0).annotations[1];
    final inkList =
        reopened.cos.resolve(resizedInk.dict['InkList']) as CosArray;
    final stroke = reopened.cos.resolve(inkList[0]) as CosArray;
    double at(int i) => (reopened.cos.resolve(stroke[i]) as CosReal).value;
    expect(at(0), closeTo(inkRect.left + (100 - inkRect.left) * 2, 1e-6));
    expect(at(1), closeTo(100, 1e-6));
    expect(at(2), closeTo(inkRect.left + (200 - inkRect.left) * 2, 1e-6));
    expect(at(3), closeTo(150, 1e-6));
  });

  test('resizing a square regenerates the appearance at constant stroke width',
      () {
    final first = PdfEditor(PdfDocument.open(buildClassicPdf()))
      ..addSquare(0, const PdfRect(100, 100, 200, 150),
          strokeWidth: 4, fillColor: 0x00FF00, opacity: 0.5);
    final doc = PdfDocument.open(first.save());

    final editor = PdfEditor(doc)
      ..resizeAnnotation(
          0, doc.page(0).annotations.single, const PdfRect(100, 100, 400, 350));
    final reopened = PdfDocument.open(editor.save());

    final square = reopened.page(0).annotations.single;
    final content = appearanceText(reopened, square);
    // the new geometry at the OLD stroke width: a doubled rect would have
    // come out of a §12.5.5 stretch as an 8pt-wide line
    expect(content, contains('4 w'));
    expect(content, contains('102 102 296 246 re'));
    expect(content, contains('B')); // fill + stroke
    // the opacity round-trips through the regenerated GS0
    final resources =
        reopened.cos.resolve(square.normalAppearance!.dictionary['Resources'])
            as CosDictionary;
    final gstates =
        reopened.cos.resolve(resources['ExtGState']) as CosDictionary;
    final gs0 = reopened.cos.resolve(gstates['GS0']) as CosDictionary;
    expect(
        (reopened.cos.resolve(gs0['ca']) as CosReal).value, closeTo(0.5, 1e-9));
    // no stretch matrix: the regenerated form maps 1:1
    expect(square.normalAppearance!.dictionary['Matrix'], isNull);
  });

  test('resizing a fill-only circle regenerates fill without a stroke', () {
    final first = PdfEditor(PdfDocument.open(buildClassicPdf()))
      ..addCircle(0, const PdfRect(100, 100, 200, 150),
          strokeColor: null, fillColor: 0x2060C0);
    final doc = PdfDocument.open(first.save());

    final editor = PdfEditor(doc)
      ..resizeAnnotation(
          0, doc.page(0).annotations.single, const PdfRect(50, 50, 350, 250));
    final reopened = PdfDocument.open(editor.save());

    final content =
        appearanceText(reopened, reopened.page(0).annotations.single);
    expect(content, contains('c')); // the ellipse Béziers
    expect(content.trimRight(), endsWith('f')); // filled, not stroked
    // the new ellipse spans the new rect: center (200,150), rx 150
    expect(content, contains('350 150')); // right extreme of the ellipse
  });

  test('a dashed shape regenerates on resize, keeping its dash', () {
    final first = PdfEditor(PdfDocument.open(buildClassicPdf()))
      ..addSquare(0, const PdfRect(100, 100, 200, 150), dashPattern: const [3]);
    final doc = PdfDocument.open(first.save());

    final square = doc.page(0).annotations.single;
    expect(square.borderDash, [3]);
    final editor = PdfEditor(doc)
      ..resizeAnnotation(0, square, const PdfRect(100, 100, 400, 350));
    final reopened = PdfDocument.open(editor.save());

    final resized = reopened.page(0).annotations.single;
    expect(resized.rect, const PdfRect(100, 100, 400, 350));
    // dashed shapes regenerate at a constant stroke width now (like solid
    // ones), so the appearance paints the NEW geometry, still dashed
    final content = appearanceText(reopened, resized);
    expect(content, contains('101 101 298 248 re'));
    expect(content, contains('[3] 0 d'));
  });

  test('line and arrow annotations carry endpoints and line endings', () {
    final doc = roundTrip((e) {
      e.addLine(0, (100, 100), (200, 140),
          strokeColor: 0x2040A0,
          strokeWidth: 3,
          dashPattern: const [9, 6],
          endEnding: PdfLineEnding.closedArrow,
          author: 'Ben');
    });

    final line = doc.page(0).annotations.single;
    expect(line.subtype, 'Line');
    expect(line.line, ((100.0, 100.0), (200.0, 140.0)));
    expect(line.borderWidth, 3);
    expect(line.borderDash, isNotNull);
    final le = doc.cos.resolve(line.dict['LE']) as CosArray;
    expect((doc.cos.resolve(le[0]) as CosName).value, 'None');
    expect((doc.cos.resolve(le[1]) as CosName).value, 'ClosedArrow');
    final content = appearanceText(doc, line);
    expect(content, contains('[9 6] 0 d'));
    expect(content, contains('100 100 m'));
    expect(content, contains('200 140 l'));
    expect(content, contains('f'));
    expect((doc.cos.resolve(line.dict['T']) as CosString).text, 'Ben');
  });

  test('polyline and polygon annotations carry vertices', () {
    final doc = roundTrip((e) {
      e.addPolyLine(0, [(100, 100), (140, 130), (180, 110)]);
      e.addPolygon(0, [(220, 100), (260, 140), (300, 100)],
          fillColor: 0xFFE0E0, dashPattern: const [6, 4]);
    });

    final annots = doc.page(0).annotations;
    expect(annots[0].subtype, 'PolyLine');
    expect(
        annots[0].vertices, [(100.0, 100.0), (140.0, 130.0), (180.0, 110.0)]);
    expect(appearanceText(doc, annots[0]), isNot(contains('h')));

    expect(annots[1].subtype, 'Polygon');
    expect(
        annots[1].vertices, [(220.0, 100.0), (260.0, 140.0), (300.0, 100.0)]);
    expect(annots[1].interiorColor, 0xFFE0E0);
    final content = appearanceText(doc, annots[1]);
    expect(content, contains('h'));
    expect(content, contains('B'));
    expect(content, contains('[6 4] 0 d'));
  });

  test('cloud polygon carries border effect and generated cloud appearance',
      () {
    final doc = roundTrip((e) {
      e.addPolygon(
        0,
        [(100, 100), (220, 100), (220, 180), (100, 180)],
        strokeWidth: 3,
        fillColor: 0xE8F2FF,
        cloudy: true,
      );
    });

    final annotation = doc.page(0).annotations.single;
    expect(annotation.subtype, 'Polygon');
    expect(annotation.hasCloudyBorder, isTrue);
    expect(annotation.vertices, [
      (100.0, 100.0),
      (220.0, 100.0),
      (220.0, 180.0),
      (100.0, 180.0),
    ]);
    final be = doc.cos.resolve(annotation.dict['BE']) as CosDictionary;
    expect((doc.cos.resolve(be['S']) as CosName).value, 'Cloudy');
    expect(annotation.rect.left, lessThan(100));
    expect(annotation.rect.right, greaterThan(220));
    final content = appearanceText(doc, annotation);
    expect(content, contains(' c\n'));
    // The scalloped cloud outline is filled and stroked in one pass (B), so
    // the interior colour reaches the puffed edges rather than stopping at
    // the straight polygon footprint.
    expect(content, contains('B\n'));
  });

  test('cloud scallops stay inside the form BBox (no clipped puffs)', () {
    // A rectangle's every edge lies on the box extreme, so the outward puffs
    // protrude by the full bulge. If /Rect and the form BBox are not padded
    // enough, the form XObject clips the outer half of each scallop.
    final doc = roundTrip((e) {
      e.addPolygon(
        0,
        [(120, 500), (420, 500), (420, 640), (120, 640)],
        strokeWidth: 2,
        cloudy: true,
      );
    });
    final annotation = doc.page(0).annotations.single;
    final bbox = doc.cos
        .resolve(annotation.normalAppearance!.dictionary['BBox']) as CosArray;
    double num(CosObject o) {
      final r = doc.cos.resolve(o);
      return switch (r) {
        CosInteger(:final value) => value.toDouble(),
        CosReal(:final value) => value,
        _ => throw StateError('not a number: $r'),
      };
    }

    final bx0 = num(bbox[0]);
    final by0 = num(bbox[1]);
    final bx1 = num(bbox[2]);
    final by1 = num(bbox[3]);

    // Walk every path-construction coordinate in the appearance stream and
    // confirm it (plus half the stroke) lands inside the BBox.
    final content = appearanceText(doc, annotation);
    final tokens = content.split(RegExp(r'\s+'));
    final nums = <double>[];
    var minX = double.infinity, minY = double.infinity;
    var maxX = double.negativeInfinity, maxY = double.negativeInfinity;
    void point(double x, double y) {
      if (x < minX) minX = x;
      if (y < minY) minY = y;
      if (x > maxX) maxX = x;
      if (y > maxY) maxY = y;
    }

    for (final token in tokens) {
      final value = double.tryParse(token);
      if (value != null) {
        nums.add(value);
        continue;
      }
      switch (token) {
        case 'm':
        case 'l':
          if (nums.length >= 2) {
            point(nums[nums.length - 2], nums[nums.length - 1]);
          }
        case 'c':
          if (nums.length >= 6) {
            for (var i = nums.length - 6; i < nums.length; i += 2) {
              point(nums[i], nums[i + 1]);
            }
          }
      }
      nums.clear();
    }

    expect(maxX, greaterThan(minX), reason: 'sanity: some path was parsed');
    const halfStroke = 1.0; // strokeWidth 2 / 2
    expect(minX - halfStroke, greaterThanOrEqualTo(bx0));
    expect(minY - halfStroke, greaterThanOrEqualTo(by0));
    expect(maxX + halfStroke, lessThanOrEqualTo(bx1));
    expect(maxY + halfStroke, lessThanOrEqualTo(by1));
    // and the puffs really do bulge out past the polygon vertices
    expect(maxY, greaterThan(640));
    expect(minY, lessThan(500));
  });

  test('a cloud scale rides on /BE /I and bulges bigger scallops', () {
    // The scallop size is driven by cloudScale, independent of the pen.
    Iterable<double> puffExtent(double scale) {
      final doc = roundTrip((e) {
        e.addPolygon(
          0,
          [(120, 500), (420, 500), (420, 640), (120, 640)],
          strokeWidth: 2,
          cloudy: true,
          cloudScale: scale,
        );
      });
      final annotation = doc.page(0).annotations.single;
      expect(annotation.cloudBorderScale, closeTo(scale, 1e-9));
      final be = doc.cos.resolve(annotation.dict['BE']) as CosDictionary;
      expect((doc.cos.resolve(be['I']) as CosReal).value, closeTo(scale, 1e-9));
      // how far the /Rect balloons past the polygon footprint - a proxy for
      // the scallop bulge
      return [
        120 - annotation.rect.left,
        annotation.rect.right - 420,
        annotation.rect.top - 640,
      ];
    }

    final small = puffExtent(1).toList();
    final big = puffExtent(2.5).toList();
    for (var i = 0; i < small.length; i++) {
      expect(big[i], greaterThan(small[i]));
    }
  });

  test('restyling a cloud preserves its scale across a colour change', () {
    final doc = roundTrip((e) {
      e.addPolygon(
        0,
        [(120, 500), (420, 500), (420, 640), (120, 640)],
        strokeWidth: 2,
        cloudy: true,
        cloudScale: 2.5,
      );
    });
    final editor = PdfEditor(doc)
      ..restyleAnnotation(0, doc.page(0).annotations.single, color: 0x123456);
    final reopened = PdfDocument.open(editor.save());
    final annotation = reopened.page(0).annotations.single;
    expect(annotation.hasCloudyBorder, isTrue);
    expect(annotation.cloudBorderScale, closeTo(2.5, 1e-9));
    // and the puffs are still the wider ones the scale asked for
    expect(annotation.rect.top - 640, greaterThan(20));
  });

  test('restyleAnnotation cloudScale resizes the scallops', () {
    final doc = roundTrip((e) {
      e.addPolygon(
        0,
        [(120, 500), (420, 500), (420, 640), (120, 640)],
        strokeWidth: 2,
        cloudy: true,
      );
    });
    final before = doc.page(0).annotations.single.rect.top - 640;
    final editor = PdfEditor(doc)
      ..restyleAnnotation(0, doc.page(0).annotations.single, cloudScale: 3);
    final reopened = PdfDocument.open(editor.save());
    final annotation = reopened.page(0).annotations.single;
    expect(annotation.cloudBorderScale, closeTo(3, 1e-9));
    expect(annotation.rect.top - 640, greaterThan(before));
  });

  test('resizing a dashed arrow regenerates with scaled endpoints', () {
    final first = PdfEditor(PdfDocument.open(buildClassicPdf()))
      ..addLine(0, (100, 100), (200, 140),
          strokeWidth: 3,
          dashPattern: const [9, 6],
          endEnding: PdfLineEnding.closedArrow);
    final doc = PdfDocument.open(first.save());

    final editor = PdfEditor(doc)
      ..resizeAnnotation(
          0, doc.page(0).annotations.single, const PdfRect(50, 50, 350, 250));
    final reopened = PdfDocument.open(editor.save());

    final line = reopened.page(0).annotations.single;
    expect(line.line!.$1.$1, closeTo(61.111111, 1e-6));
    expect(line.line!.$1.$2, closeTo(66.666667, 1e-6));
    expect(line.line!.$2.$1, closeTo(338.888889, 1e-6));
    expect(line.line!.$2.$2, closeTo(233.333333, 1e-6));
    final content = appearanceText(reopened, line);
    expect(content, contains('[9 6] 0 d'));
    expect(content, contains('61.111 66.667 m'));
    expect(content, contains('338.889 233.333 l'));
    expect(line.normalAppearance!.dictionary['Matrix'], isNull);
  });

  test('reshaping line annotations rewrites vertices and appearance', () {
    final first = PdfEditor(PdfDocument.open(buildClassicPdf()))
      ..addLine(0, (100, 100), (200, 140),
          strokeWidth: 3,
          dashPattern: const [9, 6],
          endEnding: PdfLineEnding.closedArrow)
      ..addPolyLine(0, [(100, 220), (140, 250), (180, 230)]);
    final doc = PdfDocument.open(first.save());

    final editor = PdfEditor(doc)
      ..reshapeLineAnnotation(
          0, doc.page(0).annotations[0], [(90, 95), (240, 160)])
      ..reshapeLineAnnotation(
          0, doc.page(0).annotations[1], [(100, 220), (160, 280), (180, 230)]);
    final reopened = PdfDocument.open(editor.save());

    final line = reopened.page(0).annotations[0];
    expect(line.line, ((90.0, 95.0), (240.0, 160.0)));
    expect(line.borderDash, isNotNull);
    final lineContent = appearanceText(reopened, line);
    expect(lineContent, contains('90 95 m'));
    expect(lineContent, contains('240 160 l'));
    expect(lineContent, contains('f'), reason: 'closed arrowhead preserved');

    final poly = reopened.page(0).annotations[1];
    expect(poly.vertices, [(100.0, 220.0), (160.0, 280.0), (180.0, 230.0)]);
    expect(appearanceText(reopened, poly), contains('160 280 l'));
  });

  test('resizing free text re-wraps at the same font size', () {
    const text = 'several words that wrap differently at different widths';
    final first = PdfEditor(PdfDocument.open(buildClassicPdf()))
      ..addFreeText(0, const PdfRect(100, 100, 200, 200), text);
    final doc = PdfDocument.open(first.save());

    final narrow = appearanceText(doc, doc.page(0).annotations.single);
    final editor = PdfEditor(doc)
      ..resizeAnnotation(
          0, doc.page(0).annotations.single, const PdfRect(100, 100, 450, 200));
    final reopened = PdfDocument.open(editor.save());

    final wide = appearanceText(reopened, reopened.page(0).annotations.single);
    expect(wide, contains('/Helv 12 Tf')); // font size unchanged
    int lines(String s) => ' Tj'.allMatches(s).length;
    expect(lines(narrow), greaterThan(1));
    expect(lines(wide), lessThan(lines(narrow))); // fewer wrapped lines
    expect(reopened.page(0).annotations.single.rect,
        const PdfRect(100, 100, 450, 200));
  });

  test('a box auto-sized to its line width keeps the text on one line', () {
    // Auto-size sets the rect width to measure(line) + 2*pad (pad = 3), and
    // the wrapper breaks at width - 2*pad. The two cancel in exact math, but
    // `(w + 6) - 6` rounds to a hair under `w`, so a strict comparison used
    // to push the last word onto a second line. These three lines reproduce
    // that round-off at 12pt and 18pt Helvetica.
    for (final (text, size) in const [
      ('Date brown', 12.0),
      ('Notes Total', 12.0),
      ('Hello Customer', 18.0),
    ]) {
      const pad = 3.0;
      final lineWidth = measureStandardText(text, size);
      final width = lineWidth + 2 * pad;
      final doc = roundTrip((e) => e.addFreeText(
            0,
            PdfRect(100, 600, 100 + width, 660),
            text,
            fontSize: size,
          ));
      final content = appearanceText(doc, doc.page(0).annotations.single);
      expect(' Tj'.allMatches(content).length, 1,
          reason: '"$text" at ${size}pt fits its own width on one line');
    }
  });

  test('free text persists and regenerates fill and border', () {
    final first = PdfEditor(PdfDocument.open(buildClassicPdf()))
      ..addFreeText(0, const PdfRect(100, 100, 250, 180), 'styled box',
          fillColor: 0xFFFBE6, borderColor: 0x806820, borderWidth: 2);
    final doc = PdfDocument.open(first.save());

    final style = doc.page(0).annotations.single.freeTextStyle!;
    expect(style.color, 0x000000);
    expect(style.fillColor, 0xFFFBE6);
    expect(style.borderColor, 0x806820);
    expect(style.borderWidth, 2);
    expect(style.fontName, 'Helv');
    expect(style.fontSize, 12);

    final editor = PdfEditor(doc)
      ..resizeAnnotation(
          0, doc.page(0).annotations.single, const PdfRect(100, 100, 400, 300));
    final reopened = PdfDocument.open(editor.save());

    final box = reopened.page(0).annotations.single;
    final content = appearanceText(reopened, box);
    expect(content, contains('100 100 300 200 re')); // background at new size
    expect(content, contains('2 w')); // border width survives
    expect(content, contains('RG')); // stroked border color
    // and the style still parses identically from the resized annotation
    final after = box.freeTextStyle!;
    expect(after.fillColor, 0xFFFBE6);
    expect(after.borderColor, 0x806820);
  });

  test('plain free text reads back without a phantom background', () {
    final first = PdfEditor(PdfDocument.open(buildClassicPdf()))
      ..addFreeText(0, const PdfRect(100, 100, 250, 180), 'plain',
          color: 0xD02020);
    final doc = PdfDocument.open(first.save());
    final style = doc.page(0).annotations.single.freeTextStyle!;
    expect(style.color, 0xD02020);
    // legacy-compatible /C (mirroring the text color) is not a background
    expect(style.fillColor, isNull);
    expect(style.borderColor, isNull);
  });

  test('PdfTextAlign maps to and from /Q quadding', () {
    expect(PdfTextAlign.left.quadding, 0);
    expect(PdfTextAlign.center.quadding, 1);
    expect(PdfTextAlign.right.quadding, 2);
    expect(PdfTextAlign.fromQuadding(0), PdfTextAlign.left);
    expect(PdfTextAlign.fromQuadding(1), PdfTextAlign.center);
    expect(PdfTextAlign.fromQuadding(2), PdfTextAlign.right);
    expect(PdfTextAlign.fromQuadding(null), PdfTextAlign.left);
    expect(PdfTextAlign.fromQuadding(7), PdfTextAlign.left);
  });

  test('free text alignment writes /Q and shifts the line', () {
    PdfDocument make(PdfTextAlign align) => roundTrip((e) => e.addFreeText(
          0,
          const PdfRect(100, 600, 400, 640),
          'Hi',
          align: align,
        ));

    final left = make(PdfTextAlign.left);
    final center = make(PdfTextAlign.center);
    final right = make(PdfTextAlign.right);

    int quad(PdfDocument d) =>
        (d.cos.resolve(d.page(0).annotations.single.dict['Q']) as CosInteger)
            .value;
    expect(quad(left), 0);
    expect(quad(center), 1);
    expect(quad(right), 2);

    // alignment round-trips through the parsed style
    expect(left.page(0).annotations.single.freeTextStyle!.alignment,
        PdfTextAlign.left);
    expect(center.page(0).annotations.single.freeTextStyle!.alignment,
        PdfTextAlign.center);
    expect(right.page(0).annotations.single.freeTextStyle!.alignment,
        PdfTextAlign.right);

    double lineX(PdfDocument d) {
      final content = appearanceText(d, d.page(0).annotations.single);
      final m = RegExp(r'(-?[\d.]+) -?[\d.]+ Td').firstMatch(content);
      return double.parse(m!.group(1)!);
    }

    // left hugs the padded left edge (100 + 3pt pad); center and right
    // move the line progressively rightward in the 300pt-wide box
    expect(lineX(left), closeTo(103, 0.5));
    expect(lineX(center), greaterThan(lineX(left) + 20));
    expect(lineX(right), greaterThan(lineX(center)));
  });

  test('resizing a centered free text box keeps it centered', () {
    final first = PdfEditor(PdfDocument.open(buildClassicPdf()))
      ..addFreeText(0, const PdfRect(100, 600, 300, 640), 'Centered',
          align: PdfTextAlign.center);
    final doc = PdfDocument.open(first.save());
    expect(doc.page(0).annotations.single.freeTextStyle!.alignment,
        PdfTextAlign.center);

    final editor = PdfEditor(doc)
      ..resizeAnnotation(
          0, doc.page(0).annotations.single, const PdfRect(100, 600, 500, 640));
    final reopened = PdfDocument.open(editor.save());
    final box = reopened.page(0).annotations.single;
    // /Q (and so the alignment) survives the regenerated appearance
    expect((reopened.cos.resolve(box.dict['Q']) as CosInteger).value, 1);
    expect(box.freeTextStyle!.alignment, PdfTextAlign.center);

    // the line is centered in the now-wider box: x is well past the left pad
    final content = appearanceText(reopened, box);
    final m = RegExp(r'(-?[\d.]+) -?[\d.]+ Td').firstMatch(content);
    expect(double.parse(m!.group(1)!), greaterThan(150));
  });

  test('free text line/character spacing and width round-trip and emit', () {
    final doc = roundTrip((e) => e.addFreeText(
          0,
          const PdfRect(100, 600, 400, 660),
          'Spaced out text',
          lineSpacing: 2.0,
          charSpacing: 3,
          horizontalScale: 150,
        ));
    final box = doc.page(0).annotations.single;
    final style = box.freeTextStyle!;
    expect(style.lineSpacing, closeTo(2.0, 1e-9));
    expect(style.charSpacing, closeTo(3, 1e-9));
    expect(style.horizontalScale, closeTo(150, 1e-9));

    final content = appearanceText(doc, box);
    expect(content, contains('3 Tc'));
    expect(content, contains('150 Tz'));
    // leading is fontSize (12) * lineSpacing (2) = 24
    expect(content, contains('24 TL'));

    // the values survive a resize (which regenerates the appearance)
    final editor = PdfEditor(doc)
      ..resizeAnnotation(0, box, const PdfRect(100, 600, 520, 660));
    final reopened = PdfDocument.open(editor.save());
    final resized = reopened.page(0).annotations.single.freeTextStyle!;
    expect(resized.lineSpacing, closeTo(2.0, 1e-9));
    expect(resized.charSpacing, closeTo(3, 1e-9));
    expect(resized.horizontalScale, closeTo(150, 1e-9));
    expect(appearanceText(reopened, reopened.page(0).annotations.single),
        contains('150 Tz'));
  });

  test('a plain free text box writes no spacing keys', () {
    final doc = roundTrip(
        (e) => e.addFreeText(0, const PdfRect(100, 600, 400, 640), 'Plain'));
    final dict = doc.page(0).annotations.single.dict;
    expect(dict[kPdfFreeTextLineSpacingKey], isNull);
    expect(dict[kPdfFreeTextCharSpacingKey], isNull);
    expect(dict[kPdfFreeTextHScaleKey], isNull);
    expect(dict[kPdfFreeTextUnderlineKey], isNull);
  });

  test('underlined free text draws a rule and round-trips the flag', () {
    final doc = roundTrip((e) => e.addFreeText(
          0,
          const PdfRect(100, 600, 400, 640),
          'Underlined',
          underline: true,
        ));
    final box = doc.page(0).annotations.single;
    expect(box.freeTextStyle!.underline, isTrue);
    // the underline is a filled rectangle drawn after the text object
    final content = appearanceText(doc, box);
    expect(content, contains('ET'));
    expect(content.lastIndexOf(' re'), greaterThan(content.lastIndexOf('ET')));

    // it survives a resize
    final editor = PdfEditor(doc)
      ..resizeAnnotation(0, box, const PdfRect(100, 600, 500, 640));
    final reopened = PdfDocument.open(editor.save());
    expect(
        reopened.page(0).annotations.single.freeTextStyle!.underline, isTrue);
  });

  test('rich free text carries per-run underline through /RC', () {
    final doc = roundTrip((e) => e.addFreeTextRich(
          0,
          const PdfRect(100, 600, 400, 640),
          const [
            PdfFreeTextRun('plain '),
            PdfFreeTextRun('under', underline: true),
          ],
        ));
    final box = doc.page(0).annotations.single;
    final rc = box.richContent!;
    expect(rc, contains('text-decoration:underline'));
    final runs = PdfAnnotationEditing.parseFreeTextRichContent(rc);
    expect(runs.where((r) => r.underline).map((r) => r.text).join(),
        contains('under'));
    // the appearance draws one underline rule (a re after the text object)
    final content = appearanceText(doc, box);
    expect(content.lastIndexOf('ET'), lessThan(content.lastIndexOf(' re')));
  });

  test('resizeAnnotation rejects degenerate rects', () {
    final first = PdfEditor(PdfDocument.open(buildClassicPdf()))
      ..addSquare(0, const PdfRect(100, 100, 200, 150));
    final doc = PdfDocument.open(first.save());
    expect(
        () => PdfEditor(doc).resizeAnnotation(
            0, doc.page(0).annotations.single, const PdfRect(50, 50, 50, 80)),
        throwsArgumentError);
  });

  test('resizeAnnotation flipX mirrors stretched artwork and point arrays', () {
    final first = PdfEditor(PdfDocument.open(buildClassicPdf()))
      ..addInk(0, [
        [(100, 100), (200, 150)],
      ]);
    final doc = PdfDocument.open(first.save());
    final ink = doc.page(0).annotations.single;
    final from = ink.rect;

    // resize to the SAME rect, flipped horizontally: a flip mirrors the
    // content, never moves the box
    final editor = PdfEditor(doc)..resizeAnnotation(0, ink, from, flipX: true);
    final reopened = PdfDocument.open(editor.save());
    final flipped = reopened.page(0).annotations.single;
    expect(flipped.rect.left, closeTo(from.left, 1e-6));
    expect(flipped.rect.right, closeTo(from.right, 1e-6));
    expect(flipped.rect.bottom, closeTo(from.bottom, 1e-6));
    expect(flipped.rect.top, closeTo(from.top, 1e-6));

    // the stretched appearance mirrors through a horizontal reflection
    // baked into the form /Matrix (a = −1, d = 1)
    final matrix = reopened.cos
        .resolve(flipped.normalAppearance!.dictionary['Matrix']) as CosArray;
    double m(int i) {
      final n = reopened.cos.resolve(matrix[i]);
      return n is CosInteger ? n.value.toDouble() : (n as CosReal).value;
    }

    expect(m(0), closeTo(-1, 1e-9));
    expect(m(1), closeTo(0, 1e-9));
    expect(m(2), closeTo(0, 1e-9));
    expect(m(3), closeTo(1, 1e-9));

    // /InkList reflects about the rect's horizontal center, y untouched -
    // so the centerline stays consistent with the mirrored appearance
    final cx = (from.left + from.right) / 2;
    final inkList = reopened.cos.resolve(flipped.dict['InkList']) as CosArray;
    final stroke = reopened.cos.resolve(inkList[0]) as CosArray;
    double at(int i) {
      final n = reopened.cos.resolve(stroke[i]);
      return n is CosInteger ? n.value.toDouble() : (n as CosReal).value;
    }

    expect(at(0), closeTo(2 * cx - 100, 1e-6));
    expect(at(1), closeTo(100, 1e-6));
    expect(at(2), closeTo(2 * cx - 200, 1e-6));
    expect(at(3), closeTo(150, 1e-6));
  });

  test('flipping a rotated annotation twice restores it', () {
    final first = PdfEditor(PdfDocument.open(buildClassicPdf()))
      ..addInk(0, [
        [(100, 100), (200, 150)],
      ]);
    var doc = PdfDocument.open(first.save());
    doc = PdfDocument.open((PdfEditor(doc)
          ..rotateAnnotation(0, doc.page(0).annotations.single, 90))
        .save());

    // the rest-state rect and the centerline points, read up front
    List<double> inkPoints(PdfDocument d) {
      final annot = d.page(0).annotations.single;
      final list = d.cos.resolve(annot.dict['InkList']) as CosArray;
      final stroke = d.cos.resolve(list[0]) as CosArray;
      return [
        for (var i = 0; i < stroke.length; i++)
          () {
            final n = d.cos.resolve(stroke[i]);
            return n is CosInteger ? n.value.toDouble() : (n as CosReal).value;
          }(),
      ];
    }

    final rest = doc.page(0).annotations.single.rect;
    final beforePts = inkPoints(doc);

    // the current local box (same size, just flipped) - measured from the
    // appearance quad so sx == sy == 1 and the flip only mirrors
    final quad = doc.page(0).annotations.single.appearanceQuad!;
    double dist((double, double) a, (double, double) b) {
      final dx = b.$1 - a.$1, dy = b.$2 - a.$2;
      return math.sqrt(dx * dx + dy * dy);
    }

    final fromW = dist(quad[0], quad[1]);
    final fromH = dist(quad[0], quad[3]);
    final ccx = (quad[0].$1 + quad[2].$1) / 2;
    final ccy = (quad[0].$2 + quad[2].$2) / 2;
    final localBox = PdfRect(
        ccx - fromW / 2, ccy - fromH / 2, ccx + fromW / 2, ccy + fromH / 2);

    // a local-frame flipX, then the same flip again - each is its own
    // inverse, so the geometry comes back exactly
    for (var i = 0; i < 2; i++) {
      doc = PdfDocument.open((PdfEditor(doc)
            ..resizeAnnotationLocal(0, doc.page(0).annotations.single, localBox,
                flipX: true))
          .save());
    }

    final after = doc.page(0).annotations.single.rect;
    expect(after.left, closeTo(rest.left, 1e-3));
    expect(after.bottom, closeTo(rest.bottom, 1e-3));
    expect(after.right, closeTo(rest.right, 1e-3));
    expect(after.top, closeTo(rest.top, 1e-3));

    final afterPts = inkPoints(doc);
    expect(afterPts.length, beforePts.length);
    for (var i = 0; i < beforePts.length; i++) {
      expect(afterPts[i], closeTo(beforePts[i], 1e-3));
    }
  });

  test('rotateAnnotation rotates rect, appearance matrix, and ink points', () {
    final first = PdfEditor(PdfDocument.open(buildClassicPdf()))
      ..addSquare(0, const PdfRect(100, 100, 200, 150))
      ..addInk(0, [
        [(100, 100), (200, 150)],
      ]);
    final doc = PdfDocument.open(first.save());

    final editor = PdfEditor(doc)
      ..rotateAnnotation(0, doc.page(0).annotations[0], 90)
      ..rotateAnnotation(0, doc.page(0).annotations[1], 90);
    final reopened = PdfDocument.open(editor.save());

    // the square: 100×50 centered (150,125) → 50×100, same center
    final square = reopened.page(0).annotations[0];
    expect(square.rect.left, closeTo(125, 1e-6));
    expect(square.rect.bottom, closeTo(75, 1e-6));
    expect(square.rect.right, closeTo(175, 1e-6));
    expect(square.rect.top, closeTo(175, 1e-6));

    // generated appearances have BBox == old rect (identity fit), so the
    // matrix is exactly the +90° rotation about the center: b=1, c=−1,
    // and the old bottom-left corner lands on the new bottom-right
    final matrix = reopened.cos
        .resolve(square.normalAppearance!.dictionary['Matrix']) as CosArray;
    double m(int i) {
      final n = reopened.cos.resolve(matrix[i]);
      return n is CosInteger ? n.value.toDouble() : (n as CosReal).value;
    }

    expect(m(0), closeTo(0, 1e-9));
    expect(m(1), closeTo(1, 1e-9));
    expect(m(2), closeTo(-1, 1e-9));
    expect(m(3), closeTo(0, 1e-9));
    expect(m(0) * 100 + m(2) * 100 + m(4), closeTo(175, 1e-6));
    expect(m(1) * 100 + m(3) * 100 + m(5), closeTo(75, 1e-6));

    // ink points rotate about the ink rect's center (150,125):
    // (100,100) → (175,75)
    final ink = reopened.page(0).annotations[1];
    final inkList = reopened.cos.resolve(ink.dict['InkList']) as CosArray;
    final stroke = reopened.cos.resolve(inkList[0]) as CosArray;
    double at(int i) => (reopened.cos.resolve(stroke[i]) as CosReal).value;
    expect(at(0), closeTo(175, 1e-6));
    expect(at(1), closeTo(75, 1e-6));
    expect(at(2), closeTo(125, 1e-6));
    expect(at(3), closeTo(175, 1e-6));
  });

  test('two 45° rotations land where one 90° does', () {
    PdfRect rotatedRect(List<double> steps) {
      var doc = PdfDocument.open((PdfEditor(PdfDocument.open(buildClassicPdf()))
            ..addSquare(0, const PdfRect(100, 100, 200, 150)))
          .save());
      for (final degrees in steps) {
        final editor = PdfEditor(doc)
          ..rotateAnnotation(0, doc.page(0).annotations.single, degrees);
        doc = PdfDocument.open(editor.save());
      }
      return doc.page(0).annotations.single.rect;
    }

    final twice = rotatedRect([45, 45]);
    final once = rotatedRect([90]);
    expect(twice.left, closeTo(once.left, 1e-6));
    expect(twice.bottom, closeTo(once.bottom, 1e-6));
    expect(twice.right, closeTo(once.right, 1e-6));
    expect(twice.top, closeTo(once.top, 1e-6));
  });

  test('resizeAnnotationLocal on an unrotated annotation is a plain resize',
      () {
    final first = PdfEditor(PdfDocument.open(buildClassicPdf()))
      ..addSquare(0, const PdfRect(100, 100, 200, 150), strokeWidth: 4);
    final doc = PdfDocument.open(first.save());

    final editor = PdfEditor(doc)
      ..resizeAnnotationLocal(
          0, doc.page(0).annotations.single, const PdfRect(100, 100, 300, 250));
    final reopened = PdfDocument.open(editor.save());
    final square = reopened.page(0).annotations.single;
    expect(square.rect, const PdfRect(100, 100, 300, 250));
    expect(appearanceText(reopened, square), contains('4 w'));
  });

  test('rotated square resizes in its local frame, regenerated unsheared', () {
    final first = PdfEditor(PdfDocument.open(buildClassicPdf()))
      ..addSquare(0, const PdfRect(100, 100, 200, 150), strokeWidth: 4);
    var doc = PdfDocument.open(first.save());
    doc = PdfDocument.open((PdfEditor(doc)
          ..rotateAnnotation(0, doc.page(0).annotations.single, 45))
        .save());

    // grow the local box to 150×80 about a new center (175,125)
    final editor = PdfEditor(doc)
      ..resizeAnnotationLocal(
          0, doc.page(0).annotations.single, const PdfRect(100, 85, 250, 165));
    final reopened = PdfDocument.open(editor.save());

    final square = reopened.page(0).annotations.single;
    // stroke width survives the regeneration
    expect(appearanceText(reopened, square), contains('4 w'));
    // the quad's edges measure the local box, still at 45°
    final quad = square.appearanceQuad!;
    double dist((double, double) a, (double, double) b) {
      final dx = b.$1 - a.$1, dy = b.$2 - a.$2;
      return math.sqrt(dx * dx + dy * dy);
    }

    expect(dist(quad[0], quad[1]), closeTo(150, 1e-6));
    expect(dist(quad[0], quad[3]), closeTo(80, 1e-6));
    final angle = math.atan2(quad[1].$2 - quad[0].$2, quad[1].$1 - quad[0].$1);
    expect(angle, closeTo(math.pi / 4, 1e-6));
    // centered where the local box put it
    expect((square.rect.left + square.rect.right) / 2, closeTo(175, 1e-6));
    expect((square.rect.bottom + square.rect.top) / 2, closeTo(125, 1e-6));
  });

  test('rotated ink resizes along its local axes without shear', () {
    final first = PdfEditor(PdfDocument.open(buildClassicPdf()))
      ..addInk(0, [
        [(100, 100), (200, 150)],
      ]);
    var doc = PdfDocument.open(first.save());
    doc = PdfDocument.open((PdfEditor(doc)
          ..rotateAnnotation(0, doc.page(0).annotations.single, 90))
        .save());

    // resting local box: 104×54 about (150,125) - double the local width
    final editor = PdfEditor(doc)
      ..resizeAnnotationLocal(
          0, doc.page(0).annotations.single, const PdfRect(46, 98, 254, 152));
    final reopened = PdfDocument.open(editor.save());

    final ink = reopened.page(0).annotations.single;
    // local x is page y after the 90° turn: the page rect spans 54×208
    expect(ink.rect.right - ink.rect.left, closeTo(54, 1e-6));
    expect(ink.rect.top - ink.rect.bottom, closeTo(208, 1e-6));
    expect((ink.rect.left + ink.rect.right) / 2, closeTo(150, 1e-6));
    expect((ink.rect.bottom + ink.rect.top) / 2, closeTo(125, 1e-6));
    // the ink points scale with the artwork: (175,75) → (175,25),
    // (125,175) → (125,225)
    final inkList = reopened.cos.resolve(ink.dict['InkList']) as CosArray;
    final stroke = reopened.cos.resolve(inkList[0]) as CosArray;
    double at(int i) {
      final n = reopened.cos.resolve(stroke[i]);
      return n is CosInteger ? n.value.toDouble() : (n as CosReal).value;
    }

    expect(at(0), closeTo(175, 1e-6));
    expect(at(1), closeTo(25, 1e-6));
    expect(at(2), closeTo(125, 1e-6));
    expect(at(3), closeTo(225, 1e-6));
    // and the quad still reads 90° with the doubled local width
    final quad = ink.appearanceQuad!;
    final angle = math.atan2(quad[1].$2 - quad[0].$2, quad[1].$1 - quad[0].$1);
    expect(angle.abs(), closeTo(math.pi / 2, 1e-6));
  });

  test('rotateAnnotation requires an appearance stream', () {
    final first = PdfEditor(PdfDocument.open(buildClassicPdf()))
      ..addSquare(0, const PdfRect(100, 100, 200, 150));
    final doc = PdfDocument.open(first.save());
    final square = doc.page(0).annotations.single;
    square.dict.entries.remove('AP');
    expect(
        () => PdfEditor(doc).rotateAnnotation(0, square, 90), throwsStateError);
  });

  test('print flag is set so annotations survive printing', () {
    final doc =
        roundTrip((e) => e.addHighlight(0, const [PdfRect(72, 700, 200, 712)]));
    expect(doc.page(0).annotations.single.flags & 4, 4);
  });

  group('link annotations', () {
    PdfDocument roundTripLink(
      void Function(PdfEditor) edit, {
      int pages = 1,
    }) {
      final editor = PdfEditor(PdfDocument.open(
          pages == 1 ? buildClassicPdf() : buildMultiPagePdf(pages)));
      edit(editor);
      return PdfDocument.open(editor.save());
    }

    test('URI link round-trips as a /Link with a /URI action', () {
      final doc = roundTripLink((e) => e.addLinkToUri(
            0,
            const [PdfRect(72, 700, 200, 712)],
            uri: 'https://example.com/docs',
            contents: 'docs',
          ));
      final link = doc.page(0).annotations.single;
      expect(link, isA<PdfLinkAnnotation>());
      expect(link.subtype, 'Link');
      expect(link.rect, const PdfRect(72, 700, 200, 712));

      final action = link.action;
      expect(action, isA<PdfUriAction>());
      expect((action as PdfUriAction).uri, 'https://example.com/docs');

      // invisible by default: no border, no appearance stream
      final border = doc.cos.resolve(link.dict['Border']) as CosArray;
      expect((doc.cos.resolve(border[2]) as CosReal).value, 0);
      expect(link.normalAppearance, isNull);
      expect(link.name, isNotNull);
      expect(
          (doc.cos.resolve(link.dict['Contents']) as CosString).text, 'docs');
    });

    test('a multi-line selection becomes one link with per-quad regions', () {
      final doc = roundTripLink((e) => e.addLinkToUri(
            0,
            const [PdfRect(72, 700, 200, 712), PdfRect(72, 686, 150, 698)],
            uri: 'mailto:team@example.com',
          ));
      final link = doc.page(0).annotations.single;
      // /Rect is the bounding box of both quads
      expect(link.rect, const PdfRect(72, 686, 200, 712));
      final quads = doc.cos.resolve(link.dict['QuadPoints']) as CosArray;
      expect(quads.length, 16);
    });

    test('internal link jumps to a page via a /GoTo destination', () {
      final doc = roundTripLink(
        (e) => e.addLinkToPage(
          0,
          const [PdfRect(72, 700, 200, 712)],
          targetPage: 2,
        ),
        pages: 3,
      );
      final action = doc.page(0).annotations.single.action;
      expect(action, isA<PdfGoToAction>());
      final destination = (action as PdfGoToAction).destination;
      expect(destination.pageIndex, 2);
      expect(destination.fit, 'Fit');
    });

    test('addLinkToDestination preserves an XYZ view target', () {
      final doc = roundTripLink(
        (e) => e.addLinkToDestination(
          0,
          const [PdfRect(72, 700, 200, 712)],
          destination:
              PdfExplicitDestination.xyz(1, left: 50, top: 400, zoom: 2),
        ),
        pages: 2,
      );
      final action = doc.page(0).annotations.single.action as PdfGoToAction;
      expect(action.destination.pageIndex, 1);
      expect(action.destination.fit, 'XYZ');
      expect(action.destination.left, 50);
      expect(action.destination.top, 400);
      expect(action.destination.zoom, 2);
    });

    test('underline decoration bakes an appearance stream', () {
      final doc = roundTripLink((e) => e.addLinkToUri(
            0,
            const [PdfRect(72, 700, 200, 712)],
            uri: 'https://example.com',
            underlineColor: 0x0000EE,
          ));
      final link = doc.page(0).annotations.single;
      final content = appearanceText(doc, link);
      expect(content, contains('S')); // a stroked underline
    });

    test('a visible border sets /C, a non-zero /Border, and an appearance', () {
      final doc = roundTripLink((e) => e.addLinkToUri(
            0,
            const [PdfRect(72, 700, 200, 712)],
            uri: 'https://example.com',
            borderColor: 0xFF0000,
            borderWidth: 2,
          ));
      final link = doc.page(0).annotations.single;
      expect(link.color, 0xFF0000);
      final border = doc.cos.resolve(link.dict['Border']) as CosArray;
      expect((doc.cos.resolve(border[2]) as CosReal).value, 2);
      final content = appearanceText(doc, link);
      expect(content, contains('re'));
    });

    test('an empty URI is rejected', () {
      final editor = PdfEditor(PdfDocument.open(buildClassicPdf()));
      expect(
        () => editor.addLinkToUri(0, const [PdfRect(0, 0, 10, 10)], uri: ''),
        throwsArgumentError,
      );
    });

    test('links carry the print flag', () {
      final doc = roundTripLink((e) => e.addLinkToUri(
            0,
            const [PdfRect(72, 700, 200, 712)],
            uri: 'https://example.com',
          ));
      expect(doc.page(0).annotations.single.flags & 4, 4);
    });
  });
}
