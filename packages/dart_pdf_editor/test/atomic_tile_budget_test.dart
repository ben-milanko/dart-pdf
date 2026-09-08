import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:dart_pdf_editor/src/region_replay_index.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';

import 'fixtures/high_zoom_pdf.dart';

const _paint = PdfFillPathCommand(
    PdfPath([
      PdfMoveTo(10, 10),
      PdfLineTo(20, 10),
      PdfLineTo(20, 20),
      PdfLineTo(10, 20),
      PdfClosePath(),
    ]),
    PdfColor(1, 0, 0),
    PdfFillRule.nonzero,
    1);

List<PdfRenderCommand> _group(int paints) => [
      const PdfBeginGroupCommand(1, isolated: true),
      for (var i = 0; i < paints; i++) _paint,
      const PdfEndGroupCommand(),
    ];

void main() {
  test('atomic span survives the worker index codec', () {
    final index = PdfRegionReplayIndex.build(_group(1023), maxCommands: 2000);
    expect(index.maxAtomicCommandSpan, 1025);
    final restored =
        deserializeRegionReplayIndex(serializeRegionReplayIndex(index)!);
    expect(restored.maxAtomicCommandSpan, 1025);
  });

  testWidgets('large groups keep selective patches without enabling tiles',
      (tester) async {
    await tester.runAsync(() async {
      final page = PdfDocument.open(buildHighZoomPagePdf()).page(0);
      for (final (paints, tiled) in [(40, true), (1022, true), (1023, false)]) {
        final scene = await PdfRetainedScene.fromCommands(page, _group(paints),
            includeImages: false);
        try {
          expect(scene.supportsRegionRaster, isTrue);
          expect(scene.supportsTiledRegionRaster, tiled,
              reason: '$paints paints in one indivisible group');
          final selected =
              scene.selectRegion(const ui.Rect.fromLTWH(12, 774, 2, 2));
          expect(selected, hasLength(1));
          expect(selected!.single.endCommandIndex, paints + 2);
          expect(scene.selectRegion(const ui.Rect.fromLTWH(100, 100, 10, 10)),
              isEmpty,
              reason: 'single-patch culling remains available');
          scene.dropRegionIndex();
          expect(scene.supportsTiledRegionRaster, tiled,
              reason: 'memory-pressure rebuild keeps the same tile verdict');
        } finally {
          scene.dispose();
        }
      }
    });
  });

  testWidgets('tile budget counts nested mask and cell commands',
      (tester) async {
    await tester.runAsync(() async {
      final page = PdfDocument.open(buildHighZoomPagePdf()).page(0);
      final mask = List<PdfRenderCommand>.filled(1024, _paint);
      final cases = <List<PdfRenderCommand>>[
        [
          const PdfBeginSoftMaskedCommand(),
          _paint,
          PdfEndSoftMaskedCommand(
            luminosity: false,
            backdrop: const PdfRect(0, 0, 612, 792),
            maskCommands: mask,
          ),
        ],
        [
          const PdfBeginGroupCommand(1, isolated: true),
          PdfDrawTiledCellCommand(
              mask, Float64List.fromList([0]), Float64List.fromList([0])),
          const PdfEndGroupCommand(),
        ],
        [
          const PdfBeginGroupCommand(1, isolated: true),
          PdfDrawTiledCellCommand(
              const [_paint], Float64List(1024), Float64List(1024)),
          const PdfEndGroupCommand(),
        ],
      ];
      for (final commands in cases) {
        final scene = await PdfRetainedScene.fromCommands(page, commands,
            includeImages: false);
        try {
          expect(scene.commands, hasLength(3));
          expect(scene.supportsRegionRaster, isTrue);
          expect(scene.supportsTiledRegionRaster, isFalse,
              reason: 'nested work must not hide behind a three-slot range');
        } finally {
          scene.dispose();
        }
      }
    });
  });
}
