import 'dart:convert';
import 'dart:math' as math;

import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:test/test.dart';

void main() {
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
    // seg 0's c2 = p1 − (p2 − p0)/6 = (43.33, 85) — left of every sample
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
    expect('T*'.allMatches(content).length, greaterThanOrEqualTo(2));
    expect(content, contains('W')); // clipped to the rect

    final form = ft.normalAppearance!;
    final resources =
        doc.cos.resolve(form.dictionary['Resources']) as CosDictionary;
    final fonts = doc.cos.resolve(resources['Font']) as CosDictionary;
    final helv = doc.cos.resolve(fonts['Helv']) as CosDictionary;
    expect((doc.cos.resolve(helv['BaseFont']) as CosName).value, 'Helvetica');
    expect((doc.cos.resolve(helv['Widths']) as CosArray).length, 95);
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
    expect(PdfStandardFont.fromName('Times-Italic'),
        PdfStandardFont.timesItalic);
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
    expect(measureStandardText('M', 1000, font: PdfStandardFont.timesBold), 944);
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
    final doc = PdfDocument.open(buildAnnotatedPdf());
    final before = doc.page(0).annotations.length;
    final editor = PdfEditor(doc)
      ..removeAnnotation(0, doc.page(0).annotations.first);
    final reopened = PdfDocument.open(editor.save());
    expect(reopened.page(0).annotations.length, before - 1);
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
    // (100,100)-(200,150) — after a move the §12.5.5 mapping must land it
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
    // §12.5.5 stretch — its rect doubles below and the points follow)
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
      ..addSquare(0, const PdfRect(100, 100, 200, 150),
          dashPattern: const [3]);
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
    int lines(String s) => 'T*'.allMatches(s).length;
    expect(lines(narrow), greaterThan(0));
    expect(lines(wide), lessThan(lines(narrow))); // fewer wrapped lines
    expect(reopened.page(0).annotations.single.rect,
        const PdfRect(100, 100, 450, 200));
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

  test('resizeAnnotation rejects degenerate rects', () {
    final first = PdfEditor(PdfDocument.open(buildClassicPdf()))
      ..addSquare(0, const PdfRect(100, 100, 200, 150));
    final doc = PdfDocument.open(first.save());
    expect(
        () => PdfEditor(doc).resizeAnnotation(
            0, doc.page(0).annotations.single, const PdfRect(50, 50, 50, 80)),
        throwsArgumentError);
  });

  test('resizeAnnotation flipX mirrors stretched artwork and point arrays',
      () {
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

    // /InkList reflects about the rect's horizontal center, y untouched —
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

    // the current local box (same size, just flipped) — measured from the
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

    // a local-frame flipX, then the same flip again — each is its own
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

    // resting local box: 104×54 about (150,125) — double the local width
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
}
