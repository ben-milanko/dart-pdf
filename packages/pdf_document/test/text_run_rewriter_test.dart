import 'dart:typed_data';

import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/src/content_run_rewriter.dart';
import 'package:test/test.dart';

/// A minimal one-byte-per-glyph codec built on a fixed per-character width
/// table - enough to exercise the engine's match / splice / kern-compensation
/// / coalescing math with no document, font, or editor.
class _FakeCodec extends RunCodec {
  _FakeCodec(this.widths, {this.brackets = false});

  /// char code -> advance (thousandths of an em); absent chars are 500.
  final Map<int, double> widths;

  /// When set, each replacement is wrapped in `[` ... `]` marker operators, so
  /// the barrier (op-flush) path through the coalescer is exercised too.
  final bool brackets;

  @override
  List<RunCell> flatten(List<ContentOperation> run) => simpleRunCells(run);

  @override
  String glyphText(int glyph) => String.fromCharCode(glyph);

  @override
  double glyphWidth(int glyph) => widths[glyph] ?? 500;

  @override
  void emitReplacement(
      List<Emit> out, String replace, double oldWidth, bool hasTrailing) {
    if (brackets) out.add(OpEmit(ContentOperation('[', const [])));
    var newWidth = 0.0;
    for (final unit in replace.codeUnits) {
      out.add(CellEmit((glyph: unit, kern: null)));
      newWidth += glyphWidth(unit);
    }
    if (brackets) out.add(OpEmit(ContentOperation(']', const [])));
    if (hasTrailing && (newWidth - oldWidth).abs() >= 0.001) {
      out.add(CellEmit((glyph: null, kern: newWidth - oldWidth)));
    }
  }

  @override
  List<ContentOperation> assemble(
          List<ContentOperation> run, List<Emit> out) =>
      RunCodec.coalesce(run, out,
          putGlyph: (g, buffer) => buffer.add(g),
          makeString: (buffer) => CosString(Uint8List.fromList(buffer)));
}

ContentOperation _tj(String s) =>
    ContentOperation('Tj', [CosString(Uint8List.fromList(s.codeUnits))]);

ContentOperation _tjArray(List<Object> parts) => ContentOperation('TJ', [
      CosArray([
        for (final p in parts)
          if (p is String)
            CosString(Uint8List.fromList(p.codeUnits))
          else
            CosInteger((p as num).toInt()),
      ])
    ]);

/// The show strings of [ops], concatenated.
String _text(List<ContentOperation> ops) {
  final buf = StringBuffer();
  for (final op in ops) {
    if (op.operands.isEmpty) continue;
    final a = op.operands[0];
    if (a is CosString) {
      buf.write(String.fromCharCodes(a.bytes));
    } else if (a is CosArray) {
      for (final item in a.items) {
        if (item is CosString) buf.write(String.fromCharCodes(item.bytes));
      }
    }
  }
  return buf.toString();
}

/// The kern numbers inside every TJ array of [ops].
List<double> _kerns(List<ContentOperation> ops) {
  final out = <double>[];
  for (final op in ops) {
    if (op.operator == 'TJ' && op.operands[0] is CosArray) {
      for (final item in (op.operands[0] as CosArray).items) {
        if (item is CosInteger) out.add(item.value.toDouble());
        if (item is CosReal) out.add(item.value);
      }
    }
  }
  return out;
}

void main() {
  group('match alignment and counting', () {
    test('replaces every non-overlapping occurrence', () {
      final codec = _FakeCodec(const {});
      final (ops, n) =
          TextRunRewriter(codec).rewrite([_tj('a.a.a')], 'a', 'b');
      expect(n, 3);
      expect(_text(ops), 'b.b.b');
    });

    test('a non-matching find leaves the run untouched, count 0', () {
      final run = [_tj('hello')];
      final (ops, n) = TextRunRewriter(_FakeCodec(const {})).rewrite(
        run,
        'zzz',
        'x',
      );
      expect(n, 0);
      expect(identical(ops, run), isTrue, reason: 'same list returned');
    });

    test('matches span consecutive strings and consume interior kerns', () {
      // "split" is spread across two TJ strings with a kern between them.
      final (ops, n) = TextRunRewriter(_FakeCodec(const {}))
          .rewrite([_tjArray(['spli', -20, 't run'])], 'split', 'joined');
      expect(n, 1);
      expect(_text(ops), 'joined run');
      // the interior -20 kern is consumed by the match, not re-emitted before
      // the following " run".
      expect(_kerns(ops), isNot(contains(-20)));
    });
  });

  group('kern compensation', () {
    test('inserts newWidth - oldWidth when text follows the match', () {
      // A=300, B=100. "AAA"(900) -> "B"(100) shrinks by 800 with " x" after.
      final codec = _FakeCodec({0x41: 300, 0x42: 100, 0x78: 400});
      final (ops, _) =
          TextRunRewriter(codec).rewrite([_tj('AAA x')], 'AAA', 'B');
      expect(_kerns(ops), [100 - 900]);
      expect(_text(ops), 'B x');
    });

    test('omits the compensation when the match ends the line', () {
      final codec = _FakeCodec({0x41: 300, 0x42: 100});
      final (ops, _) =
          TextRunRewriter(codec).rewrite([_tj('AAA')], 'AAA', 'B');
      expect(_kerns(ops), isEmpty, reason: 'nothing follows, no compensation');
      expect(_text(ops), 'B');
    });

    test('omits the compensation when the width is unchanged', () {
      final codec = _FakeCodec({0x41: 300, 0x42: 300});
      final (ops, _) =
          TextRunRewriter(codec).rewrite([_tj('A x')], 'A', 'B');
      expect(_kerns(ops), isEmpty);
    });
  });

  group('coalescing', () {
    test('a single unchanged Tj stays a Tj', () {
      final (ops, _) =
          TextRunRewriter(_FakeCodec(const {})).rewrite([_tj('foo')], 'foo', 'bar');
      expect(ops, hasLength(1));
      expect(ops.single.operator, 'Tj');
      expect(_text(ops), 'bar');
    });

    test('merges the compensation kern into the following TJ array', () {
      // A=667. "AAA"->"AA" over `[(AAA) (BBB)]` yields `[(AA) -667 (BBB)]`.
      final codec = _FakeCodec({0x41: 667, 0x42: 667});
      final (ops, _) = TextRunRewriter(codec)
          .rewrite([_tjArray(['AAA', 'BBB'])], 'AAA', 'AA');
      expect(ops, hasLength(1));
      expect(ops.single.operator, 'TJ');
      expect(_text(ops), 'AABBB');
      expect(_kerns(ops), [-667]);
    });

    test('adjacent kern cells are summed into one number', () {
      // Two matches back to back each leave a kern; between them nothing else,
      // so their compensations coalesce with the surrounding text correctly.
      final codec = _FakeCodec({0x41: 300, 0x42: 100, 0x2e: 200});
      final (ops, n) =
          TextRunRewriter(codec).rewrite([_tj('A.A.')], 'A', 'B');
      expect(n, 2);
      expect(_text(ops), 'B.B.');
      // each 'A'(300)->'B'(100) leaves -200; both are followed by more text.
      expect(_kerns(ops), [-200, -200]);
    });
  });

  group('barrier operators (styled / fallback shape)', () {
    test('op emits flush pending cells and pass through as barriers', () {
      final codec = _FakeCodec({0x41: 300, 0x42: 100}, brackets: true);
      final (ops, n) =
          TextRunRewriter(codec).rewrite([_tj('xAy')], 'A', 'B');
      expect(n, 1);
      // (x) [ (B) ] then the following (y) with the compensation kern.
      expect(ops.map((o) => o.operator).toList(),
          ['Tj', '[', 'Tj', ']', 'TJ']);
      expect(_text(ops), 'xBy');
      expect(_kerns(ops), [100 - 300]);
    });
  });
}
