// The viewer's scroll metrics must be exact, not estimated: stock
// ListView reports a maxScrollExtent extrapolated from the average extent
// of the built children, which oscillates by tens of thousands of pixels
// on long mixed-size documents (AMT-SP-101: 93k↔162k between frames) and
// makes the scrollbar thumb leap around while scrolling.
import 'dart:async';
import 'dart:convert' as convert;
import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

Uint8List _mixedWidthPages(int count) {
  final objects = <String>[
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [${[
      for (var i = 0; i < count; i++) '${i + 3} 0 R',
    ].join(' ')}] /Count $count >>',
    for (var i = 0; i < count; i++)
      '<< /Type /Page /Parent 2 0 R /MediaBox '
          '${i == 0 ? '[0 0 6000 1200]' : '[0 0 792 612]'} >>',
  ];
  final buffer = StringBuffer('%PDF-1.4\n');
  final offsets = <int>[];
  for (var i = 0; i < objects.length; i++) {
    offsets.add(buffer.length);
    buffer.write('${i + 1} 0 obj\n${objects[i]}\nendobj\n');
  }
  final xrefOffset = buffer.length;
  buffer
    ..write('xref\n0 ${objects.length + 1}\n')
    ..write('0000000000 65535 f \n');
  for (final offset in offsets) {
    buffer.write('${offset.toString().padLeft(10, '0')} 00000 n \n');
  }
  buffer
    ..write('trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\n')
    ..write('startxref\n$xrefOffset\n%%EOF\n');
  return Uint8List.fromList(convert.ascii.encode(buffer.toString()));
}

void main() {
  testWidgets('maxScrollExtent is exact and constant on mixed-size documents',
      (tester) async {
    const pageCount = 30;
    final document = PdfDocument.open(buildVariedHeightPdf(pageCount));
    final controller = PdfViewerController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PdfViewer(
          document: document,
          controller: controller,
          initialFit: PdfViewerFit.width,
        ),
      ),
    ));
    await tester.pump();

    final position =
        tester.state<ScrollableState>(find.byType(Scrollable).first).position;

    // the exact total: pages lay out fit-width (viewport 800 wide), so
    // each page is aspect * 800 tall, separated by pageSpacing (12) with
    // a trailing bottom pad of the same
    const width = 800.0;
    const spacing = 12.0;
    const heights = [792.0, 396.0, 1008.0]; // buildVariedHeightPdf's cycle
    var content = 0.0;
    for (var i = 0; i < pageCount; i++) {
      content += heights[i % 3] / 612.0 * width;
    }
    content += spacing * pageCount; // between pages + bottom padding
    final expected = content - position.viewportDimension;
    expect(position.maxScrollExtent, moreOrLessEquals(expected, epsilon: 1));

    // scrolling through windows dominated by short or tall pages must not
    // move the metrics - this is what the estimating sliver gets wrong
    final initialMax = position.maxScrollExtent;
    for (final fraction in [0.15, 0.4, 0.65, 0.9, 0.3, 0.05]) {
      position.jumpTo(initialMax * fraction);
      await tester.pump();
      await tester.pump();
      expect(position.maxScrollExtent, initialMax,
          reason: 'maxScrollExtent drifted at scroll fraction $fraction');
    }
    await tester.pump(const Duration(milliseconds: 400)); // settle timers
  });

  testWidgets('zoomed canvas gaps keep scrolling with the select tool armed',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final editing = PdfEditingController(_mixedWidthPages(20))
      ..tool = PdfEditTool.select;
    final controller = PdfViewerController();
    addTearDown(editing.dispose);
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ListenableBuilder(
          listenable: editing,
          builder: (context, _) => PdfViewer(
            document: editing.document,
            editing: editing,
            controller: controller,
            initialFit: PdfViewerFit.width,
            pagePreviews: false,
            active: false,
          ),
        ),
      ),
    ));
    await tester.pump();

    // The 6000pt first page establishes fit width. The later 792pt pages
    // are narrow islands in a wide canvas, matching the CAD file that
    // exposed this: at 3.2x transform zoom most touch-downs still land on
    // canvas, not a per-page editing overlay.
    controller.setZoom(800 / 6000 * 3.2);
    await tester.pump();
    unawaited(controller.jumpToPage(10));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final position =
        tester.state<ScrollableState>(find.byType(Scrollable).first).position;
    final before = position.pixels;
    final gesture = await tester.startGesture(const Offset(20, 450),
        kind: PointerDeviceKind.touch);
    await gesture.moveBy(const Offset(0, -100),
        timeStamp: const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.moveBy(const Offset(0, -100),
        timeStamp: const Duration(milliseconds: 32));
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.up(timeStamp: const Duration(milliseconds: 48));
    await tester.pump(const Duration(milliseconds: 200));

    // Gesture deltas are reported in list space (screen delta / 3.2 zoom),
    // so the second 100px move advances by about 31pt after pan slop. Before
    // the fix the list did not move at all: InteractiveViewer consumed the
    // canvas drag into its unbounded transform instead.
    expect(position.pixels, greaterThan(before + 20));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    final interactive =
        tester.widget<InteractiveViewer>(find.byType(InteractiveViewer));
    final matrix = interactive.transformationController!.value;
    final scale = matrix.getMaxScaleOnAxis();
    final height = tester.getSize(find.byType(InteractiveViewer)).height;
    expect(matrix.storage[13], greaterThanOrEqualTo(height * (1 - scale)));
    expect(matrix.storage[13], lessThanOrEqualTo(0));

    // At the list's bottom, further upward motion moves only the bounded
    // zoom window. The page number/render focus must follow that transform,
    // not remain on the page at the untransformed list centre.
    unawaited(controller.jumpToPage(19));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final edgeGesture = await tester.startGesture(const Offset(20, 750),
        kind: PointerDeviceKind.touch);
    for (var i = 1; i <= 8; i++) {
      await edgeGesture.moveBy(const Offset(0, -100),
          timeStamp: Duration(milliseconds: 16 * i));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await edgeGesture.up(timeStamp: const Duration(milliseconds: 144));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    // The transformed screen centre lands in the final inter-page gap,
    // assigned to page index 18 by the viewer's slot convention. Ignoring
    // transform translation would still report a substantially earlier page.
    expect(controller.currentPage, 18);
    await tester.pump(const Duration(milliseconds: 400));
  });
}
