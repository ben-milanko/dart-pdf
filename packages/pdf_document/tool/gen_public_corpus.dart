// Generates the dart-pdf public test corpus (test_corpora/dartpdf/) - the
// project-owned, license-clean sibling of the Ghent and pdf.js suites.
// Everything is synthesized by dart-pdf's own writers, so the files are
// redistributable (CC0) and BYTE-DETERMINISTIC: fixed seeds, fixed
// annotation names/authors (never the random /NM path), no timestamps.
// Committed bytes are the measurement contract; regenerate deliberately
// via tool/gen_corpus.sh and review the diff like a baseline change.
//
//   cd packages/pdf_document
//   fvm dart run tool/gen_public_corpus.dart --out ../../test_corpora/dartpdf
//
// Document classes (the CAD sheet comes from pdf_cos/tool/gen_cad_pdf.dart,
// orchestrated by tool/gen_corpus.sh):
//   text-report-40p.pdf    office-style text: paragraphs, bold headings
//   letterhead-report-40p.pdf  the same text under a small shared letterhead
//                          image XObject on every page - the corporate-report
//                          class
//   image-scan-4p.pdf      scan-like full-page RGB images (gradient+noise)
//   cmyk-jpeg-1p.pdf       print-image color edge (#370): Adobe YCCK and
//                          plain CMYK DCTDecode twins of the same swatches
//   annotated-10p.pdf      markup on a text base via PdfEditor (highlight/
//                          ink/shapes/free text/note/underline/strikeout,
//                          generated appearances, incremental revision)
//   broken-startxref.pdf   recovery class: smashed startxref keyword
//   junk-prefix.pdf        leniency class: junk bytes before %PDF- header
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';

/// Deterministic 64-bit LCG; top 52 bits, never divide by 1 << 63 (that
/// literal is int64-negative on the VM).
class _Lcg {
  _Lcg(this._state);
  int _state;

  int _next() =>
      _state = (_state * 6364136223846793005 + 1442695040888963407) &
          0x7FFFFFFFFFFFFFFF;

  double unit() => (_next() >> 11) * (1.0 / (1 << 52));

  int intBelow(int n) => (unit() * n).floor();
}

const _words = [
  'annotation', 'baseline', 'content', 'document', 'engine', 'filter',
  'glyph', 'header', 'incremental', 'interpreter', 'kerning', 'layout',
  'matrix', 'notation', 'object', 'page', 'quadrant', 'raster', 'stream',
  'trailer', 'update', 'vector', 'workflow', 'xref', 'yield', 'zone',
];

String _sentence(_Lcg rng) {
  final n = 6 + rng.intBelow(10);
  final parts = [for (var i = 0; i < n; i++) _words[rng.intBelow(_words.length)]];
  final first = parts.first;
  parts[0] = first[0].toUpperCase() + first.substring(1);
  return '${parts.join(' ')}.';
}

Uint8List _deflate(String content) {
  final zlib = ZLibCodec(level: 6);
  return Uint8List.fromList(zlib.encode(content.codeUnits));
}

CosReference _addContent(CosDocumentBuilder builder, String content) {
  final deflated = _deflate(content);
  return builder.add(CosStream(
    CosDictionary({
      'Filter': const CosName('FlateDecode'),
      'Length': CosInteger(deflated.length),
    }),
    deflated,
  ));
}

/// The corporate-report class: the office text document above with a small
/// letterhead mark - one shared image XObject - drawn at the top of every
/// page, plus a rule under it.
///
/// Trivial to render and completely ordinary, which is the point. Every page
/// declaring an /XObject is what real reports look like, and rendering
/// policies that ask "does this page have an image?" rather than "how big is
/// it?" switch themselves off across the whole file. A field trace of a
/// 113-page document of exactly this shape - a 42x10 mark per page - is what
/// put this class in the corpus.
Uint8List buildLetterheadReport(int pageCount, {int seed = 20260819}) {
  const pageW = 612.0, pageH = 792.0;
  // The mark: small enough that decoding it inside a scrolling frame is
  // nothing, which is exactly the judgement under test.
  const markW = 96, markH = 24;
  final rng = _Lcg(seed);
  final builder = CosDocumentBuilder();

  // 1 = catalog, 2 = pages tree, 3/4 = fonts, 5 = the shared mark, then
  // content+page per page.
  const treeRef = CosReference(2, 0);
  const regularRef = CosReference(3, 0);
  const boldRef = CosReference(4, 0);
  const markRef = CosReference(5, 0);
  final pageRefs = [
    for (var i = 0; i < pageCount; i++) CosReference(6 + i * 2 + 1, 0),
  ];

  builder.add(CosDictionary(
      {'Type': const CosName('Catalog'), 'Pages': treeRef})); // 1
  builder.add(CosDictionary({
    'Type': const CosName('Pages'),
    'Kids': CosArray(pageRefs),
    'Count': CosInteger(pageCount),
  })); // 2
  for (final base in ['Helvetica', 'Helvetica-Bold']) {
    builder.add(CosDictionary({
      'Type': const CosName('Font'),
      'Subtype': const CosName('Type1'),
      'BaseFont': CosName(base),
    })); // 3, 4
  }

  // A deterministic two-tone wordmark: a filled block and a lighter slab.
  final rgb = Uint8List(markW * markH * 3);
  for (var y = 0, at = 0; y < markH; y++) {
    for (var x = 0; x < markW; x++) {
      final solid = x < markH && y > 3 && y < markH - 4;
      final slab = x >= markH + 6 && y > markH ~/ 3 && y < markH - 6;
      final v = solid ? 24 : (slab ? 96 : 246);
      rgb[at++] = v;
      rgb[at++] = solid ? 64 : v;
      rgb[at++] = solid ? 132 : v;
    }
  }
  final deflatedMark = Uint8List.fromList(ZLibCodec(level: 6).encode(rgb));
  builder.add(CosStream(
    CosDictionary({
      'Type': const CosName('XObject'),
      'Subtype': const CosName('Image'),
      'Width': const CosInteger(markW),
      'Height': const CosInteger(markH),
      'ColorSpace': const CosName('DeviceRGB'),
      'BitsPerComponent': const CosInteger(8),
      'Filter': const CosName('FlateDecode'),
      'Length': CosInteger(deflatedMark.length),
    }),
    deflatedMark,
  )); // 5

  var section = 0;
  for (var p = 0; p < pageCount; p++) {
    final sb = StringBuffer()
      // the mark, at its natural aspect, then the rule beneath it
      ..writeln('q 96 0 0 24 72 ${pageH - 60} cm /Im0 Do Q')
      ..writeln('0.6 w 72 ${pageH - 70} m ${pageW - 72} ${pageH - 70} l S')
      ..write('BT /F1 11 Tf 72 ${pageH - 96} Td 14 TL\n');
    var lines = 0;
    while (lines < 40) {
      if (lines == 0 || rng.intBelow(12) == 0) {
        section++;
        sb.writeln('/F2 13 Tf ($section. ${_sentence(rng)}) Tj T* /F1 11 Tf');
        lines += 1;
      }
      final para = 3 + rng.intBelow(4);
      for (var l = 0; l < para && lines < 40; l++, lines++) {
        sb.writeln('(${_sentence(rng)} ${_sentence(rng)}) Tj T*');
      }
      sb.writeln('T*');
      lines++;
    }
    sb.writeln('ET');
    final contentRef = _addContent(builder, sb.toString());
    builder.add(CosDictionary({
      'Type': const CosName('Page'),
      'Parent': treeRef,
      'MediaBox': CosArray([
        const CosInteger(0),
        const CosInteger(0),
        const CosReal(pageW),
        const CosReal(pageH),
      ]),
      'Resources': CosDictionary({
        'Font': CosDictionary({'F1': regularRef, 'F2': boldRef}),
        'XObject': CosDictionary({'Im0': markRef}),
      }),
      'Contents': contentRef,
    }));
  }
  return builder.build(root: const CosReference(1, 0));
}

/// Office-style text document: paragraphs with bold section headings.
Uint8List buildTextReport(int pageCount, {int seed = 20260718}) {
  const pageW = 612.0, pageH = 792.0;
  final rng = _Lcg(seed);
  final builder = CosDocumentBuilder();

  // 1 = catalog, 2 = pages tree, 3/4 = fonts, then content+page per page.
  final treeRef = const CosReference(2, 0);
  final regularRef = const CosReference(3, 0);
  final boldRef = const CosReference(4, 0);
  final pageRefs = [
    for (var i = 0; i < pageCount; i++) CosReference(5 + i * 2 + 1, 0),
  ];

  builder.add(CosDictionary(
      {'Type': const CosName('Catalog'), 'Pages': treeRef})); // 1
  builder.add(CosDictionary({
    'Type': const CosName('Pages'),
    'Kids': CosArray(pageRefs),
    'Count': CosInteger(pageCount),
  })); // 2
  for (final base in ['Helvetica', 'Helvetica-Bold']) {
    builder.add(CosDictionary({
      'Type': const CosName('Font'),
      'Subtype': const CosName('Type1'),
      'BaseFont': CosName(base),
    })); // 3, 4
  }

  var section = 0;
  for (var p = 0; p < pageCount; p++) {
    final sb = StringBuffer('BT /F1 11 Tf 72 ${pageH - 72} Td 14 TL\n');
    var lines = 0;
    while (lines < 44) {
      if (lines == 0 || rng.intBelow(12) == 0) {
        section++;
        sb.writeln('/F2 13 Tf ($section. ${_sentence(rng)}) Tj T* /F1 11 Tf');
        lines += 1;
      }
      // A paragraph: 3-6 wrapped lines then a blank line.
      final para = 3 + rng.intBelow(4);
      for (var l = 0; l < para && lines < 44; l++, lines++) {
        sb.writeln('(${_sentence(rng)} ${_sentence(rng)}) Tj T*');
      }
      sb.writeln('T*');
      lines++;
    }
    sb.writeln('ET');
    final contentRef = _addContent(builder, sb.toString());
    builder.add(CosDictionary({
      'Type': const CosName('Page'),
      'Parent': treeRef,
      'MediaBox': CosArray([
        const CosInteger(0),
        const CosInteger(0),
        const CosReal(pageW),
        const CosReal(pageH),
      ]),
      'Resources': CosDictionary({
        'Font': CosDictionary({'F1': regularRef, 'F2': boldRef}),
      }),
      'Contents': contentRef,
    }));
  }
  return builder.build(root: const CosReference(1, 0));
}

/// Print-image color edge (#370): one page painting the same two swatches
/// twice - once through an Adobe YCCK JPEG (APP14 transform=2, Y'CbCr of
/// the inverted CMY, K as ink) and once through a plain CMYK JPEG
/// (transform=0). Both 16x8 files are hand-built baseline JPEGs (constant
/// 8x8 blocks, custom Huffman tables), so the stored samples are exact by
/// construction: left half cyan ink (255,0,0,0), right half magenta + half
/// K (0,255,0,128). A conforming render shows two identical swatch pairs;
/// a decoder that skips the YCCK inversion shows red/green complements.
/// pdf.js renders of the same XObjects are the ground truth pinned in
/// pdf_graphics/test/image_pixels_test.dart.
Uint8List buildCmykJpeg() {
  const ycckJpeg =
      '/9j/7gAOQWRvYmUAZAAAAAAC/9sAQwAQCwoQGCgzPQwMDhMaOjw3Dg0QGCg5RTgOERYdM1dQPhIWJThEbWdNGCM3QFFocVwxQE5XZ3l4ZUhcX2JwZGdj/9sAQwEREhgvY2NjYxIVGkJjY2NjGBo4Y2NjY2MvQmNjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2Nj/8AAFAgACAAQBAERAAIRAQMRAQQRAP/EABYAAQEBAAAAAAAAAAAAAAAAAAUGB//EABQQAQAAAAAAAAAAAAAAAAAAAAD/2gAOBAEAAgADAAQAAD8AaKINn6ZKNuaA/9k=';
  const cmykJpeg =
      '/9j/7gAOQWRvYmUAZAAAAAAA/9sAQwAQCwoQGCgzPQwMDhMaOjw3Dg0QGCg5RTgOERYdM1dQPhIWJThEbWdNGCM3QFFocVwxQE5XZ3l4ZUhcX2JwZGdj/9sAQwEREhgvY2NjYxIVGkJjY2NjGBo4Y2NjY2MvQmNjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2Nj/8AAFAgACAAQBAERAAIRAQMRAQQRAP/EABcAAQEBAQAAAAAAAAAAAAAAAAAGBwj/xAAUEAEAAAAAAAAAAAAAAAAAAAAA/9oADgQBAAIAAwAEAAA/ANAQaDZ+5/bwNAf/2Q==';

  const pageW = 612.0, pageH = 792.0;
  final builder = CosDocumentBuilder();
  const treeRef = CosReference(2, 0);
  const fontRef = CosReference(3, 0);
  const ycckRef = CosReference(4, 0);
  const cmykRef = CosReference(5, 0);
  const contentRef = CosReference(6, 0);
  const pageRef = CosReference(7, 0);

  builder.add(CosDictionary(
      {'Type': const CosName('Catalog'), 'Pages': treeRef})); // 1
  builder.add(CosDictionary({
    'Type': const CosName('Pages'),
    'Kids': CosArray([pageRef]),
    'Count': const CosInteger(1),
  })); // 2
  builder.add(CosDictionary({
    'Type': const CosName('Font'),
    'Subtype': const CosName('Type1'),
    'BaseFont': const CosName('Helvetica'),
  })); // 3

  void jpegImage(String b64) {
    final bytes = base64Decode(b64);
    builder.add(CosStream(
      CosDictionary({
        'Type': const CosName('XObject'),
        'Subtype': const CosName('Image'),
        'Width': const CosInteger(16),
        'Height': const CosInteger(8),
        'ColorSpace': const CosName('DeviceCMYK'),
        'BitsPerComponent': const CosInteger(8),
        'Filter': const CosName('DCTDecode'),
        'Length': CosInteger(bytes.length),
      }),
      bytes,
    ));
  }

  jpegImage(ycckJpeg); // 4
  jpegImage(cmykJpeg); // 5

  final content = StringBuffer()
    ..writeln('q 480 0 0 240 66 462 cm /ImYcck Do Q')
    ..writeln('q 480 0 0 240 66 192 cm /ImCmyk Do Q')
    ..writeln('BT /F1 10 Tf 66 440 Td (Adobe YCCK (transform=2)) Tj ET')
    ..writeln('BT /F1 10 Tf 66 170 Td (plain CMYK (transform=0)) Tj ET')
    ..writeln('BT /F1 8 Tf 66 140 Td (Both rows must match: cyan swatch '
        'left, magenta+half-K swatch right - #370.) Tj ET');
  final deflated = _deflate(content.toString());
  builder.add(CosStream(
    CosDictionary({
      'Filter': const CosName('FlateDecode'),
      'Length': CosInteger(deflated.length),
    }),
    deflated,
  )); // 6

  builder.add(CosDictionary({
    'Type': const CosName('Page'),
    'Parent': treeRef,
    'MediaBox': CosArray([
      const CosInteger(0),
      const CosInteger(0),
      const CosReal(pageW),
      const CosReal(pageH),
    ]),
    'Resources': CosDictionary({
      'Font': CosDictionary({'F1': fontRef}),
      'XObject': CosDictionary({'ImYcck': ycckRef, 'ImCmyk': cmykRef}),
    }),
    'Contents': contentRef,
  })); // 7
  return builder.build(root: const CosReference(1, 0));
}

/// Scan-like pages: one full-page RGB image each (vertical gradient with
/// noise rows and dark scanline bands - decode-heavy but compressible
/// enough to commit), plus a caption line.
Uint8List buildImageScan(int pageCount, {int seed = 20260718}) {
  const pageW = 612.0, pageH = 792.0;
  const imgW = 600, imgH = 800;
  final rng = _Lcg(seed);
  final builder = CosDocumentBuilder();

  final treeRef = const CosReference(2, 0);
  final fontRef = const CosReference(3, 0);
  final pageRefs = [
    for (var i = 0; i < pageCount; i++) CosReference(4 + i * 3 + 2, 0),
  ];

  builder.add(CosDictionary(
      {'Type': const CosName('Catalog'), 'Pages': treeRef})); // 1
  builder.add(CosDictionary({
    'Type': const CosName('Pages'),
    'Kids': CosArray(pageRefs),
    'Count': CosInteger(pageCount),
  })); // 2
  builder.add(CosDictionary({
    'Type': const CosName('Font'),
    'Subtype': const CosName('Type1'),
    'BaseFont': const CosName('Helvetica'),
  })); // 3

  final zlib = ZLibCodec(level: 6);
  final rgb = Uint8List(imgW * imgH * 3);
  for (var p = 0; p < pageCount; p++) {
    var at = 0;
    for (var y = 0; y < imgH; y++) {
      final gradient = 235 - (y * 60 ~/ imgH) - p * 3;
      final noisy = y % 8 == 0;
      final band = y % 190 < 3; // scanner streak
      for (var x = 0; x < imgW; x++) {
        var v = gradient;
        if (noisy) v -= rng.intBelow(24);
        if (band) v -= 60;
        rgb[at++] = v;
        rgb[at++] = v - 4;
        rgb[at++] = v - 10;
      }
    }
    final deflated = Uint8List.fromList(zlib.encode(rgb));
    final imageRef = builder.add(CosStream(
      CosDictionary({
        'Type': const CosName('XObject'),
        'Subtype': const CosName('Image'),
        'Width': const CosInteger(imgW),
        'Height': const CosInteger(imgH),
        'ColorSpace': const CosName('DeviceRGB'),
        'BitsPerComponent': const CosInteger(8),
        'Filter': const CosName('FlateDecode'),
        'Length': CosInteger(deflated.length),
      }),
      deflated,
    ));
    final contentRef = _addContent(
      builder,
      'q ${pageW - 12} 0 0 ${pageH - 40} 6 28 cm /Im0 Do Q\n'
      'BT /F1 8 Tf 6 14 Td (dartpdf public corpus - scan page ${p + 1}) Tj ET\n',
    );
    builder.add(CosDictionary({
      'Type': const CosName('Page'),
      'Parent': treeRef,
      'MediaBox': CosArray([
        const CosInteger(0),
        const CosInteger(0),
        const CosReal(pageW),
        const CosReal(pageH),
      ]),
      'Resources': CosDictionary({
        'Font': CosDictionary({'F1': fontRef}),
        'XObject': CosDictionary({'Im0': imageRef}),
      }),
      'Contents': contentRef,
    }));
  }
  return builder.build(root: const CosReference(1, 0));
}

/// Markup over a text base: one incremental revision carrying every common
/// annotation kind with generated appearance streams. Explicit name/author
/// on every call keeps the output byte-deterministic (no random /NM).
Uint8List buildAnnotated() {
  final base = buildTextReport(10, seed: 20260719);
  final document = PdfDocument.open(base);
  final editor = PdfEditor(document);

  editor.addHighlight(
    0,
    const [PdfRect(72, 690, 340, 706), PdfRect(72, 676, 280, 690)],
    contents: 'Key requirement',
    author: 'dartpdf-corpus',
    name: 'corpus-highlight-1',
  );
  editor.addUnderline(
    1,
    const [PdfRect(72, 650, 300, 664)],
    author: 'dartpdf-corpus',
    name: 'corpus-underline-1',
  );
  editor.addStrikeOut(
    1,
    const [PdfRect(72, 610, 260, 624)],
    author: 'dartpdf-corpus',
    name: 'corpus-strikeout-1',
  );
  editor.addInk(
    2,
    const [
      [(90.0, 200.0), (140.0, 260.0), (200.0, 210.0), (260.0, 280.0)],
      [(300.0, 220.0), (330.0, 240.0), (360.0, 215.0)],
    ],
    author: 'dartpdf-corpus',
    name: 'corpus-ink-1',
  );
  editor.addSquare(
    3,
    const PdfRect(100, 420, 320, 540),
    fillColor: 0xFFF2CC,
    author: 'dartpdf-corpus',
    name: 'corpus-square-1',
  );
  editor.addCircle(
    3,
    const PdfRect(360, 420, 500, 540),
    strokeColor: 0x2A78D6,
    author: 'dartpdf-corpus',
    name: 'corpus-circle-1',
  );
  editor.addLine(
    4,
    const (110.0, 500.0),
    const (480.0, 380.0),
    author: 'dartpdf-corpus',
    name: 'corpus-line-1',
  );
  editor.addFreeText(
    5,
    const PdfRect(90, 500, 380, 560),
    'Free text in Helvetica with a border,\nwrapped over two lines.',
    fillColor: 0xFFFFFF,
    borderColor: 0xD02020,
    author: 'dartpdf-corpus',
    name: 'corpus-freetext-1',
  );
  editor.addNote(
    6,
    120,
    600,
    'A sticky note for the corpus.',
    author: 'dartpdf-corpus',
    name: 'corpus-note-1',
  );
  return editor.save();
}

/// The scanned-circuit-book class, profiled from a real (unshareable)
/// 187 MB / 198-page relay-room "Reds" book that OOM-crashed an app on
/// upload: every page is one large scanned image, content streams are
/// trivial (~8 ops), and memory - not the interpreter - is the workload
/// (COS layer alone reached 760 MB RSS; decoded pixels are what kill a
/// device). The sim keeps committed bytes small but the DECODED footprint
/// real: big-dimension grayscale pages of ruled circuit-like line art
/// (structured, so Flate crushes it) - 2200x1700 x 8-bit = 3.7 MB decoded
/// per page, ~45 MB for the set.
Uint8List buildScanBook(int pageCount, {int seed = 20260723}) {
  const pageW = 1190.0, pageH = 842.0; // A3 landscape sheet
  const imgW = 2200, imgH = 1700;
  final rng = _Lcg(seed);
  final builder = CosDocumentBuilder();
  final zlib = ZLibCodec(level: 6);

  final catalog = CosDictionary({'Type': const CosName('Catalog')});
  final catalogRef = builder.add(catalog);
  final tree = CosDictionary({'Type': const CosName('Pages')});
  final treeRef = builder.add(tree);
  catalog['Pages'] = treeRef;

  final gray = Uint8List(imgW * imgH);
  final pageRefs = <CosReference>[];
  for (var p = 0; p < pageCount; p++) {
    gray.fillRange(0, gray.length, 245); // paper
    void hline(int y, int x0, int x1, int ink) {
      if (y < 0 || y >= imgH) return;
      for (var x = x0.clamp(0, imgW - 1); x <= x1.clamp(0, imgW - 1); x++) {
        gray[y * imgW + x] = ink;
      }
    }

    void vline(int x, int y0, int y1, int ink) {
      if (x < 0 || x >= imgW) return;
      for (var y = y0.clamp(0, imgH - 1); y <= y1.clamp(0, imgH - 1); y++) {
        gray[y * imgW + x] = ink;
      }
    }

    // Sheet frame + title block.
    for (var t = 0; t < 3; t++) {
      hline(40 + t, 40, imgW - 40, 30);
      hline(imgH - 40 - t, 40, imgW - 40, 30);
      vline(40 + t, 40, imgH - 40, 30);
      vline(imgW - 40 - t, 40, imgH - 40, 30);
    }
    // Circuit-like ruling: horizontal bus lines with vertical drops.
    final buses = 14 + rng.intBelow(8);
    for (var b = 0; b < buses; b++) {
      final y = 120 + rng.intBelow(imgH - 240);
      final x0 = 80 + rng.intBelow(300);
      final x1 = imgW - 80 - rng.intBelow(300);
      hline(y, x0, x1, 25 + rng.intBelow(40));
      final drops = 4 + rng.intBelow(10);
      for (var d = 0; d < drops; d++) {
        final x = x0 + rng.intBelow((x1 - x0).clamp(1, imgW));
        vline(x, y, y + 60 + rng.intBelow(300), 25 + rng.intBelow(40));
      }
    }
    // Scanner artefacts: speckle + a skewed streak (keeps flate honest).
    for (var s = 0; s < 2200; s++) {
      gray[rng.intBelow(gray.length)] = 60 + rng.intBelow(120);
    }
    final streakY = 200 + rng.intBelow(imgH - 400);
    for (var x = 0; x < imgW; x++) {
      hline(streakY + x ~/ 90, x, x, 200);
    }

    final deflated = Uint8List.fromList(zlib.encode(gray));
    final imageRef = builder.add(CosStream(
      CosDictionary({
        'Type': const CosName('XObject'),
        'Subtype': const CosName('Image'),
        'Width': const CosInteger(imgW),
        'Height': const CosInteger(imgH),
        'ColorSpace': const CosName('DeviceGray'),
        'BitsPerComponent': const CosInteger(8),
        'Filter': const CosName('FlateDecode'),
        'Length': CosInteger(deflated.length),
      }),
      deflated,
    ));
    final contentRef = _addContent(
        builder, 'q $pageW 0 0 $pageH 0 0 cm /Im0 Do Q\n');
    final page = CosDictionary({
      'Type': const CosName('Page'),
      'Parent': treeRef,
      'MediaBox': CosArray([
        const CosInteger(0),
        const CosInteger(0),
        const CosReal(pageW),
        const CosReal(pageH),
      ]),
      'Resources': CosDictionary({
        'XObject': CosDictionary({'Im0': imageRef}),
      }),
      'Contents': contentRef,
    });
    pageRefs.add(builder.add(page));
  }
  tree['Kids'] = CosArray(pageRefs);
  tree['Count'] = CosInteger(pageCount);
  return builder.build(root: catalogRef);
}

/// The DCTDecode-photo class (#458): full-page DeviceRGB JPEG covers, the shape
/// the print/photo-book workload takes. Unlike the Flate `scan-book` pages,
/// these ride the platform/browser JPEG codec, so they are the corpus's only
/// non-CMYK DCT decode workload - on web the render worker's browser codec, or
/// the main thread's `_decodeOne` when the worker declines (the iOS Safari
/// case). Large STORED dimensions (~150 dpi A4), because JPEG decode cost is per
/// stored pixel, not display size. Real photo-like spectral content (smooth
/// gradient + a soft blob + light grain) so the JPEG keeps a realistic size and
/// the decode stays honest. Byte-deterministic: fixed seed, fixed encoder
/// quality (`package:image` is a pure function of pixels + quality).
Uint8List buildPhotoJpeg(int pageCount, {int seed = 20260723}) {
  const pageW = 595.0, pageH = 842.0; // A4 portrait
  const imgW = 1240, imgH = 1654; // ~150 dpi, the #458 cover shape
  final rng = _Lcg(seed);
  final builder = CosDocumentBuilder();

  final catalog = CosDictionary({'Type': const CosName('Catalog')});
  final catalogRef = builder.add(catalog);
  final tree = CosDictionary({'Type': const CosName('Pages')});
  final treeRef = builder.add(tree);
  catalog['Pages'] = treeRef;

  final pageRefs = <CosReference>[];
  for (var p = 0; p < pageCount; p++) {
    final photo = img.Image(width: imgW, height: imgH);
    final cx = imgW * (0.3 + 0.4 * rng.unit());
    final cy = imgH * (0.3 + 0.4 * rng.unit());
    for (final px in photo) {
      final gx = px.x * 255 ~/ imgW;
      final gy = px.y * 255 ~/ imgH;
      final dx = px.x - cx, dy = px.y - cy;
      final blob = (120.0 / (1 + (dx * dx + dy * dy) / 40000)).toInt();
      final n = rng.intBelow(18) - 9;
      px
        ..r = (gx + blob + n).clamp(0, 255)
        ..g = (gy + (blob >> 1) + n + p * 7).clamp(0, 255)
        ..b = (170 - (gx >> 1) + n).clamp(0, 255);
    }
    final jpeg = img.encodeJpg(photo, quality: 78);
    final imageRef = builder.add(CosStream(
      CosDictionary({
        'Type': const CosName('XObject'),
        'Subtype': const CosName('Image'),
        'Width': const CosInteger(imgW),
        'Height': const CosInteger(imgH),
        'ColorSpace': const CosName('DeviceRGB'),
        'BitsPerComponent': const CosInteger(8),
        'Filter': const CosName('DCTDecode'),
        'Length': CosInteger(jpeg.length),
      }),
      Uint8List.fromList(jpeg),
    ));
    final contentRef =
        _addContent(builder, 'q $pageW 0 0 $pageH 0 0 cm /Im0 Do Q\n');
    pageRefs.add(builder.add(CosDictionary({
      'Type': const CosName('Page'),
      'Parent': treeRef,
      'MediaBox': CosArray([
        const CosInteger(0),
        const CosInteger(0),
        const CosReal(pageW),
        const CosReal(pageH),
      ]),
      'Resources': CosDictionary({
        'XObject': CosDictionary({'Im0': imageRef}),
      }),
      'Contents': contentRef,
    })));
  }
  tree['Kids'] = CosArray(pageRefs);
  tree['Count'] = CosInteger(pageCount);
  return builder.build(root: catalogRef);
}

/// The replay-bound CAD-label class (#454): dense sheets of survey-point
/// labels that are UNIQUE across the whole document, drawn in a substituted
/// standard-14 font. Uniqueness is the point - the paint pass's run-layout
/// cache misses on every label, so this reproduces the "mostly-unique CAD
/// label" pathology the plan set only shows on its cold pages. It is the
/// worst case for substituted-text shaping and the workload a per-glyph text
/// cache would be measured against. Trivial vector content, so `replay` is
/// almost entirely text: shaping (the cache-miss `TextPainter` layout) plus
/// the per-label canvas calls.
Uint8List buildCadLabels(int pageCount) {
  const pageW = 1190.0, pageH = 842.0; // A3 landscape sheet
  const cols = 22, rows = 30; // 660 unique labels per page
  final builder = CosDocumentBuilder();

  final catalog = CosDictionary({'Type': const CosName('Catalog')});
  final catalogRef = builder.add(catalog);
  final tree = CosDictionary({'Type': const CosName('Pages')});
  final treeRef = builder.add(tree);
  catalog['Pages'] = treeRef;
  final fontRef = builder.add(CosDictionary({
    'Type': const CosName('Font'),
    'Subtype': const CosName('Type1'),
    'BaseFont': const CosName('Helvetica'),
  }));

  final pageRefs = <CosReference>[];
  var counter = 0;
  for (var p = 0; p < pageCount; p++) {
    final sb = StringBuffer('BT /F1 6 Tf\n');
    for (var r = 0; r < rows; r++) {
      final y = pageH - 30 - r * ((pageH - 60) / rows);
      for (var c = 0; c < cols; c++) {
        final x = 30 + c * ((pageW - 60) / cols);
        // A survey point that never repeats: guarantees a run-cache miss.
        final n = 1000000 + counter++;
        final north = '${n ~/ 1000}.${(n % 1000).toString().padLeft(3, '0')}';
        final e = 9000000 - n;
        final east = '${e ~/ 1000}.${(e % 1000).toString().padLeft(3, '0')}';
        sb.writeln('1 0 0 1 ${x.toStringAsFixed(1)} ${y.toStringAsFixed(1)} Tm '
            '(N$north E$east) Tj');
      }
    }
    sb.writeln('ET');
    final contentRef = _addContent(builder, sb.toString());
    pageRefs.add(builder.add(CosDictionary({
      'Type': const CosName('Page'),
      'Parent': treeRef,
      'MediaBox': CosArray([
        const CosInteger(0),
        const CosInteger(0),
        const CosReal(pageW),
        const CosReal(pageH),
      ]),
      'Resources': CosDictionary({
        'Font': CosDictionary({'F1': fontRef}),
      }),
      'Contents': contentRef,
    })));
  }
  tree['Kids'] = CosArray(pageRefs);
  tree['Count'] = CosInteger(pageCount);
  return builder.build(root: catalogRef);
}

/// A designed-booklet workload: the "InDesign export" class, profiled from
/// a real (unredistributable) RPG quickstart with the perf sweep - 62pp,
/// 93 embedded font programs, ~13 content-stream tokenizations per page
/// (Form XObject decoration), ~8k ops/page, transparency, full-page art.
/// This sim reproduces the SHAPE at committable size: multiple embedded
/// TrueType programs (the A/B test font - headings are AB-alphabet
/// strings, the corpus measures work not prose), shared + per-page Form
/// XObjects, a translucent full-page background image, two-column body
/// text, and vector ornament density.
Uint8List buildStyledBooklet(int pageCount, {int seed = 20260720}) {
  const pageW = 612.0, pageH = 792.0;
  final rng = _Lcg(seed);
  final builder = CosDocumentBuilder();
  final zlib = ZLibCodec(level: 6);

  // Registration order is dynamic here (fonts/forms/image before pages), so
  // collect page refs afterward instead of precomputing numbers.
  final catalog = CosDictionary({'Type': const CosName('Catalog')});
  final catalogRef = builder.add(catalog);
  final tree = CosDictionary({'Type': const CosName('Pages')});
  final treeRef = builder.add(tree);
  catalog['Pages'] = treeRef;

  final helveticaRef = builder.add(CosDictionary({
    'Type': const CosName('Font'),
    'Subtype': const CosName('Type1'),
    'BaseFont': const CosName('Helvetica'),
  }));

  // Eight distinct embedded font programs (the real booklet carried 93
  // subsets; eight keeps fontParse hot without bloating the file).
  final ttf = buildTestTrueTypeFont(includePost: true);
  final headingFonts = <String, CosObject>{};
  final headingEncoders = <String, PdfEmbeddedFont>{};
  for (var i = 0; i < 8; i++) {
    final name = 'HF$i';
    final font = PdfEmbeddedFont.parse(ttf, resourceName: name);
    headingEncoders[name] = font;
    headingFonts[name] = font.buildResource(builder.add).entries.values.first;
  }
  final headingRefs = <String, CosReference>{
    for (final e in headingFonts.entries) e.key: builder.add(e.value),
  };

  // Shared translucent background art: one 300x400 RGB wash reused by every
  // page (decoded once, cached - like a booklet's repeating spread art).
  final rgb = Uint8List(300 * 400 * 3);
  var at = 0;
  for (var y = 0; y < 400; y++) {
    for (var x = 0; x < 300; x++) {
      rgb[at++] = 140 + (x * 80 ~/ 300);
      rgb[at++] = 120 + (y * 60 ~/ 400);
      rgb[at++] = 170;
    }
  }
  final bgDeflated = Uint8List.fromList(zlib.encode(rgb));
  final bgRef = builder.add(CosStream(
    CosDictionary({
      'Type': const CosName('XObject'),
      'Subtype': const CosName('Image'),
      'Width': const CosInteger(300),
      'Height': const CosInteger(400),
      'ColorSpace': const CosName('DeviceRGB'),
      'BitsPerComponent': const CosInteger(8),
      'Filter': const CosName('FlateDecode'),
      'Length': CosInteger(bgDeflated.length),
    }),
    bgDeflated,
  ));

  final alphaRef = builder.add(CosDictionary({
    'Type': const CosName('ExtGState'),
    'CA': const CosReal(0.35),
    'ca': const CosReal(0.35),
  }));

  CosReference addForm(String content, double w, double h) {
    final deflated = _deflate(content);
    return builder.add(CosStream(
      CosDictionary({
        'Type': const CosName('XObject'),
        'Subtype': const CosName('Form'),
        'BBox': CosArray([
          const CosInteger(0),
          const CosInteger(0),
          CosReal(w),
          CosReal(h),
        ]),
        'Filter': const CosName('FlateDecode'),
        'Length': CosInteger(deflated.length),
      }),
      deflated,
    ));
  }

  String ornament(double w, double h, int strokes) {
    final sb = StringBuffer('0.4 w\n');
    for (var i = 0; i < strokes; i++) {
      sb.writeln('${(rng.unit() * w).toStringAsFixed(1)} '
          '${(rng.unit() * h).toStringAsFixed(1)} m '
          '${(rng.unit() * w).toStringAsFixed(1)} '
          '${(rng.unit() * h).toStringAsFixed(1)} l S');
    }
    return sb.toString();
  }

  // Eight shared decoration forms (sidebars, rules, flourishes).
  final sharedForms = <String, CosReference>{
    for (var i = 0; i < 8; i++)
      'Dec$i': addForm(ornament(120, 700, 60 + rng.intBelow(60)), 120, 700),
  };

  String heading(_Lcg rng) {
    const letters = ['A', 'B'];
    return [
      for (var i = 0, n = 5 + rng.intBelow(6); i < n; i++)
        letters[rng.intBelow(2)],
    ].join();
  }

  final pageRefs = <CosReference>[];
  for (var p = 0; p < pageCount; p++) {
    // Four page-unique callout forms on top of the shared eight - the
    // per-use tokenization mix the real booklet showed (~12 forms/page).
    final pageForms = <String, CosReference>{
      ...sharedForms,
      for (var i = 0; i < 4; i++)
        'Box$i': addForm(ornament(180, 90, 25), 180, 90),
    };

    final headingFont = 'HF${rng.intBelow(8)}';
    final hex = headingEncoders[headingFont]!.encodeHex(heading(rng));
    final sb = StringBuffer()
      // Translucent background art, scaled full page.
      ..writeln('q /GS0 gs $pageW 0 0 $pageH 0 0 cm /Bg Do Q')
      // Decoration forms.
      ..writeln('q 1 0 0 1 12 60 cm /Dec${p % 8} Do Q')
      ..writeln('q 1 0 0 1 ${pageW - 132} 60 cm /Dec${(p + 3) % 8} Do Q');
    for (var i = 0; i < 4; i++) {
      sb.writeln('q 1 0 0 1 ${150 + i * 80} ${90 + rng.intBelow(40)} cm '
          '/Box$i Do Q');
    }
    // Embedded-font chapter heading.
    sb.writeln('BT /$headingFont 22 Tf 150 ${pageH - 80} Td <$hex> Tj ET');
    // Two-column body text.
    for (final colX in const [150.0, 390.0]) {
      sb.writeln('BT /F1 9 Tf $colX ${pageH - 120} Td 11 TL');
      for (var l = 0; l < 52; l++) {
        sb.writeln('(${_sentence(rng)}) Tj T*');
      }
      sb.writeln('ET');
    }
    // Direct vector ornament to bring ops/page toward the profiled density.
    sb.write(ornament(pageW - 40, 40, 260));

    final contentRef = _addContent(builder, sb.toString());
    final page = CosDictionary({
      'Type': const CosName('Page'),
      'Parent': treeRef,
      'MediaBox': CosArray([
        const CosInteger(0),
        const CosInteger(0),
        const CosReal(pageW),
        const CosReal(pageH),
      ]),
      'Resources': CosDictionary({
        'Font': CosDictionary({
          'F1': helveticaRef,
          headingFont: headingRefs[headingFont]!,
        }),
        'XObject': CosDictionary({
          'Bg': bgRef,
          for (final e in pageForms.entries) e.key: e.value,
        }),
        'ExtGState': CosDictionary({'GS0': alphaRef}),
      }),
      'Contents': contentRef,
    });
    pageRefs.add(builder.add(page));
  }
  tree['Kids'] = CosArray(pageRefs);
  tree['Count'] = CosInteger(pageCount);
  return builder.build(root: catalogRef);
}

/// Smashes every [needle] occurrence so offsets stay valid.
Uint8List _smash(Uint8List bytes, String needle) {
  final text = String.fromCharCodes(bytes);
  final replaced = text.replaceAll(needle, '#' * needle.length);
  if (replaced == text) throw StateError('needle "$needle" not found');
  return Uint8List.fromList(replaced.codeUnits);
}

void main(List<String> argv) {
  var out = 'test_corpora/dartpdf';
  for (var i = 0; i < argv.length; i++) {
    if (argv[i] == '--out') out = argv[++i];
  }
  Directory(out).createSync(recursive: true);

  void write(String name, Uint8List bytes) {
    File('$out/$name').writeAsBytesSync(bytes);
    stderr.writeln(
        '  $name  ${(bytes.length / 1024).toStringAsFixed(0)} KB');
  }

  final textReport = buildTextReport(40);
  write('text-report-40p.pdf', textReport);
  write('letterhead-report-40p.pdf', buildLetterheadReport(40));
  write('image-scan-4p.pdf', buildImageScan(4));
  write('cmyk-jpeg-1p.pdf', buildCmykJpeg());
  write('annotated-10p.pdf', buildAnnotated());
  write('styled-booklet-24p.pdf', buildStyledBooklet(24));
  write('scan-book-12p.pdf', buildScanBook(12));
  write('photo-jpeg-6p.pdf', buildPhotoJpeg(6));
  write('cad-labels-6p.pdf', buildCadLabels(6));
  // Damaged classes derive from a well-formed base so recovery/leniency
  // timing measures the same underlying document.
  write('broken-startxref.pdf', _smash(textReport, 'startxref'));
  // The header scan is lenient only within the first 1024 bytes (see
  // CosDocument._findHeader) - keep the junk inside that window.
  write(
      'junk-prefix.pdf',
      Uint8List.fromList([
        ...'%!PS-Adobe junk preamble the parser must skip\n'.codeUnits,
        ...List.filled(720, 0x20),
        ...textReport,
      ]));
  stderr.writeln('wrote 5 documents to $out '
      '(plus the CAD sheet from tool/gen_corpus.sh)');
}
