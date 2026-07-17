import 'dart:convert';

import 'package:pdf_document/pdf_document.dart';
import 'package:test/test.dart';

/// Decodes a [ContentWriter]'s buffered operators back to text.
String _content(ContentWriter w) => latin1.decode(w.takeBytes());

/// Accumulates the `Td` deltas an appearance emits into absolute baseline
/// positions, one per shown line.
List<(double x, double y)> _baselines(String content) {
  final out = <(double, double)>[];
  var x = 0.0, y = 0.0;
  for (final m in RegExp(r'(-?[\d.]+) (-?[\d.]+) Td').allMatches(content)) {
    x += double.parse(m.group(1)!);
    y += double.parse(m.group(2)!);
    out.add((x, y));
  }
  return out;
}

/// The literal strings shown by `(...) Tj` operators, in order.
List<String> _shown(String content) => [
      for (final m in RegExp(r'\(([^)]*)\) Tj').allMatches(content))
        m.group(1)!,
    ];

void main() {
  group('pdfWrapText', () {
    // A width of one unit per character makes the arithmetic obvious.
    double byChars(String s) => s.length.toDouble();

    test('breaks greedily at word boundaries', () {
      expect(pdfWrapText('aa bb cc', 5, byChars), ['aa bb', 'cc']);
    });

    test('keeps each paragraph on its own line run', () {
      expect(pdfWrapText('a\nb', 100, byChars), ['a', 'b']);
      // An empty paragraph contributes an empty line (a blank row).
      expect(pdfWrapText('a\n\nb', 100, byChars), ['a', '', 'b']);
    });

    test('a single overlong word overflows onto its own line', () {
      expect(pdfWrapText('aaaaaaa bb', 5, byChars), ['aaaaaaa', 'bb']);
    });

    test('tolerance keeps a line that rounds a hair over the width', () {
      // width == maxWidth + tolerance/2 stays on the line; without the
      // tolerance the strict `>` test would wrap it.
      double measure(String s) => 5 + 5e-7;
      expect(pdfWrapText('a b', 5, measure, tolerance: 1e-6), ['a b']);
      expect(pdfWrapText('a b', 5, measure), ['a', 'b']);
    });
  });

  group('pdfTextBoxLineX (quadding)', () {
    const box = PdfRect(0, 0, 100, 50);

    test('left sits at the left padding', () {
      expect(pdfTextBoxLineX(PdfTextAlign.left, box, 20, 3), 3);
    });

    test('centre places the line symmetrically, ignoring padding', () {
      expect(pdfTextBoxLineX(PdfTextAlign.center, box, 20, 3), 40);
    });

    test('right hugs the right padding', () {
      expect(pdfTextBoxLineX(PdfTextAlign.right, box, 20, 3), 77);
    });

    test('clamp pins an overflowing line to the left padding', () {
      // Unclamped, a 200-wide line would start off the left edge.
      expect(pdfTextBoxLineX(PdfTextAlign.center, box, 200, 3), -50);
      expect(
          pdfTextBoxLineX(PdfTextAlign.center, box, 200, 3, clamp: true), 3);
      expect(
          pdfTextBoxLineX(PdfTextAlign.right, box, 200, 3, clamp: true), 3);
    });
  });

  group('writePdfTextBox', () {
    const font = PdfStandardFont.helvetica;
    const box = PdfRect(0, 0, 100, 50);

    test('clips, opens a text object, and selects the font', () {
      final w = ContentWriter();
      writePdfTextBox(w, box, ['Hi'],
          font: font, fontSize: 10, align: PdfTextAlign.left, padding: 3,
          lineHeight: 12);
      final content = _content(w);
      expect(content, contains('0 0 100 50 re'));
      expect(content, contains('W')); // clip
      expect(content, contains('BT'));
      expect(content, contains('/Helv 10 Tf'));
      expect(content, contains('(Hi) Tj'));
      expect(content, contains('ET'));
    });

    test('centre quadding centres the line horizontally', () {
      final w = ContentWriter();
      writePdfTextBox(w, box, ['Hi'],
          font: font, fontSize: 10, align: PdfTextAlign.center, padding: 3,
          lineHeight: 12);
      final width = font.measure('Hi', 10);
      final (x, _) = _baselines(_content(w)).single;
      expect(x, closeTo((100 - width) / 2, 1e-6));
    });

    test('top anchoring puts the first baseline one ascent below the top', () {
      final w = ContentWriter();
      writePdfTextBox(w, box, ['a', 'b'],
          font: font, fontSize: 10, align: PdfTextAlign.left, padding: 3,
          lineHeight: 12);
      final lines = _baselines(_content(w));
      final ascent = 10 * font.ascent / 1000;
      expect(lines[0].$2, closeTo(50 - 3 - ascent, 1e-6));
      // the second line drops by exactly one line height
      expect(lines[1].$2, closeTo(lines[0].$2 - 12, 1e-6));
    });

    test('centreLine centres a single line by its ascent', () {
      const shortBox = PdfRect(0, 0, 100, 20);
      final w = ContentWriter();
      writePdfTextBox(w, shortBox, ['x'],
          font: font, fontSize: 10, align: PdfTextAlign.left, padding: 3,
          lineHeight: 12, vAlign: PdfTextBoxVAlign.centerLine);
      final ascent = 10 * font.ascent / 1000;
      expect(_baselines(_content(w)).single.$2,
          closeTo((20 - ascent) / 2, 1e-6));
    });

    test('centreBlock centres the whole block vertically', () {
      final w = ContentWriter();
      writePdfTextBox(w, box, ['a', 'b'],
          font: font, fontSize: 10, align: PdfTextAlign.left, padding: 0,
          lineHeight: 12, vAlign: PdfTextBoxVAlign.centerBlock);
      final ascent = 10 * font.ascent / 1000;
      final blockTop = (50 + 2 * 12) / 2;
      final lines = _baselines(_content(w));
      expect(lines[0].$2, closeTo(blockTop - ascent, 1e-6));
      expect(lines[1].$2, closeTo(blockTop - ascent - 12, 1e-6));
    });

    test('leading emits a TL only when asked', () {
      final withLeading = ContentWriter();
      writePdfTextBox(withLeading, box, ['x'],
          font: font, fontSize: 12, align: PdfTextAlign.left, padding: 3,
          lineHeight: 24, leading: true);
      expect(_content(withLeading), contains('24 TL'));

      final without = ContentWriter();
      writePdfTextBox(without, box, ['x'],
          font: font, fontSize: 12, align: PdfTextAlign.left, padding: 3,
          lineHeight: 24);
      expect(_content(without), isNot(contains('TL')));
    });

    test('writeColor and emitLine hooks control paint and encoding', () {
      final w = ContentWriter();
      writePdfTextBox(w, box, ['Hi'],
          font: font, fontSize: 10, align: PdfTextAlign.left, padding: 3,
          lineHeight: 12,
          writeColor: (cw) => cw.raw('1 0 0 rg'),
          emitLine: (cw, line) => cw.showText('[$line]'));
      final content = _content(w);
      expect(content, contains('1 0 0 rg'));
      expect(_shown(content), ['[Hi]']);
    });

    test('underlineColor draws a filled rule under each non-empty line', () {
      final w = ContentWriter();
      writePdfTextBox(w, box, ['Hi', ''],
          font: font, fontSize: 10, align: PdfTextAlign.left, padding: 3,
          lineHeight: 12, underlineColor: 0x000000);
      final content = _content(w);
      final afterText = content.substring(content.indexOf('ET'));
      // exactly one filled rule, for the single non-empty line, and it is
      // drawn after the text object closes
      expect('\nf\n'.allMatches(afterText).length, 1);
      expect(afterText, contains(' re\n'));
    });
  });

  group('writePdfCounterRotation', () {
    test('emits the expected cm matrix per rotation', () {
      String matrix(int rotation) {
        final w = ContentWriter();
        writePdfCounterRotation(w, 10, 20, rotation);
        return _content(w).trim();
      }

      expect(matrix(0), isEmpty);
      expect(matrix(90), '0 1 -1 0 30 10 cm');
      expect(matrix(180), '-1 0 0 -1 20 40 cm');
      expect(matrix(270), '0 -1 1 0 -10 30 cm');
    });
  });
}
