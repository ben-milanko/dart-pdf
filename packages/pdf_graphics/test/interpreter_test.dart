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
  final softMaskEnds = <(bool, void Function())>[];

  @override
  void setBlendMode(PdfBlendMode mode) {
    calls.add('blend:${mode.name}');
    blendModes.add(mode);
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
      // the ghost run still reaches the device — it is the text layer of
      // OCR'd scans, so extraction/selection must see it — but flagged so
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
      // its text — and keeps it selectable
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
      // No /Font entry needed — /Missing resolves to the Helvetica fallback.
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
      // solid fill colour showing through (issue4246 sibling — pattern text).
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
  });
}
