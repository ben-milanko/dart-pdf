// pdf.js test corpus — pure-Dart pass.
//
// The suite lives in test_corpora/pdfjs (checked in): ~170 real-world
// edge-case PDFs curated from mozilla/pdf.js test/pdfs (see the README
// there for provenance and per-file notes). Where the Ghent suite pins
// print-production features, this one pins *robustness*: fuzzed files,
// lying xrefs and /Counts, junk in content streams, odd fonts and
// filters, encryption corner cases.
//
// Expectations are pinned per file:
//  - files in [unopenable] must throw a controlled CosParseException
//    (never a StackOverflowError, RangeError, or hang);
//  - files in [requiresPassword] must throw CosPasswordException when
//    opened without one;
//  - everything else must open, report a page count, and interpret every
//    page without throwing — painting at least one op unless the file is
//    listed in [mayBeBlank] (legitimately empty pages, or known gaps,
//    each annotated below).
import 'dart:io';

import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';
import 'package:test/test.dart';

/// User passwords, from the pdf.js manifest and unit tests.
const passwords = {
  'issue6010_1.pdf': 'abc',
  'issue6010_2.pdf': 'æøå',
  'issue15893_reduced.pdf': 'test',
  'bug1782186.pdf': 'Hello',
  'issue3371.pdf': 'ELXRTQWS',
  'encrypted-attachment.pdf': '000000',
};

/// Password-protected without a known-empty password — pdf.js shows the
/// password dialog for these too.
const requiresPassword = {'print_protection.pdf'};

/// Fuzzed beyond recovery (no catalog / no page tree reachable at all).
/// The pin here is the *failure mode*: a controlled CosParseException —
/// possibly deferred to the lazy pageCount — or zero reachable pages.
/// Never a StackOverflowError, RangeError, or hang.
const unopenable = {
  'GHOSTSCRIPT-698804-1-fuzzed.pdf',
  'REDHAT-1531897-0.pdf',
  'poppler-395-0-fuzzed.pdf',
  'poppler-742-0-fuzzed.pdf',
  'poppler-85140-0.pdf',
  'poppler-937-0-fuzzed.pdf',
};

/// Pages that legitimately paint nothing.
const mayBeBlank = {
  'PDFBOX-3148-2-fuzzed.pdf', // fuzzed content
  'PDFBOX-4352-0.pdf', // content stream data fails its filter
  'empty.pdf', // empty page by design
  'empty_protected.pdf', // ditto, encrypted
  'extractPages_null_in_array.pdf', // empty page by design
  'freetext_no_appearance.pdf', // no /AP — we render appearances only
  'issue3521.pdf', // predefined CJK CMap (GBKp-EUC-H) — known gap
  'issue4461.pdf', // /Length 0 content stream
  'issue4684.pdf', // invisible (Tr 3) text only
  'labelled_pages.pdf', // pages are empty by design
  'noembed-eucjp.pdf', // predefined CJK CMap — known gap
  'noembed-sjis.pdf', // predefined CJK CMap — known gap
  'operator_list_cycle.pdf', // content cycle resolves to nothing
  'rc_annotation.pdf', // annotation without /AP
};

void main() {
  final root = Directory('../../test_corpora/pdfjs');
  if (!root.existsSync()) {
    test('pdf.js suite', skip: 'test_corpora/pdfjs not found', () {});
    return;
  }

  final files = root
      .listSync()
      .whereType<File>()
      .where((f) => f.path.toLowerCase().endsWith('.pdf'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  for (final file in files) {
    final name = file.uri.pathSegments.last;
    test(name, () {
      final bytes = file.readAsBytesSync();
      if (unopenable.contains(name)) {
        try {
          // pageCount forces the lazy catalog/page-tree resolution
          expect(PdfDocument.open(bytes).pageCount, 0,
              reason: 'expected a controlled failure or no reachable pages');
        } on CosParseException {
          // the controlled failure mode this test pins
        }
        return;
      }
      if (requiresPassword.contains(name)) {
        expect(() => PdfDocument.open(bytes),
            throwsA(isA<CosPasswordException>()));
        return;
      }
      final doc =
          PdfDocument.open(bytes, password: passwords[name] ?? '');
      expect(doc.pageCount, greaterThan(0));
      for (var i = 0; i < doc.pageCount; i++) {
        final page = doc.page(i);
        final device = _CountingDevice();
        PdfInterpreter(cos: doc.cos, device: device)
          ..drawPage(page)
          ..drawAnnotations(page);
        if (!mayBeBlank.contains(name)) {
          expect(device.paintOps, greaterThan(0),
              reason: 'page $i painted nothing');
        }
      }
    });
  }
}

/// Counts paint callbacks; recurses into soft-mask groups like a real
/// compositor so masked content is interpreted too. Invisible text
/// (Tr 3 OCR layers) reaches devices but is not paint.
class _CountingDevice implements PdfDevice {
  int paintOps = 0;

  @override
  void save() {}
  @override
  void restore() {}
  @override
  void fillPath(PdfPath path, PdfColor color, PdfFillRule rule, double alpha) {
    paintOps++;
  }

  @override
  void fillPathGradient(
      PdfPath path, PdfFillRule rule, PdfGradient gradient, double alpha) {
    paintOps++;
  }

  @override
  void fillMesh(PdfMesh mesh, double alpha) {
    paintOps++;
  }

  @override
  void strokePath(
      PdfPath path, PdfColor color, PdfStroke stroke, double alpha) {
    paintOps++;
  }

  @override
  void clipPath(PdfPath path, PdfFillRule rule) {}
  @override
  void drawText(PdfTextRun run) {
    if (!run.invisible) paintOps++;
  }

  @override
  void drawImage(PdfImageRequest request) {
    paintOps++;
  }

  @override
  void setBlendMode(PdfBlendMode mode) {}
  @override
  void beginGroup(double alpha, {bool knockout = false}) {}
  @override
  void endGroup() {}
  @override
  void beginSoftMasked() {}
  @override
  void endSoftMasked({
    required bool luminosity,
    required PdfRect backdrop,
    required void Function() drawMask,
    double backdropLuminance = 0,
    double transferScale = 1,
    double transferOffset = 0,
  }) {
    drawMask();
  }
}
