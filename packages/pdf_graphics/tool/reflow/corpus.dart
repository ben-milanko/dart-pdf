// The reading-view reflow evaluation corpus: ten synthetic documents, each
// built to break one specific assumption a layout-analysis pipeline makes.
//
// The point of generating rather than annotating: the same pass that writes a
// line's content-stream operators records the block it belongs to, so the
// ground truth cannot drift from the bytes. Everything here is deterministic
// (fixed word lists, fixed seeds, no timestamps, no random /NM), so the
// committed PDFs are a byte-stable measurement contract exactly like
// test_corpora/dartpdf - regenerate deliberately and review the diff.
//
// What each document is for:
//   simple-report          the easy case, plus running head/foot and page
//                          numbers that must NOT be read
//   two-column             a spanning title over two columns
//   three-column-news      narrower columns, headings inside them
//   justified-kerned       justification as TJ per-gap kerns (the LaTeX /
//                          InDesign shape) - inter-word gaps that a column
//                          detector can mistake for a gutter
//   justified-wordspaced   the same text justified with Tw instead
//   nested-lists           bullets and numbers at two depths
//   table-ruled            a bordered table read row-major
//   table-borderless       the same table with no rules - whitespace-aligned
//                          columns, the classic false-column trap
//   figures-captions       raster AND vector figures with captions
//   footnotes              body text over a rule with small-type footnotes
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';

import 'truth.dart';

/// One generated corpus document: the bytes and what is true about them.
class ReflowCorpusDoc {
  const ReflowCorpusDoc(this.bytes, this.truth);

  final Uint8List bytes;
  final ReflowTruth truth;

  String get name => truth.name;
}

/// How a block's lines are stretched to the column's right edge.
enum _Justify {
  /// Ragged right.
  none,

  /// Per-gap kerns inside a `TJ` array - what LaTeX and InDesign emit.
  kerned,

  /// A `Tw` word-spacing value - what Word emits.
  wordSpaced,
}

// --- deterministic filler prose ---------------------------------------------

/// A fixed sentence bank. Real words in real sentences (not lorem ipsum), so
/// hyphenation, capitalisation, and token matching behave like prose - and
/// fixed, so the corpus is reproducible to the byte.
const _sentences = [
  'The interpreter walks the content stream once and hands every operator to '
      'the device it was built with.',
  'A cross reference table maps object numbers to byte offsets so the reader '
      'can load an object without scanning the file.',
  'Fonts are embedded as programs whose glyph descriptions the rasterizer '
      'turns into filled outlines at the requested size.',
  'Filters decode a stream lazily, which keeps a large document cheap to open '
      'when only a few pages are ever displayed.',
  'Reading order is not stored in an ordinary page, so it has to be inferred '
      'from the geometry of the text that was drawn.',
  'A column detector that trusts horizontal gaps will split a justified '
      'paragraph down the middle and read it as two narrow columns.',
  'Annotations live beside the page content and carry their own appearance '
      'streams, which the viewer draws after the page itself.',
  'Incremental updates append a new revision instead of rewriting the file, '
      'so every earlier version remains byte for byte intact.',
  'The graphics state stack restores clipping, colour, and transformation '
      'together, which is why a stray q without Q corrupts a page.',
  'Text is positioned by two matrices, one for the line and one for the run, '
      'and every show operator advances the second of them.',
  'Word spacing applies only to the single byte code thirty two, which is why '
      'it silently does nothing inside a composite font.',
  'Images arrive as samples in some colour space and a transform that maps '
      'the unit square onto the region they occupy.',
];

const _headings = [
  'Content streams and the interpreter',
  'Cross reference recovery',
  'Font programs and glyph outlines',
  'Filters and lazy decoding',
  'Inferring reading order',
  'Column detection failures',
  'Annotation appearance streams',
  'Incremental revisions',
];

/// Deterministic sentence picker - an index walk, not a random number
/// generator, so adding a document never reshuffles another one's text.
class _Prose {
  _Prose(this._cursor);
  int _cursor;

  String sentence() => _sentences[_cursor++ % _sentences.length];

  String paragraph(int sentences) =>
      [for (var i = 0; i < sentences; i++) sentence()].join(' ');

  String heading() => _headings[_cursor++ % _headings.length];
}

// --- the builder -------------------------------------------------------------

/// Lays content out into columns and pages while recording the truth.
///
/// Every emitter goes through [_flowText], which wraps to the current column,
/// breaks to the next column or page when it runs out of room, and records
/// one truth block per *column fragment* (see
/// [ReflowTruthBlock.continuesPrevious]).
class _Builder {
  _Builder({
    required this.name,
    required this.description,
    this.columns = 1,
    this.justify = _Justify.none,
    this.runningHead,
    this.runningFoot,
    this.pageNumbers = false,
    this.bodySize = 10.5,
    this.leading = 14.5,
    this.needsImage = false,
  });

  final String name;
  final String description;
  final int columns;
  final _Justify justify;
  final String? runningHead;
  final String? runningFoot;
  final bool pageNumbers;
  final double bodySize;
  final double leading;
  final bool needsImage;

  static const pageWidth = 612.0;
  static const pageHeight = 792.0;
  static const margin = 72.0;
  static const gutter = 20.0;
  static const headFootInset = 36.0;

  static const bodyFont = PdfStandardFont.helvetica;
  static const boldFont = PdfStandardFont.helveticaBold;
  static const italicFont = PdfStandardFont.helveticaOblique;

  /// Resource names, fixed so the content streams read the same everywhere.
  static const _fontRes = {
    PdfStandardFont.helvetica: 'F1',
    PdfStandardFont.helveticaBold: 'F2',
    PdfStandardFont.helveticaOblique: 'F3',
  };

  final List<StringBuffer> _pages = [];
  final List<ReflowTruthBlock> _blocks = [];
  int _reading = 0;
  int _column = 0;
  late double _y;

  /// True while a block is being laid across the full content width.
  bool _spanned = false;

  /// The y every column on this page starts at - the top margin, or the
  /// bottom of a spanning block once one has been laid down.
  double _columnStartY = pageHeight - margin;

  double get _contentWidth => pageWidth - margin * 2;
  double get _columnWidth => (_contentWidth - gutter * (columns - 1)) / columns;
  double get _columnLeft => margin + _column * (_columnWidth + gutter);

  /// Where the current block starts and how wide it is - the column, or the
  /// whole content width while [_spanning] is running.
  double get _blockLeft => _spanned ? margin : _columnLeft;
  double get _blockWidth => _spanned ? _contentWidth : _columnWidth;
  double get _bottom => margin + footerReserve;

  /// Extra space held back at the foot of every page, so body text stops
  /// above a footnote block instead of colliding with it.
  double footerReserve = 0;
  double get _top => pageHeight - margin;

  StringBuffer get _page => _pages.last;
  int get _pageIndex => _pages.length - 1;

  void start() {
    _newPage();
  }

  void _newPage() {
    _pages.add(StringBuffer());
    _column = 0;
    _columnStartY = _top;
    _y = _top;
    _drawFurniture();
  }

  /// Running head, running foot, and page number: the page furniture a
  /// reading view must recognise as furniture. Drawn as ordinary text (not
  /// marked as an /Artifact), because that is the hard, common case - an
  /// untagged file gives the pipeline nothing but position and repetition.
  void _drawFurniture() {
    final head = runningHead;
    if (head != null) {
      _drawStandalone(head, italicFont, 8.5, margin, pageHeight - headFootInset,
          ReflowRole.artifact);
    }
    final foot = runningFoot;
    if (foot != null) {
      _drawStandalone(
          foot, italicFont, 8.5, margin, headFootInset, ReflowRole.artifact);
    }
    if (pageNumbers) {
      final label = '${_pages.length}';
      final width = _measure(bodyFont, label, 9);
      _drawStandalone(label, bodyFont, 9, pageWidth - margin - width,
          headFootInset, ReflowRole.artifact);
    }
  }

  void _drawStandalone(String text, PdfStandardFont font, double size, double x,
      double baseline, ReflowRole role) {
    _page.writeln('BT /${_fontRes[font]} $size Tf '
        '1 0 0 1 ${_n(x)} ${_n(baseline)} Tm (${_esc(text)}) Tj ET');
    _blocks.add(ReflowTruthBlock(
      pageIndex: _pageIndex,
      role: role,
      text: text,
      bounds: PdfRect(x, baseline - size * 0.22, x + _measure(font, text, size),
          baseline + size * 0.72),
      readingIndex: role == ReflowRole.artifact ? -1 : _reading++,
    ));
  }

  /// Moves to the next column, or the next page when the last column is full.
  void _break() {
    if (!_spanned && _column + 1 < columns) {
      _column++;
      _y = _columnStartY;
    } else {
      _newPage();
    }
  }

  void _ensure(double height) {
    if (_y - height < _bottom) _break();
  }

  /// Forces the next block onto a fresh page (not merely the next column).
  void breakPage() => _newPage();

  // --- text flow -------------------------------------------------------------

  /// Wraps [text] into [width] and returns the lines.
  List<String> _wrap(String text, PdfStandardFont font, double size,
      double width, double firstIndent) {
    final words = text.split(' ').where((w) => w.isNotEmpty).toList();
    final lines = <String>[];
    var current = '';
    var available = width - firstIndent;
    for (final word in words) {
      final candidate = current.isEmpty ? word : '$current $word';
      if (_measure(font, candidate, size) <= available || current.isEmpty) {
        current = candidate;
      } else {
        lines.add(current);
        current = word;
        available = width;
      }
    }
    if (current.isNotEmpty) lines.add(current);
    return lines;
  }

  /// Emits [text] as a block, flowing across columns and pages as needed, and
  /// records one truth block per fragment.
  void _flowText(
    String text,
    ReflowRole role, {
    PdfStandardFont font = bodyFont,
    double? size,
    double? lineHeight,
    double firstIndent = 0,
    double leftIndent = 0,
    double spaceBefore = 0,
    double spaceAfter = 6,
    _Justify? justifyOverride,
    int? headingLevel,
    int? listDepth,
    String? tableId,
  }) {
    final fontSize = size ?? bodySize;
    final lead = lineHeight ?? leading;
    final mode = justifyOverride ?? justify;
    if (spaceBefore > 0) _y -= spaceBefore;
    _ensure(lead);

    final width = _blockWidth - leftIndent;
    final lines = _wrap(text, font, fontSize, width, firstIndent);

    var index = 0;
    var continues = false;
    while (index < lines.length) {
      final left = _blockLeft + leftIndent;
      final fits = ((_y - _bottom) / lead).floor();
      if (fits <= 0) {
        _break();
        continue;
      }
      final take = fits < lines.length - index ? fits : lines.length - index;
      final slice = lines.sublist(index, index + take);
      final top = _y;
      final startX = left + (index == 0 ? firstIndent : 0);

      _page.writeln('BT /${_fontRes[font]} ${_n(fontSize)} Tf '
          '${_n(lead)} TL 1 0 0 1 ${_n(startX)} ${_n(_y - fontSize)} Tm');
      for (var i = 0; i < slice.length; i++) {
        final isLast = index + i == lines.length - 1;
        final lineWidth = width - (index == 0 && i == 0 ? firstIndent : 0);
        _showLine(slice[i], font, fontSize, lineWidth,
            justify: mode != _Justify.none && !isLast, mode: mode);
        _page.writeln('T*');
      }
      _page.writeln('ET');

      _y -= lead * slice.length;
      _blocks.add(ReflowTruthBlock(
        pageIndex: _pageIndex,
        role: role,
        text: slice.join(' '),
        bounds: PdfRect(left, _y, left + width, top),
        readingIndex: _reading++,
        headingLevel: headingLevel,
        listDepth: listDepth,
        tableId: tableId,
        continuesPrevious: continues,
      ));

      index += take;
      continues = true;
      if (index < lines.length) _break();
    }
    _y -= spaceAfter;
  }

  /// Writes one line, justified or not. Ragged and `Tw` lines are a single
  /// `Tj`; a kerned line becomes a `TJ` array with the slack spread over its
  /// inter-word gaps, which is the shape that makes naive gap-based column
  /// detection misfire.
  void _showLine(String line, PdfStandardFont font, double size, double width,
      {required bool justify, required _Justify mode}) {
    if (!justify) {
      _page.writeln('(${_esc(line)}) Tj');
      return;
    }
    final words = line.split(' ').where((w) => w.isNotEmpty).toList();
    if (words.length < 2) {
      _page.writeln('(${_esc(line)}) Tj');
      return;
    }
    final natural = _measure(font, line, size);
    final slack = width - natural;
    if (slack <= 0.01) {
      _page.writeln('(${_esc(line)}) Tj');
      return;
    }
    final gaps = words.length - 1;
    if (mode == _Justify.wordSpaced) {
      _page
        ..writeln('${_n(slack / gaps)} Tw')
        ..writeln('(${_esc(line)}) Tj')
        ..writeln('0 Tw');
      return;
    }
    // TJ numbers are thousandths of an em, SUBTRACTED from the advance, so a
    // negative number opens the gap up.
    final kern = -(slack / gaps) / size * 1000;
    final parts = <String>[];
    for (var i = 0; i < words.length; i++) {
      parts.add('(${_esc(i == 0 ? words[i] : ' ${words[i]}')})');
      if (i != words.length - 1) parts.add(_n(kern));
    }
    _page.writeln('[${parts.join(' ')}] TJ');
  }

  // --- content emitters --------------------------------------------------

  void heading(String text, {int level = 1, bool spanning = false}) {
    final size = level == 1 ? bodySize * 1.7 : bodySize * 1.3;
    if (spanning && columns > 1) {
      _spanning(() => _flowText(text, ReflowRole.heading,
          font: boldFont,
          size: size,
          lineHeight: size * 1.25,
          spaceBefore: _y < _top ? 10 : 0,
          spaceAfter: 10,
          justifyOverride: _Justify.none,
          headingLevel: level));
      return;
    }
    _flowText(text, ReflowRole.heading,
        font: boldFont,
        size: size,
        lineHeight: size * 1.25,
        spaceBefore: _y < _top ? 10 : 0,
        spaceAfter: 7,
        justifyOverride: _Justify.none,
        headingLevel: level);
  }

  void paragraph(String text, {double firstIndent = 0}) =>
      _flowText(text, ReflowRole.paragraph, firstIndent: firstIndent);

  void listItem(String marker, String text, {int depth = 0}) {
    final indent = 18.0 + depth * 18.0;
    _flowText('$marker $text', ReflowRole.listItem,
        leftIndent: indent,
        spaceAfter: 3,
        justifyOverride: _Justify.none,
        listDepth: depth);
  }

  void caption(String text) => _flowText(text, ReflowRole.caption,
      font: italicFont,
      size: bodySize * 0.85,
      lineHeight: bodySize * 1.15,
      spaceAfter: 10,
      justifyOverride: _Justify.none);

  /// Runs [body] across the full content width, then drops every column's
  /// start line below it. This is the academic-paper shape: a title that
  /// spans the page over two columns that begin underneath it.
  void _spanning(void Function() body) {
    _column = 0;
    _spanned = true;
    body();
    _spanned = false;
    _columnStartY = _y;
  }

  // --- figures -------------------------------------------------------------

  /// A raster figure: the shared image XObject scaled into a box.
  void figureRaster(double height) {
    _ensure(height + 6);
    final left = _blockLeft;
    final top = _y;
    final width = _blockWidth;
    _page.writeln('q ${_n(width)} 0 0 ${_n(height)} ${_n(left)} '
        '${_n(top - height)} cm /Im0 Do Q');
    _blocks.add(ReflowTruthBlock(
      pageIndex: _pageIndex,
      role: ReflowRole.figure,
      text: '',
      bounds: PdfRect(left, top - height, left + width, top),
      readingIndex: _reading++,
      isRaster: true,
    ));
    _y -= height + 6;
  }

  /// A vector figure: a small schematic of strokes and fills that reads as
  /// one picture. Nothing in the reading view surfaces these today - that is
  /// the point of having them in the corpus.
  void figureVector(double height) {
    _ensure(height + 6);
    final left = _blockLeft;
    final top = _y;
    final width = _blockWidth;
    final bottom = top - height;
    final buffer = StringBuffer('q 0.6 w 0.25 0.25 0.3 RG 0.85 0.87 0.92 rg\n');
    final cells = 5;
    for (var i = 0; i < cells; i++) {
      final x = left + width * (i + 0.5) / cells - 14;
      final h = height * (0.25 + 0.14 * i);
      buffer.writeln('${_n(x)} ${_n(bottom + 8)} 28 ${_n(h)} re B');
    }
    buffer
      ..writeln('${_n(left)} ${_n(bottom + 8)} m '
          '${_n(left + width)} ${_n(bottom + 8)} l S')
      ..writeln('${_n(left)} ${_n(bottom + 8)} m '
          '${_n(left)} ${_n(top - 4)} l S')
      ..writeln('Q');
    _page.write(buffer);
    _blocks.add(ReflowTruthBlock(
      pageIndex: _pageIndex,
      role: ReflowRole.figure,
      text: '',
      bounds: PdfRect(left, bottom, left + width, top),
      readingIndex: _reading++,
    ));
    _y -= height + 6;
  }

  // --- tables ---------------------------------------------------------------

  /// A table read row-major. [ruled] draws the grid; without it the columns
  /// are held apart by whitespace alone, which is what makes a borderless
  /// table read as two columns of prose.
  void table(List<List<String>> rows,
      {required bool ruled, required String id}) {
    const cellPad = 5.0;
    const rowHeight = 19.0;
    final columnsCount = rows.first.length;
    final cellWidth = _blockWidth / columnsCount;
    _ensure(rowHeight * rows.length + 8);
    final tableTop = _y;
    final left = _blockLeft;

    if (ruled) {
      final buffer = StringBuffer('q 0.5 w 0.3 0.3 0.3 RG\n');
      for (var r = 0; r <= rows.length; r++) {
        final y = tableTop - r * rowHeight;
        buffer.writeln('${_n(left)} ${_n(y)} m '
            '${_n(left + _blockWidth)} ${_n(y)} l S');
      }
      for (var c = 0; c <= columnsCount; c++) {
        final x = left + c * cellWidth;
        buffer.writeln('${_n(x)} ${_n(tableTop)} m '
            '${_n(x)} ${_n(tableTop - rows.length * rowHeight)} l S');
      }
      buffer.writeln('Q');
      _page.write(buffer);
    }

    for (var r = 0; r < rows.length; r++) {
      final font = r == 0 ? boldFont : bodyFont;
      final rowTop = tableTop - r * rowHeight;
      final baseline = rowTop - rowHeight + 6;
      for (var c = 0; c < columnsCount; c++) {
        final text = rows[r][c];
        if (text.isEmpty) continue;
        final x = left + c * cellWidth + cellPad;
        _page.writeln('BT /${_fontRes[font]} ${_n(bodySize * 0.92)} Tf '
            '1 0 0 1 ${_n(x)} ${_n(baseline)} Tm (${_esc(text)}) Tj ET');
        _blocks.add(ReflowTruthBlock(
          pageIndex: _pageIndex,
          role: ReflowRole.tableCell,
          text: text,
          bounds: PdfRect(x, baseline - 3, x + cellWidth - cellPad * 2,
              baseline + bodySize),
          readingIndex: _reading++,
          tableId: id,
        ));
      }
    }
    _y = tableTop - rows.length * rowHeight - 8;
  }

  // --- footnotes ------------------------------------------------------------

  /// Draws a separator rule and the footnote bodies at the foot of the
  /// current page, then leaves the cursor above them.
  void footnotes(List<String> notes) {
    const noteSize = 8.0;
    const noteLead = 10.0;
    final height = notes.length * noteLead + 14;
    final ruleY = margin + height;
    _page.writeln('q 0.5 w 0.4 0.4 0.4 RG ${_n(_blockLeft)} ${_n(ruleY)} m '
        '${_n(_blockLeft + _blockWidth * 0.35)} ${_n(ruleY)} l S Q');
    var y = ruleY - 10;
    for (final note in notes) {
      _page.writeln('BT /${_fontRes[bodyFont]} $noteSize Tf '
          '1 0 0 1 ${_n(_blockLeft)} ${_n(y)} Tm (${_esc(note)}) Tj ET');
      _blocks.add(ReflowTruthBlock(
        pageIndex: _pageIndex,
        role: ReflowRole.footnote,
        text: note,
        bounds:
            PdfRect(_blockLeft, y - 2, _blockLeft + _blockWidth, y + noteSize),
        readingIndex: _reading++,
      ));
      y -= noteLead;
    }
  }

  // --- assembly -------------------------------------------------------------

  ReflowCorpusDoc build() {
    final builder = CosDocumentBuilder();
    final catalog = CosDictionary({'Type': const CosName('Catalog')});
    final catalogRef = builder.add(catalog);
    final tree = CosDictionary({'Type': const CosName('Pages')});
    final treeRef = builder.add(tree);
    catalog['Pages'] = treeRef;

    final fontRefs = <String, CosReference>{};
    for (final entry in _fontRes.entries) {
      fontRefs[entry.value] = builder.add(CosDictionary({
        'Type': const CosName('Font'),
        'Subtype': const CosName('Type1'),
        'BaseFont': CosName(entry.key.baseFont),
        'Encoding': const CosName('WinAnsiEncoding'),
      }));
    }

    CosReference? imageRef;
    if (needsImage) imageRef = builder.add(_imageXObject());

    final xobjects = CosDictionary({if (imageRef != null) 'Im0': imageRef});
    final resources = CosDictionary({
      'Font': CosDictionary(fontRefs),
      if (imageRef != null) 'XObject': xobjects,
    });
    final resourcesRef = builder.add(resources);

    final pageRefs = <CosReference>[];
    for (final content in _pages) {
      final deflated = Uint8List.fromList(
          ZLibCodec(level: 6).encode(latin1.encode(content.toString())));
      final contentRef = builder.add(CosStream(
        CosDictionary({
          'Filter': const CosName('FlateDecode'),
          'Length': CosInteger(deflated.length),
        }),
        deflated,
      ));
      pageRefs.add(builder.add(CosDictionary({
        'Type': const CosName('Page'),
        'Parent': treeRef,
        'MediaBox': CosArray(const [
          CosInteger(0),
          CosInteger(0),
          CosReal(pageWidth),
          CosReal(pageHeight),
        ]),
        'Resources': resourcesRef,
        'Contents': contentRef,
      })));
    }
    tree['Kids'] = CosArray(pageRefs);
    tree['Count'] = CosInteger(pageRefs.length);

    return ReflowCorpusDoc(
      builder.build(root: catalogRef),
      ReflowTruth(
        name: name,
        description: description,
        pageCount: _pages.length,
        blocks: List.unmodifiable(_blocks),
      ),
    );
  }

  /// A 24x16 RGB gradient - small, deterministic, and unmistakably an image
  /// to anything that looks at /XObject /Image.
  CosStream _imageXObject() {
    const w = 24, h = 16;
    final samples = Uint8List(w * h * 3);
    var i = 0;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        samples[i++] = (x * 255 ~/ (w - 1));
        samples[i++] = (y * 255 ~/ (h - 1));
        samples[i++] = 160;
      }
    }
    final deflated = Uint8List.fromList(ZLibCodec(level: 6).encode(samples));
    return CosStream(
      CosDictionary({
        'Type': const CosName('XObject'),
        'Subtype': const CosName('Image'),
        'Width': const CosInteger(w),
        'Height': const CosInteger(h),
        'ColorSpace': const CosName('DeviceRGB'),
        'BitsPerComponent': const CosInteger(8),
        'Filter': const CosName('FlateDecode'),
        'Length': CosInteger(deflated.length),
      }),
      deflated,
    );
  }
}

/// Formats a number for a content stream: short, deterministic, no exponent.
String _n(double v) {
  final rounded = (v * 100).roundToDouble() / 100;
  if (rounded == rounded.roundToDouble()) return rounded.toInt().toString();
  return rounded.toString();
}

/// The non-Latin-1 characters the corpus draws, mapped onto their
/// WinAnsiEncoding byte. Everything downstream - the bytes written, the
/// widths measured, and so the line breaks - has to agree on these, or the
/// truth would describe a layout the file does not have.
const _winAnsiSubstitutions = {
  0x2022: 0x95, // bullet
  0x2018: 0x91,
  0x2019: 0x92,
  0x201c: 0x93,
  0x201d: 0x94,
  0x2013: 0x96, // en dash
  0x2014: 0x97, // em dash
  0x2026: 0x85, // ellipsis
};

/// Re-codes [text] into a string whose code units are WinAnsi bytes.
String _winAnsi(String text) => String.fromCharCodes([
      for (final rune in text.runes)
        _winAnsiSubstitutions[rune] ?? (rune <= 0xFF ? rune : 0x3F)
    ]);

/// Width of [text] as the file will actually draw it.
double _measure(PdfStandardFont font, String text, double size) =>
    font.measure(_winAnsi(text), size);

/// Escapes a PDF literal string (after re-coding to WinAnsi bytes).
String _esc(String text) => _winAnsi(text)
    .replaceAll(r'\', r'\\')
    .replaceAll('(', r'\(')
    .replaceAll(')', r'\)');

// --- the corpus --------------------------------------------------------------

/// Builds every evaluation document, in a fixed order.
List<ReflowCorpusDoc> buildReflowCorpus() => [
      _simpleReport(),
      _twoColumn(),
      _threeColumnNews(),
      _justified(kerned: true),
      _justified(kerned: false),
      _nestedLists(),
      _table(ruled: true),
      _table(ruled: false),
      _figuresCaptions(),
      _footnotes(),
    ];

ReflowCorpusDoc _simpleReport() {
  final prose = _Prose(0);
  final b = _Builder(
    name: 'simple-report',
    description: 'Single column prose with a running head, running foot, and '
        'page numbers that must stay out of the reading stream.',
    runningHead: 'Reading order in untagged documents',
    runningFoot: 'Draft - internal circulation only',
    pageNumbers: true,
  )..start();
  b.heading('Inferring structure from geometry');
  b.paragraph(prose.paragraph(4));
  for (var section = 0; section < 5; section++) {
    b.heading(prose.heading(), level: 2);
    for (var para = 0; para < 3; para++) {
      b.paragraph(prose.paragraph(3 + para % 2));
    }
  }
  return b.build();
}

ReflowCorpusDoc _twoColumn() {
  final prose = _Prose(3);
  final b = _Builder(
    name: 'two-column',
    description: 'Academic shape: a title and abstract spanning the page over '
        'two columns that begin underneath it.',
    columns: 2,
    pageNumbers: true,
  )..start();
  b.heading('Column detection without a structure tree', spanning: true);
  b.paragraph(prose.paragraph(3));
  for (var section = 0; section < 5; section++) {
    b.heading(prose.heading(), level: 2);
    for (var para = 0; para < 2; para++) {
      b.paragraph(prose.paragraph(4));
    }
  }
  return b.build();
}

ReflowCorpusDoc _threeColumnNews() {
  final prose = _Prose(6);
  final b = _Builder(
    name: 'three-column-news',
    description: 'Three narrow columns under a spanning masthead, with '
        'headings inside the columns.',
    columns: 3,
    bodySize: 9,
    leading: 12,
  )..start();
  b.heading('The interpreter review', spanning: true);
  for (var section = 0; section < 6; section++) {
    b.heading(prose.heading(), level: 2);
    b.paragraph(prose.paragraph(3));
    b.paragraph(prose.paragraph(2));
  }
  return b.build();
}

ReflowCorpusDoc _justified({required bool kerned}) {
  final prose = _Prose(2);
  final b = _Builder(
    name: kerned ? 'justified-kerned' : 'justified-wordspaced',
    description: kerned
        ? 'One justified column whose slack is spread as per-gap TJ kerns - '
            'the LaTeX and InDesign shape. Wide inter-word gaps are what a '
            'naive gutter detector mistakes for a column break.'
        : 'The same justified column, stretched with a Tw word-spacing value '
            'instead - the shape Word emits.',
    justify: kerned ? _Justify.kerned : _Justify.wordSpaced,
    runningHead: 'Justification and false gutters',
  )..start();
  b.heading('Slack, gaps, and gutters');
  for (var section = 0; section < 4; section++) {
    b.paragraph(prose.paragraph(5));
    b.paragraph(prose.paragraph(4));
    if (section.isOdd) b.heading(prose.heading(), level: 2);
  }
  return b.build();
}

ReflowCorpusDoc _nestedLists() {
  final prose = _Prose(4);
  final b = _Builder(
    name: 'nested-lists',
    description: 'Bulleted and numbered lists at two depths, between prose - '
        'each item its own block, never folded into the paragraph above.',
  )..start();
  b.heading('What the reader has to recover');
  b.paragraph(prose.paragraph(3));
  const bullets = [
    'Visual lines, grouped from runs that share a baseline.',
    'Columns, separated by a gutter that no line crosses.',
    'Paragraphs, bounded by leading, indentation, and a short last line.',
  ];
  for (final item in bullets) {
    b.listItem('•', item);
  }
  b.paragraph(prose.paragraph(3));
  const steps = [
    'Collect the positioned runs for the page.',
    'Sort them into bands and merge the bands into lines.',
    'Cluster the lines into columns by horizontal overlap.',
    'Walk the columns in order and split them into paragraphs.',
  ];
  for (var i = 0; i < steps.length; i++) {
    b.listItem('${i + 1}.', steps[i]);
    if (i == 1) {
      b.listItem('a)', 'A band is a baseline plus the ascent it carries.',
          depth: 1);
      b.listItem('b)', 'Bands that overlap vertically belong to one line.',
          depth: 1);
    }
  }
  b.paragraph(prose.paragraph(4));
  return b.build();
}

ReflowCorpusDoc _table({required bool ruled}) {
  final prose = _Prose(8);
  final b = _Builder(
    name: ruled ? 'table-ruled' : 'table-borderless',
    description: ruled
        ? 'A bordered table read row-major, between prose.'
        : 'The same table with no rules at all - columns held apart by '
            'whitespace, which is what makes a borderless table read as '
            'parallel columns of prose.',
  )..start();
  b.heading('Filter support by stream class');
  b.paragraph(prose.paragraph(3));
  const rows = [
    ['Filter', 'Class', 'Decoder', 'Status'],
    ['FlateDecode', 'General', 'zlib', 'Complete'],
    ['LZWDecode', 'General', 'built in', 'Complete'],
    ['DCTDecode', 'Image', 'baseline JPEG', 'Complete'],
    ['CCITTFaxDecode', 'Image', 'group 3 and 4', 'Complete'],
    ['JBIG2Decode', 'Image', 'embedded profile', 'Partial'],
    ['JPXDecode', 'Image', 'JPEG 2000', 'Partial'],
  ];
  b.table(rows, ruled: ruled, id: 'filters');
  b.caption('Table 1. Stream filters and the decoders behind them.');
  b.paragraph(prose.paragraph(4));
  b.paragraph(prose.paragraph(3));
  return b.build();
}

ReflowCorpusDoc _figuresCaptions() {
  final prose = _Prose(1);
  final b = _Builder(
    name: 'figures-captions',
    description: 'Raster and vector figures with captions. The vector figure '
        'is the interesting one: the reading view surfaces image XObjects '
        'only, so artwork drawn as paths disappears from the reflow.',
    needsImage: true,
  )..start();
  b.heading('Figures in the reading order');
  b.paragraph(prose.paragraph(4));
  b.figureRaster(120);
  b.caption('Figure 1. A sampled image placed by a unit square transform.');
  b.paragraph(prose.paragraph(3));
  b.figureVector(130);
  b.caption('Figure 2. The same measurements drawn as vector artwork.');
  b.paragraph(prose.paragraph(4));
  b.figureRaster(90);
  b.caption('Figure 3. A second sampled image, half the height of the first.');
  b.paragraph(prose.paragraph(3));
  return b.build();
}

ReflowCorpusDoc _footnotes() {
  final prose = _Prose(5);
  final b = _Builder(
    name: 'footnotes',
    description: 'Body text over a separator rule with small-type footnotes, '
        'which belong after the page body and not inside the paragraph that '
        'happens to sit above them.',
    runningHead: 'Notes and apparatus',
    pageNumbers: true,
  )
    ..footerReserve = 46
    ..start();
  b.heading('Apparatus at the foot of the page');
  b.paragraph(prose.paragraph(4));
  b.paragraph(prose.paragraph(4));
  b.footnotes(const [
    '1. The separator rule is drawn, not tagged, so it carries no structure.',
    '2. Footnote type is smaller than the body, which is the only hint.',
  ]);
  b.breakPage();
  b.heading(prose.heading(), level: 2);
  b.paragraph(prose.paragraph(4));
  b.paragraph(prose.paragraph(3));
  b.footnotes(const [
    '3. A reading view should keep the note after the body of its page.',
  ]);
  return b.build();
}
