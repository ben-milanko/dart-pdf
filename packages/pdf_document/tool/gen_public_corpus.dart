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
//   image-scan-4p.pdf      scan-like full-page RGB images (gradient+noise)
//   annotated-10p.pdf      markup on a text base via PdfEditor (highlight/
//                          ink/shapes/free text/note/underline/strikeout,
//                          generated appearances, incremental revision)
//   broken-startxref.pdf   recovery class: smashed startxref keyword
//   junk-prefix.pdf        leniency class: junk bytes before %PDF- header
import 'dart:io';
import 'dart:typed_data';

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
  write('image-scan-4p.pdf', buildImageScan(4));
  write('annotated-10p.pdf', buildAnnotated());
  write('styled-booklet-24p.pdf', buildStyledBooklet(24));
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
