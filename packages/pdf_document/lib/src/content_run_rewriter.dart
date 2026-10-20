import 'dart:typed_data';

import 'package:pdf_cos/pdf_cos.dart';

/// The shared text-run rewrite engine behind `PdfContentEditing.replaceText`.
///
/// Every rewrite path - simple byte fonts, styled simple fonts, composite
/// (/Type0) fonts, and composite fonts drawing an undrawable character in a
/// fallback face - is the *same* skeleton: flatten a run's `Tj`/`TJ`
/// operators into (glyph | kern) cells, align `find` to glyph boundaries,
/// splice the replacement in at each match, append a compensating kern so
/// following text holds position, and coalesce back into one `Tj`-or-`TJ`.
/// That skeleton lives here once ([TextRunRewriter]); only the *encoding* -
/// how a glyph is a byte or a 2-byte code, how a replacement is drawn, how
/// cells serialize - varies, and that is a [RunCodec]. Keeping the engine
/// free of any document/editor dependency is what makes the kern and
/// coalescing math unit-testable against a fake codec.

/// One flattened position in a text run: a glyph (a simple byte or a 2-byte
/// composite code) or a `TJ` kern number (advance of `-kern/1000` em).
/// Exactly one field is set.
typedef RunCell = ({int? glyph, double? kern});

/// One token of rewriter output. A [CellEmit] is coalescable into a show
/// string or kern number; an [OpEmit] is a literal operator that acts as a
/// barrier - it flushes any pending cells before it - used to bracket a
/// styled or fallback-font replacement with its `Tf`/colour operators.
sealed class Emit {}

class CellEmit implements Emit {
  const CellEmit(this.cell);
  final RunCell cell;
}

class OpEmit implements Emit {
  const OpEmit(this.op);
  final ContentOperation op;
}

/// The encoding-agnostic half of the rewrite: flatten, align, match, splice,
/// coalesce. A [RunCodec] supplies the encoding-specific half.
class TextRunRewriter {
  TextRunRewriter(this.codec);
  final RunCodec codec;

  /// Rewrites [run], replacing each boundary-aligned, non-overlapping
  /// occurrence of [find] with [replace]. Returns the operations to emit in
  /// the run's place (the originals untouched when nothing matches) and the
  /// number of replacements made.
  (List<ContentOperation>, int) rewrite(
      List<ContentOperation> run, String find, String replace) {
    if (codec.shouldSkip(run)) return (run, 0);
    final cells = codec.flatten(run);

    // decode glyph cells into a string, tracking where each glyph's text
    // begins so matches align to glyph boundaries: a composite code can map
    // to a multi-char string, a simple byte always to one char.
    final glyphCell = <int>[]; // glyph index -> cell index
    final startAt = <int>[]; // glyph index -> char offset in `decoded`
    final decoded = StringBuffer();
    for (var c = 0; c < cells.length; c++) {
      if (cells[c].glyph case final int g) {
        startAt.add(decoded.length);
        glyphCell.add(c);
        decoded.write(codec.glyphText(g));
      }
    }
    startAt.add(decoded.length);
    final text = decoded.toString();
    final boundaryAt = <int, int>{
      for (var k = 0; k < startAt.length; k++) startAt[k]: k
    };

    final matches = <(int, int)>[]; // [startGlyph, endGlyph)
    if (find.isNotEmpty) {
      var from = 0;
      while (true) {
        final at = text.indexOf(find, from);
        if (at < 0) break;
        final start = boundaryAt[at];
        final end = boundaryAt[at + find.length];
        if (start != null && end != null && end > start) {
          matches.add((start, end));
          from = at + find.length;
        } else {
          from = at + 1; // not on glyph boundaries - skip
        }
      }
    }
    if (matches.isEmpty) return (run, 0);

    final numGlyphs = glyphCell.length;
    final out = <Emit>[];
    var count = 0;
    var cell = 0;
    var m = 0;
    while (cell < cells.length) {
      if (m < matches.length && cell == glyphCell[matches[m].$1]) {
        final (_, endGlyph) = matches[m];
        final lastCell = glyphCell[endGlyph - 1];
        final oldWidth = _spanWidth(cells, cell, lastCell);
        codec.emitReplacement(out, replace, oldWidth, endGlyph < numGlyphs);
        count++;
        cell = lastCell + 1;
        m++;
      } else {
        codec.beforePassthrough(out);
        out.add(CellEmit(cells[cell]));
        cell++;
      }
    }
    codec.finish(out);
    return (codec.assemble(run, out), count);
  }

  /// The advance a matched span [first]..[last] (inclusive) covers, its
  /// interior kern numbers included.
  double _spanWidth(List<RunCell> cells, int first, int last) {
    var w = 0.0;
    for (var x = first; x <= last; x++) {
      w += cells[x].glyph != null
          ? codec.glyphWidth(cells[x].glyph!)
          : -cells[x].kern!;
    }
    return w;
  }
}

/// The encoding-specific half of [TextRunRewriter]: how a run flattens into
/// cells, what text/width each glyph carries, how a replacement (and its
/// compensating kern) is encoded, and how cells serialize back into show
/// operators.
abstract class RunCodec {
  /// True when the run can't be safely rewritten and must be left as-is
  /// (e.g. a /Type0 string with an odd byte length).
  bool shouldSkip(List<ContentOperation> run) => false;

  /// Flattens [run] into glyph/kern cells.
  List<RunCell> flatten(List<ContentOperation> run);

  /// The decoded text a glyph cell contributes, for match alignment.
  String glyphText(int glyph);

  /// The advance (thousandths of an em) of a glyph cell.
  double glyphWidth(int glyph);

  /// Appends the replacement for a matched span to [out]. [oldWidth] is the
  /// span's advance and [hasTrailing] whether text still follows on the line
  /// (so a compensating kern is needed). Owns both encoding and compensation.
  void emitReplacement(
      List<Emit> out, String replace, double oldWidth, bool hasTrailing);

  /// Hook before an unchanged (pass-through) cell is appended - lets a
  /// stateful codec restore its base font first.
  void beforePassthrough(List<Emit> out) {}

  /// Hook after the last cell - restores any lingering state.
  void finish(List<Emit> out) {}

  /// Coalesces [out] back into show operators.
  List<ContentOperation> assemble(List<ContentOperation> run, List<Emit> out);

  /// Shared coalescer: accumulates glyph cells into a show string (via
  /// [putGlyph]/[makeString]) and kern cells into a `TJ` number, with literal
  /// [OpEmit] ops flushing the pending show as a barrier. A single unchanged
  /// `Tj` whose result is one plain string keeps its `Tj` form (and hex flag).
  static List<ContentOperation> coalesce(
    List<ContentOperation> run,
    List<Emit> out, {
    required void Function(int glyph, List<int> buffer) putGlyph,
    required CosString Function(List<int> buffer) makeString,
  }) {
    final result = <ContentOperation>[];
    var items = <CosObject>[];
    final buffer = <int>[];
    var kern = 0.0;

    void flushString() {
      if (buffer.isNotEmpty) {
        items.add(makeString(buffer));
        buffer.clear();
      }
    }

    void flushKern() {
      if (kern.abs() >= 0.001) items.add(numberObject(kern));
      kern = 0;
    }

    void flushShow() {
      flushString();
      flushKern();
      if (items.isEmpty) return;
      if (items.length == 1 && items[0] is CosString) {
        result.add(ContentOperation('Tj', [items[0]]));
      } else {
        result.add(ContentOperation('TJ', [CosArray(items)]));
      }
      items = <CosObject>[];
    }

    for (final emit in out) {
      switch (emit) {
        case CellEmit(:final cell):
          if (cell.glyph case final int g) {
            flushKern();
            putGlyph(g, buffer);
          } else {
            flushString();
            kern += cell.kern!;
          }
        case OpEmit(:final op):
          flushShow();
          result.add(op);
      }
    }
    flushShow();

    if (run.length == 1 &&
        run[0].operator == 'Tj' &&
        result.length == 1 &&
        result[0].operator == 'Tj') {
      final produced = result[0].operands[0] as CosString;
      final original = run[0].operands[0];
      run[0].operands[0] = CosString(
        produced.bytes,
        isHex: original is CosString ? original.isHex : produced.isHex,
      );
      return run;
    }
    return result;
  }
}

/// A PDF number object for [value], an integer when it rounds to one, at
/// three-decimal precision (matches the content-stream serializer's rounding).
CosObject numberObject(double value) {
  final rounded = double.parse(value.toStringAsFixed(3));
  return rounded == rounded.roundToDouble()
      ? CosInteger(rounded.toInt())
      : CosReal(rounded);
}

/// Flattens a simple-font run: one cell per shown byte, plus a kern cell per
/// `TJ` number.
List<RunCell> simpleRunCells(List<ContentOperation> run) {
  final cells = <RunCell>[];
  for (final op in run) {
    if (op.operator == 'TJ' &&
        op.operands.isNotEmpty &&
        op.operands[0] is CosArray) {
      for (final item in (op.operands[0] as CosArray).items) {
        switch (item) {
          case CosString(:final bytes):
            for (final b in bytes) {
              cells.add((glyph: b, kern: null));
            }
          case CosInteger(:final value):
            cells.add((glyph: null, kern: value.toDouble()));
          case CosReal(:final value):
            cells.add((glyph: null, kern: value));
          default:
            break; // names, dicts, etc. carry no advance in a TJ array
        }
      }
    } else if (op.operands.isNotEmpty && op.operands[0] is CosString) {
      for (final b in (op.operands[0] as CosString).bytes) {
        cells.add((glyph: b, kern: null));
      }
    }
  }
  return cells;
}

/// Flattens a composite (/Type0) run: one cell per 2-byte code, plus a kern
/// cell per `TJ` number.
List<RunCell> type0RunCells(List<ContentOperation> run) {
  final cells = <RunCell>[];
  void addString(Uint8List bytes) {
    for (var i = 0; i + 1 < bytes.length; i += 2) {
      cells.add((glyph: (bytes[i] << 8) | bytes[i + 1], kern: null));
    }
  }

  for (final op in run) {
    if (op.operator == 'TJ' &&
        op.operands.isNotEmpty &&
        op.operands[0] is CosArray) {
      for (final item in (op.operands[0] as CosArray).items) {
        switch (item) {
          case CosString(:final bytes):
            addString(bytes);
          case CosInteger(:final value):
            cells.add((glyph: null, kern: value.toDouble()));
          case CosReal(:final value):
            cells.add((glyph: null, kern: value));
          default:
            break;
        }
      }
    } else if (op.operands.isNotEmpty && op.operands[0] is CosString) {
      addString((op.operands[0] as CosString).bytes);
    }
  }
  return cells;
}

/// True when any show string in a composite run has an odd byte length - a
/// 2-byte code split across strings would misalign, so the run is left alone.
bool type0RunHasOddString(List<ContentOperation> run) {
  for (final op in run) {
    if (op.operator == 'TJ' &&
        op.operands.isNotEmpty &&
        op.operands[0] is CosArray) {
      for (final item in (op.operands[0] as CosArray).items) {
        if (item is CosString && item.bytes.length.isOdd) return true;
      }
    } else if (op.operands.isNotEmpty && op.operands[0] is CosString) {
      if ((op.operands[0] as CosString).bytes.length.isOdd) return true;
    }
  }
  return false;
}
