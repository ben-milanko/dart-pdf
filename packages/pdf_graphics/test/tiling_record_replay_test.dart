import 'dart:typed_data';

import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart' show PdfRect;
import 'package:pdf_graphics/pdf_graphics.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:test/test.dart';

import 'interpreter_test.dart' show RecordingDevice;

/// The record-once/replay-per-tile path (#524) and the path-builder leak it
/// exposed: geometry per tile must be exactly what direct per-tile
/// interpretation produced, and the region being filled must never bleed
/// into a cell's painted paths.
void main() {
  CosDictionary hatchResources({double step = 8}) => CosDictionary({
        'Pattern': CosDictionary({
          'P1': CosStream(
            CosDictionary({
              'PatternType': const CosInteger(1),
              'PaintType': const CosInteger(1),
              'BBox': CosArray([
                const CosInteger(0),
                const CosInteger(0),
                CosReal(step),
                CosReal(step),
              ]),
              'XStep': CosReal(step),
              'YStep': CosReal(step),
              'Length': const CosInteger(0),
            }),
            Uint8List.fromList('0.4 w 0 0 m 8 8 l S'.codeUnits),
          ),
        }),
      });

  RecordingDevice run(String content, CosDictionary resources) {
    final doc = CosDocument.open(buildClassicPdf());
    final device = RecordingDevice();
    PdfInterpreter(cos: doc, device: device).run(
      ContentStreamParser.parse(Uint8List.fromList(content.codeUnits)),
      resources,
    );
    return device;
  }

  test('multi-tile fill replays one recorded cell per tile position', () {
    // A 32x32 region at 8pt steps spans >= 4 tiles, engaging the recorded
    // path; every tile must stroke the same diagonal, offset by exact
    // multiples of the step.
    final device = run('/Pattern cs /P1 scn 0 0 32 32 re f', hatchResources());
    expect(device.strokes, isNotEmpty);
    final base = device.strokes.first.$1.segments;
    expect(base, hasLength(2), reason: 'one m + one l per cell stroke');
    for (final (path, _, stroke, _) in device.strokes) {
      expect(path.segments, hasLength(2),
          reason: 'no tile may carry more than the cell diagonal');
      expect(stroke.width, closeTo(0.4, 1e-9));
      final m = path.segments[0] as PdfMoveTo;
      final l = path.segments[1] as PdfLineTo;
      final baseM = base[0] as PdfMoveTo;
      // Every tile's diagonal is the base diagonal translated by an integer
      // number of 8pt steps.
      final di = (m.x - baseM.x) / 8, dj = (m.y - baseM.y) / 8;
      expect(di, closeTo(di.roundToDouble(), 1e-6));
      expect(dj, closeTo(dj.roundToDouble(), 1e-6));
      expect(l.x - m.x, closeTo(8, 1e-6));
      expect(l.y - m.y, closeTo(8, 1e-6));
    }
  });

  test('small fills produce the same geometry as multi-tile fills', () {
    // A region under the record threshold takes the direct loop; its tile
    // geometry must match the recorded path's output for the same tile.
    final small = run('/Pattern cs /P1 scn 0 0 9 9 re f', hatchResources());
    final large = run('/Pattern cs /P1 scn 0 0 32 32 re f', hatchResources());
    // Both contain the tile whose diagonal starts at the origin.
    bool hasOriginDiagonal(RecordingDevice d) => d.strokes.any((s) {
          final m = s.$1.segments[0] as PdfMoveTo;
          return (m.x).abs() < 1e-6 && (m.y).abs() < 1e-6;
        });
    expect(hasOriginDiagonal(small), isTrue);
    expect(hasOriginDiagonal(large), isTrue);
  });

  test('the filled region path does not leak into cell paints', () {
    // Regression (#524): _paintPath used to reset its segment builder only
    // after the pattern fill returned, so the first executed cell appended
    // its geometry into the still-live region path - the region rect showed
    // up merged into the first tile's stroke (and, once cells are recorded,
    // into every tile's replay).
    final device =
        run('/Pattern cs /P1 scn 10 20 30 30 re f', hatchResources());
    for (final (path, _, _, _) in device.strokes) {
      expect(path.segments.whereType<PdfClosePath>(), isEmpty,
          reason: 'a cell stroke must never contain the region rect');
      expect(path.segments, hasLength(2));
    }
  });

  test('a recording device keeps the cell nested as one tiled command', () {
    final doc = CosDocument.open(buildClassicPdf());
    final recorder = RecordingPdfDevice();
    PdfInterpreter(cos: doc, device: recorder).run(
      ContentStreamParser.parse(
          Uint8List.fromList('/Pattern cs /P1 scn 0 0 32 32 re f'.codeUnits)),
      hatchResources(),
    );
    final tiled = recorder.commands.whereType<PdfDrawTiledCellCommand>();
    expect(tiled, hasLength(1), reason: 'O(cell + tiles), not O(cell x tiles)');
    final command = tiled.single;
    expect(command.originsX.length, greaterThanOrEqualTo(16));
    expect(command.originsX[0], 0);
    expect(command.originsY[0], 0);
    expect(
        command.cellCommands.whereType<PdfStrokePathCommand>(), hasLength(1));

    // Expanding the recorded transcript through a plain device must produce
    // exactly what direct interpretation produces.
    final expanded = RecordingDevice();
    replayCommands(recorder.commands, expanded);
    final direct = run('/Pattern cs /P1 scn 0 0 32 32 re f', hatchResources());
    expect(expanded.strokes.length, direct.strokes.length);
    for (var i = 0; i < direct.strokes.length; i++) {
      final a = expanded.strokes[i].$1.segments;
      final b = direct.strokes[i].$1.segments;
      expect(a.length, b.length);
      expect((a[0] as PdfMoveTo).x, closeTo((b[0] as PdfMoveTo).x, 1e-9));
      expect((a[0] as PdfMoveTo).y, closeTo((b[0] as PdfMoveTo).y, 1e-9));
    }

    // The wire codec round-trips the nested command bit-stably.
    final bytes = serializeCommands(recorder.commands, cos: doc);
    expect(bytes, isNotNull);
    final decoded = deserializeCommands(bytes!);
    final decodedTiled = decoded.whereType<PdfDrawTiledCellCommand>().toList();
    expect(decodedTiled, hasLength(1));
    expect(decodedTiled.single.originsX, command.originsX);
    expect(decodedTiled.single.originsY, command.originsY);
    expect(
        decodedTiled.single.cellCommands.length, command.cellCommands.length);
    final reencoded = serializeCommands(decoded, cos: doc);
    expect(reencoded, bytes, reason: 're-serialization is byte-stable');

    // And the decoded transcript still expands to the same geometry.
    final replayed = RecordingDevice();
    replayCommands(decoded, replayed);
    expect(replayed.strokes.length, direct.strokes.length);
  });

  test('repeated Type3 glyphs share one recorded cell (#535)', () {
    final doc = CosDocument.open(buildClassicPdf());
    final charProc = CosStream(
      CosDictionary({'Length': const CosInteger(0)}),
      Uint8List.fromList('600 0 d0 0.2 g 50 50 400 500 re f'.codeUnits),
    );
    final type3 = CosDictionary({
      'Type': const CosName('Font'),
      'Subtype': const CosName('Type3'),
      'FontBBox': CosArray([
        const CosInteger(0),
        const CosInteger(0),
        const CosInteger(600),
        const CosInteger(700),
      ]),
      'FontMatrix': CosArray([
        const CosReal(0.001),
        const CosInteger(0),
        const CosInteger(0),
        const CosReal(0.001),
        const CosInteger(0),
        const CosInteger(0),
      ]),
      'FirstChar': const CosInteger(0x58),
      'LastChar': const CosInteger(0x58),
      'Widths': CosArray([const CosInteger(600)]),
      'Encoding': CosDictionary({
        'Differences': CosArray([const CosInteger(0x58), const CosName('X')]),
      }),
      'CharProcs': CosDictionary({'X': charProc}),
    });
    final resources = CosDictionary({
      'Font': CosDictionary({'T3': type3}),
    });

    // Through a sink device, five occurrences of the same glyph at the same
    // size become five single-origin tiled commands sharing ONE recorded
    // cell list - the identity a canvas keys its cached sub-picture on.
    final recorder = RecordingPdfDevice();
    PdfInterpreter(cos: doc, device: recorder).run(
      ContentStreamParser.parse(
          Uint8List.fromList('BT /T3 10 Tf (XXXXX) Tj ET'.codeUnits)),
      resources,
    );
    final tiled =
        recorder.commands.whereType<PdfDrawTiledCellCommand>().toList();
    expect(tiled, hasLength(5));
    for (final t in tiled) {
      expect(t.originsX, hasLength(1));
      expect(identical(t.cellCommands, tiled.first.cellCommands), isTrue,
          reason: 'occurrences must share one recorded cell');
    }
    // Successive glyphs advance by 6 pt (600/1000 em at 10 pt).
    expect(tiled[1].originsX[0] - tiled[0].originsX[0], closeTo(6, 1e-9));

    // And the expansion through a plain device matches per-glyph geometry.
    final expanded = RecordingDevice();
    replayCommands(recorder.commands, expanded);
    expect(expanded.fills, hasLength(5));
    final x0 = (expanded.fills[0].$1.segments[0] as PdfMoveTo).x;
    final x1 = (expanded.fills[1].$1.segments[0] as PdfMoveTo).x;
    expect(x1 - x0, closeTo(6, 1e-9));
  });

  test('a Type3 cell is reused only under the stroke colour it was drawn in',
      () {
    // A d0 glyph that strokes inherits the text state's stroke colour, so the
    // colour is part of what a recorded cell stands for: setting it again to
    // the same value keeps sharing the cell, changing it must record afresh.
    final doc = CosDocument.open(buildClassicPdf());
    final type3 = CosDictionary({
      'Type': const CosName('Font'),
      'Subtype': const CosName('Type3'),
      'FontBBox': CosArray([
        const CosInteger(0),
        const CosInteger(0),
        const CosInteger(600),
        const CosInteger(700),
      ]),
      'FontMatrix': CosArray([
        const CosReal(0.001),
        const CosInteger(0),
        const CosInteger(0),
        const CosReal(0.001),
        const CosInteger(0),
        const CosInteger(0),
      ]),
      'FirstChar': const CosInteger(0x58),
      'LastChar': const CosInteger(0x58),
      'Widths': CosArray([const CosInteger(600)]),
      'Encoding': CosDictionary({
        'Differences': CosArray([const CosInteger(0x58), const CosName('X')]),
      }),
      'CharProcs': CosDictionary({
        'X': CosStream(
          CosDictionary({'Length': const CosInteger(0)}),
          Uint8List.fromList('600 0 d0 40 w 50 50 m 450 550 l S'.codeUnits),
        ),
      }),
    });
    final resources = CosDictionary({
      'Font': CosDictionary({'T3': type3}),
    });
    const content = 'BT /T3 10 Tf '
        '0 0 1 RG (X) Tj '
        '0 0 1 RG (X) Tj '
        '1 0 0 RG (X) Tj ET';

    final recorder = RecordingPdfDevice();
    PdfInterpreter(cos: doc, device: recorder).run(
      ContentStreamParser.parse(Uint8List.fromList(content.codeUnits)),
      resources,
    );
    final tiled =
        recorder.commands.whereType<PdfDrawTiledCellCommand>().toList();
    expect(tiled, hasLength(3));
    expect(identical(tiled[1].cellCommands, tiled[0].cellCommands), isTrue,
        reason: 'the same colour set twice is still the same cell');
    expect(identical(tiled[2].cellCommands, tiled[0].cellCommands), isFalse,
        reason: 'a new stroke colour must not replay the old cell');

    // What reaches a device is what direct interpretation paints.
    final expanded = RecordingDevice();
    replayCommands(recorder.commands, expanded);
    final direct = run(content, resources);
    expect(expanded.strokes, hasLength(3));
    expect(direct.strokes, hasLength(3));
    for (var i = 0; i < 3; i++) {
      expect(expanded.strokes[i].$2, direct.strokes[i].$2);
    }
    expect(expanded.strokes[0].$2, expanded.strokes[1].$2);
    expect(expanded.strokes[2].$2, isNot(expanded.strokes[0].$2));
  });

  test('unpainted cell segments do not leak into later content', () {
    // A cell that builds a path but never paints it must not prepend those
    // segments to the path the enclosing stream draws next.
    final resources = CosDictionary({
      'Pattern': CosDictionary({
        'P1': CosStream(
          CosDictionary({
            'PatternType': const CosInteger(1),
            'PaintType': const CosInteger(1),
            'BBox': CosArray([
              const CosInteger(0),
              const CosInteger(0),
              const CosInteger(8),
              const CosInteger(8),
            ]),
            'XStep': const CosInteger(8),
            'YStep': const CosInteger(8),
            'Length': const CosInteger(0),
          }),
          // builds a path, paints nothing
          Uint8List.fromList('0 0 m 8 8 l'.codeUnits),
        ),
      }),
    });
    final device = run(
        '/Pattern cs /P1 scn 0 0 32 32 re f 1 0 0 RG 40 40 m 50 50 l S',
        resources);
    expect(device.strokes, hasLength(1));
    final segments = device.strokes.single.$1.segments;
    expect(segments, hasLength(2),
        reason: 'the trailing stroke must contain only its own two points');
    expect((segments[0] as PdfMoveTo).x, closeTo(40, 1e-6));
  });

  group('a stamped cell lists its images', () {
    // A recorder lists a cell's images again for every stamp, in the order
    // the wire codec writes them. A Type3 glyph cell carries that list with
    // it instead of being walked per glyph.
    CosDictionary bitmapFont() => CosDictionary({
          'Type': const CosName('Font'),
          'Subtype': const CosName('Type3'),
          'FontBBox': CosArray([
            const CosInteger(0),
            const CosInteger(0),
            const CosInteger(600),
            const CosInteger(700),
          ]),
          'FontMatrix': CosArray([
            const CosReal(0.001),
            const CosInteger(0),
            const CosInteger(0),
            const CosReal(0.001),
            const CosInteger(0),
            const CosInteger(0),
          ]),
          'FirstChar': const CosInteger(0x58),
          'LastChar': const CosInteger(0x59),
          'Widths': CosArray([const CosInteger(600), const CosInteger(600)]),
          'Encoding': CosDictionary({
            'Differences': CosArray([
              const CosInteger(0x58),
              const CosName('X'),
              const CosName('Y'),
            ]),
          }),
          'CharProcs': CosDictionary({
            // A 1-bit stencil, the shape of a TeX PK-font glyph.
            'X': CosStream(
              CosDictionary({'Length': const CosInteger(0)}),
              Uint8List.fromList(('600 0 0 0 600 700 d1 '
                      'q 400 0 0 500 50 50 cm '
                      'BI /W 2 /H 2 /IM true /BPC 1 ID @A EI Q')
                  .codeUnits),
            ),
            // A vector glyph: no images at all.
            'Y': CosStream(
              CosDictionary({'Length': const CosInteger(0)}),
              Uint8List.fromList(
                  '600 0 0 0 600 700 d1 50 50 400 500 re f'.codeUnits),
            ),
          }),
        });

    /// The images a wire transcript of [commands] carries, in order: each
    /// distinct cell list contributes the first time it is stamped.
    List<PdfImageRequest> wireOrder(List<PdfRenderCommand> commands) {
      final out = <PdfImageRequest>[];
      final seen = Set<List<PdfRenderCommand>>.identity();
      void walk(List<PdfRenderCommand> list) {
        for (final c in list) {
          if (c is PdfDrawImageCommand) {
            out.add(c.request);
          } else if (c is PdfEndSoftMaskedCommand) {
            walk(c.maskCommands);
          } else if (c is PdfDrawTiledCellCommand && seen.add(c.cellCommands)) {
            walk(c.cellCommands);
          }
        }
      }

      walk(commands);
      return out;
    }

    void expectSameRequests(
        List<PdfImageRequest> actual, List<PdfImageRequest> expected) {
      expect(actual, hasLength(expected.length));
      for (var i = 0; i < expected.length; i++) {
        expect(identical(actual[i], expected[i]), isTrue, reason: 'image $i');
      }
    }

    test('a Type3 glyph is listed once, however often it is stamped', () {
      final doc = CosDocument.open(buildClassicPdf());
      final resources = CosDictionary({
        'Font': CosDictionary({'T3': bitmapFont()}),
      });
      final content = ContentStreamParser.parse(
          Uint8List.fromList('BT /T3 10 Tf (XYXXY) Tj ET'.codeUnits));

      final recorder = RecordingPdfDevice();
      PdfInterpreter(cos: doc, device: recorder).run(content, resources);
      final stamps =
          recorder.commands.whereType<PdfDrawTiledCellCommand>().toList();
      expect(stamps, hasLength(5));
      expect(identical(stamps[0].cellCommands, stamps[2].cellCommands), isTrue);
      // Stamps of one cell say so; different cells do not share a marker.
      expect(stamps[0].share, isNotNull);
      expect(identical(stamps[0].share, stamps[2].share), isTrue);
      expect(identical(stamps[0].share, stamps[1].share), isFalse);

      // Three stencil glyphs drawn, one image listed - the first stamp's.
      expect(recorder.imageRequests, hasLength(1));
      expectSameRequests(recorder.imageRequests, wireOrder(recorder.commands));

      // The streaming writer lists exactly what the recorder does, and the
      // wire carries that one image once.
      final writer = PdfStreamingCommandWriter(cos: doc);
      PdfInterpreter(cos: doc, device: writer).run(content, resources);
      expect(writer.imageRequests, hasLength(1));
      final bytes = writer.snapshot();
      expect(bytes, serializeCommands(recorder.commands, cos: doc));
      expect(wireOrder(deserializeCommands(bytes)), hasLength(1));
    });

    test('the listing follows the wire through nested and repeated cells', () {
      final doc = CosDocument.open(buildClassicPdf());
      final source = RecordingPdfDevice();
      PdfInterpreter(cos: doc, device: source).run(
          ContentStreamParser.parse(
              Uint8List.fromList('BT /T3 10 Tf (XX) Tj ET'.codeUnits)),
          CosDictionary({
            'Font': CosDictionary({'T3': bitmapFont()}),
          }));
      final glyph = source.commands.whereType<PdfDrawTiledCellCommand>().first;
      PdfDrawTiledCellCommand stamp(List<PdfRenderCommand> cell) =>
          PdfDrawTiledCellCommand(cell, Float64List(1), Float64List(1));

      // The glyph cell inside another cell, twice; that outer cell stamped
      // twice; then the glyph cell on its own; then a second, distinct list
      // holding the same image command - a different cell, listed again.
      final outer = <PdfRenderCommand>[glyph, glyph];
      final copy = List<PdfRenderCommand>.of(glyph.cellCommands);
      final commands = <PdfRenderCommand>[
        stamp(outer),
        stamp(outer),
        glyph,
        stamp(copy),
        stamp(copy),
      ];

      final recorder = RecordingPdfDevice();
      final writer = PdfStreamingCommandWriter(cos: doc);
      for (final command in commands.cast<PdfDrawTiledCellCommand>()) {
        recorder.drawTiledCell(command);
        writer.drawTiledCell(command);
      }
      expect(recorder.imageRequests, hasLength(2));
      expectSameRequests(recorder.imageRequests, wireOrder(commands));
      expectSameRequests(writer.imageRequests, recorder.imageRequests);

      // And it is what the decoded wire holds, image for image.
      final decoded = deserializeCommands(writer.snapshot());
      expect(wireOrder(decoded), hasLength(recorder.imageRequests.length));
    });

    test('a recording replayed into a second recorder lists the same', () {
      // The marker a stamp carries remembers the last recorder that listed
      // it. A second recorder - or the first one again - must not be fooled.
      final doc = CosDocument.open(buildClassicPdf());
      final first = RecordingPdfDevice();
      PdfInterpreter(cos: doc, device: first).run(
          ContentStreamParser.parse(
              Uint8List.fromList('BT /T3 10 Tf (XXYX) Tj ET'.codeUnits)),
          CosDictionary({
            'Font': CosDictionary({'T3': bitmapFont()}),
          }));
      expect(first.imageRequests, hasLength(1));

      final second = RecordingPdfDevice();
      replayCommands(first.commands, second);
      expectSameRequests(second.imageRequests, first.imageRequests);

      // Interleaved between two recorders, stamp by stamp.
      final a = RecordingPdfDevice(), b = RecordingPdfDevice();
      for (final c in first.commands.whereType<PdfDrawTiledCellCommand>()) {
        a.drawTiledCell(c);
        b.drawTiledCell(c);
      }
      expectSameRequests(a.imageRequests, first.imageRequests);
      expectSameRequests(b.imageRequests, first.imageRequests);

      // The same list stamped with and without its marker is still one cell.
      final glyph = first.commands.whereType<PdfDrawTiledCellCommand>().first;
      final bare = PdfDrawTiledCellCommand(
          glyph.cellCommands, glyph.originsX, glyph.originsY);
      for (final order in [
        [glyph, bare, glyph],
        [bare, glyph, bare],
      ]) {
        final recorder = RecordingPdfDevice();
        order.forEach(recorder.drawTiledCell);
        expect(recorder.imageRequests, hasLength(1));
      }
    });

    test('an image behind a soft mask inside a cell is listed', () {
      final doc = CosDocument.open(buildClassicPdf());
      final source = RecordingPdfDevice();
      PdfInterpreter(cos: doc, device: source).run(
          ContentStreamParser.parse(
              Uint8List.fromList('BT /T3 10 Tf (X) Tj ET'.codeUnits)),
          CosDictionary({
            'Font': CosDictionary({'T3': bitmapFont()}),
          }));
      final glyph = source.commands.whereType<PdfDrawTiledCellCommand>().first;
      final image = glyph.cellCommands.whereType<PdfDrawImageCommand>().single;
      // A cell whose only image sits in a soft mask's command list, next to
      // a stamp of the glyph cell.
      final masked = <PdfRenderCommand>[
        PdfEndSoftMaskedCommand(
          luminosity: true,
          backdrop: const PdfRect(0, 0, 1, 1),
          maskCommands: [image, glyph],
          backdropLuminance: 0,
          transferScale: 1,
          transferOffset: 0,
        ),
      ];
      final command =
          PdfDrawTiledCellCommand(masked, Float64List(1), Float64List(1));
      final recorder = RecordingPdfDevice()
        ..drawTiledCell(command)
        ..drawTiledCell(command)
        ..drawTiledCell(glyph);
      expect(recorder.imageRequests, hasLength(2));
      expectSameRequests(
          recorder.imageRequests, wireOrder([command, command, glyph]));
    });
  });
}
