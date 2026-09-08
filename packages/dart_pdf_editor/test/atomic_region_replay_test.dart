import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:dart_pdf_editor/src/region_replay_index.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';

PdfPath _rect(double l, double b, double r, double t) => PdfPath([
      PdfMoveTo(l, b),
      PdfLineTo(r, b),
      PdfLineTo(r, t),
      PdfLineTo(l, t),
      const PdfClosePath(),
    ]);

PdfFillPathCommand _fill(double l, double b, double r, double t,
        [PdfColor color = const PdfColor(1, 0, 0)]) =>
    PdfFillPathCommand(_rect(l, b, r, t), color, PdfFillRule.nonzero, 1);

const _maskEnd = PdfEndSoftMaskedCommand(
  luminosity: false,
  backdrop: PdfRect(0, 0, 612, 792),
  maskCommands: [],
  transferScale: 0,
  transferOffset: 1,
);

void main() {
  test('selects complete groups and source outside a transferred soft mask',
      () {
    final commands = <PdfRenderCommand>[
      _fill(300, 300, 320, 320),
      const PdfBeginGroupCommand(.7,
          isolated: true, bounds: PdfRect(0, 0, 1, 1)),
      const PdfBeginSoftMaskedCommand(),
      _fill(40, 40, 70, 70),
      _maskEnd,
      const PdfEndGroupCommand(),
      _fill(400, 400, 420, 420),
    ];
    for (final grid in [false, true]) {
      final index = PdfRegionReplayIndex.build(commands,
          maxCommands: 100, buildGrid: grid);
      expect(index.supported, isTrue);
      final selected = index.select(const PdfRect(60, 60, 65, 65));
      expect(selected, hasLength(1));
      expect(selected.single.commandIndex, 1);
      expect(selected.single.endCommandIndex, 6);
      // The allocation hint and empty mask never bound the visible source.
      expect(selected.single.bounds.left, lessThanOrEqualTo(40));
      expect(selected.single.bounds.right, greaterThanOrEqualTo(70));
      expect(index.select(const PdfRect(200, 200, 210, 210)), isEmpty);
      final restored =
          deserializeRegionReplayIndex(serializeRegionReplayIndex(index)!);
      expect(
          restored.select(const PdfRect(60, 60, 65, 65)).single.endCommandIndex,
          6);
    }
  });

  test('groups restore clips; only soft masks restore their entry blend', () {
    final commands = <PdfRenderCommand>[
      const PdfSetBlendModeCommand(PdfBlendMode.multiply),
      const PdfBeginGroupCommand(.5, isolated: true),
      PdfClipPathCommand(_rect(10, 10, 20, 20), PdfFillRule.nonzero),
      _fill(10, 10, 20, 20),
      const PdfSetBlendModeCommand(PdfBlendMode.screen),
      const PdfEndGroupCommand(),
      _fill(100, 100, 120, 120),
      const PdfBeginSoftMaskedCommand(),
      const PdfSetBlendModeCommand(PdfBlendMode.darken),
      _fill(150, 150, 170, 170),
      _maskEnd,
      _fill(200, 200, 220, 220),
    ];
    final index = PdfRegionReplayIndex.build(commands, maxCommands: 100);
    expect(index.supported, isTrue);
    final afterGroup = index.select(const PdfRect(105, 105, 110, 110)).single;
    expect(afterGroup.clips, isNull);
    expect(afterGroup.blendMode, PdfBlendMode.screen);
    final afterMask = index.select(const PdfRect(205, 205, 210, 210)).single;
    expect(afterMask.blendMode, PdfBlendMode.screen);
  });

  test('unsafe compositing and state crossings retain full-replay fallback',
      () {
    const begin = PdfBeginGroupCommand(1, isolated: true);
    const end = PdfEndGroupCommand();
    const save = PdfSaveCommand();
    const restore = PdfRestoreCommand();
    const overprint =
        PdfSetOverprintCommand(fill: true, stroke: false, mode: 1);
    final unsafe = <List<PdfRenderCommand>>[
      [begin, _fill(0, 0, 10, 10)],
      [end],
      [begin, _maskEnd],
      [const PdfBeginSoftMaskedCommand(), end],
      [save, begin, restore, end],
      [begin, save, end, restore],
      [begin, overprint, _fill(0, 0, 10, 10), end],
      [const PdfBeginGroupCommand(1, backdropColor: PdfColor(1, 1, 1)), end],
      [
        const PdfBeginSoftMaskedCommand(),
        _fill(0, 0, 10, 10),
        const PdfEndSoftMaskedCommand(
            luminosity: false,
            backdrop: PdfRect(0, 0, 10, 10),
            maskCommands: [overprint])
      ],
      [
        PdfDrawTiledCellCommand([begin, overprint, end],
            Float64List.fromList([0]), Float64List.fromList([0]))
      ],
    ];
    for (var i = 0; i < unsafe.length; i++) {
      final index = PdfRegionReplayIndex.build(unsafe[i], maxCommands: 100);
      expect(index.supported, isFalse, reason: 'unsafe case $i');
      expect(index.commandsForRegion(const PdfRect(0, 0, 10, 10), unsafe[i]),
          same(unsafe[i]));
    }
    expect(
        PdfRegionReplayIndex.build([begin, begin, end, end],
                maxCommands: 100, maxStateDepth: 1)
            .supported,
        isFalse);
  });

  test('shared cells preserve the blend mode of each invocation', () {
    const normal = PdfSetBlendModeCommand(PdfBlendMode.normal);
    const multiply = PdfSetBlendModeCommand(PdfBlendMode.multiply);
    const screen = PdfSetBlendModeCommand(PdfBlendMode.screen);
    PdfDrawTiledCellCommand cell(List<PdfRenderCommand> commands) =>
        PdfDrawTiledCellCommand(
            commands, Float64List.fromList([0]), Float64List.fromList([0]));
    final resetNormal = cell([multiply, _fill(0, 0, 10, 10), normal]);
    final cases = <(List<PdfRenderCommand>, bool)>[
      ([resetNormal], true),
      (
        [
          multiply,
          cell([screen, _fill(0, 0, 10, 10), multiply])
        ],
        true
      ),
      (
        [
          cell([multiply, _fill(0, 0, 10, 10)])
        ],
        false
      ),
      // An identity-only safety cache would accept the second invocation.
      ([resetNormal, multiply, resetNormal], false),
      (
        [
          cell([PdfClipPathCommand(_rect(0, 0, 10, 10), PdfFillRule.nonzero)])
        ],
        false
      ),
      (
        [
          multiply,
          const PdfBeginSoftMaskedCommand(),
          resetNormal,
          PdfEndSoftMaskedCommand(
              luminosity: false,
              backdrop: const PdfRect(0, 0, 10, 10),
              maskCommands: [resetNormal])
        ],
        true
      ),
    ];
    for (var i = 0; i < cases.length; i++) {
      expect(
          PdfRegionReplayIndex.build(cases[i].$1, maxCommands: 100).supported,
          cases[i].$2,
          reason: 'cell context $i');
    }
  });

  testWidgets('nested masks, knockout and clips retain exact high-zoom pixels',
      (tester) async {
    await tester.runAsync(() async {
      final page = PdfDocument.open(buildClassicPdf()).page(0);
      final commands = <PdfRenderCommand>[
        _fill(0, 0, 612, 792, const PdfColor(.7, .85, 1)),
        const PdfSaveCommand(),
        PdfClipPathCommand(_rect(40, 700, 100, 760), PdfFillRule.nonzero),
        const PdfSetBlendModeCommand(PdfBlendMode.multiply),
        const PdfBeginGroupCommand(.7, isolated: true, knockout: true),
        _fill(45, 715, 80, 750),
        const PdfSaveCommand(),
        PdfClipPathCommand(_rect(50, 720, 75, 747), PdfFillRule.nonzero),
        const PdfBeginSoftMaskedCommand(),
        _fill(53, 722, 78, 748, const PdfColor(0, 1, 0)),
        const PdfBeginGroupCommand(.5, isolated: true),
        _fill(57, 728, 70, 746, const PdfColor(0, 0, 1)),
        const PdfEndGroupCommand(),
        PdfEndSoftMaskedCommand(
            luminosity: false,
            backdrop: const PdfRect(0, 0, 612, 792),
            maskCommands: [_fill(56, 726, 62, 731, const PdfColor(1, 1, 1))],
            transferScale: .65,
            transferOffset: .35),
        const PdfRestoreCommand(),
        const PdfSetBlendModeCommand(PdfBlendMode.screen),
        const PdfEndGroupCommand(),
        const PdfRestoreCommand(),
        _fill(85, 725, 95, 740, const PdfColor(1, 0, 1)),
        const PdfSetBlendModeCommand(PdfBlendMode.normal),
        _fill(300, 300, 320, 320),
        _fill(400, 400, 420, 420),
        for (var i = 0; i < 32; i++)
          _fill(300 + i * 3.0, 300, 301 + i * 3.0, 301),
      ];
      for (final useGrid in [false, true]) {
        final index = deserializeRegionReplayIndex(serializeRegionReplayIndex(
            PdfRegionReplayIndex.build(commands,
                maxCommands: 100, buildGrid: useGrid))!);
        expect(index.supported, isTrue);
        for (final ratio in [30.0, 100.0]) {
          for (final region in [
            const ui.Rect.fromLTWH(50.137, 45.271, 12, 9),
            const ui.Rect.fromLTWH(60.129, 61.331, 12, 9),
            const ui.Rect.fromLTWH(84.137, 52.271, 12, 9),
          ]) {
            final pageRegion = PdfRect(region.left, 792 - region.bottom,
                region.right, 792 - region.top);
            final source = await _raster(page, commands, region, ratio);
            final selected = index.commandsForRegion(pageRegion, commands);
            expect(selected.length, lessThan(commands.length));
            final actual = await _raster(page, selected, region, ratio);
            try {
              expect(await _pixels(actual), await _pixels(source),
                  reason: 'grid=$useGrid ratio=$ratio region=$region');
            } finally {
              source.dispose();
              actual.dispose();
            }
          }
        }
      }
    });
  });
}

Future<ui.Image> _raster(PdfPage page, List<PdfRenderCommand> commands,
    ui.Rect region, double ratio) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder)
    ..scale(ratio)
    ..translate(-region.left, -region.top);
  PdfPageRenderer.preparePageCanvas(canvas, page, const PdfPageRenderPlan());
  replayCommands(commands, CanvasPdfDevice(canvas, images: const {}));
  final picture = recorder.endRecording();
  try {
    return await picture.toImage(
        (region.width * ratio).ceil(), (region.height * ratio).ceil());
  } finally {
    picture.dispose();
  }
}

Future<Uint8List> _pixels(ui.Image image) async =>
    (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!
        .buffer
        .asUint8List();
