import 'dart:typed_data';

import 'package:pdf_cos/pdf_cos.dart';
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
    final device = run(
        '/Pattern cs /P1 scn 10 20 30 30 re f', hatchResources());
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
      ContentStreamParser.parse(Uint8List.fromList(
          '/Pattern cs /P1 scn 0 0 32 32 re f'.codeUnits)),
      hatchResources(),
    );
    final tiled = recorder.commands.whereType<PdfDrawTiledCellCommand>();
    expect(tiled, hasLength(1), reason: 'O(cell + tiles), not O(cell x tiles)');
    final command = tiled.single;
    expect(command.originsX.length, greaterThanOrEqualTo(16));
    expect(command.originsX[0], 0);
    expect(command.originsY[0], 0);
    expect(command.cellCommands.whereType<PdfStrokePathCommand>(),
        hasLength(1));

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
    final decodedTiled =
        decoded.whereType<PdfDrawTiledCellCommand>().toList();
    expect(decodedTiled, hasLength(1));
    expect(decodedTiled.single.originsX, command.originsX);
    expect(decodedTiled.single.originsY, command.originsY);
    expect(decodedTiled.single.cellCommands.length,
        command.cellCommands.length);
    final reencoded = serializeCommands(decoded, cos: doc);
    expect(reencoded, bytes, reason: 're-serialization is byte-stable');

    // And the decoded transcript still expands to the same geometry.
    final replayed = RecordingDevice();
    replayCommands(decoded, replayed);
    expect(replayed.strokes.length, direct.strokes.length);
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
}
