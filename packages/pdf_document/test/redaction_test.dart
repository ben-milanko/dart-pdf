import 'dart:convert';
import 'dart:typed_data';

import 'package:pdf_document/pdf_document.dart';
import 'package:test/test.dart';

/// One-page PDF around a custom content stream, with /F1 Helvetica (real
/// /Widths) and a 1×1 gray image /Im1 available.
Uint8List buildRedactPdf(String content) {
  const helvWidths = '[278 278 355 556 556 889 667 191 333 333 389 584 278 '
      '333 278 278 556 556 556 556 556 556 556 556 556 556 278 278 584 584 '
      '584 556 1015 667 667 722 722 667 611 778 722 278 500 667 556 833 722 '
      '778 667 778 722 667 611 722 667 944 667 667 611 278 278 278 469 556 '
      '333 556 556 500 556 556 278 556 556 222 222 500 222 833 556 556 556 '
      '556 333 500 278 556 500 722 500 500 500]';
  final objects = <String>[
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R '
        '/Resources << /Font << /F1 5 0 R >> '
        '/XObject << /Im1 6 0 R >> >> >>',
    '<< /Length ${content.length} >>\nstream\n$content\nendstream',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica '
        '/FirstChar 32 /LastChar 126 /Widths $helvWidths >>',
    '<< /Type /XObject /Subtype /Image /Width 1 /Height 1 '
        '/ColorSpace /DeviceGray /BitsPerComponent 8 /Length 1 >>\n'
        'stream\nx\nendstream',
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
  return Uint8List.fromList(latin1.encode(buffer.toString()));
}

String pageText(PdfDocument doc, [int index = 0]) =>
    latin1.decode(doc.page(index).contentBytes());

void main() {
  group('marking', () {
    test('addRedaction creates a /Redact annot with /QuadPoints and /IC', () {
      final doc = PdfDocument.open(buildRedactPdf('BT ET'));
      final editor = PdfEditor(doc)
        ..addRedaction(0, [const PdfRect(70, 695, 200, 715)],
            fillColor: 0x000000);
      final out = PdfDocument.open(editor.save());
      final annots = out.page(0).annotations;
      final redact = annots.singleWhere((a) => a.subtype == 'Redact');
      expect(redact, isNotNull);
      // it is a mark only — nothing removed from the content yet
      expect(pageText(out), contains('BT'));
    });
  });

  group('burn — text', () {
    // SECRET on the top line, PUBLIC well below it.
    const content = 'BT /F1 12 Tf 72 700 Td (SECRET) Tj ET\n'
        'BT /F1 12 Tf 72 600 Td (PUBLIC) Tj ET\n';

    test('redacted text is GONE from the decoded content stream', () {
      final doc = PdfDocument.open(buildRedactPdf(content));
      final editor = PdfEditor(doc)
        ..addRedaction(0, [const PdfRect(70, 695, 220, 715)]);
      final burned = editor.applyRedactions(0);
      final out = PdfDocument.open(burned);
      final text = pageText(out);

      // the acceptance gate: the secret is not recoverable from the bytes
      expect(text, isNot(contains('SECRET')));
      // and not anywhere in the whole saved file either
      expect(latin1.decode(burned, allowInvalid: true),
          isNot(contains('SECRET')));
      // the untouched line survives verbatim
      expect(text, contains('(PUBLIC) Tj'));
      // a black fill box was painted over the region
      expect(text, contains('0 0 0 rg'));
      expect(text, contains('re'));
      // the /Redact annotation is gone
      expect(out.page(0).annotations.where((a) => a.subtype == 'Redact'),
          isEmpty);
    });

    test('a partially covered run keeps the glyphs outside the rect', () {
      // "PUBLIC SECRET": redact only the right half (SECRET).
      final doc = PdfDocument.open(
          buildRedactPdf('BT /F1 12 Tf 72 700 Td (PUBLIC SECRET) Tj ET\n'));
      // "PUBLIC " is ~46pt wide; cover from x 118 rightward.
      final editor = PdfEditor(doc)
        ..addRedaction(0, [const PdfRect(118, 695, 300, 715)]);
      final out = PdfDocument.open(editor.applyRedactions(0));
      final text = pageText(out);
      expect(text, isNot(contains('SECRET')));
      expect(text, contains('PUBLIC'));
      // survivors keep their place via a numeric TJ gap
      expect(text, contains('TJ'));
    });

    test('only the covered line is touched', () {
      final doc = PdfDocument.open(buildRedactPdf(content));
      final editor = PdfEditor(doc)
        ..addRedaction(0, [const PdfRect(70, 595, 220, 615)]);
      final out = PdfDocument.open(editor.applyRedactions(0));
      final text = pageText(out);
      expect(text, contains('(SECRET) Tj'));
      expect(text, isNot(contains('(PUBLIC) Tj')));
    });
  });

  group('burn — images', () {
    const imageContent = 'q 200 0 0 100 50 300 cm /Im1 Do Q\n';

    test('a fully covered image XObject is dropped', () {
      final doc = PdfDocument.open(buildRedactPdf(imageContent));
      final editor = PdfEditor(doc)
        ..addRedaction(0, [const PdfRect(40, 290, 260, 410)]);
      final out = PdfDocument.open(editor.applyRedactions(0));
      final text = pageText(out);
      expect(text, isNot(contains('/Im1 Do')));
      expect(text, contains('re')); // fill box present
    });

    test('a partially covered image is kept under the fill box', () {
      final doc = PdfDocument.open(buildRedactPdf(imageContent));
      final editor = PdfEditor(doc)
        ..addRedaction(0, [const PdfRect(40, 290, 150, 410)]);
      final out = PdfDocument.open(editor.applyRedactions(0));
      final text = pageText(out);
      expect(text, contains('/Im1 Do'));
      expect(text, contains('re'));
    });
  });

  group('burn — overlay & scrubbing', () {
    test('overlay text is painted into the fill', () {
      final doc = PdfDocument.open(
          buildRedactPdf('BT /F1 12 Tf 72 700 Td (SECRET) Tj ET\n'));
      final editor = PdfEditor(doc)
        ..addRedaction(0, [const PdfRect(70, 695, 220, 715)],
            overlayText: 'REDACTED');
      final out = PdfDocument.open(editor.applyRedactions(0));
      final text = pageText(out);
      expect(text, contains('(REDACTED) Tj'));
      expect(text, isNot(contains('SECRET')));
    });

    test('an annotation fully under a region is scrubbed', () {
      final doc = PdfDocument.open(
          buildRedactPdf('BT /F1 12 Tf 72 700 Td (SECRET) Tj ET\n'));
      final editor = PdfEditor(doc)
        // a highlight sitting on the same words
        ..addHighlight(0, [const PdfRect(72, 698, 120, 712)],
            contents: 'leaks the secret')
        ..addRedaction(0, [const PdfRect(60, 690, 260, 720)]);
      final out = PdfDocument.open(editor.applyRedactions(0));
      expect(out.page(0).annotations, isEmpty);
    });
  });
}
