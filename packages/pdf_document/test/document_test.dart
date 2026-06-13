import 'dart:typed_data';

import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:test/test.dart';

void main() {
  group('classic one-page document', () {
    late PdfDocument doc;

    setUp(() => doc = PdfDocument.open(buildClassicPdf()));

    test('page count', () {
      expect(doc.pageCount, 1);
    });

    test('page attributes', () {
      final page = doc.page(0);
      expect(page.mediaBox, const PdfRect(0, 0, 612, 792));
      expect(page.cropBox, page.mediaBox);
      expect(page.rotation, 0);
      expect(page.resources.containsKey('Font'), isTrue);
    });

    test('content bytes decode', () {
      final text = String.fromCharCodes(doc.page(0).contentBytes());
      expect(text, contains('Hello, world!'));
    });

    test('out-of-range page throws', () {
      expect(() => doc.page(1), throwsRangeError);
      expect(() => doc.page(-1), throwsRangeError);
    });
  });

  group('xref-stream document', () {
    late PdfDocument doc;

    setUp(() => doc = PdfDocument.open(buildXrefStreamPdf()));

    test('page tree resolves out of the object stream', () {
      expect(doc.pageCount, 1);
      expect(doc.page(0).mediaBox, const PdfRect(0, 0, 612, 792));
    });
  });

  group('page lookup with intermediate /Count', () {
    /// Root /Pages with two kids: an inner /Pages node (two leaves, with
    /// [innerCount] declared and [innerKids] as its children) and one
    /// direct leaf with /Rotate 180. The real page order is 4, 5, 6.
    Uint8List buildTree({required int innerCount, String? innerKids}) {
      final objects = <String>[
        '<< /Type /Catalog /Pages 2 0 R >>',
        '<< /Type /Pages /Kids [3 0 R 6 0 R] /Count 3 '
            '/MediaBox [0 0 612 792] >>',
        '<< /Type /Pages /Parent 2 0 R /Kids [${innerKids ?? '4 0 R 5 0 R'}]'
            ' /Count $innerCount >>',
        '<< /Type /Page /Parent 3 0 R >>',
        '<< /Type /Page /Parent 3 0 R /Rotate 90 >>',
        '<< /Type /Page /Parent 2 0 R /Rotate 180 >>',
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
      return ascii(buffer.toString());
    }

    test('a correct /Count skips the subtree without resolving its kids', () {
      // the inner node's kids are dangling references, so reaching page 2
      // can only succeed by trusting /Count and skipping the subtree
      final doc = PdfDocument.open(
          buildTree(innerCount: 2, innerKids: '40 0 R 50 0 R'));
      expect(doc.page(2).rotation, 180);
    });

    test('a lying /Count falls back to walking every leaf', () {
      final doc = PdfDocument.open(buildTree(innerCount: 1));
      expect(doc.page(2).rotation, 180);
      expect(() => doc.page(3), throwsRangeError);
    });

    test('normal lookup still finds pages inside the subtree', () {
      final doc = PdfDocument.open(buildTree(innerCount: 2));
      expect(doc.page(0).rotation, 0);
      expect(doc.page(1).rotation, 90);
      expect(doc.page(2).rotation, 180);
    });
  });

  group('corrupt page trees and contents (pdf.js corpus classes)', () {
    Uint8List build(List<String> objects) {
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
      return ascii(buffer.toString());
    }

    test('pageCount reports reachable pages, not a lying /Count', () {
      // pdf.js Pages-tree-refs: /Count 2, but one "subtree" is an
      // interior-node cycle that never reaches a leaf. pageCount must
      // never exceed what page() can actually return.
      final doc = PdfDocument.open(build([
        '<< /Type /Catalog /Pages 2 0 R >>',
        '<< /Type /Pages /Kids [5 0 R 3 0 R] /Count 2 '
            '/MediaBox [0 0 100 100] >>',
        '<< /Type /Pages /Kids [4 0 R] /Count 1 >>',
        '<< /Type /Pages /Kids [3 0 R] /Count 1 >>', // cycle: 3 -> 4 -> 3
        '<< /Type /Page /Parent 2 0 R >>',
      ]));
      expect(doc.pageCount, 1);
      expect(doc.page(0).dict.typeName, 'Page');
    });

    test('a /Count that is a reference to a stream still counts pages', () {
      // poppler-91414: /Count 4 0 R where object 4 is a (self-referencing)
      // stream — counting must walk the tree instead of trusting it
      final doc = PdfDocument.open(build([
        '<< /Type /Catalog /Pages 2 0 R >>',
        '<< /Type /Pages /Kids [3 0 R] /Count 4 0 R '
            '/MediaBox [0 0 100 100] >>',
        '<< /Type /Page /Parent 2 0 R >>',
        '<< /Length 4 0 R >>\nstream\n2\nendstream',
      ]));
      expect(doc.pageCount, 1);
    });

    test('an undecodable content stream renders the page as empty', () {
      // PDFBOX-4352: junk behind a /FlateDecode filter must not fail the
      // page — and the rest of a /Contents array still draws
      const good = 'BT (still here) Tj ET';
      final doc = PdfDocument.open(build([
        '<< /Type /Catalog /Pages 2 0 R >>',
        '<< /Type /Pages /Kids [3 0 R] /Count 1 '
            '/MediaBox [0 0 100 100] >>',
        '<< /Type /Page /Parent 2 0 R /Contents [4 0 R 5 0 R] >>',
        '<< /Length 9 /Filter /FlateDecode >>\nstream\nnot-flate\nendstream',
        '<< /Length ${good.length} >>\nstream\n$good\nendstream',
      ]));
      final text = String.fromCharCodes(doc.page(0).contentBytes());
      expect(text, contains('still here'));
      expect(text, isNot(contains('not-flate')));
    });

    test('invalid page boxes fall back to visible page geometry', () {
      // pdf.js boundingBox_invalid: zero-area boxes must not collapse the
      // rendered page to a 1x1 raster.
      final doc = PdfDocument.open(build([
        '<< /Type /Catalog /Pages 2 0 R >>',
        '<< /Type /Pages /Kids [3 0 R 4 0 R 5 0 R] /Count 3 >>',
        '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 0 0] >>',
        '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 800 600] '
            '/CropBox [0 0 0 0] >>',
        '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 600 800] '
            '/CropBox [600 800 1000 1000] >>',
      ]));

      expect(doc.page(0).mediaBox, const PdfRect(0, 0, 612, 792));
      expect(doc.page(0).cropBox, const PdfRect(0, 0, 612, 792));
      expect(doc.page(1).cropBox, const PdfRect(0, 0, 800, 600));
      expect(doc.page(2).cropBox, const PdfRect(0, 0, 600, 800));
    });
  });
}
