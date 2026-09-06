import 'dart:typed_data';
import 'package:pdf_cos/pdf_cos.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:dart_pdf_editor/src/editing/editing_overlay.dart';
import 'package:pdf_document/pdf_document.dart';

import 'editing_reflow_test.dart' show buildParagraphPdf;

void main() {
  testWidgets('region deletion removes only the selected glyph pixels',
      (tester) async {
    await tester.runAsync(() async {
      // Spacing, scale, TJ kerning and a separate following run exercise the
      // actual interpreter/rasterizer, independently of PdfPageElements.
      final doc = PdfDocument.open(
          buildParagraphPdf('BT /F1 20 Tf 2 Tc 3 Tw 80 Tz 72 700 Td '
              '[(AA) -500 ( B) 100 (CC)] TJ (DD) Tj ET'));
      final before =
          await PdfPageRenderer.renderImage(doc.page(0), pixelRatio: 2);
      final editor = PdfEditor(doc);
      // A + Tc = 15.34pt, two at 80% = 24.544; kern = 8pt;
      // space + Tc + Tw = 10.56pt at 80% = 8.448. B starts at 112.992.
      const erase = PdfRect(112.99, 690, 125.27, 725);
      expect(editor.deleteElementsInRect(PdfPageElements.of(doc, 0), erase), 1);
      final out = PdfDocument.open(editor.save());
      final after =
          await PdfPageRenderer.renderImage(out.page(0), pixelRatio: 2);
      try {
        final a = (await before.toByteData())!;
        final b = (await after.toByteData())!;
        var changedInside = 0;
        var changedOutside = 0;
        for (var y = 0; y < before.height; y++) {
          for (var x = 0; x < before.width; x++) {
            final i = (y * before.width + x) * 4;
            if (a.getUint32(i) == b.getUint32(i)) continue;
            final px = x / 2, py = 792 - y / 2;
            if (px >= erase.left - 1 &&
                px <= erase.right + 1 &&
                py >= erase.bottom &&
                py <= erase.top) {
              changedInside++;
            } else {
              changedOutside++;
            }
          }
        }
        expect(changedInside, greaterThan(50));
        expect(changedOutside, 0, reason: 'surviving text must not move');
      } finally {
        before.dispose();
        after.dispose();
      }
    });
  });
  testWidgets('dragging the tool slices a rotated page vector in one undo step',
      (tester) async {
    final editing =
        PdfEditingController(graphicPdf('100 100 200 150 re f', rotation: 90))
          ..tool = PdfEditTool.contentDelete;
    addTearDown(editing.dispose);
    final geometry = PdfPageGeometry(
        cropBox: editing.document.page(0).cropBox,
        rotation: 90,
        viewSize: const Size(400, 400));
    await tester.pumpWidget(MaterialApp(
        home: Center(
            child: SizedBox(
      width: 400,
      height: 400,
      child: ListenableBuilder(
          listenable: editing,
          builder: (context, _) => EditingPageOverlay(
              controller: editing,
              pageIndex: 0,
              geometry: geometry,
              textPrompt: showPdfTextPrompt)),
    ))));
    final origin = tester.getTopLeft(find.byType(EditingPageOverlay));
    final rect = geometry.toViewRect(const PdfRect(150, 130, 200, 180));
    final gesture = await tester.startGesture(origin + rect.topLeft,
        kind: PointerDeviceKind.mouse);
    await gesture.moveTo(origin + rect.center);
    await tester.pump();
    await gesture.moveTo(origin + rect.bottomRight);
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 400));
    expect(editing.canUndo, isTrue);

    Future<void> expectPixels({required bool cut}) async {
      await tester.runAsync(() async {
        final image = await PdfPageRenderer.renderImage(
            editing.document.page(0),
            rotation: 0);
        try {
          final data = (await image.toByteData())!;
          int red(int x, int y) =>
              data.getUint8(((400 - y) * image.width + x) * 4);
          expect(red(175, 155), cut ? 255 : 0);
          expect(red(120, 155), 0,
              reason: 'outside artwork must survive the drag');
        } finally {
          image.dispose();
        }
      });
    }

    await expectPixels(cut: true);
    editing.undo();
    await tester.pump();
    expect(editing.canUndo, isFalse,
        reason: 'one region is exactly one revision');
    await expectPixels(cut: false);
    editing.redo();
    await tester.pump();
    await expectPixels(cut: true);
  });

  testWidgets('a box slices filled vectors instead of deleting whole paths',
      (tester) async {
    await expectGraphicCut(
        tester, graphicPdf('100 100 200 150 re f'), [box(150, 130, 200, 180)]);
  });

  testWidgets('a box slices dashed strokes, curves and compound paths',
      (tester) async {
    await expectGraphicCut(
        tester,
        graphicPdf('6 w 1 J [15 6] 4 d 60 140 m 340 140 l S '
            '[] 0 d 80 110 m 100 280 290 280 320 110 c S '
            '80 80 240 240 re 110 110 180 180 re f*'),
        [box(170, 100, 230, 240)]);
  });

  testWidgets('cuts use page coordinates under skewed and changing transforms',
      (tester) async {
    await expectGraphicCut(
        tester,
        graphicPdf('q 1 .3 -.2 1 30 40 cm 70 70 200 200 re f Q '
            '4 w 60 80 m q 1 0 .2 1 40 0 cm 260 160 l Q 260 280 l S'),
        [box(160, 140, 220, 230)]);
  });

  testWidgets(
      'painting a pending clip preserves its outside stroke and later clip',
      (tester) async {
    await expectGraphicCut(
        tester,
        graphicPdf('100 100 200 150 re W 8 w B 1 0 0 rg 60 60 350 250 re f'),
        [box(150, 130, 200, 180)]);
  });

  testWidgets('a concave lasso cuts vectors along its actual boundary',
      (tester) async {
    await expectGraphicCut(
        tester,
        graphicPdf('80 80 240 240 re f'),
        [
          const [
            Offset(120, 120),
            Offset(280, 120),
            Offset(280, 280),
            Offset(230, 280),
            Offset(230, 170),
            Offset(170, 170),
            Offset(170, 280),
            Offset(120, 280),
          ]
        ],
        polygon: true);
  });

  testWidgets('a vector form is cut without dropping its outside artwork',
      (tester) async {
    await expectGraphicCut(tester, graphicPdf('q 1 0 0 1 100 80 cm /Fm Do Q'),
        [box(150, 130, 200, 180)]);
  });

  testWidgets('an image is cut without dropping its outside pixels',
      (tester) async {
    await expectGraphicCut(
        tester,
        graphicPdf('q 250 0 0 200 70 90 cm /Im Do Q'),
        [box(150, 130, 200, 180)]);
  });

  testWidgets('an interleaved image does not consume an unpainted vector path',
      (tester) async {
    await expectGraphicCut(
        tester,
        graphicPdf(
            '100 100 200 150 re W q 240 0 0 200 60 70 cm /Im Do Q 8 w S'),
        [box(150, 130, 200, 180)]);
  });

  testWidgets('repeated cuts preserve the earlier hole and surviving vector',
      (tester) async {
    await expectGraphicCut(tester, graphicPdf('80 80 240 240 re f'),
        [box(100, 100, 160, 180), box(200, 200, 280, 280)]);
  });

  testWidgets('the stroke width counts when a box only grazes its edge',
      (tester) async {
    await expectGraphicCut(tester, graphicPdf('/Heavy gs 80 120 m 330 120 l S'),
        [box(150, 130, 200, 150)]);
  });
}

/// A small graphic-only page with a reusable vector form and a black image.
Uint8List graphicPdf(String content, {String? formContent, int rotation = 0}) {
  final builder = CosDocumentBuilder();
  final pages = CosDictionary({'Type': const CosName('Pages')});
  final pagesRef = builder.add(pages);
  final image = builder.add(CosStream(
      CosDictionary({
        'Type': const CosName('XObject'),
        'Subtype': const CosName('Image'),
        'Width': const CosInteger(1),
        'Height': const CosInteger(1),
        'ColorSpace': const CosName('DeviceGray'),
        'BitsPerComponent': const CosInteger(8),
      }),
      Uint8List.fromList([0])));
  final form = builder.add(CosStream(
      CosDictionary({
        'Type': const CosName('XObject'),
        'Subtype': const CosName('Form'),
        'BBox': CosArray([
          for (final n in [0, 0, 200, 200]) CosInteger(n)
        ]),
        'Matrix': CosArray([
          for (final n in [1.0, 0.2, -0.1, 1.0, 0.0, 0.0]) CosReal(n)
        ]),
      }),
      Uint8List.fromList((formContent ?? '0 0 200 200 re f').codeUnits)));
  final page = builder.add(CosDictionary({
    'Type': const CosName('Page'),
    'Parent': pagesRef,
    'MediaBox': CosArray([
      for (final n in [0, 0, 400, 400]) CosInteger(n)
    ]),
    'Rotate': CosInteger(rotation),
    'Contents': builder
        .add(CosStream(CosDictionary(), Uint8List.fromList(content.codeUnits))),
    'Resources': CosDictionary({
      'XObject': CosDictionary({'Fm': form, 'Im': image}),
      'ExtGState': CosDictionary({
        'Heavy': CosDictionary({
          'LW': const CosInteger(40),
          'LJ': const CosInteger(1),
        })
      }),
    }),
  }));
  pages['Kids'] = CosArray([page]);
  pages['Count'] = const CosInteger(1);
  final root = builder.add(
      CosDictionary({'Type': const CosName('Catalog'), 'Pages': pagesRef}));
  return builder.build(root: root);
}

Future<void> expectGraphicCut(
    WidgetTester tester, Uint8List bytes, List<List<Offset>> regions,
    {bool polygon = false}) async {
  await tester.runAsync(() async {
    final doc = PdfDocument.open(bytes);
    final before =
        await PdfPageRenderer.renderImage(doc.page(0), pixelRatio: 2);
    final editor = PdfEditor(doc);
    for (final region in regions) {
      final elements = PdfPageElements.of(doc, 0);
      final count = polygon
          ? editor.deleteElementsInPolygon(
              elements, [for (final p in region) (p.dx, p.dy)])
          : editor.deleteElementsInRect(elements,
              PdfRect(region[0].dx, region[0].dy, region[2].dx, region[2].dy));
      expect(count, greaterThan(0));
    }
    final out = PdfDocument.open(editor.save());
    final after = await PdfPageRenderer.renderImage(out.page(0), pixelRatio: 2);
    try {
      final masks = [
        for (final region in regions)
          Path()
            ..fillType = PathFillType.evenOdd
            ..addPolygon(region, true)
      ];
      final a = (await before.toByteData())!, b = (await after.toByteData())!;
      var erasedPixels = 0, outsideChanges = 0, remainingInside = 0;
      for (var y = 0; y < before.height; y++) {
        for (var x = 0; x < before.width; x++) {
          final point = Offset(x / 2, 400 - y / 2);
          // Exclude the subpixel clip edge, whose antialiasing is expected.
          if (regions.any((r) => nearBoundary(point, r))) continue;
          final i = (y * before.width + x) * 4;
          if (masks.any((m) => m.contains(point))) {
            if (b.getUint8(i) < 250 ||
                b.getUint8(i + 1) < 250 ||
                b.getUint8(i + 2) < 250) {
              remainingInside++;
            }
            if (a.getUint32(i) != b.getUint32(i)) erasedPixels++;
          } else if (a.getUint32(i) != b.getUint32(i)) {
            outsideChanges++;
          }
        }
      }
      expect(erasedPixels, greaterThan(20),
          reason: 'the cut must remove visible artwork');
      expect(remainingInside, 0, reason: 'the selected area must be clear');
      expect(outsideChanges, 0,
          reason: 'the vector outside the cut must survive unchanged');
    } finally {
      before.dispose();
      after.dispose();
    }
  });
}

bool nearBoundary(Offset point, List<Offset> polygon) {
  for (var i = 0; i < polygon.length; i++) {
    final a = polygon[i], delta = polygon[(i + 1) % polygon.length] - a;
    final t = delta.distanceSquared == 0
        ? 0.0
        : (((point - a).dx * delta.dx + (point - a).dy * delta.dy) /
                delta.distanceSquared)
            .clamp(0.0, 1.0);
    if ((point - (a + delta * t)).distance < 1) return true;
  }
  return false;
}

List<Offset> box(double l, double b, double r, double t) =>
    [Offset(l, b), Offset(r, b), Offset(r, t), Offset(l, t)];
