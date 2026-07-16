import 'package:pdf_document/pdf_document.dart';
import 'package:test/test.dart';

/// Applies the computed offsets to [rects], returning the moved rects.
List<PdfRect> _apply(List<PdfRect> rects, PdfAlignment alignment) {
  final offsets = alignmentOffsets(rects, alignment);
  return [
    for (var i = 0; i < rects.length; i++)
      PdfRect(
        rects[i].left + offsets[i].dx,
        rects[i].bottom + offsets[i].dy,
        rects[i].right + offsets[i].dx,
        rects[i].top + offsets[i].dy,
      ),
  ];
}

void main() {
  group('alignmentOffsets', () {
    // Three differently-sized boxes scattered around the page (y up).
    //   a: left 10, bottom 10, 40x20  -> right 50,  top 30
    //   b: left 100, bottom 200, 60x40 -> right 160, top 240
    //   c: left 300, bottom 80, 20x60  -> right 320, top 140
    final rects = [
      const PdfRect(10, 10, 50, 30),
      const PdfRect(100, 200, 160, 240),
      const PdfRect(300, 80, 320, 140),
    ];

    test('too few rects is a no-op', () {
      final one = [const PdfRect(0, 0, 10, 10)];
      expect(alignmentOffsets(one, PdfAlignment.left),
          [(dx: 0.0, dy: 0.0)]);
      // Distribution needs three.
      final two = [const PdfRect(0, 0, 10, 10), const PdfRect(50, 0, 60, 10)];
      expect(alignmentOffsets(two, PdfAlignment.distributeHorizontal),
          everyElement((dx: 0.0, dy: 0.0)));
    });

    test('align left puts every left edge on the minimum', () {
      final out = _apply(rects, PdfAlignment.left);
      expect(out.map((r) => r.left), everyElement(10));
      // widths and vertical position untouched
      expect(out[1].width, 60);
      expect(out[1].bottom, 200);
    });

    test('align right puts every right edge on the maximum', () {
      final out = _apply(rects, PdfAlignment.right);
      expect(out.map((r) => r.right), everyElement(320));
    });

    test('align top puts every top edge on the maximum', () {
      final out = _apply(rects, PdfAlignment.top);
      expect(out.map((r) => r.top), everyElement(240));
      expect(out[0].left, 10); // x untouched
    });

    test('align bottom puts every bottom edge on the minimum', () {
      final out = _apply(rects, PdfAlignment.bottom);
      expect(out.map((r) => r.bottom), everyElement(10));
    });

    test('horizontal centre lines up the midpoints', () {
      final out = _apply(rects, PdfAlignment.horizontalCenter);
      // group spans left 10 .. right 320 -> centre x 165
      for (final r in out) {
        expect((r.left + r.right) / 2, closeTo(165, 1e-9));
      }
    });

    test('vertical centre lines up the midpoints', () {
      final out = _apply(rects, PdfAlignment.verticalCenter);
      // group spans bottom 10 .. top 240 -> centre y 125
      for (final r in out) {
        expect((r.bottom + r.top) / 2, closeTo(125, 1e-9));
      }
    });

    test('distribute horizontally equalises the gaps and holds the ends', () {
      final out = _apply(rects, PdfAlignment.distributeHorizontal);
      // ends stay put
      final byLeft = [...out]..sort((a, b) => a.left.compareTo(b.left));
      expect(byLeft.first.left, 10);
      expect(byLeft.last.right, 320);
      // gaps between consecutive boxes are equal
      final gap1 = byLeft[1].left - byLeft[0].right;
      final gap2 = byLeft[2].left - byLeft[1].right;
      expect(gap1, closeTo(gap2, 1e-9));
      // widths preserved
      expect(byLeft.map((r) => r.width), containsAll([40, 60, 20]));
    });

    test('distribute vertically equalises the gaps and holds the ends', () {
      final out = _apply(rects, PdfAlignment.distributeVertical);
      final byBottom = [...out]..sort((a, b) => a.bottom.compareTo(b.bottom));
      expect(byBottom.first.bottom, 10);
      expect(byBottom.last.top, 240);
      final gap1 = byBottom[1].bottom - byBottom[0].top;
      final gap2 = byBottom[2].bottom - byBottom[1].top;
      expect(gap1, closeTo(gap2, 1e-9));
    });

    test('already-aligned input yields zero offsets', () {
      final aligned = [
        const PdfRect(10, 0, 50, 20),
        const PdfRect(10, 100, 70, 140),
      ];
      expect(alignmentOffsets(aligned, PdfAlignment.left),
          everyElement((dx: 0.0, dy: 0.0)));
    });

    test('minimumCount and isDistribute', () {
      expect(PdfAlignment.left.minimumCount, 2);
      expect(PdfAlignment.left.isDistribute, isFalse);
      expect(PdfAlignment.distributeHorizontal.minimumCount, 3);
      expect(PdfAlignment.distributeHorizontal.isDistribute, isTrue);
    });
  });
}
