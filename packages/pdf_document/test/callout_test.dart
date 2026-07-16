import 'dart:convert';

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

  List<double> numbers(PdfDocument doc, CosObject? raw) {
    final arr = doc.cos.resolve(raw) as CosArray;
    return [
      for (final item in arr.items)
        switch (doc.cos.resolve(item)) {
          CosInteger(:final value) => value.toDouble(),
          CosReal(:final value) => value,
          _ => double.nan,
        }
    ];
  }

  test('callout is a FreeText with /IT, /CL, /LE, /RD and a leader + box', () {
    final doc = roundTrip((e) => e.addCallout(
          0,
          const PdfRect(300, 600, 460, 660),
          'See this detail',
          (120, 500),
          author: 'Ben',
        ));
    final annot = doc.page(0).annotations.single;
    expect(annot.subtype, 'FreeText');
    expect(annot.isCallout, isTrue);
    expect(annot.contents, 'See this detail');
    expect((doc.cos.resolve(annot.dict['IT']) as CosName).value,
        'FreeTextCallout');
    expect((doc.cos.resolve(annot.dict['LE']) as CosName).value, 'OpenArrow');

    // /CL starts at the arrow tip (the target) and ends on the box edge.
    final cl = numbers(doc, annot.dict['CL']);
    expect(cl.length, anyOf(4, 6));
    expect(cl[0], 120);
    expect(cl[1], 500);
    expect(cl[cl.length - 2], 300, reason: 'last CL point meets the box left');

    // /RD is non-negative on every side and the box fits inside /Rect.
    final rd = numbers(doc, annot.dict['RD']);
    expect(rd, hasLength(4));
    expect(rd.every((v) => v >= -0.001), isTrue);

    // /Rect encloses the arrow tip well below the text box.
    final rect = annot.rect;
    expect(rect.left, lessThanOrEqualTo(120));
    expect(rect.bottom, lessThanOrEqualTo(500));
    expect(rect.top, greaterThanOrEqualTo(660));

    // The appearance draws the arrowhead (a fill) and the wrapped text.
    final content = appearanceText(doc, annot);
    expect(content, contains('120 500 m'),
        reason: 'leader starts at the arrow tip');
    expect(content, contains('BT'));
    expect(content, contains('/Helv 12 Tf'));
    expect(content, contains(' Tj'));
  });

  test('calloutLine getter reads the /CL points back', () {
    final doc = roundTrip((e) => e.addCallout(
          0,
          const PdfRect(300, 600, 460, 660),
          'x',
          (120, 500),
        ));
    final line = doc.page(0).annotations.single.calloutLine!;
    expect(line.first, (120.0, 500.0));
    expect(line.last.$1, 300.0, reason: 'attaches to the box left edge');
  });

  test('the leader attaches to the box edge nearest the target', () {
    // box is (300,600)-(460,660): left=300 right=460 bottom=600 top=660
    ((double, double), List<(double, double)>) place((double, double) target) {
      final doc = roundTrip(
          (e) => e.addCallout(0, const PdfRect(300, 600, 460, 660), 'x', target));
      final line = doc.page(0).annotations.single.calloutLine!;
      return (line.last, line);
    }

    // target to the right -> attaches on the right edge (x == 460)
    expect(place((560, 630)).$1.$1, 460);
    // target above -> attaches on the top edge (y == 660)
    expect(place((380, 760)).$1.$2, 660);
    // target below -> attaches on the bottom edge (y == 600)
    expect(place((380, 500)).$1.$2, 600);
    // target inside the box -> a straight 2-point leader, no knee
    expect(place((380, 630)).$2, hasLength(2));
  });

  test('restyling a callout regenerates its leader + box', () {
    final editor = PdfEditor(PdfDocument.open(buildClassicPdf()));
    editor.addCallout(
        0, const PdfRect(300, 600, 460, 660), 'restyle me', (120, 500),
        color: 0x000000);
    final doc0 = PdfDocument.open(editor.save());
    final annot0 = doc0.page(0).annotations.single;

    final editor2 = PdfEditor(doc0);
    editor2.restyleAnnotation(0, annot0, color: 0x2060C0);
    final doc = PdfDocument.open(editor2.save());
    final annot = doc.page(0).annotations.single;

    expect(annot.isCallout, isTrue);
    expect(annot.calloutLine!.first, (120.0, 500.0));
    final content = appearanceText(doc, annot);
    expect(content, contains('120 500 m'), reason: 'leader still drawn');
    expect(content, contains(' Tj'), reason: 'text still drawn');
  });

  test('a plain free text is not a callout', () {
    final doc = roundTrip((e) =>
        e.addFreeText(0, const PdfRect(72, 600, 240, 680), 'plain text'));
    final annot = doc.page(0).annotations.single;
    expect(annot.isCallout, isFalse);
    expect(annot.calloutLine, isNull);
  });

  test('reshapeCallout with a new box keeps the terminus fixed', () {
    final editor = PdfEditor(PdfDocument.open(buildClassicPdf()));
    editor.addCallout(
        0, const PdfRect(300, 600, 460, 660), 'move box', (120, 500));
    final doc0 = PdfDocument.open(editor.save());
    final a0 = doc0.page(0).annotations.single;
    final terminus0 = a0.calloutLine!.first;

    final editor2 = PdfEditor(doc0);
    expect(
        editor2.reshapeCallout(0, a0, box: const PdfRect(340, 620, 500, 680)),
        isTrue);
    final a = PdfDocument.open(editor2.save()).page(0).annotations.single;

    expect(a.isCallout, isTrue);
    expect(a.calloutLine!.first, terminus0, reason: 'terminus unchanged');
    expect(a.calloutBox!.left, closeTo(340, 0.5));
    expect(a.calloutBox!.top, closeTo(680, 0.5));
  });

  test('reshapeCallout with a new target keeps the box fixed', () {
    final editor = PdfEditor(PdfDocument.open(buildClassicPdf()));
    editor.addCallout(
        0, const PdfRect(300, 600, 460, 660), 'move arrow', (120, 500));
    final doc0 = PdfDocument.open(editor.save());
    final a0 = doc0.page(0).annotations.single;
    final box0 = a0.calloutBox!;

    final editor2 = PdfEditor(doc0);
    expect(editor2.reshapeCallout(0, a0, target: (560, 630)), isTrue);
    final a = PdfDocument.open(editor2.save()).page(0).annotations.single;

    expect(a.calloutLine!.first, (560.0, 630.0), reason: 'terminus moved');
    expect(a.calloutBox!.left, closeTo(box0.left, 0.5));
    expect(a.calloutBox!.right, closeTo(box0.right, 0.5));
    expect(a.calloutBox!.top, closeTo(box0.top, 0.5));
    expect(a.calloutBox!.bottom, closeTo(box0.bottom, 0.5));
    // the base stays pinned where it was (left edge) - moving the arrow tip
    // doesn't slide the base around the box
    expect(a.calloutLine!.last.$1, closeTo(box0.left, 0.5));
  });

  double bsWidth(PdfDocument doc, PdfAnnotation a) {
    final bs = doc.cos.resolve(a.dict['BS']) as CosDictionary;
    return switch (doc.cos.resolve(bs['W'])) {
      CosInteger(:final value) => value.toDouble(),
      CosReal(:final value) => value,
      _ => double.nan,
    };
  }

  test('the leader keeps its stroke width when the terminus moves', () {
    final editor = PdfEditor(PdfDocument.open(buildClassicPdf()));
    // a callout with no separate box border still has a definite stroke
    editor.addCallout(0, const PdfRect(300, 600, 460, 660), 'x', (120, 500),
        strokeColor: 0x000000, strokeWidth: 3);
    final doc0 = PdfDocument.open(editor.save());
    final a0 = doc0.page(0).annotations.single;
    // /BS persists the width even without a distinct box-border color
    expect(bsWidth(doc0, a0), 3);

    final e2 = PdfEditor(doc0);
    e2.reshapeCallout(0, a0, target: (140, 520));
    final doc = PdfDocument.open(e2.save());
    final a = doc.page(0).annotations.single;
    expect(bsWidth(doc, a), 3,
        reason: 'arrow width unchanged after moving the terminus');
  });

  test('reshapeCallout with a new attach slides the base along the box', () {
    final editor = PdfEditor(PdfDocument.open(buildClassicPdf()));
    editor.addCallout(0, const PdfRect(300, 600, 460, 660), 'x', (120, 500));
    final doc0 = PdfDocument.open(editor.save());
    final a0 = doc0.page(0).annotations.single;
    final terminus0 = a0.calloutLine!.first;

    final e2 = PdfEditor(doc0);
    // drag the base toward the top edge; it snaps onto the perimeter
    expect(e2.reshapeCallout(0, a0, attach: (380, 655)), isTrue);
    final a = PdfDocument.open(e2.save()).page(0).annotations.single;

    expect(a.calloutLine!.first, terminus0, reason: 'terminus unchanged');
    final base = a.calloutLine!.last;
    // snapped to the top edge (y == 660), x near where we dragged
    expect(base.$2, closeTo(660, 0.5));
    expect(base.$1, closeTo(380, 0.5));
    expect(a.calloutBox!.left, closeTo(300, 0.5), reason: 'box unchanged');
  });

  test('the base keeps its relative edge position when the box resizes', () {
    final editor = PdfEditor(PdfDocument.open(buildClassicPdf()));
    editor.addCallout(0, const PdfRect(300, 600, 460, 660), 'x', (120, 500));
    final doc0 = PdfDocument.open(editor.save());
    final a0 = doc0.page(0).annotations.single;
    // pin the base at the top edge, mid-box
    final e1 = PdfEditor(doc0);
    e1.reshapeCallout(0, a0, attach: (380, 660));
    final doc1 = PdfDocument.open(e1.save());
    final a1 = doc1.page(0).annotations.single;
    expect(a1.calloutLine!.last.$2, closeTo(660, 0.5));

    // grow the box; the base rides the top edge to the same fraction across
    final e2 = PdfEditor(doc1);
    e2.reshapeCallout(0, a1, box: const PdfRect(300, 600, 500, 700));
    final a2 = PdfDocument.open(e2.save()).page(0).annotations.single;
    final base = a2.calloutLine!.last;
    expect(base.$2, closeTo(700, 0.5), reason: 'still on the (new) top edge');
    // was at x=380 in a 160-wide box starting at 300 => 50% across;
    // new box is 200 wide starting at 300 => 400
    expect(base.$1, closeTo(400, 1));
  });

  test('reshapeCallout refuses a plain free text', () {
    final editor = PdfEditor(PdfDocument.open(buildClassicPdf()));
    editor.addFreeText(0, const PdfRect(72, 600, 240, 680), 'plain');
    final doc0 = PdfDocument.open(editor.save());
    final a0 = doc0.page(0).annotations.single;
    final editor2 = PdfEditor(doc0);
    expect(editor2.reshapeCallout(0, a0, target: (10, 10)), isFalse);
  });

  test('resizing a callout scales its leader and keeps it a callout', () {
    final editor = PdfEditor(PdfDocument.open(buildClassicPdf()));
    editor.addCallout(
        0, const PdfRect(300, 600, 460, 660), 'detail', (120, 500));
    final doc0 = PdfDocument.open(editor.save());
    final annot0 = doc0.page(0).annotations.single;
    final grown = PdfRect(annot0.rect.left, annot0.rect.bottom,
        annot0.rect.right + 80, annot0.rect.top + 40);

    final editor2 = PdfEditor(doc0);
    editor2.resizeAnnotation(0, annot0, grown);
    final doc = PdfDocument.open(editor2.save());
    final annot = doc.page(0).annotations.single;

    expect(annot.isCallout, isTrue);
    expect(annot.rect.width, closeTo(grown.width, 0.5));
    // The leader still starts at the (scaled) arrow tip and the appearance
    // still draws text - not a stretched blur.
    final line = annot.calloutLine!;
    expect(line.length, greaterThanOrEqualTo(2));
    final content = appearanceText(doc, annot);
    expect(content, contains(' Tj'));
    expect(content, contains('Tf'));
  });
}
