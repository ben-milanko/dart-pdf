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
      final doc = roundTrip((e) =>
          e.addCallout(0, const PdfRect(300, 600, 460, 660), 'x', target));
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
    editor
        .addCallout(0, const PdfRect(300, 600, 460, 660), 'detail', (120, 500));
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

  group('multiple leaders', () {
    PdfDocument reopen(PdfEditor editor) => PdfDocument.open(editor.save());

    test('extraLeaders draws every arrow and round-trips', () {
      final doc = roundTrip((e) => e.addCallout(
            0,
            const PdfRect(300, 600, 460, 660),
            'two arrows',
            (120, 500),
            extraLeaders: const [(target: (560, 450), attach: null)],
          ));
      final annot = doc.page(0).annotations.single;
      final leaders = annot.calloutLeaders!;
      expect(leaders, hasLength(2));
      expect(leaders[0].first, (120.0, 500.0));
      expect(leaders[1].first, (560.0, 450.0));
      expect(annot.calloutLine!.first, (120.0, 500.0),
          reason: '/CL stays the first leader');
      // /Rect covers both tips; the appearance strokes both leaders
      expect(annot.rect.left, lessThanOrEqualTo(120));
      expect(annot.rect.right, greaterThanOrEqualTo(560));
      expect(annot.rect.bottom, lessThanOrEqualTo(450));
      final content = appearanceText(doc, annot);
      expect(content, contains('120 500 m'));
      expect(content, contains('560 450 m'));
    });

    test('addCalloutLeader adds an arrow and keeps the box + first leader', () {
      final editor = PdfEditor(PdfDocument.open(buildClassicPdf()))
        ..addCallout(0, const PdfRect(300, 600, 460, 660), 'x', (120, 500));
      final doc0 = reopen(editor);
      final a0 = doc0.page(0).annotations.single;
      final box0 = a0.calloutBox!;
      final editor2 = PdfEditor(doc0);
      expect(editor2.addCalloutLeader(0, a0, (380, 450)), isTrue);
      final a = reopen(editor2).page(0).annotations.single;
      expect(a.calloutLeaders, hasLength(2));
      expect(a.calloutLeaders![0].first, (120.0, 500.0));
      expect(a.calloutLeaders![1].first, (380.0, 450.0));
      expect(a.calloutLeaders![1].last.$2, closeTo(box0.bottom, 0.01),
          reason: 'a target below the box meets the bottom edge');
      expect(a.calloutBox!.left, closeTo(box0.left, 0.01));
      expect(a.calloutBox!.top, closeTo(box0.top, 0.01));
    });

    test('removeCalloutLeader drops one arrow but never the last', () {
      final editor = PdfEditor(PdfDocument.open(buildClassicPdf()))
        ..addCallout(0, const PdfRect(300, 600, 460, 660), 'x', (
          120,
          500
        ), extraLeaders: const [
          (target: (560, 450), attach: null),
          (target: (380, 720), attach: null),
        ]);
      final doc0 = reopen(editor);
      final a0 = doc0.page(0).annotations.single;
      final editor2 = PdfEditor(doc0);
      // removing leader 0 promotes the next one into /CL
      expect(editor2.removeCalloutLeader(0, a0, 0), isTrue);
      final doc1 = reopen(editor2);
      final a1 = doc1.page(0).annotations.single;
      expect([for (final l in a1.calloutLeaders!) l.first],
          [(560.0, 450.0), (380.0, 720.0)]);
      expect(a1.calloutLine!.first, (560.0, 450.0));

      final editor3 = PdfEditor(doc1);
      expect(editor3.removeCalloutLeader(0, a1, 1), isTrue);
      final doc2 = reopen(editor3);
      final a2 = doc2.page(0).annotations.single;
      expect(a2.calloutLeaders, hasLength(1));
      expect(a2.dict.entries.containsKey(kPdfCalloutLeadersKey), isFalse);
      expect(PdfEditor(doc2).removeCalloutLeader(0, a2, 0), isFalse,
          reason: 'a callout keeps at least one leader');
    });

    test('a box reshape keeps every tip and re-aims one leader by index', () {
      final editor = PdfEditor(PdfDocument.open(buildClassicPdf()))
        ..addCallout(0, const PdfRect(300, 600, 460, 660), 'x', (120, 500),
            extraLeaders: const [(target: (560, 450), attach: null)]);
      final doc0 = reopen(editor);
      final a0 = doc0.page(0).annotations.single;
      final editor2 = PdfEditor(doc0);
      expect(
          editor2.reshapeCallout(0, a0, box: const PdfRect(250, 650, 410, 710)),
          isTrue);
      final doc1 = reopen(editor2);
      final a1 = doc1.page(0).annotations.single;
      expect([for (final l in a1.calloutLeaders!) l.first],
          [(120.0, 500.0), (560.0, 450.0)]);
      expect(a1.calloutBox!.left, closeTo(250, 0.01));

      final editor3 = PdfEditor(doc1);
      expect(
          editor3.reshapeCallout(0, a1, target: (500, 300), leader: 1), isTrue);
      final a2 = reopen(editor3).page(0).annotations.single;
      expect(a2.calloutLeaders![0].first, (120.0, 500.0));
      expect(a2.calloutLeaders![1].first, (500.0, 300.0));
      expect(PdfEditor(doc1).reshapeCallout(0, a1, target: (1, 1), leader: 2),
          isFalse);
    });

    test('moving a callout shifts its extra leaders too', () {
      final editor = PdfEditor(PdfDocument.open(buildClassicPdf()))
        ..addCallout(0, const PdfRect(300, 600, 460, 660), 'x', (120, 500),
            extraLeaders: const [(target: (560, 450), attach: null)]);
      final doc0 = reopen(editor);
      final editor2 = PdfEditor(doc0)
        ..moveAnnotation(0, doc0.page(0).annotations.single, 10, -20);
      final a = reopen(editor2).page(0).annotations.single;
      expect(a.calloutLeaders![1].first, (570.0, 430.0));
    });
  });
}
