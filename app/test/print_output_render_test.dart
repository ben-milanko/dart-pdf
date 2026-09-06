import 'dart:typed_data';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';

import 'package:dart_pdf_editor_app/print_composer.dart';
import 'package:dart_pdf_editor_app/print_settings.dart';

void main() {
  late PdfDocument source;

  setUp(() {
    final editor = PdfEditor(PdfDocument.open(buildMultiPagePdf(1)));
    editor.stampPage(0, (stamp) {
      stamp.rect(100, 600, 100, 100, fillColor: 0xFF0000);
    });
    editor.addSquare(0, const PdfRect(300, 600, 400, 700),
        strokeColor: 0x00A000, fillColor: 0x00A000);
    source = PdfDocument.open(editor.save());
  });

  Future<(ByteData, int, int)> raster(PrintSettings settings) async {
    final printed = PdfDocument.open(preparePrintDocument(source, settings));
    final image = await PdfPageRenderer.renderImage(printed.page(0));
    try {
      return ((await image.toByteData())!, image.width, image.height);
    } finally {
      image.dispose();
    }
  }

  (int, int, int) pixel((ByteData, int, int) raster, int x, int y) {
    final offset = (y * raster.$2 + x) * 4;
    return (
      raster.$1.getUint8(offset),
      raster.$1.getUint8(offset + 1),
      raster.$1.getUint8(offset + 2),
    );
  }

  testWidgets('printed document and markup streams match their preview pixels',
      (tester) async {
    await tester.runAsync(() async {
      final settings = PrintSettings(pages: [0]);
      final both = await raster(settings);
      expect((both.$2, both.$3), (612, 792));
      expect(pixel(both, 150, 142), (255, 0, 0));
      expect(pixel(both, 350, 142), (0, 160, 0));

      final document =
          await raster(settings.copyWith(content: PrintContent.documentOnly));
      expect(pixel(document, 150, 142), (255, 0, 0));
      expect(pixel(document, 350, 142), (255, 255, 255));

      final markups =
          await raster(settings.copyWith(content: PrintContent.markupsOnly));
      expect(pixel(markups, 150, 142), (255, 255, 255));
      expect(pixel(markups, 350, 142), (0, 160, 0));
    });
  });

  testWidgets('custom scale and top-left offsets move real printed artwork',
      (tester) async {
    await tester.runAsync(() async {
      final output = await raster(PrintSettings(
        pages: [0],
        scaling: PrintScaling.custom,
        customScale: 50,
        rotation: PrintRotation.none,
        center: false,
        offsetX: 20,
        offsetY: 30,
      ));
      expect(pixel(output, 95, 101), (255, 0, 0));
      expect(pixel(output, 195, 101), (0, 160, 0));
      expect(pixel(output, 150, 142), (255, 255, 255));
    });
  });

  testWidgets('dimming fades one stream without washing out the other',
      (tester) async {
    await tester.runAsync(() async {
      final pageDim =
          await raster(PrintSettings(pages: [0], dimPageContent: true));
      final fadedRed = pixel(pageDim, 150, 142);
      expect(fadedRed.$1, 255);
      expect(fadedRed.$2, closeTo(166, 2));
      expect(fadedRed.$3, closeTo(166, 2));
      expect(pixel(pageDim, 350, 142), (0, 160, 0));

      final markupDim =
          await raster(PrintSettings(pages: [0], dimMarkups: true));
      expect(pixel(markupDim, 150, 142), (255, 0, 0));
      final fadedGreen = pixel(markupDim, 350, 142);
      expect(fadedGreen.$1, closeTo(166, 2));
      expect(fadedGreen.$2, closeTo(222, 2));
      expect(fadedGreen.$3, closeTo(166, 2));
    });
  });

  testWidgets('clockwise rotation prints the artwork in the chosen orientation',
      (tester) async {
    await tester.runAsync(() async {
      final output = await raster(PrintSettings(
        pages: [0],
        paperSize: PrintPaperSize.letter,
        orientation: PrintOrientation.landscape,
        rotation: PrintRotation.clockwise90,
      ));
      expect((output.$2, output.$3), (792, 612));
      expect(pixel(output, 650, 150), (255, 0, 0));
      expect(pixel(output, 650, 350), (0, 160, 0));
    });
  });

  testWidgets('Get Window clips content and markups to the chosen area',
      (tester) async {
    await tester.runAsync(() async {
      final output = await raster(PrintSettings(
        pages: [0],
        region: const PdfRect(80, 72, 220, 212),
        rotation: PrintRotation.none,
      ));
      expect((output.$2, output.$3), (140, 140));
      expect(pixel(output, 70, 70), (255, 0, 0));
      expect(pixel(output, 135, 135), (255, 255, 255));
      expect(source.page(0).cropBox, const PdfRect(0, 0, 612, 792));
      expect(source.page(0).annotations, hasLength(1));
    });
  });
}
