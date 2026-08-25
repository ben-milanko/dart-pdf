import 'dart:io';

import 'package:dart_pdf_editor_flutter_gpu/dart_pdf_editor_flutter_gpu.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_graphics/pdf_graphics.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';

void main() {
  late FlutterGpuTrueTypeFontFace face;
  late FlutterGpuTrueTypeTextOutliner outliner;

  setUp(() {
    face = FlutterGpuTrueTypeFontFace(buildTestTrueTypeFont());
    outliner = FlutterGpuTrueTypeTextOutliner((_) => face);
  });

  PdfTextRun run(
    String text,
    List<double> offsets, {
    double width = 1.6,
    String fontName = 'Helvetica',
  }) =>
      PdfTextRun(
        text: text,
        transform: const PdfMatrix(20, 0, 0, 20, 40, 80),
        color: PdfColor.black,
        width: width,
        fontName: fontName,
        fontSize: 20,
        charOffsets: offsets,
      );

  test('retains PDF origins and copy-fits glyph shapes uniformly', () {
    // Fixture natural advances are A=.6, B=1.0. Doubling the PDF advances
    // makes xScale=2 while the mapped page-space origins remain 40 and 64.
    final outlined =
        outliner.outline(run('AB', const [0, 1.2, 3.2], width: 3.2));
    expect(outlined, isNotNull);
    expect(outlined!.transform.a, 40);
    expect(outlined.width, 1.6);
    expect(outlined.charOffsets, const [0, 0.6, 1.6]);
    expect(outlined.glyphs, hasLength(2));
    expect(outlined.glyphs![0].offset, 0);
    expect(outlined.glyphs![1].offset, 0.6);
    expect(outlined.glyphs!.every((glyph) => glyph.outline != null), isTrue);

    final firstPageX = outlined.transform.transformX(
      outlined.glyphs![0].offset,
      0,
    );
    final secondPageX = outlined.transform.transformX(
      outlined.glyphs![1].offset,
      0,
    );
    expect(firstPageX, 40);
    expect(secondPageX, 64);
  });

  test('keeps whitespace as an empty placement at its PDF offset', () {
    final outlined = outliner.outline(
      run('A B', const [0, 0.6, 0.9, 1.9], width: 1.9),
    );
    expect(outlined, isNotNull);
    expect(outlined!.glyphs, hasLength(3));
    expect(outlined.glyphs![1].outline, isNull);
    expect(outlined.glyphs![1].text, ' ');
  });

  test('keeps default-ignorable controls as empty placements', () {
    final outlined = outliner.outline(
      run('A\u007fB\u0081', const [0, 0.6, 0.8, 1.8, 2.0], width: 2),
    );
    expect(outlined, isNotNull);
    expect(outlined!.glyphs, hasLength(4));
    expect(outlined.glyphs![1].outline, isNull);
    expect(outlined.glyphs![1].text, '\u007f');
    expect(outlined.glyphs![3].outline, isNull);
    expect(outlined.glyphs![3].text, '\u0081');

    final controlsOnly =
        outliner.outline(run('\u007f', const [0, 0.5], width: 0.5));
    expect(controlsOnly, isNotNull);
    expect(controlsOnly!.glyphs!.single.outline, isNull);
    expect(controlsOnly.transform, run('', const [0]).transform);
  });

  test('declines missing glyphs, malformed offsets, and complex shaping', () {
    expect(outliner.outline(run('AC', const [0, 0.6, 1.2])), isNull);
    expect(outliner.outline(run('AB', const [0, 0.6])), isNull);
    expect(outliner.outline(run('AB', const [0, 0.6, 1.6]).copyWithText('אב')),
        isNull);
  });

  test(
    'macOS system adapter resolves exact Latin and CJK faces',
    () {
      final system = FlutterGpuSystemTextOutliner.tryCreate();
      expect(system, isNotNull);
      for (final name in const [
        'Helvetica',
        'Helvetica-Bold',
        'Helvetica-Oblique',
        'Helvetica-BoldOblique',
      ]) {
        expect(
          system!.outline(
            run('AB', const [0, 0.6, 1.6], fontName: name),
          ),
          isNotNull,
          reason: name,
        );
      }
      expect(
        system!.outline(
          run(
            'AB',
            const [0, 0.6, 1.6],
            fontName: 'TeXGyreAdventor-Regular',
          ),
        ),
        isNull,
      );
      for (final (name, text) in const [
        ('ºÚÌå', '中文'),
        ('·ÂËÎ_GB2312', '中文'),
        ('HeiseiMin-W3', '日本'),
        ('MS-Gothic', '日本'),
      ]) {
        expect(
          system.outline(
            run(text, const [0, 0.8, 1.6], fontName: name),
          ),
          isNotNull,
          reason: name,
        );
      }
    },
    skip: !Platform.isMacOS,
  );
}

extension on PdfTextRun {
  PdfTextRun copyWithText(String value) => PdfTextRun(
        text: value,
        transform: transform,
        color: color,
        width: width,
        fontName: fontName,
        fontSize: fontSize,
        charOffsets: charOffsets,
      );
}
