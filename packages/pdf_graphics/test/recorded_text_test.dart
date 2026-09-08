import 'dart:typed_data';

import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:test/test.dart';

void main() {
  test('recorded page preserves advances, tagged text and rotated search quads',
      () {
    final document = _document('''
/Span << /MCID 7 >> BDC
BT /F1 24 Tf 2 Tc 12 Tw 72 720 Td (IIII WWWW) Tj ET
EMC
q 0 1 -1 0 300 400 cm
BT /F1 18 Tf 0 0 Td (Rotated text) Tj ET
Q
''');
    final recorded = _record(document);
    final extracted = _expectEquivalent(document, recorded);
    expect(extracted.runs.first.mcid, 7);
    expect(extracted.runs.first.charOffsets, hasLength(10));
    final matches = extracted.findAll('WWWW');
    expect(matches, hasLength(1));
    expect(
        matches.single.quads.single.corners,
        PdfTextExtractor.extract(document, 0)
            .findAll('WWWW')
            .single
            .quads
            .single
            .corners);
    final center = matches.single.rects.single;
    expect(
      extracted.positionNear(center.left + 1, center.bottom + 1),
      PdfTextExtractor.extract(document, 0)
          .positionNear(center.left + 1, center.bottom + 1),
    );
  });

  test('capture excludes masks and annotations but includes invisible sources',
      () {
    final document = _document('''
q /Masked gs
BT /F1 12 Tf 72 720 Td (Masked source) Tj ET
Q
BT /F1 12 Tf 72 680 Td 3 Tr (OCR text) Tj ET
BT /F1 12 Tf 72 640 Td 7 Tr (Clip text) Tj ET
''');
    final recorder = RecordingPdfDevice();
    final interpreter = PdfInterpreter(
        cos: document.cos, device: recorder, collectCharOffsets: true);
    interpreter.drawPage(document.page(0));
    expect(recorder.commands.whereType<PdfEndSoftMaskedCommand>(), isNotEmpty);
    final recorded = PdfRecordedText.capture(recorder.commands);
    interpreter.drawAnnotations(document.page(0));
    expect(
        recorder.commands
            .whereType<PdfDrawTextCommand>()
            .map((c) => c.run.text),
        contains('ANNOTATION_ONLY'));
    recorder.commands.clear();

    final extracted = _expectEquivalent(document, recorded);
    expect(extracted.text, 'Masked source\nOCR text\nClip text');
    expect(extracted.text, isNot(contains('MASK_ONLY')));
    expect(recorded.runs.where((run) => run.invisible), hasLength(2));
  });

  test('Type3 and text-bearing pattern cells match fresh extraction', () {
    final document = _document('''
BT /T3 24 Tf 72 720 Td (AA) Tj ET
q /Pattern cs /PatternText scn 80 80 30 30 re f Q
''');
    final recorder = RecordingPdfDevice();
    PdfInterpreter(
            cos: document.cos, device: recorder, collectCharOffsets: true)
        .drawPage(document.page(0));
    final cells = recorder.commands.whereType<PdfDrawTiledCellCommand>();
    expect(cells.length, greaterThanOrEqualTo(3));
    expect(cells.any((cell) => cell.originsX.length > 1), isTrue);
    final recorded = PdfRecordedText.capture(recorder.commands);
    final extracted = _expectEquivalent(document, recorded);
    expect(extracted.text, contains('TYPE3_TEXT'));
    expect(extracted.text, contains('PATTERN_TEXT'));
    expect(
        extracted.runs.where((run) => run.text == 'TYPE3_TEXT'), hasLength(2));
  });

  test('embedded RTL glyphs and positioned combining marks retain logical text',
      () {
    for (final bytes in [
      buildPositionedTashkilPdf(),
      buildRtlTextPdf(lines: const ['اهلا وسهلا', 'كيف حالك', 'خوش آمدید']),
    ]) {
      final document = PdfDocument.open(bytes);
      final recorded = _record(document);
      final extracted = _expectEquivalent(document, recorded);
      expect(extracted.text, isNotEmpty);
      expect(recorded.runs.any((run) => run.glyphs != null), isTrue);
      expect(extracted.runs.any((run) => run.isRightToLeft), isTrue);
    }
  });

  test('projection snapshots metrics, strips outlines and retains glyph kind',
      () {
    final offsets = <double>[0, 0.2, 0.8];
    final glyphs = <PdfGlyphPlacement>[
      PdfGlyphPlacement(
        offset: 0,
        offsetY: -0.3,
        text: 'fi',
        outline: PdfPath(const [PdfMoveTo(0, 0), PdfLineTo(100, 100)]),
      ),
    ];
    final commands = <PdfRenderCommand>[
      PdfDrawTextCommand(_run('fi', glyphs: glyphs, offsets: offsets)),
      PdfDrawTextCommand(_run('مرحبا', y: 40)),
      PdfDrawTextCommand(_run('', y: 80, glyphs: [])),
    ];
    final recorded = PdfRecordedText.capture(commands);
    offsets[1] = 999;
    glyphs.clear();
    commands.clear();

    final runs = recorded.runs.toList();
    expect(runs[0].charOffsets, [0, 0.2, 0.8]);
    expect(runs[0].glyphs!.single.text, 'fi');
    expect(runs[0].glyphs!.single.offsetY, -0.3);
    expect(runs[0].glyphs!.single.outline, isNull);
    expect(runs[0].mcid, 12);
    expect(runs[1].glyphs, isNull);
    expect(runs[2].glyphs, isEmpty);
    expect(
        PdfTextExtractor.fromRecordedText(recorded, 0).text, contains('مرحبا'));
    expect(() => runs[0].charOffsets![0] = 1, throwsUnsupportedError);
    expect(() => runs[0].glyphs!.clear(), throwsUnsupportedError);
  });

  test('nested cells retain exact translated positions and stay compact', () {
    final original = _run('Repeated', x: 1e16, y: 50);
    final innerX = Float64List.fromList([-1e16]);
    final outerX = Float64List.fromList([1, 5]);
    final leaf = <PdfRenderCommand>[PdfDrawTextCommand(original)];
    final commands = <PdfRenderCommand>[
      PdfDrawTiledCellCommand([
        PdfDrawTiledCellCommand(leaf, innerX, Float64List(1)),
      ], outerX, Float64List(2)),
    ];
    final reference = _TextDevice();
    replayCommands(commands, reference);
    final recorded = PdfRecordedText.capture(commands);
    final positions = recorded.runs.map((run) => run.transform.e).toList();
    expect(positions, [1, 5]);
    expect(positions, reference.runs.map((run) => run.transform.e));
    innerX[0] = 0;
    outerX[0] = 0;
    leaf.clear();
    commands.clear();
    expect(recorded.runs.map((run) => run.transform.e), [1, 5]);

    final shared = [PdfDrawTextCommand(_run('Shared'))];
    PdfRecordedText repeated(int count) => PdfRecordedText.capture([
          PdfDrawTiledCellCommand(
              shared, Float64List(count), Float64List(count)),
        ]);
    final once = repeated(1);
    final many = repeated(1000);
    expect(many.estimatedBytes - once.estimatedBytes, 999 * 16);
    expect(many.runs.length, 1000);
    expect(many.estimatedBytes, lessThan(20000));
  });

  test('shared cell metadata is retained once and graphics do not add weight',
      () {
    final cell = [PdfDrawTextCommand(_run('Shared'))];
    PdfDrawTiledCellCommand stamp(List<PdfRenderCommand> source) =>
        PdfDrawTiledCellCommand(source, Float64List(1), Float64List(1));
    final shared = PdfRecordedText.capture([stamp(cell), stamp(cell)]);
    final distinct = PdfRecordedText.capture([
      stamp(cell),
      stamp([PdfDrawTextCommand(_run('Shared'))]),
    ]);
    expect(shared.estimatedBytes, lessThan(distinct.estimatedBytes));
    final plain = PdfRecordedText.capture(cell);
    final decorated = PdfRecordedText.capture([
      PdfFillPathCommand(
          PdfPath(List.generate(1000, (i) => PdfLineTo(i.toDouble(), 1))),
          PdfColor.black,
          PdfFillRule.nonzero,
          1),
      ...cell,
    ]);
    expect(decorated.estimatedBytes, plain.estimatedBytes);
  });

  test('empty graphs stay empty and malformed cell cycles are rejected', () {
    final empty = PdfRecordedText.capture([const PdfSaveCommand()]);
    expect(empty.isEmpty, isTrue);
    expect(PdfTextExtractor.fromRecordedText(empty, 9).pageIndex, 9);
    expect(PdfTextExtractor.fromRecordedText(empty, 9).text, isEmpty);
    final cyclic = <PdfRenderCommand>[];
    cyclic.add(PdfDrawTiledCellCommand(cyclic, Float64List(1), Float64List(1)));
    expect(() => PdfRecordedText.capture(cyclic), throwsArgumentError);
  });
}

PdfTextRun _run(String text,
        {double x = 10,
        double y = 20,
        List<PdfGlyphPlacement>? glyphs,
        List<double>? offsets}) =>
    PdfTextRun(
      text: text,
      transform: PdfMatrix(12, 0, 0, 12, x, y),
      color: PdfColor.black,
      width: offsets?.last ?? text.length * 0.5,
      glyphs: glyphs,
      charOffsets: offsets,
      mcid: 12,
    );

class _TextDevice implements PdfDevice {
  final runs = <PdfTextRun>[];

  @override
  void drawText(PdfTextRun run) => runs.add(run);

  @override
  dynamic noSuchMethod(Invocation invocation) {}
}

PdfRecordedText _record(PdfDocument document) {
  final recorder = RecordingPdfDevice();
  PdfInterpreter(cos: document.cos, device: recorder, collectCharOffsets: true)
      .drawPage(document.page(0));
  return PdfRecordedText.capture(recorder.commands);
}

PdfPageText _expectEquivalent(PdfDocument document, PdfRecordedText recorded) {
  final expected = PdfTextExtractor.extract(document, 0);
  final actual = PdfTextExtractor.fromRecordedText(recorded, 0);
  // The extraction wire includes text, bidi flags, every character offset,
  // MCIDs, matrices and bounds. Exact bytes guard all of them together.
  expect(serializePageText(actual), serializePageText(expected));
  return actual;
}

PdfDocument _document(String content) {
  final builder = CosDocumentBuilder();
  CosArray numbers(List<num> values) => CosArray([
        for (final value in values)
          if (value is int) CosInteger(value) else CosReal(value.toDouble()),
      ]);
  final pages = CosDictionary({'Type': const CosName('Pages')});
  final pagesRef = builder.add(pages);
  final font = builder.add(CosDictionary({
    'Type': const CosName('Font'),
    'Subtype': const CosName('Type1'),
    'BaseFont': const CosName('Helvetica'),
  }));
  final fonts = CosDictionary({'F1': font});
  final resources = CosDictionary({'Font': fonts});
  final cellResources = CosDictionary({
    'Font': CosDictionary({'F1': font}),
  });
  CosReference stream(String content, [Map<String, CosObject>? fields]) =>
      builder.add(CosStream(
          CosDictionary(fields ?? {}), Uint8List.fromList(content.codeUnits)));
  CosReference form(String content, {bool group = false}) => stream(content, {
        'Type': const CosName('XObject'),
        'Subtype': const CosName('Form'),
        'BBox': numbers([0, 0, 612, 792]),
        'Resources': cellResources,
        if (group)
          'Group': CosDictionary({
            'S': const CosName('Transparency'),
            'CS': const CosName('DeviceGray'),
          }),
      });
  resources['ExtGState'] = CosDictionary({
    'Masked': CosDictionary({
      'Type': const CosName('ExtGState'),
      'SMask': CosDictionary({
        'S': const CosName('Luminosity'),
        'G': form('BT /F1 12 Tf 72 720 Td (MASK_ONLY) Tj ET', group: true),
      }),
    }),
  });
  fonts['T3'] = builder.add(CosDictionary({
    'Type': const CosName('Font'),
    'Subtype': const CosName('Type3'),
    'FontBBox': numbers([0, 0, 1000, 1000]),
    'FontMatrix': numbers([0.001, 0, 0, 0.001, 0, 0]),
    'FirstChar': const CosInteger(65),
    'LastChar': const CosInteger(65),
    'Widths': numbers([1000]),
    'Encoding': CosDictionary({
      'Differences': CosArray([const CosInteger(65), const CosName('A')]),
    }),
    'Resources': cellResources,
    'CharProcs': CosDictionary({
      'A': stream('1000 0 d0 BT /F1 20 Tf 0 0 Td (TYPE3_TEXT) Tj ET'),
    }),
  }));
  resources['Pattern'] = CosDictionary({
    'PatternText': stream('BT /F1 4 Tf 0 0 Td (PATTERN_TEXT) Tj ET', {
      'Type': const CosName('Pattern'),
      'PatternType': const CosInteger(1),
      'PaintType': const CosInteger(1),
      'TilingType': const CosInteger(1),
      'BBox': numbers([0, 0, 20, 20]),
      'XStep': const CosInteger(20),
      'YStep': const CosInteger(20),
      'Resources': cellResources,
    }),
  });
  final annotation = builder.add(CosDictionary({
    'Type': const CosName('Annot'),
    'Subtype': const CosName('FreeText'),
    'Rect': numbers([50, 100, 200, 200]),
    'AP': CosDictionary({
      'N': form('BT /F1 12 Tf 72 720 Td (ANNOTATION_ONLY) Tj ET'),
    }),
  }));
  final page = builder.add(CosDictionary({
    'Type': const CosName('Page'),
    'Parent': pagesRef,
    'MediaBox': numbers([0, 0, 612, 792]),
    'Resources': resources,
    'Contents': stream(content),
    'Annots': CosArray([annotation]),
  }));
  pages['Kids'] = CosArray([page]);
  pages['Count'] = const CosInteger(1);
  return PdfDocument.open(builder.build(
      root: builder.add(CosDictionary(
          {'Type': const CosName('Catalog'), 'Pages': pagesRef}))));
}
