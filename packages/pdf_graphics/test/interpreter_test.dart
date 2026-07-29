import 'dart:io';
import 'dart:typed_data';

import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:test/test.dart';

class RecordingDevice implements PdfDevice {
  final calls = <String>[];
  final fills = <(PdfPath, PdfColor, PdfFillRule, double)>[];
  final strokes = <(PdfPath, PdfColor, PdfStroke, double)>[];
  final clips = <(PdfPath, PdfFillRule)>[];
  final texts = <PdfTextRun>[];
  final images = <PdfImageRequest>[];

  @override
  void save() => calls.add('save');

  @override
  void restore() => calls.add('restore');

  final gradients = <(PdfPath, PdfGradient)>[];

  @override
  void fillPath(PdfPath path, PdfColor color, PdfFillRule rule, double alpha) {
    calls.add('fill');
    fills.add((path, color, rule, alpha));
  }

  @override
  void fillPathGradient(
      PdfPath path, PdfFillRule rule, PdfGradient gradient, double alpha) {
    calls.add('gradient');
    gradients.add((path, gradient));
  }

  final meshes = <PdfMesh>[];

  @override
  void fillMesh(PdfMesh mesh, double a) {
    calls.add('mesh');
    meshes.add(mesh);
  }

  @override
  void strokePath(
      PdfPath path, PdfColor color, PdfStroke stroke, double alpha) {
    calls.add('stroke');
    strokes.add((path, color, stroke, alpha));
  }

  @override
  void clipPath(PdfPath path, PdfFillRule rule) {
    calls.add('clip');
    clips.add((path, rule));
  }

  @override
  void drawText(PdfTextRun run) {
    calls.add('text');
    texts.add(run);
  }

  @override
  void drawImage(PdfImageRequest request) {
    calls.add('image');
    images.add(request);
  }

  final blendModes = <PdfBlendMode>[];
  final overprints = <(bool, bool, int)>[];
  final softMaskEnds = <(bool, void Function())>[];

  @override
  void setBlendMode(PdfBlendMode mode) {
    calls.add('blend:${mode.name}');
    blendModes.add(mode);
  }

  @override
  void setOverprint(
      {required bool fill, required bool stroke, required int mode}) {
    calls.add('overprint:$fill,$stroke,$mode');
    overprints.add((fill, stroke, mode));
  }

  @override
  void beginGroup(double alpha, {bool knockout = false}) =>
      calls.add('beginGroup($alpha${knockout ? ' knockout' : ''})');
  @override
  void endGroup() => calls.add('endGroup');
  @override
  void beginSoftMasked() => calls.add('beginSoftMasked');

  @override
  void endSoftMasked(
      {required bool luminosity,
      required PdfRect backdrop,
      required void Function() drawMask,
      double backdropLuminance = 0,
      double transferScale = 1,
      double transferOffset = 0}) {
    calls.add('endSoftMasked');
    softMaskEnds.add((luminosity, drawMask));
  }
}

RecordingDevice interpret(String content) {
  final doc = CosDocument.open(buildClassicPdf());
  final device = RecordingDevice();
  PdfInterpreter(cos: doc, device: device).run(
    ContentStreamParser.parse(Uint8List.fromList(content.codeUnits)),
    CosDictionary(),
  );
  return device;
}

void main() {
  test('fills a rectangle transformed by cm', () {
    final device = interpret('q 2 0 0 2 10 10 cm 0 0 1 rg 5 5 20 30 re f Q');
    final (path, color, rule, alpha) = device.fills.single;
    expect(color, const PdfColor(0, 0, 1));
    expect(rule, PdfFillRule.nonzero);
    expect(alpha, 1);
    final move = path.segments.first as PdfMoveTo;
    expect(move.x, 20); // 2*5 + 10
    expect(move.y, 20);
    final corner = path.segments[2] as PdfLineTo;
    expect(corner.x, 60); // 2*(5+20) + 10
    expect(corner.y, 80); // 2*(5+30) + 10
  });

  test('stroke width scales with the CTM', () {
    final device = interpret('4 w 2 0 0 2 0 0 cm 0 0 10 10 re S');
    expect(device.strokes.single.$3.width, 8);
  });

  test('q/Q restores color state', () {
    final device = interpret('q 1 0 0 rg 0 0 1 1 re f Q 0 0 2 2 re f');
    expect(device.fills[0].$2, const PdfColor(1, 0, 0));
    expect(device.fills[1].$2, PdfColor.black);
  });

  test('clip applies after painting, with the same path', () {
    final device = interpret('0 0 5 5 re W n 0 0 10 10 re f');
    expect(device.calls, ['clip', 'fill']);
    expect(device.clips.single.$2, PdfFillRule.nonzero);
  });

  test('hidden optional content groups do not paint', () {
    final doc = PdfDocument.open(
        File('../../test_corpora/pdfjs/issue269_1.pdf').readAsBytesSync());
    final device = RecordingDevice();
    PdfInterpreter(cos: doc.cos, device: device).drawPage(doc.page(0));

    // Two black paths plus the visible blue path. The green /MC2 path is
    // mapped to an OCG in the document's default /OFF list.
    expect(device.fills, hasLength(3));
  });

  test('CMYK and gray color operators convert to RGB', () {
    final device = interpret('0 0 0 1 k 0 0 1 1 re f 0.5 g 0 0 1 1 re f');
    // DeviceCMYK uses pdf.js's SWOP-class polynomial, so pure K is not a
    // perfect black but the profile's dark grey (≈ RGB 44,46,53).
    expect(device.fills[0].$2.red, closeTo(0.171, 0.01));
    expect(device.fills[0].$2.green, closeTo(0.182, 0.01));
    expect(device.fills[0].$2.blue, closeTo(0.206, 0.01));
    expect(device.fills[1].$2, const PdfColor.gray(0.5));
  });

  test('scn with the wrong operand count falls back to a device reading', () {
    // /DeviceRGB has 3 channels; a single scn operand does not match, so the
    // interpreter reads it leniently as a 1-component (gray) device colour.
    final device = interpret('/DeviceRGB cs 0.5 scn 0 0 1 1 re f');
    expect(device.fills.single.$2, const PdfColor.gray(0.5));
  });

  test('pure process cyan converts through the SWOP polynomial', () {
    final device = interpret('1 0 0 0 k 0 0 1 1 re f');
    final color = device.fills.single.$2;
    // pdf.js DeviceCmykCS for (1,0,0,0) ≈ RGB(0, 184, 242).
    expect(color.red, 0);
    expect(color.green, closeTo(0.724, 0.01));
    expect(color.blue, closeTo(0.948, 0.01));
  });

  test('Separation colors evaluate the tint transform', () {
    final doc = CosDocument.open(buildClassicPdf());
    final device = RecordingDevice();
    final resources = CosDictionary({
      'ColorSpace': CosDictionary({
        // /All over CMYK: tint 1 → rich black, tint 0 → white
        'CS1': CosArray([
          const CosName('Separation'),
          const CosName('All'),
          const CosName('DeviceCMYK'),
          CosDictionary({
            'FunctionType': const CosInteger(2),
            'Domain': CosArray([const CosInteger(0), const CosInteger(1)]),
            'N': const CosInteger(1),
            'C0': CosArray([
              for (var i = 0; i < 4; i++) const CosInteger(0),
            ]),
            'C1': CosArray([
              for (var i = 0; i < 4; i++) const CosInteger(1),
            ]),
          }),
        ]),
      }),
    });
    PdfInterpreter(cos: doc, device: device).run(
      ContentStreamParser.parse(Uint8List.fromList(
          '/CS1 cs 1 scn 0 0 1 1 re f 0 scn 0 0 1 1 re f'.codeUnits)),
      resources,
    );
    expect(device.fills[0].$2.red, lessThan(0.05), reason: 'tint 1 ≈ black');
    expect(device.fills[0].$2.green, lessThan(0.05));
    expect(device.fills[1].$2, const PdfColor(1, 1, 1));
  });

  test('Separation colors convert a Lab alternate space', () {
    final doc = CosDocument.open(buildClassicPdf());
    final device = RecordingDevice();
    final resources = CosDictionary({
      'ColorSpace': CosDictionary({
        'Black': CosArray([
          const CosName('Separation'),
          const CosName('Black'),
          CosArray([
            const CosName('Lab'),
            CosDictionary({
              'WhitePoint': CosArray([
                const CosReal(0.9505),
                const CosInteger(1),
                const CosReal(1.089),
              ]),
              'Range': CosArray([
                const CosInteger(-128),
                const CosInteger(127),
                const CosInteger(-128),
                const CosInteger(127),
              ]),
            }),
          ]),
          CosDictionary({
            'FunctionType': const CosInteger(2),
            'Domain': CosArray([const CosInteger(0), const CosInteger(1)]),
            'Range': CosArray([
              const CosInteger(0),
              const CosInteger(100),
              const CosInteger(-128),
              const CosInteger(127),
              const CosInteger(-128),
              const CosInteger(127),
            ]),
            'C0': CosArray([
              const CosInteger(100),
              const CosInteger(0),
              const CosInteger(0),
            ]),
            'C1': CosArray([
              const CosReal(26.869612),
              const CosReal(2.070039),
              const CosReal(-4.385214),
            ]),
            'N': const CosInteger(1),
          }),
        ]),
      }),
    });
    PdfInterpreter(cos: doc, device: device).run(
      ContentStreamParser.parse(
          Uint8List.fromList('/Black CS 1 SCN 0 0 1 1 re S'.codeUnits)),
      resources,
    );
    final color = device.strokes.single.$2;
    expect(color.red, lessThan(0.35));
    expect(color.green, lessThan(0.35));
    expect(color.blue, lessThan(0.35));
  });

  test('CalGray colors are converted to sRGB', () {
    final doc = CosDocument.open(buildClassicPdf());
    final device = RecordingDevice();
    final resources = CosDictionary({
      'ColorSpace': CosDictionary({
        'CG': CosArray([
          const CosName('CalGray'),
          CosDictionary({
            'WhitePoint': CosArray([
              const CosInteger(1),
              const CosInteger(1),
              const CosInteger(1),
            ]),
            'Gamma': const CosInteger(1),
          }),
        ]),
      }),
    });
    PdfInterpreter(cos: doc, device: device).run(
      ContentStreamParser.parse(
          Uint8List.fromList('/CG cs 0.5 sc 0 0 1 1 re f'.codeUnits)),
      resources,
    );
    final color = device.fills.single.$2;
    expect(color.red, closeTo(194 / 255, 0.002));
    expect(color.green, closeTo(194 / 255, 0.002));
    expect(color.blue, closeTo(194 / 255, 0.002));
  });

  test('CalRGB colors are converted to sRGB', () {
    final doc = CosDocument.open(buildClassicPdf());
    final device = RecordingDevice();
    final resources = CosDictionary({
      'ColorSpace': CosDictionary({
        'CR': CosArray([
          const CosName('CalRGB'),
          CosDictionary({
            'WhitePoint': CosArray([
              const CosInteger(1),
              const CosInteger(1),
              const CosInteger(1),
            ]),
            'Gamma': CosArray([
              const CosInteger(1),
              const CosInteger(1),
              const CosInteger(1),
            ]),
            'Matrix': CosArray([
              const CosInteger(1),
              const CosInteger(0),
              const CosInteger(0),
              const CosInteger(0),
              const CosInteger(1),
              const CosInteger(0),
              const CosInteger(0),
              const CosInteger(0),
              const CosInteger(1),
            ]),
          }),
        ]),
      }),
    });
    PdfInterpreter(cos: doc, device: device).run(
      ContentStreamParser.parse(
          Uint8List.fromList('/CR cs 0.75 0 0 sc 0 0 1 1 re f'.codeUnits)),
      resources,
    );
    final color = device.fills.single.$2;
    expect(color.red, 1);
    expect(color.green, 0);
    expect(color.blue, closeTo(60 / 255, 0.01));
  });

  test('ExtGState alpha applies to fills', () {
    final doc = CosDocument.open(buildClassicPdf());
    final device = RecordingDevice();
    final resources = CosDictionary({
      'ExtGState': CosDictionary({
        'GS1': CosDictionary({'ca': const CosReal(0.25)}),
      }),
    });
    PdfInterpreter(cos: doc, device: device).run(
      ContentStreamParser.parse(
          Uint8List.fromList('/GS1 gs 0 0 1 1 re f'.codeUnits)),
      resources,
    );
    expect(device.fills.single.$4, 0.25);
  });

  group('text', () {
    test('renders the fixture page text with correct placement', () {
      final doc = PdfDocument.open(buildClassicPdf());
      final device = RecordingDevice();
      PdfInterpreter(cos: doc.cos, device: device).drawPage(doc.page(0));

      final run = device.texts.single;
      expect(run.text, 'Hello, world!');
      expect(run.fontName, 'Helvetica');
      expect(run.transform.e, 72); // Td x
      expect(run.transform.f, 720); // Td y
      expect(run.transform.a, 24); // font size on the x axis
      expect(run.transform.d, 24);
      // built-in Helvetica AFM advances (no /Widths in the fixture font)
      expect(run.width, closeTo(5.501, 1e-9));
    });

    test('word/char spacing and edge whitespace feed the substitute geometry',
        () {
      // A Type1 Helvetica resource (built-in AFM widths: a=b=0.556, space=0.278
      // em) so we can predict the advances exactly.
      final doc = CosDocument.open(buildClassicPdf());
      final resources = CosDictionary({
        'Font': CosDictionary({
          'F1': CosDictionary({
            'Type': const CosName('Font'),
            'Subtype': const CosName('Type1'),
            'BaseFont': const CosName('Helvetica'),
            'Encoding': const CosName('WinAnsiEncoding'),
          }),
        }),
      });

      // Trailing space carrying a large Tw (the tabular-column pattern): the gap
      // stays in width for positioning but is excluded from visibleWidth so a
      // substituting device does not stretch "ab" across it.
      final trailing = RecordingDevice();
      PdfInterpreter(cos: doc, device: trailing).run(
        ContentStreamParser.parse(Uint8List.fromList(
            'BT /F1 10 Tf 5 Tw 0 700 Td (ab ) Tj ET'.codeUnits)),
        resources,
      );
      final t = trailing.texts.single;
      expect(t.wordSpacing, closeTo(0.5, 1e-9)); // Tw 5 / size 10
      expect(t.letterSpacing, 0);
      expect(t.leadingSpace, 0);
      expect(t.width, closeTo(1.890, 1e-6)); // a+b+space(0.278)+Tw(0.5)
      // visibleWidth = a+b only; the trailing space's 0.778 em is dropped.
      expect(t.visibleWidth, closeTo(1.112, 1e-6));
      expect(t.width - t.visibleWidth!, closeTo(0.778, 1e-6));

      // Leading space carrying the same Tw: the gap becomes leadingSpace (a
      // device shifts the trimmed glyphs right by it), width stays full, and
      // visibleWidth is null because nothing trails the last visible glyph.
      final leading = RecordingDevice();
      PdfInterpreter(cos: doc, device: leading).run(
        ContentStreamParser.parse(Uint8List.fromList(
            'BT /F1 10 Tf 5 Tw 0 700 Td ( ab) Tj ET'.codeUnits)),
        resources,
      );
      final l = leading.texts.single;
      expect(l.leadingSpace, closeTo(0.778, 1e-6)); // space(0.278)+Tw(0.5)
      expect(l.width, closeTo(1.890, 1e-6));
      expect(l.visibleWidth, isNull);

      // No word spacing: width, visibleWidth, spacing all reduce to the plain
      // metric advance, so ordinary runs are untouched.
      final plain = RecordingDevice();
      PdfInterpreter(cos: doc, device: plain).run(
        ContentStreamParser.parse(Uint8List.fromList(
            'BT /F1 10 Tf 0 700 Td (ab) Tj ET'.codeUnits)),
        resources,
      );
      final p = plain.texts.single;
      expect(p.wordSpacing, 0);
      expect(p.letterSpacing, 0);
      expect(p.leadingSpace, 0);
      expect(p.visibleWidth, isNull);
      expect(p.width, closeTo(1.112, 1e-6));
    });

    test('a Type3 glyph that shows text does not corrupt the outer run', () {
      // A Type3 CharProc is an arbitrary content stream and may itself show
      // text, which re-enters _showText mid-loop. The run-text buffer is reused
      // across calls, so the nested call must take a private buffer and leave
      // the outer Type3 run's accumulated text intact.
      final doc = CosDocument.open(buildClassicPdf());
      final charProc = CosStream(
        CosDictionary({'Length': const CosInteger(0)}),
        // d0 (glyph width) then a nested text object showing "inner".
        Uint8List.fromList(
            '1000 0 d0 BT /F1 8 Tf 0 0 Td (inner) Tj ET'.codeUnits),
      );
      final type3 = CosDictionary({
        'Type': const CosName('Font'),
        'Subtype': const CosName('Type3'),
        'FontBBox': CosArray([
          const CosInteger(0),
          const CosInteger(0),
          const CosInteger(750),
          const CosInteger(750),
        ]),
        'FontMatrix': CosArray([
          const CosReal(0.001),
          const CosInteger(0),
          const CosInteger(0),
          const CosReal(0.001),
          const CosInteger(0),
          const CosInteger(0),
        ]),
        'FirstChar': const CosInteger(0x58),
        'LastChar': const CosInteger(0x58),
        'Widths': CosArray([const CosInteger(600)]),
        'Encoding': CosDictionary({
          'Differences': CosArray([const CosInteger(0x58), const CosName('X')]),
        }),
        'CharProcs': CosDictionary({'X': charProc}),
        'Resources': CosDictionary({
          'Font': CosDictionary({
            'F1': CosDictionary({
              'Type': const CosName('Font'),
              'Subtype': const CosName('Type1'),
              'BaseFont': const CosName('Helvetica'),
            }),
          }),
        }),
      });
      final device = RecordingDevice();
      PdfInterpreter(cos: doc, device: device).run(
        ContentStreamParser.parse(
            Uint8List.fromList('BT /T3 10 Tf (X) Tj ET'.codeUnits)),
        CosDictionary({
          'Font': CosDictionary({'T3': type3}),
        }),
      );
      // The nested CharProc text emits first, then the outer Type3 run.
      final inner = device.texts.firstWhere((t) => t.text == 'inner');
      final outer = device.texts.firstWhere((t) => t.text != 'inner');
      expect(inner.text, 'inner');
      expect(outer.text, 'X',
          reason: 'the nested show must not overwrite the outer buffer');
    });

    test('a Type3 glyph draws through its /FontMatrix at the pen position', () {
      // A CharProc that fills a 100x100 glyph-space box. With FontMatrix
      // 0.001 and Tf size 10, glyph space scales to page by 0.001*10 = 0.01,
      // so the box is 1x1 page units, dropped at the text origin. This
      // exercises the renderGlyph seam: the font supplies the glyph-space
      // matrix and CharProc, the interpreter re-enters its run loop.
      final doc = CosDocument.open(buildClassicPdf());
      final charProc = CosStream(
        CosDictionary({'Length': const CosInteger(0)}),
        Uint8List.fromList('1000 0 d0 0 0 100 100 re f'.codeUnits),
      );
      final type3 = CosDictionary({
        'Type': const CosName('Font'),
        'Subtype': const CosName('Type3'),
        'FontBBox': CosArray([
          const CosInteger(0),
          const CosInteger(0),
          const CosInteger(100),
          const CosInteger(100),
        ]),
        'FontMatrix': CosArray([
          const CosReal(0.001),
          const CosInteger(0),
          const CosInteger(0),
          const CosReal(0.001),
          const CosInteger(0),
          const CosInteger(0),
        ]),
        'FirstChar': const CosInteger(0x58),
        'LastChar': const CosInteger(0x58),
        'Widths': CosArray([const CosInteger(1000)]),
        'Encoding': CosDictionary({
          'Differences': CosArray([const CosInteger(0x58), const CosName('X')]),
        }),
        'CharProcs': CosDictionary({'X': charProc}),
      });
      final device = RecordingDevice();
      PdfInterpreter(cos: doc, device: device).run(
        ContentStreamParser.parse(Uint8List.fromList(
            'BT /T3 10 Tf 100 200 Td (X) Tj ET'.codeUnits)),
        CosDictionary({
          'Font': CosDictionary({'T3': type3}),
        }),
      );
      final (path, _, _, _) = device.fills.single;
      final move = path.segments.first as PdfMoveTo;
      expect(move.x, closeTo(100, 1e-9)); // glyph (0,0) at the pen origin
      expect(move.y, closeTo(200, 1e-9));
      final corner = path.segments[2] as PdfLineTo;
      expect(corner.x, closeTo(101, 1e-9)); // 100*0.001*10 = 1 page unit wide
      expect(corner.y, closeTo(201, 1e-9));
    });

    test('a d1 Type3 glyph ignores its own colour, painting in text colour',
        () {
      // §9.6.5: a CharProc that opens with d1 is a shape-only glyph. The red
      // `rg` inside it must be ignored; the glyph paints in the blue fill
      // colour that was in effect when the glyph was shown.
      CosDictionary type3(String proc) => CosDictionary({
            'Type': const CosName('Font'),
            'Subtype': const CosName('Type3'),
            'FontBBox': CosArray([
              const CosInteger(0),
              const CosInteger(0),
              const CosInteger(100),
              const CosInteger(100),
            ]),
            'FontMatrix': CosArray([
              const CosReal(0.001),
              const CosInteger(0),
              const CosInteger(0),
              const CosReal(0.001),
              const CosInteger(0),
              const CosInteger(0),
            ]),
            'FirstChar': const CosInteger(0x58),
            'LastChar': const CosInteger(0x58),
            'Widths': CosArray([const CosInteger(1000)]),
            'Encoding': CosDictionary({
              'Differences':
                  CosArray([const CosInteger(0x58), const CosName('X')]),
            }),
            'CharProcs': CosDictionary({
              'X': CosStream(CosDictionary({'Length': const CosInteger(0)}),
                  Uint8List.fromList(proc.codeUnits)),
            }),
          });

      PdfColor glyphFill(String proc) {
        final doc = CosDocument.open(buildClassicPdf());
        final device = RecordingDevice();
        PdfInterpreter(cos: doc, device: device).run(
          ContentStreamParser.parse(Uint8List.fromList(
              'BT /T3 10 Tf 100 200 Td 0 0 1 rg (X) Tj ET'.codeUnits)),
          CosDictionary({
            'Font': CosDictionary({'T3': type3(proc)}),
          }),
        );
        return device.fills.single.$2;
      }

      // d1: the inner red rg is ignored -> the glyph keeps the blue text fill.
      expect(glyphFill('0 0 0 0 100 100 d1 1 0 0 rg 0 0 100 100 re f'),
          const PdfColor(0, 0, 1));
      // Control: d0 imposes no colour rule, so the inner red rg wins.
      expect(glyphFill('1000 0 d0 1 0 0 rg 0 0 100 100 re f'),
          const PdfColor(1, 0, 0));
    });

    test('TJ adjustments shift subsequent runs', () {
      final doc = PdfDocument.open(buildClassicPdf());
      final device = RecordingDevice();
      final page = doc.page(0);
      PdfInterpreter(cos: doc.cos, device: device).run(
        ContentStreamParser.parse(
            Uint8List.fromList('BT /F1 10 Tf [(A) -500 (B)] TJ ET'.codeUnits)),
        page.resources,
      );
      expect(device.texts, hasLength(2));
      expect(device.texts[0].transform.e, 0);
      // A advances 667/1000 em * 10 = 6.67; adjustment -500/1000 * 10 = 5
      expect(device.texts[1].transform.e, closeTo(11.67, 1e-9));
    });

    test('invisible text (Tr 3) is emitted flagged, and advances', () {
      final doc = PdfDocument.open(buildClassicPdf());
      final device = RecordingDevice();
      final page = doc.page(0);
      PdfInterpreter(cos: doc.cos, device: device).run(
        ContentStreamParser.parse(Uint8List.fromList(
            'BT /F1 10 Tf 3 Tr (ghost) Tj 0 Tr (real) Tj ET'.codeUnits)),
        page.resources,
      );
      // the ghost run still reaches the device - it is the text layer of
      // OCR'd scans, so extraction/selection must see it - but flagged so
      // painting devices skip it
      expect(device.texts, hasLength(2));
      expect(device.texts[0].text, 'ghost');
      expect(device.texts[0].invisible, isTrue);
      final run = device.texts[1];
      expect(run.text, 'real');
      expect(run.invisible, isFalse);
      // advanced past the ghost glyphs at Helvetica AFM widths
      expect(run.transform.e, closeTo(24.46, 1e-9));
    });
  });

  group('lenient real-world behavior (pdf.js corpus classes)', () {
    test(
        'an unresolvable font substitutes Helvetica instead of dropping '
        'the text', () {
      // pdf.js issue4461 class: a page with no /Resources still shows
      // its text - and keeps it selectable
      final doc = CosDocument.open(buildClassicPdf());
      final device = RecordingDevice();
      PdfInterpreter(cos: doc, device: device).run(
        ContentStreamParser.parse(Uint8List.fromList(
            'BT /Nope 12 Tf 10 10 Td (still visible) Tj ET'.codeUnits)),
        CosDictionary(),
      );
      final run = device.texts.single;
      expect(run.text, 'still visible');
      expect(run.fontName, 'Helvetica');
      expect(run.width, greaterThan(0));
    });

    test('a function-based (type 1) shading paints through sh', () {
      const program = '{ pop dup dup }';
      final resources = CosDictionary({
        'Shading': CosDictionary({
          'S1': CosDictionary({
            'ShadingType': const CosInteger(1),
            'ColorSpace': const CosName('DeviceRGB'),
            'Function': CosStream(
              CosDictionary({
                'FunctionType': const CosInteger(4),
                'Domain': CosArray([
                  const CosInteger(0),
                  const CosInteger(1),
                  const CosInteger(0),
                  const CosInteger(1),
                ]),
                'Range': CosArray([
                  for (var i = 0; i < 3; i++) ...[
                    const CosInteger(0),
                    const CosInteger(1),
                  ],
                ]),
                'Length': CosInteger(program.length),
              }),
              Uint8List.fromList(program.codeUnits),
            ),
          }),
        }),
      });
      final doc = CosDocument.open(buildClassicPdf());
      final device = RecordingDevice();
      PdfInterpreter(cos: doc, device: device).run(
        ContentStreamParser.parse(Uint8List.fromList('/S1 sh'.codeUnits)),
        resources,
      );
      expect(device.meshes, hasLength(1));
      expect(device.meshes.single.vertices, isNotEmpty);
    });
  });

  group('patterns', () {
    CosDictionary shadingPatternResources() => CosDictionary({
          'Pattern': CosDictionary({
            'P0': CosDictionary({
              'PatternType': const CosInteger(2),
              'Shading': CosDictionary({
                'ShadingType': const CosInteger(2),
                'ColorSpace': const CosName('DeviceRGB'),
                'Coords': CosArray([
                  const CosInteger(0),
                  const CosInteger(0),
                  const CosInteger(10),
                  const CosInteger(0),
                ]),
                'Function': CosDictionary({
                  'FunctionType': const CosInteger(2),
                  'C0': CosArray([
                    const CosInteger(1),
                    const CosInteger(0),
                    const CosInteger(0),
                  ]),
                  'C1': CosArray([
                    const CosInteger(0),
                    const CosInteger(0),
                    const CosInteger(1),
                  ]),
                  'N': const CosInteger(1),
                }),
              }),
            }),
          }),
        });

    test('shading pattern fills become gradients, not solid color', () {
      final doc = CosDocument.open(buildClassicPdf());
      final device = RecordingDevice();
      PdfInterpreter(cos: doc, device: device).run(
        ContentStreamParser.parse(Uint8List.fromList(
            '0 0 0 rg /Pattern cs /P0 scn 0 0 10 10 re f'.codeUnits)),
        shadingPatternResources(),
      );
      // regression: this used to paint solid black (the last set color)
      expect(device.fills, isEmpty);
      expect(device.gradients, hasLength(1));
      final gradient = device.gradients.single.$2;
      expect(gradient.colors.first, const PdfColor(1, 0, 0));
    });

    test('shading pattern text carries the resolved gradient', () {
      final doc = CosDocument.open(buildClassicPdf());
      final device = RecordingDevice();
      PdfInterpreter(cos: doc, device: device).run(
        ContentStreamParser.parse(Uint8List.fromList(
            '/Pattern cs /P0 scn BT /Missing 12 Tf (gradient) Tj ET'
                .codeUnits)),
        shadingPatternResources(),
      );
      final gradient = device.texts.single.gradient;
      expect(gradient, isNotNull);
      expect(gradient!.colors.first, const PdfColor(1, 0, 0));
    });

    test('direct fill color clears the active pattern for text', () {
      final doc = CosDocument.open(buildClassicPdf());
      final device = RecordingDevice();
      PdfInterpreter(cos: doc, device: device).run(
        ContentStreamParser.parse(Uint8List.fromList(
            '/Pattern cs /P0 scn BT /Missing 12 Tf (gradient) Tj ET '
                    '0 0 0 rg BT /Missing 12 Tf (black) Tj ET'
                .codeUnits)),
        shadingPatternResources(),
      );
      expect(device.texts[0].gradient, isNotNull);
      expect(device.texts[1].gradient, isNull);
      expect(device.texts[1].color, PdfColor.black);
    });

    test('substituted text honours stroke render modes', () {
      // A substituted (non-embedded) font is drawn by filling a system font,
      // so the device needs the stroke colour to outline glyphs for modes
      // 1/2/5/6. /Missing resolves to the Helvetica fallback (no outlines).
      final doc = CosDocument.open(buildClassicPdf());
      final device = RecordingDevice();
      PdfInterpreter(cos: doc, device: device).run(
        ContentStreamParser.parse(Uint8List.fromList(
            ('1 0 0 RG 0 0 1 rg '
                    'BT /Missing 12 Tf 2 Tr (fs) Tj ET '
                    'BT /Missing 12 Tf 1 Tr (so) Tj ET '
                    'BT /Missing 12 Tf 0 Tr (fo) Tj ET')
                .codeUnits)),
        shadingPatternResources(),
      );
      // mode 2: fill (blue) + stroke (red)
      expect(device.texts[0].fill, isTrue);
      expect(device.texts[0].color, const PdfColor(0, 0, 1));
      expect(device.texts[0].strokeColor, const PdfColor(1, 0, 0));
      // mode 1: stroke only, no fill
      expect(device.texts[1].fill, isFalse);
      expect(device.texts[1].strokeColor, const PdfColor(1, 0, 0));
      // mode 0: fill only, no stroke
      expect(device.texts[2].fill, isTrue);
      expect(device.texts[2].strokeColor, isNull);
    });

    test('substituted fill+stroke text fills a tiling pattern with its '
        'representative colour', () {
      // /Pattern cs /P1 scn sets a tiling-pattern fill that can't be clipped
      // through a substituted font's (absent) outlines. We fall back to the
      // cell's fill colour (magenta) as a solid approximation rather than
      // dropping the fill, so the glyphs read in the pattern's colour with the
      // stroke on top.
      final doc = CosDocument.open(buildClassicPdf());
      final device = RecordingDevice();
      const cell = '1 0 1 rg 0 0 1 1 re f';
      // No /Font entry needed - /Missing resolves to the Helvetica fallback.
      final resources = CosDictionary({
        'Pattern': CosDictionary({
          'P1': CosStream(
            CosDictionary({
              'PatternType': const CosInteger(1),
              'PaintType': const CosInteger(1),
              'BBox': CosArray([
                const CosInteger(0),
                const CosInteger(0),
                const CosInteger(4),
                const CosInteger(4),
              ]),
              'XStep': const CosInteger(4),
              'YStep': const CosInteger(4),
              'Length': CosInteger(cell.length),
            }),
            Uint8List.fromList(cell.codeUnits),
          ),
        }),
      });
      PdfInterpreter(cos: doc, device: device).run(
        ContentStreamParser.parse(Uint8List.fromList(
            ('0 0 1 RG /Pattern cs /P1 scn '
                    'BT /Missing 12 Tf 2 Tr (x) Tj ET')
                .codeUnits)),
        resources,
      );
      final run = device.texts.single;
      expect(run.fill, isTrue, reason: 'tiling fill approximated as a solid');
      expect(run.color, const PdfColor(1, 0, 1), reason: 'the cell fill colour');
      expect(run.strokeColor, const PdfColor(0, 0, 1));
    });

    test('tiling patterns run their cell content per tile, clipped', () {
      final doc = CosDocument.open(buildClassicPdf());
      final device = RecordingDevice();
      const cell = '1 0 0 rg 0 0 1 1 re f';
      final resources = CosDictionary({
        'Pattern': CosDictionary({
          'P1': CosStream(
            CosDictionary({
              'PatternType': const CosInteger(1),
              'PaintType': const CosInteger(1),
              'BBox': CosArray([
                const CosInteger(0),
                const CosInteger(0),
                const CosInteger(4),
                const CosInteger(4),
              ]),
              'XStep': const CosInteger(4),
              'YStep': const CosInteger(4),
              'Length': CosInteger(cell.length),
            }),
            Uint8List.fromList(cell.codeUnits),
          ),
        }),
      });
      PdfInterpreter(cos: doc, device: device).run(
        ContentStreamParser.parse(
            Uint8List.fromList('/Pattern cs /P1 scn 0 0 8 8 re f'.codeUnits)),
        resources,
      );
      expect(device.clips, isNotEmpty);
      // 8x8 area on a 4pt grid: at least 4 cells painted in the cell color
      expect(device.fills.length, greaterThanOrEqualTo(4));
      expect(device.fills.first.$2, const PdfColor(1, 0, 0));
    });

    test('tiling pattern fills text through the glyph outlines', () {
      // Embedded TrueType 'A' filled with a red tiling pattern: the pattern
      // must paint through the glyph outlines (clip + per-tile fill) and the
      // text run must be emitted invisibly so it stays selectable without the
      // solid fill colour showing through (issue4246 sibling - pattern text).
      final doc = CosDocument.open(buildEmbeddedFontPdf());
      final device = RecordingDevice();
      const cell = '1 0 0 rg 0 0 1 1 re f';
      final resources = CosDictionary({
        'Font': CosDictionary({'F1': const CosReference(5, 0)}),
        'Pattern': CosDictionary({
          'P1': CosStream(
            CosDictionary({
              'PatternType': const CosInteger(1),
              'PaintType': const CosInteger(1),
              'BBox': CosArray([
                const CosInteger(0),
                const CosInteger(0),
                const CosInteger(4),
                const CosInteger(4),
              ]),
              'XStep': const CosInteger(4),
              'YStep': const CosInteger(4),
              'Length': CosInteger(cell.length),
            }),
            Uint8List.fromList(cell.codeUnits),
          ),
        }),
      });
      PdfInterpreter(cos: doc, device: device).run(
        ContentStreamParser.parse(Uint8List.fromList(
            '/Pattern cs /P1 scn BT /F1 24 Tf 72 700 Td (A) Tj ET'.codeUnits)),
        resources,
      );
      // the glyph outline became a clip and the cell painted inside it
      expect(device.clips, isNotEmpty);
      expect(device.fills.any((f) => f.$2 == const PdfColor(1, 0, 0)), isTrue);
      // the text is still emitted (selectable) but not painted as a solid glyph
      expect(device.texts.single.invisible, isTrue);
      expect(device.texts.single.text, 'A');
    });

    test('sh paints a gradient across the page area', () {
      final doc = CosDocument.open(buildClassicPdf());
      final device = RecordingDevice();
      final pattern = (shadingPatternResources()['Pattern']
          as CosDictionary)['P0'] as CosDictionary;
      final resources = CosDictionary({
        'Shading': CosDictionary({'S0': pattern['Shading']!}),
      });
      PdfInterpreter(cos: doc, device: device).run(
        ContentStreamParser.parse(Uint8List.fromList('/S0 sh'.codeUnits)),
        resources,
      );
      expect(device.gradients, hasLength(1));
    });

    // A radial shading whose circles are not nested (r0=0 focal point d=90
    // outside the r1=60 circle): a device radial gradient can't express it,
    // so the interpreter must fall through to a cone mesh instead.
    CosDictionary radialPatternResources() => CosDictionary({
          'Pattern': CosDictionary({
            'P0': CosDictionary({
              'PatternType': const CosInteger(2),
              'Shading': CosDictionary({
                'ShadingType': const CosInteger(3),
                'ColorSpace': const CosName('DeviceRGB'),
                'Coords': CosArray([
                  const CosInteger(521),
                  const CosInteger(289),
                  const CosInteger(0),
                  const CosInteger(431),
                  const CosInteger(289),
                  const CosInteger(60),
                ]),
                'Extend': CosArray([
                  const CosBoolean(false),
                  const CosBoolean(true),
                ]),
                'Function': CosDictionary({
                  'FunctionType': const CosInteger(2),
                  'C0': CosArray([
                    const CosInteger(1),
                    const CosInteger(0),
                    const CosInteger(0),
                  ]),
                  'C1': CosArray([
                    const CosInteger(0),
                    const CosInteger(0),
                    const CosInteger(1),
                  ]),
                  'N': const CosInteger(1),
                }),
              }),
            }),
          }),
        });

    test('non-nested radial pattern fill clips a cone mesh, not a gradient',
        () {
      final doc = CosDocument.open(buildClassicPdf());
      final device = RecordingDevice();
      PdfInterpreter(cos: doc, device: device).run(
        ContentStreamParser.parse(Uint8List.fromList(
            '/Pattern cs /P0 scn 400 250 130 80 re f'.codeUnits)),
        radialPatternResources(),
      );
      expect(device.gradients, isEmpty);
      expect(device.meshes, hasLength(1));
      expect(device.meshes.single.vertices, isNotEmpty);
      // clipped to the fill path: save/clip/mesh/restore, in that order
      expect(device.calls, containsAllInOrder(['save', 'clip', 'mesh', 'restore']));
    });

    test('non-nested radial sh paints a cone mesh', () {
      final doc = CosDocument.open(buildClassicPdf());
      final device = RecordingDevice();
      final pattern =
          (radialPatternResources()['Pattern'] as CosDictionary)['P0']
              as CosDictionary;
      final resources = CosDictionary({
        'Shading': CosDictionary({'S0': pattern['Shading']!}),
      });
      PdfInterpreter(cos: doc, device: device).run(
        ContentStreamParser.parse(Uint8List.fromList('/S0 sh'.codeUnits)),
        resources,
      );
      expect(device.gradients, isEmpty);
      expect(device.meshes, hasLength(1));
    });
  });

  group('soft masks and blend modes', () {
    CosDictionary maskResources({String type = 'Luminosity'}) {
      const maskContent = '1 g 0 0 50 100 re f';
      return CosDictionary({
        'ExtGState': CosDictionary({
          'GS1': CosDictionary({
            'SMask': CosDictionary({
              'Type': const CosName('Mask'),
              'S': CosName(type),
              'G': CosStream(
                CosDictionary({
                  'Subtype': const CosName('Form'),
                  'BBox': CosArray([
                    const CosInteger(0),
                    const CosInteger(0),
                    const CosInteger(100),
                    const CosInteger(100),
                  ]),
                  'Length': CosInteger(maskContent.length),
                }),
                Uint8List.fromList(maskContent.codeUnits),
              ),
            }),
          }),
        }),
      });
    }

    test('q /gs ... Q wraps content in a masked group', () {
      final doc = CosDocument.open(buildClassicPdf());
      final device = RecordingDevice();
      PdfInterpreter(cos: doc, device: device).run(
        ContentStreamParser.parse(Uint8List.fromList(
            'q /GS1 gs 0 0 100 100 re f Q 0 0 1 1 re f'.codeUnits)),
        maskResources(),
      );
      expect(
        device.calls.where((c) => c.contains('SoftMasked')),
        ['beginSoftMasked', 'endSoftMasked'],
      );
      // begin before the masked fill, end before the unmasked one
      expect(device.calls.indexOf('beginSoftMasked'),
          lessThan(device.calls.indexOf('fill')));
      final (luminosity, drawMask) = device.softMaskEnds.single;
      expect(luminosity, isTrue);
      // the mask painter emits the mask group's content
      final fillsBefore = device.fills.length;
      drawMask();
      expect(device.fills.length, greaterThan(fillsBefore));
    });

    test('alpha masks report luminosity=false', () {
      final doc = CosDocument.open(buildClassicPdf());
      final device = RecordingDevice();
      PdfInterpreter(cos: doc, device: device).run(
        ContentStreamParser.parse(
            Uint8List.fromList('q /GS1 gs 0 0 9 9 re f Q'.codeUnits)),
        maskResources(type: 'Alpha'),
      );
      expect(device.softMaskEnds.single.$1, isFalse);
    });

    test('blend modes reach the device and restore on Q', () {
      final doc = CosDocument.open(buildClassicPdf());
      final device = RecordingDevice();
      final resources = CosDictionary({
        'ExtGState': CosDictionary({
          'GS1': CosDictionary({'BM': const CosName('Multiply')}),
        }),
      });
      PdfInterpreter(cos: doc, device: device).run(
        ContentStreamParser.parse(Uint8List.fromList(
            'q /GS1 gs 0 0 9 9 re f Q 0 0 9 9 re f'.codeUnits)),
        resources,
      );
      expect(device.blendModes, [PdfBlendMode.multiply, PdfBlendMode.normal]);
    });
  });

  test('image XObjects reach the device with the CTM', () {
    final doc = CosDocument.open(buildClassicPdf());
    final device = RecordingDevice();
    final image = CosStream(
      CosDictionary({
        'Subtype': const CosName('Image'),
        'Width': const CosInteger(1),
        'Height': const CosInteger(1),
      }),
      Uint8List.fromList([0]),
    );
    final resources = CosDictionary({
      'XObject': CosDictionary({'Im0': image}),
    });
    PdfInterpreter(cos: doc, device: device).run(
      ContentStreamParser.parse(
          Uint8List.fromList('q 100 0 0 50 20 30 cm /Im0 Do Q'.codeUnits)),
      resources,
    );
    final request = device.images.single;
    expect(request.stream, same(image));
    expect(request.transform.a, 100);
    expect(request.transform.d, 50);
    expect(request.transform.e, 20);
    expect(request.transform.f, 30);
  });

  test('form XObjects run with their matrix and clipped bbox', () {
    final doc = CosDocument.open(buildClassicPdf());
    final device = RecordingDevice();
    final form = CosStream(
      CosDictionary({
        'Subtype': const CosName('Form'),
        'BBox': CosArray([
          const CosInteger(0),
          const CosInteger(0),
          const CosInteger(10),
          const CosInteger(10),
        ]),
        'Matrix': CosArray([
          const CosInteger(2),
          const CosInteger(0),
          const CosInteger(0),
          const CosInteger(2),
          const CosInteger(0),
          const CosInteger(0),
        ]),
        'Length': CosInteger('0 0 4 4 re f'.length),
      }),
      Uint8List.fromList('0 0 4 4 re f'.codeUnits),
    );
    final resources = CosDictionary({
      'XObject': CosDictionary({'Fm0': form}),
    });
    PdfInterpreter(cos: doc, device: device).run(
      ContentStreamParser.parse(
          Uint8List.fromList('q 1 0 0 1 100 0 cm /Fm0 Do Q'.codeUnits)),
      resources,
    );
    // bbox clip arrives, then the inner fill, doubly transformed
    expect(device.calls, contains('clip'));
    final fill = device.fills.single;
    final corner = fill.$1.segments[2] as PdfLineTo;
    expect(corner.x, 108); // 2*4 + 100
    expect(corner.y, 8);
  });

  test('a knockout group (/K true) opens a knockout layer at full alpha', () {
    // §11.4.5: a knockout group needs its own compositing layer even when it
    // paints at alpha 1, so each element can replace (not blend over) the
    // ones before it. Without /K the same group at alpha 1 stays unwrapped.
    const content = '1 0 0 rg 0 0 60 60 re f 0 0 1 rg 30 30 60 60 re f';
    CosStream group(bool knockout) => CosStream(
          CosDictionary({
            'Subtype': const CosName('Form'),
            'BBox': CosArray(const [
              CosInteger(0),
              CosInteger(0),
              CosInteger(100),
              CosInteger(100),
            ]),
            'Group': CosDictionary({
              'Type': const CosName('Group'),
              'S': const CosName('Transparency'),
              if (knockout) 'K': const CosBoolean(true),
            }),
            'Length': CosInteger(content.length),
          }),
          Uint8List.fromList(content.codeUnits),
        );
    final doc = CosDocument.open(buildClassicPdf());

    final ko = RecordingDevice();
    PdfInterpreter(cos: doc, device: ko).run(
      ContentStreamParser.parse(Uint8List.fromList('/Fm0 Do'.codeUnits)),
      CosDictionary({
        'XObject': CosDictionary({'Fm0': group(true)}),
      }),
    );
    expect(ko.calls, contains('beginGroup(1.0 knockout)'));
    expect(ko.calls, contains('endGroup'));

    final plain = RecordingDevice();
    PdfInterpreter(cos: doc, device: plain).run(
      ContentStreamParser.parse(Uint8List.fromList('/Fm0 Do'.codeUnits)),
      CosDictionary({
        'XObject': CosDictionary({'Fm0': group(false)}),
      }),
    );
    expect(plain.calls.where((c) => c.startsWith('beginGroup')), isEmpty);
  });

  group('annotation appearances', () {
    // page-space bounding box of a recorded fill
    (double, double, double, double) boundsOf(PdfPath path) {
      var minX = double.infinity, minY = double.infinity;
      var maxX = double.negativeInfinity, maxY = double.negativeInfinity;
      for (final segment in path.segments) {
        if (segment
            case PdfMoveTo(:final x, :final y) ||
                PdfLineTo(:final x, :final y)) {
          if (x < minX) minX = x;
          if (y < minY) minY = y;
          if (x > maxX) maxX = x;
          if (y > maxY) maxY = y;
        }
      }
      return (minX, minY, maxX, maxY);
    }

    RecordingDevice drawAnnotations() {
      final doc = PdfDocument.open(buildAppearanceAnnotationsPdf());
      final device = RecordingDevice();
      PdfInterpreter(cos: doc.cos, device: device)
        ..drawPage(doc.page(0))
        ..drawAnnotations(doc.page(0));
      return device;
    }

    test('appearances draw after content; hidden and Popup are skipped', () {
      final device = drawAnnotations();
      // blue page content + green square + red stamp + gray checkbox;
      // the magenta hidden and yellow popup appearances never paint
      expect(device.fills.map((f) => f.$2), [
        const PdfColor(0, 0, 1),
        const PdfColor(0, 1, 0),
        const PdfColor(1, 0, 0),
        const PdfColor.gray(0.5),
      ]);
    });

    test('BBox is scaled onto the annotation Rect', () {
      final device = drawAnnotations();
      final green =
          device.fills.firstWhere((f) => f.$2 == const PdfColor(0, 1, 0));
      expect(boundsOf(green.$1), (100, 100, 200, 150));
    });

    test('appearance /Matrix rotates, then the result maps onto Rect', () {
      final device = drawAnnotations();
      final red =
          device.fills.firstWhere((f) => f.$2 == const PdfColor(1, 0, 0));
      expect(boundsOf(red.$1), (300, 100, 350, 200));
    });

    test('/AS selects the appearance state', () {
      final device = drawAnnotations();
      final gray =
          device.fills.firstWhere((f) => f.$2 == const PdfColor.gray(0.5));
      expect(boundsOf(gray.$1), (400, 100, 420, 120));
    });

    test('each appearance clips to its BBox', () {
      final doc = PdfDocument.open(buildAppearanceAnnotationsPdf());
      final device = RecordingDevice();
      PdfInterpreter(cos: doc.cos, device: device).drawAnnotations(doc.page(0));
      // three drawn appearances, one BBox clip each
      expect(device.clips, hasLength(3));
      expect(boundsOf(device.clips.first.$1), (100, 100, 200, 150));
    });

    test('fallback highlights use multiply so text remains visible', () {
      final doc = PdfDocument.open(buildClassicPdf());
      final annotation = PdfAnnotation.fromDict(
        doc,
        CosDictionary({
          'Subtype': const CosName('Highlight'),
          'Rect': CosArray([
            const CosInteger(10),
            const CosInteger(20),
            const CosInteger(110),
            const CosInteger(40),
          ]),
          'QuadPoints': CosArray([
            const CosInteger(10),
            const CosInteger(40),
            const CosInteger(110),
            const CosInteger(40),
            const CosInteger(10),
            const CosInteger(20),
            const CosInteger(110),
            const CosInteger(20),
          ]),
          'C': CosArray([
            const CosInteger(1),
            const CosInteger(1),
            const CosInteger(0),
          ]),
        }),
      );
      final device = RecordingDevice();
      PdfInterpreter(cos: doc.cos, device: device)
          .drawAnnotation(doc.page(0), annotation);

      expect(device.blendModes, [PdfBlendMode.multiply, PdfBlendMode.normal]);
      expect(device.fills.single.$2, const PdfColor(1, 1, 0));
    });

    test('fallback text widgets draw their field value', () {
      final doc = PdfDocument.open(buildClassicPdf());
      final annotation = PdfAnnotation.fromDict(
        doc,
        CosDictionary({
          'Subtype': const CosName('Widget'),
          'FT': const CosName('Tx'),
          'Rect': CosArray([
            const CosInteger(20),
            const CosInteger(100),
            const CosInteger(170),
            const CosInteger(122),
          ]),
          'DA': CosString.fromText('/Helv 12 Tf 0 g'),
          'V': CosString.fromText('tx annotation'),
        }),
      );
      final device = RecordingDevice();
      PdfInterpreter(cos: doc.cos, device: device)
          .drawAnnotation(doc.page(0), annotation);

      expect(device.texts.single.text, 'tx annotation');
      expect(device.texts.single.fontName, 'Helvetica');
      expect(device.texts.single.fontSize, 12);
      expect(device.texts.single.transform.e, 22);
      expect(device.texts.single.transform.f, closeTo(106.692, 1e-3));
      expect(device.clips, hasLength(1));
    });

    RecordingDevice drawFallback(CosDictionary dict) {
      final doc = PdfDocument.open(buildClassicPdf());
      final device = RecordingDevice();
      PdfInterpreter(cos: doc.cos, device: device)
          .drawAnnotation(doc.page(0), PdfAnnotation.fromDict(doc, dict));
      return device;
    }

    test('fallback Polygon closes and fills from /Vertices and /IC', () {
      final device = drawFallback(CosDictionary({
        'Subtype': const CosName('Polygon'),
        'Rect': CosArray([for (final v in [10, 10, 60, 60]) CosInteger(v)]),
        'Vertices': CosArray(
            [for (final v in [10, 10, 60, 10, 35, 60]) CosInteger(v)]),
        'C': CosArray([const CosInteger(0), const CosInteger(0), const CosInteger(0)]),
        'IC': CosArray([const CosInteger(1), const CosInteger(0), const CosInteger(0)]),
      }));
      // one interior fill (red) plus the stroked outline
      expect(device.fills.single.$2, const PdfColor(1, 0, 0));
      final outline = device.strokes.single.$1;
      expect(outline.segments.last, isA<PdfClosePath>());
    });

    test('fallback PolyLine strokes an open path from /Vertices', () {
      final device = drawFallback(CosDictionary({
        'Subtype': const CosName('PolyLine'),
        'Rect': CosArray([for (final v in [10, 10, 60, 60]) CosInteger(v)]),
        'Vertices': CosArray(
            [for (final v in [10, 10, 60, 10, 35, 60]) CosInteger(v)]),
      }));
      expect(device.fills, isEmpty); // open: no interior
      final path = device.strokes.single.$1;
      expect(path.segments.any((s) => s is PdfClosePath), isFalse);
    });

    test('fallback Link draws its border only with a colour and width', () {
      // no /C: nothing painted (the common invisible-link case)
      expect(
          drawFallback(CosDictionary({
            'Subtype': const CosName('Link'),
            'Rect': CosArray([for (final v in [10, 10, 60, 30]) CosInteger(v)]),
            'Border': CosArray(
                [const CosInteger(0), const CosInteger(0), const CosInteger(1)]),
          })).strokes,
          isEmpty);
      // /C plus a positive border width -> a stroked rectangle
      final device = drawFallback(CosDictionary({
        'Subtype': const CosName('Link'),
        'Rect': CosArray([for (final v in [10, 10, 60, 30]) CosInteger(v)]),
        'Border': CosArray(
            [const CosInteger(0), const CosInteger(0), const CosInteger(2)]),
        'C': CosArray([const CosInteger(0), const CosInteger(0), const CosInteger(1)]),
      }));
      expect(device.strokes.single.$2, const PdfColor(0, 0, 1));
    });

    test('fallback FreeText draws /Contents lines through /DA, clipped', () {
      final device = drawFallback(CosDictionary({
        'Subtype': const CosName('FreeText'),
        'Rect': CosArray([for (final v in [50, 500, 250, 560]) CosInteger(v)]),
        'DA': CosString.fromText('/Helv 10 Tf 1 0 0 rg'),
        'Contents': CosString.fromText('line one\nline two'),
      }));
      expect(device.texts.map((t) => t.text), ['line one', 'line two']);
      expect(device.texts.first.color, const PdfColor(1, 0, 0));
      expect(device.clips, hasLength(1));
    });

    test('fallback third-party callout infers /CL without /IT', () {
      final doc = PdfDocument.open(buildClassicPdf());
      final annotation = PdfAnnotation.fromDict(doc, CosDictionary({
        'Subtype': const CosName('FreeText'),
        'Rect': CosArray([for (final v in [20, 400, 250, 560]) CosInteger(v)]),
        'CL': CosArray([for (final v in [20, 400, 100, 500]) CosInteger(v)]),
        'RD': CosArray([for (final v in [80, 0, 0, 0]) CosInteger(v)]),
        'BS': CosDictionary({'W': const CosInteger(2)}),
        'DA': CosString.fromText('/Helv 10 Tf 0 0 1 rg 1 0 0 RG'),
        'C': CosArray([const CosInteger(1), const CosInteger(1), const CosInteger(0)]),
        'Contents': CosString.fromText(
            'wrapped third party callout text that must continue on another line'),
      }));
      final device = RecordingDevice();
      PdfInterpreter(cos: doc.cos, device: device)
          .drawAnnotation(doc.page(0), annotation);

      expect(annotation.isCallout, isTrue);
      expect(annotation.calloutBox!.left, 100);
      expect(device.fills.single.$2, const PdfColor(1, 1, 0));
      expect(device.strokes, hasLength(2), reason: 'box border and leader');
      expect(device.texts.length, greaterThan(1), reason: 'text wraps in box');
    });

    test('fallback FreeText honors right quadding', () {
      final device = drawFallback(CosDictionary({
        'Subtype': const CosName('FreeText'),
        'Rect': CosArray([for (final v in [50, 500, 250, 560]) CosInteger(v)]),
        'DA': CosString.fromText('/Helv 10 Tf 0 g'),
        'Q': const CosInteger(2),
        'Contents': CosString.fromText('right'),
      }));
      expect(device.texts.single.transform.e, greaterThan(200));
    });

    test('fallback checkbox widget marks an on /AS with no /AP', () {
      final on = drawFallback(CosDictionary({
        'Subtype': const CosName('Widget'),
        'FT': const CosName('Btn'),
        'Rect': CosArray([for (final v in [72, 540, 92, 560]) CosInteger(v)]),
        'AS': const CosName('Yes'),
        'MK': CosDictionary({
          'BC': CosArray([const CosInteger(0)]),
        }),
      }));
      // border stroke + the check-mark stroke
      expect(on.strokes, hasLength(2));

      final off = drawFallback(CosDictionary({
        'Subtype': const CosName('Widget'),
        'FT': const CosName('Btn'),
        'Rect': CosArray([for (final v in [72, 540, 92, 560]) CosInteger(v)]),
        'AS': const CosName('Off'),
        'MK': CosDictionary({
          'BC': CosArray([const CosInteger(0)]),
        }),
      }));
      // border only, no mark
      expect(off.strokes, hasLength(1));
    });

    test('fallback pushbutton widget draws its /MK caption', () {
      final device = drawFallback(CosDictionary({
        'Subtype': const CosName('Widget'),
        'FT': const CosName('Btn'),
        'Ff': const CosInteger(65536), // pushbutton
        'Rect': CosArray([for (final v in [72, 540, 172, 560]) CosInteger(v)]),
        'DA': CosString.fromText('/Helv 12 Tf 0 g'),
        'MK': CosDictionary({
          'CA': CosString.fromText('Submit'),
        }),
      }));
      expect(device.texts.single.text, 'Submit');
    });
  });

  group('annotation print flags', () {
    // A page with three Square annotations, each an /AP filling a distinct
    // colour: red is Print (/F 4), green is Print+NoView (/F 36), blue has no
    // flags (/F 0). Screen shows red+blue (NoView hidden, Print ignored);
    // print shows red+green (only /Print, NoView prints).
    Uint8List flaggedPdf() {
      String form(String content) =>
          '<< /Type /XObject /Subtype /Form /BBox [0 0 10 10] '
          '/Length ${content.length} >>\nstream\n$content\nendstream';
      const annots = '/Annots [ '
          '<< /Type /Annot /Subtype /Square /Rect [10 10 20 20] /F 4 '
          '/AP << /N 5 0 R >> >> '
          '<< /Type /Annot /Subtype /Square /Rect [30 10 40 20] /F 36 '
          '/AP << /N 6 0 R >> >> '
          '<< /Type /Annot /Subtype /Square /Rect [50 10 60 20] /F 0 '
          '/AP << /N 7 0 R >> >> ]';
      final objects = <String>[
        '<< /Type /Catalog /Pages 2 0 R >>',
        '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
        '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] '
            '/Contents 4 0 R $annots >>',
        '<< /Length 0 >>\nstream\n\nendstream',
        form('1 0 0 rg 0 0 10 10 re f'),
        form('0 1 0 rg 0 0 10 10 re f'),
        form('0 0 1 rg 0 0 10 10 re f'),
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

    List<PdfColor> drawn({required bool forPrint}) {
      final doc = PdfDocument.open(flaggedPdf());
      final device = RecordingDevice();
      PdfInterpreter(cos: doc.cos, device: device)
          .drawAnnotations(doc.page(0), forPrint: forPrint);
      return [for (final f in device.fills) f.$2];
    }

    test('screen hides NoView and ignores the Print flag', () {
      // red (Print) + blue (no flags); green is NoView
      expect(drawn(forPrint: false),
          [const PdfColor(1, 0, 0), const PdfColor(0, 0, 1)]);
    });

    test('print keeps only Print annotations, including NoView ones', () {
      // red (Print) + green (Print+NoView); blue lacks Print
      expect(drawn(forPrint: true),
          [const PdfColor(1, 0, 0), const PdfColor(0, 1, 0)]);
    });
  });

  group('cancellation', () {
    Uint8List heavyPdf() {
      final ops = StringBuffer();
      for (var i = 0; i < 200; i++) {
        ops.write('q 1 0 0 1 ${i % 10} ${i % 10} cm '
            '0 0 m 10 0 l 10 10 l 0 10 l h f Q\n');
      }
      final content = ops.toString();
      final objects = <String>[
        '<< /Type /Catalog /Pages 2 0 R >>',
        '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
        '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] '
            '/Contents 4 0 R >>',
        '<< /Length ${content.length} >>\nstream\n$content\nendstream',
      ];
      final buffer = StringBuffer('%PDF-1.4\n');
      final offsets = <int>[];
      for (var i = 0; i < objects.length; i++) {
        offsets.add(buffer.length);
        buffer.write('${i + 1} 0 obj\n${objects[i]}\nendobj\n');
      }
      final xref = buffer.length;
      buffer.write('xref\n0 ${objects.length + 1}\n0000000000 65535 f \n');
      for (final o in offsets) {
        buffer.write('${o.toString().padLeft(10, '0')} 00000 n \n');
      }
      buffer.write('trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\n'
          'startxref\n$xref\n%%EOF\n');
      return Uint8List.fromList(buffer.toString().codeUnits);
    }

    test('a cancelled token stops the walk early', () {
      final bytes = heavyPdf();
      final doc = PdfDocument.open(bytes);
      final page = doc.page(0);
      final ops = ContentStreamParser.parse(page.contentBytes());

      final token = PdfCancellationToken()..cancelled = true;
      final device = RecordingDevice();
      final interp = PdfInterpreter(
          cos: doc.cos, device: device, cancellation: token);
      expect(
        () => interp.drawPageOperations(page, ops),
        throwsA(isA<PdfCancelledException>()),
      );
      final cancelledCalls = device.calls.length;

      final fullDevice = RecordingDevice();
      PdfInterpreter(cos: doc.cos, device: fullDevice)
          .drawPageOperations(page, ops);
      expect(cancelledCalls, lessThan(fullDevice.calls.length),
          reason: 'a cancelled walk stops before the full walk');
    });

    test('drawPageOperationsAsync configurable chunk yields and checks token',
        () async {
      final bytes = heavyPdf();
      final doc = PdfDocument.open(bytes);
      final page = doc.page(0);
      final ops = ContentStreamParser.parse(page.contentBytes());

      final token = PdfCancellationToken();
      final device = RecordingDevice();
      final interp = PdfInterpreter(
          cos: doc.cos, device: device, cancellation: token);

      // Cancel after a micro-task so the async walk picks it up at a yield.
      Future<void>.delayed(Duration.zero).then((_) {
        token.cancelled = true;
      });

      await expectLater(
        interp.drawPageOperationsAsync(page, ops, yieldInterval: 1024),
        throwsA(isA<PdfCancelledException>()),
      );
    });

    test('drawPageContent streams the same device calls as a parsed list', () {
      final bytes = heavyPdf();
      final doc = PdfDocument.open(bytes);
      final page = doc.page(0);
      final content = page.contentBytes();

      final materialized = RecordingDevice();
      PdfInterpreter(cos: doc.cos, device: materialized).drawPageOperations(
        page,
        ContentStreamParser.parse(content),
      );
      final streaming = RecordingDevice();
      PdfInterpreter(cos: doc.cos, device: streaming)
          .drawPageContent(page, content);

      expect(streaming.calls, materialized.calls);
      expect(streaming.fills.length, materialized.fills.length);
      expect(streaming.strokes.length, materialized.strokes.length);
      expect(streaming.texts.length, materialized.texts.length);
      expect(streaming.images.length, materialized.images.length);
    });

    test('drawPageContentAsync can cancel while parsing and interpreting',
        () async {
      final bytes = heavyPdf();
      final doc = PdfDocument.open(bytes);
      final page = doc.page(0);
      final token = PdfCancellationToken();
      final device = RecordingDevice();
      final interpreter = PdfInterpreter(
        cos: doc.cos,
        device: device,
        cancellation: token,
      );

      Future<void>.delayed(Duration.zero).then((_) {
        token.cancelled = true;
      });

      await expectLater(
        interpreter.drawPageContentAsync(
          page,
          page.contentBytes(),
          yieldInterval: 1024,
        ),
        throwsA(isA<PdfCancelledException>()),
      );
    });

    test('no token means no cancellation overhead', () {
      final bytes = heavyPdf();
      final doc = PdfDocument.open(bytes);
      final page = doc.page(0);
      final ops = ContentStreamParser.parse(page.contentBytes());

      final device = RecordingDevice();
      PdfInterpreter(cos: doc.cos, device: device)
          .drawPageOperations(page, ops);
      expect(device.calls, isNotEmpty);
    });

    // The resumable walk (beginPageContent) is the primitive behind recording a
    // heavy page in visible increments and behind a cancelled record keeping
    // its work. drawPageContentAsync is implemented on top of it, so the whole
    // corpus already exercises the unbounded path; these pin the chunked one.
    group('resumable page walk', () {
      Future<List<String>> fullCalls(Uint8List bytes) async {
        final doc = PdfDocument.open(bytes);
        final page = doc.page(0);
        final device = RecordingDevice();
        await PdfInterpreter(cos: doc.cos, device: device)
            .drawPageContentAsync(page, page.contentBytes());
        return device.calls;
      }

      test('a chunked walk records exactly what one full walk records',
          () async {
        final bytes = heavyPdf();
        final expected = await fullCalls(bytes);

        final doc = PdfDocument.open(bytes);
        final page = doc.page(0);
        final device = RecordingDevice();
        final walk = PdfInterpreter(cos: doc.cos, device: device)
            .beginPageContent(page, page.contentBytes());
        var chunks = 0;
        while (!await walk.advance(operations: 100)) {
          chunks++;
          expect(chunks, lessThan(1000), reason: 'walk did not terminate');
        }
        expect(chunks, greaterThan(1),
            reason: 'the fixture must actually span several chunks');
        expect(walk.isComplete, isTrue);
        expect(walk.isFinished, isTrue);
        expect(device.calls, expected);
      });

      test('resuming continues rather than re-walking the prefix', () async {
        final bytes = heavyPdf();
        final doc = PdfDocument.open(bytes);
        final page = doc.page(0);
        final device = RecordingDevice();
        final walk = PdfInterpreter(cos: doc.cos, device: device)
            .beginPageContent(page, page.contentBytes());

        expect(await walk.advance(operations: 100), isFalse);
        final afterFirst = List<String>.from(device.calls);
        expect(afterFirst, isNotEmpty);

        await walk.advance(operations: 100);
        // The already-recorded calls must still be there, unchanged and not
        // duplicated: a restart would re-emit them from the top.
        expect(device.calls.length, greaterThan(afterFirst.length));
        expect(device.calls.sublist(0, afterFirst.length), afterFirst);
      });

      test('abandon releases the device exactly once and is idempotent',
          () async {
        final bytes = heavyPdf();
        final doc = PdfDocument.open(bytes);
        final page = doc.page(0);
        final device = RecordingDevice();
        final walk = PdfInterpreter(cos: doc.cos, device: device)
            .beginPageContent(page, page.contentBytes());
        await walk.advance(operations: 50);

        int restores() => device.calls.where((c) => c == 'restore').length;
        // Stopping mid-page can leave the *content's* own q unmatched by its Q
        // - inherent to not finishing, and the same thing a cancelled
        // drawPageContentAsync has always done. What must hold is that the walk
        // emits the single restore balancing beginPageContent's save.
        final before = restores();
        walk.abandon();
        expect(restores(), before + 1,
            reason: 'abandon must emit the one restore that balances '
                "beginPageContent's save");

        walk.abandon(); // idempotent: no second restore
        expect(restores(), before + 1);
        expect(walk.isFinished, isTrue);
        expect(walk.isComplete, isFalse);
      });

      test('advancing a finished walk is a no-op', () async {
        final bytes = heavyPdf();
        final doc = PdfDocument.open(bytes);
        final page = doc.page(0);
        final device = RecordingDevice();
        final walk = PdfInterpreter(cos: doc.cos, device: device)
            .beginPageContent(page, page.contentBytes());
        expect(await walk.advance(), isTrue); // unbounded: runs to completion
        final calls = List<String>.from(device.calls);

        expect(await walk.advance(operations: 100), isTrue);
        expect(device.calls, calls);
      });
    });
  });
}
