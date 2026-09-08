import 'dart:typed_data';

import 'color.dart';
import 'device.dart';
import 'matrix.dart';
import 'render_command.dart';

/// Text metadata captured from a complete, in-memory page recording.
///
/// Capture after the page content walk finishes and before drawing annotations:
/// `PdfTextExtractor` searches page content, not annotation appearances. The
/// recording interpreter must use `collectCharOffsets: true` for exact
/// selection geometry. Capture before serializing render commands, whose wire
/// format omits marked-content ids and embedded-font character offsets.
///
/// Graphics, glyph outlines and soft-mask definitions are discarded. Text in
/// Type3 and tiling cells stays compact and expands only when [runs] is read.
/// Invisible text and text inside masked source groups remain searchable, just
/// as in a fresh extraction. The snapshot does not retain the input graph and
/// is unaffected by subsequently clearing or extending its command lists.
class PdfRecordedText {
  PdfRecordedText._(this._sequence, this.estimatedBytes);

  factory PdfRecordedText.capture(List<PdfRenderCommand> commands) {
    final builder = _RecordedTextBuilder();
    final sequence = builder.capture(commands);
    return PdfRecordedText._(sequence, builder.estimatedBytes);
  }

  final _RecordedTextSequence _sequence;

  /// Approximate retained bytes for cache budgeting, including object/list
  /// overhead, UTF-16 strings, glyph metadata and copied numeric buffers.
  /// Shared cells and runs count once. This is a portable estimate, not a heap
  /// measurement, and excludes the expanded extraction produced from [runs].
  final int estimatedBytes;

  bool get isEmpty => _sequence.nodes.isEmpty;

  /// Positioned source text in the interpreter's original encounter order.
  ///
  /// Repeated cells expand lazily. Runs retain extraction geometry, Unicode,
  /// invisibility and marked-content ids; their painting properties and glyph
  /// outlines have intentionally been removed. Use `PdfTextExtractor` to
  /// reconstruct logical text, separators, and bidirectional selection data.
  Iterable<PdfTextRun> get runs => _sequence.runs;
}

sealed class _RecordedTextNode {}

class _RecordedTextRun extends _RecordedTextNode {
  _RecordedTextRun(this.run);

  final PdfTextRun run;
}

class _RecordedTextCell extends _RecordedTextNode {
  _RecordedTextCell(this.sequence, this.originsX, this.originsY);

  final _RecordedTextSequence sequence;
  final Float64List originsX;
  final Float64List originsY;
}

class _RecordedTextSequence {
  _RecordedTextSequence(this.nodes);

  final List<_RecordedTextNode> nodes;

  Iterable<PdfTextRun> get runs sync* {
    for (final node in nodes) {
      switch (node) {
        case _RecordedTextRun(:final run):
          yield run;
        case _RecordedTextCell(
            :final sequence,
            :final originsX,
            :final originsY
          ):
          for (var i = 0; i < originsX.length; i++) {
            final dx = originsX[i], dy = originsY[i];
            for (final run in sequence.runs) {
              // Match TranslatingPdfDevice's inner-to-outer additions exactly.
              // Summing nested translations first can change rounding and move
              // a search quad relative to a fresh extraction at extreme zoom.
              yield dx == 0 && dy == 0
                  ? run
                  : _textRun(run,
                      transform: PdfMatrix(
                        run.transform.a,
                        run.transform.b,
                        run.transform.c,
                        run.transform.d,
                        run.transform.e + dx,
                        run.transform.f + dy,
                      ));
            }
          }
      }
    }
  }
}

class _RecordedTextBuilder {
  final _sequences =
      Map<List<PdfRenderCommand>, _RecordedTextSequence>.identity();
  final _active = Set<List<PdfRenderCommand>>.identity();
  final _runs = Map<PdfTextRun, PdfTextRun>.identity();
  int estimatedBytes = 32;

  _RecordedTextSequence capture(List<PdfRenderCommand> commands) {
    final existing = _sequences[commands];
    if (existing != null) return existing;
    if (!_active.add(commands)) {
      throw ArgumentError('Recorded text contains a cyclic tiled cell');
    }
    final nodes = <_RecordedTextNode>[];
    for (final command in commands) {
      if (command is PdfDrawTextCommand) {
        final run =
            _runs.putIfAbsent(command.run, () => _captureRun(command.run));
        nodes.add(_RecordedTextRun(run));
        estimatedBytes += 32;
      } else if (command is PdfDrawTiledCellCommand &&
          command.originsX.isNotEmpty) {
        final cell = capture(command.cellCommands);
        if (cell.nodes.isNotEmpty) {
          nodes.add(_RecordedTextCell(
            cell,
            Float64List.fromList(command.originsX).asUnmodifiableView(),
            Float64List.fromList(command.originsY).asUnmodifiableView(),
          ));
          estimatedBytes += 112 + command.originsX.length * 16;
        }
      }
      // Mask commands live inside PdfEndSoftMaskedCommand. Never visit them:
      // the extraction device deliberately does not execute drawMask either.
    }
    _active.remove(commands);
    final sequence = _RecordedTextSequence(List.unmodifiable(nodes));
    _sequences[commands] = sequence;
    estimatedBytes += 48 + nodes.length * 8;
    return sequence;
  }

  PdfTextRun _captureRun(PdfTextRun source) {
    final glyphs = source.glyphs;
    final offsets = source.charOffsets;
    estimatedBytes += 384 + source.text.length * 2;
    if (glyphs != null) {
      estimatedBytes += 32;
      for (final glyph in glyphs) {
        estimatedBytes += 96 + (glyph.text?.length ?? 0) * 2;
      }
    }
    if (offsets != null) estimatedBytes += 32 + offsets.length * 8;
    return PdfTextRun(
      text: source.text,
      transform: source.transform,
      color: PdfColor.black,
      width: source.width,
      // Null vs non-null distinguishes substituted logical text from the
      // positioned visual glyph order of embedded fonts in the bidi pipeline.
      glyphs: glyphs == null
          ? null
          : List.unmodifiable([
              for (final glyph in glyphs)
                PdfGlyphPlacement(
                  offset: glyph.offset,
                  offsetY: glyph.offsetY,
                  text: glyph.text,
                ),
            ]),
      charOffsets: offsets == null
          ? null
          : Float64List.fromList(offsets).asUnmodifiableView(),
      invisible: source.invisible,
      mcid: source.mcid,
    );
  }
}

PdfTextRun _textRun(PdfTextRun source, {required PdfMatrix transform}) =>
    PdfTextRun(
      text: source.text,
      transform: transform,
      color: PdfColor.black,
      width: source.width,
      glyphs: source.glyphs,
      charOffsets: source.charOffsets,
      invisible: source.invisible,
      mcid: source.mcid,
    );
