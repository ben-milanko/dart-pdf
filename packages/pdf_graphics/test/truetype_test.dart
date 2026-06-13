import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';
import 'package:pdf_graphics/src/fonts/truetype.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:test/test.dart';

void main() {
  group('TrueTypeFont', () {
    late TrueTypeFont font;

    setUp(() => font = TrueTypeFont.parse(buildTestTrueTypeFont())!);

    test('parses the sfnt structure', () {
      expect(font.unitsPerEm, 1000);
      expect(font.numGlyphs, 3);
      expect(font.hasCmap, isTrue);
    });

    test('cmap maps unicode to glyph ids', () {
      expect(font.gidForUnicode(0x41), 1); // A
      expect(font.gidForUnicode(0x42), 2); // B
      expect(font.gidForUnicode(0x43), 0); // unmapped
    });

    test('hmtx advances are in em units', () {
      expect(font.advanceForGlyph(1), closeTo(0.6, 1e-9));
      expect(font.advanceForGlyph(2), closeTo(1.0, 1e-9));
    });

    test('glyph outlines scale to em units', () {
      final a = font.outlineForGlyph(1)!;
      expect(a.segments.first, isA<PdfMoveTo>());
      final move = a.segments.first as PdfMoveTo;
      expect(move.x, 0);
      expect(move.y, 0);
      final apex = a.segments[1] as PdfLineTo;
      expect(apex.x, closeTo(0.5, 1e-9));
      expect(apex.y, closeTo(1.0, 1e-9));
      expect(a.segments.last, isA<PdfClosePath>());
    });

    test('empty glyphs return no outline', () {
      expect(font.outlineForGlyph(0), isNull);
      expect(font.outlineForGlyph(99), isNull);
    });

    test('CFF-flavored OpenType parses to null', () {
      final bytes = buildTestTrueTypeFont();
      bytes.setAll(0, 'OTTO'.codeUnits);
      expect(TrueTypeFont.parse(bytes), isNull);
    });

    test('post 2.0 names resolve glyph ids without a cmap', () {
      // A cmap-less subset reaches its glyphs only by name through the post
      // table (TrueType_without_cmap.pdf — codes index empty/.notdef glyphs
      // directly, but "greater"/"i"/... name the real subset gids).
      final font = TrueTypeFont.parse(
          buildTestTrueTypeFont(includeCmap: false, includePost: true))!;
      expect(font.hasCmap, isFalse);
      expect(font.gidForName('A'), 1);
      expect(font.gidForName('B'), 2);
      expect(font.gidForName('.notdef'), 0);
      expect(font.gidForName('missing'), 0);
    });
  });

  group('embedded font in a document', () {
    test('PdfFontInfo exposes outlines and hmtx widths', () {
      final doc = PdfDocument.open(buildEmbeddedFontPdf());
      final fonts =
          doc.cos.resolve(doc.page(0).resources['Font']) as CosDictionary;
      final info = PdfFontInfo.load(
          doc.cos, doc.cos.resolve(fonts['F1']) as CosDictionary);
      expect(info.hasOutlines, isTrue);
      expect(info.outlineFor(0x41), isNotNull);
      expect(info.widthOf(0x41), closeTo(0.6, 1e-9));
    });

    test('interpreter emits glyph placements with pen offsets', () {
      final doc = PdfDocument.open(buildEmbeddedFontPdf());
      final device = _TextRecorder();
      PdfInterpreter(cos: doc.cos, device: device).drawPage(doc.page(0));

      final run = device.runs.single;
      expect(run.text, 'AB');
      expect(run.hasOutlines, isTrue);
      final glyphs = run.glyphs!;
      expect(glyphs, hasLength(2));
      expect(glyphs[0].offset, 0);
      expect(glyphs[0].outline, isNotNull);
      // B starts after A's 0.6 em advance
      expect(glyphs[1].offset, closeTo(0.6, 1e-9));
      expect(glyphs[1].outline, isNotNull);
    });
  });
}

class _TextRecorder implements PdfDevice {
  final runs = <PdfTextRun>[];

  @override
  void drawText(PdfTextRun run) => runs.add(run);

  @override
  void save() {}
  @override
  void restore() {}
  @override
  void fillPath(PdfPath path, PdfColor color, PdfFillRule rule, double a) {}
  @override
  void fillPathGradient(
      PdfPath path, PdfFillRule rule, PdfGradient gradient, double a) {}
  @override
  void fillMesh(PdfMesh mesh, double a) {}

  @override
  void strokePath(PdfPath path, PdfColor color, PdfStroke stroke, double a) {}
  @override
  void clipPath(PdfPath path, PdfFillRule rule) {}
  @override
  void drawImage(PdfImageRequest request) {}

  @override
  void setBlendMode(PdfBlendMode mode) {}
  @override
  void beginGroup(double alpha) {}
  @override
  void endGroup() {}
  @override
  void beginSoftMasked() {}
  @override
  void endSoftMasked(
      {required bool luminosity,
      required PdfRect backdrop,
      required void Function() drawMask,
      double backdropLuminance = 0,
      double transferScale = 1,
      double transferOffset = 0}) {}
}
