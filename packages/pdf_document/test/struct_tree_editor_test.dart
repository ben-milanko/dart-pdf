import 'dart:typed_data';

import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:test/test.dart';

void main() {
  group('writeStructTree (manual authoring)', () {
    test('authors a tree the read path can walk', () {
      final doc = PdfDocument.open(buildClassicPdf());
      final editor = PdfEditor(doc);
      // The classic fixture shows one line of text; tag it as a heading.
      editor.writeStructTree([
        PdfStructSpec('Document', children: [
          PdfStructSpec('H1', pageIndex: 0, mcids: [0], title: 'greeting'),
        ]),
      ], lang: 'en-US');
      // (No content tagging here — this exercises the tree writer + catalog.)

      final out = PdfDocument.open(editor.save());
      expect(pdfIsMarkedTagged(out), isTrue);
      final tree = PdfStructTree.of(out)!;
      final roots = tree.children;
      expect(roots.single.structureType, 'Document');
      expect(roots.single.children.single.structureType, 'H1');
      expect(roots.single.children.single.markedContent.single.mcid, 0);
      expect(out.cos.resolve(out.catalog['Lang']), isA<CosString>());

      // ViewerPreferences DisplayDocTitle is set for PDF/UA.
      final vp = out.cos.resolve(out.catalog['ViewerPreferences']);
      expect(vp, isA<CosDictionary>());
      expect((out.cos.resolve((vp as CosDictionary)['DisplayDocTitle'])
              as CosBoolean)
          .value, isTrue);
    });

    test('writes a parent tree resolvable from MCID', () {
      final doc = PdfDocument.open(buildClassicPdf());
      final editor = PdfEditor(doc);
      editor.writeStructTree([
        PdfStructSpec('Document', children: [
          PdfStructSpec('P', pageIndex: 0, mcids: [0]),
        ]),
      ]);
      final out = PdfDocument.open(editor.save());
      final pt = PdfStructParentTree.of(out)!;
      final key = pageStructParentsKey(out.page(0))!;
      expect(pt.elementForMcid(key, 0)!.structureType, 'P');
    });
  });

  group('autoTag (heuristic)', () {
    test('tags an untagged single-line PDF and reads back', () {
      final doc = PdfDocument.open(buildClassicPdf());
      final editor = PdfEditor(doc);
      final n = editor.autoTag(title: 'Hello', lang: 'en-US');
      expect(n, greaterThanOrEqualTo(2)); // Document + at least one block

      final bytes = editor.save();
      final out = PdfDocument.open(bytes);
      expect(pdfIsMarkedTagged(out), isTrue);

      final tree = PdfStructTree.of(out)!;
      expect(tree.children.single.structureType, 'Document');
      // The tagged content is reachable and carries the page text.
      final logical = tree.children.single
          .markedContentInReadingOrder()
          .map((m) => m.mcid)
          .toList();
      expect(logical, isNotEmpty);

      // The page content now carries marked content with /MCID.
      final content = out.page(0).contentBytes();
      final text = String.fromCharCodes(content);
      expect(text, contains('BDC'));
      expect(text, contains('/MCID'));
      expect(text, contains('Hello, world!'));
    });

    test('groups multi-size text into headings and paragraphs', () {
      final doc = PdfDocument.open(_buildArticlePdf());
      final editor = PdfEditor(doc);
      editor.autoTag();
      final out = PdfDocument.open(editor.save());
      final tree = PdfStructTree.of(out)!;
      final types =
          tree.elementsInReadingOrder().map((e) => e.structureType).toList();
      expect(types, contains('Document'));
      // The 24pt title line should become a heading; the 11pt lines stay P.
      expect(types, contains('H1'));
      expect(types, contains('P'));
    });

    test('marks non-text painting as artifacts', () {
      final doc = PdfDocument.open(_buildTextAndRectPdf());
      final editor = PdfEditor(doc);
      editor.autoTag();
      final out = PdfDocument.open(editor.save());
      final content = String.fromCharCodes(out.page(0).contentBytes());
      expect(content, contains('/Artifact BMC'));
      // The rectangle fill is wrapped, the text tagged.
      expect(content, contains('/MCID'));
    });
  });
}

/// A one-page PDF: a 24pt title line, then two 11pt body lines.
Uint8List _buildArticlePdf() {
  const content = 'BT /F1 24 Tf 72 720 Td (Annual Report) Tj ET\n'
      'BT /F1 11 Tf 72 690 Td (The first body line of the document.) Tj ET\n'
      'BT /F1 11 Tf 72 676 Td (The second body line follows it.) Tj ET';
  return _onePage(content);
}

/// A one-page PDF: one text line plus a filled rectangle.
Uint8List _buildTextAndRectPdf() {
  const content = 'BT /F1 12 Tf 72 720 Td (Some text here.) Tj ET\n'
      '0 0 1 rg 72 600 200 60 re f';
  return _onePage(content);
}

Uint8List _onePage(String content) {
  final objects = <String>[
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R '
        '/Resources << /Font << /F1 5 0 R >> >> >>',
    '<< /Length ${content.length} >>\nstream\n$content\nendstream',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
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
  return Uint8List.fromList(buffer.toString().codeUnits);
}
