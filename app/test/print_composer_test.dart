import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';

import 'package:dart_pdf_editor_app/print_composer.dart';
import 'package:dart_pdf_editor_app/print_settings.dart';

void main() {
  PdfDocument prepare(PdfDocument source, PrintSettings settings,
          {bool includeCopies = true, int? sheetIndex}) =>
      PdfDocument.open(preparePrintDocument(source, settings,
          includeCopies: includeCopies, sheetIndex: sheetIndex));

  List<String> texts(PdfDocument document) => [
        for (var page = 0; page < document.pageCount; page++)
          PdfTextExtractor.extract(document, page).text.trim(),
      ];

  test('settings snapshot pages and clearing a selected print region', () {
    final pages = [0];
    final settings =
        PrintSettings(pages: pages, region: const PdfRect(10, 20, 100, 200));
    pages.add(1);
    expect(settings.pages, [0]);
    expect(() => settings.pages.add(2), throwsUnsupportedError);
    expect(settings.copyWith(copies: 3).region, settings.region);
    expect(settings.copyWith(clearRegion: true).region, isNull);
  });

  test('copies, collation, reverse and sparse page order preserve vector text',
      () {
    final source = PdfDocument.open(buildMultiPagePdf(4));
    final settings = PrintSettings(pages: [0, 3, 1], copies: 2);
    expect(texts(prepare(source, settings)),
        ['Page 1', 'Page 4', 'Page 2', 'Page 1', 'Page 4', 'Page 2']);
    expect(texts(prepare(source, settings.copyWith(collate: false))),
        ['Page 1', 'Page 1', 'Page 4', 'Page 4', 'Page 2', 'Page 2']);
    expect(
        texts(prepare(source, settings.copyWith(reverse: true),
            includeCopies: false)),
        ['Page 2', 'Page 4', 'Page 1']);
  });

  test(
      'n-up grouping happens before copies and preview selects the actual sheet',
      () {
    final source = PdfDocument.open(buildMultiPagePdf(5));
    final settings = PrintSettings(
        pages: [0, 1, 2, 3, 4],
        scaling: PrintScaling.multiple,
        pagesPerSheet: 2,
        copies: 3,
        collate: false,
        paperSize: PrintPaperSize.letter,
        rotation: PrintRotation.none);
    final full = prepare(source, settings);
    expect(printSheetCount(settings), 3);
    expect(full.pageCount, 9);
    expect(texts(full)[0], contains('Page 1'));
    expect(texts(full)[0], contains('Page 2'));
    expect(texts(full)[3], contains('Page 3'));
    expect(texts(full)[6], 'Page 5');
    final preview = prepare(source, settings, sheetIndex: 1);
    expect(preview.pageCount, 1);
    expect(texts(preview).single, texts(full)[3]);
    expect(preview.page(0).cropBox, full.page(3).cropBox);
    expect(preview.page(0).contentBytes(), full.page(3).contentBytes());
  });

  test('n-up reading directions position pages in the expected cells', () {
    final source = PdfDocument.open(buildMultiPagePdf(4));
    final base = PrintSettings(
        pages: [0, 1, 2, 3],
        scaling: PrintScaling.multiple,
        pagesPerSheet: 4,
        paperSize: PrintPaperSize.letter,
        rotation: PrintRotation.none);
    Map<String, PdfRect> bounds(PrintPageLayout layout) {
      final doc = prepare(source, base.copyWith(layout: layout));
      return {
        for (final run in PdfTextExtractor.extract(doc, 0).runs)
          run.text: run.bounds
      };
    }

    final horizontal = bounds(PrintPageLayout.horizontal);
    expect(horizontal['Page 1']!.left, lessThan(horizontal['Page 2']!.left));
    expect(horizontal['Page 1']!.top, greaterThan(horizontal['Page 3']!.top));
    final reversed = bounds(PrintPageLayout.horizontalReverse);
    expect(reversed['Page 1']!.left, greaterThan(reversed['Page 2']!.left));
    final vertical = bounds(PrintPageLayout.vertical);
    expect(vertical['Page 1']!.top, greaterThan(vertical['Page 2']!.top));
    expect(vertical['Page 1']!.left, lessThan(vertical['Page 3']!.left));
    final verticalReverse = bounds(PrintPageLayout.verticalReverse);
    expect(verticalReverse['Page 1']!.top,
        greaterThan(verticalReverse['Page 2']!.top));
    expect(verticalReverse['Page 1']!.left,
        greaterThan(verticalReverse['Page 3']!.left));
  });

  test('copies share forms and resources instead of duplicating artwork', () {
    final source = PdfDocument.open(buildMultiPagePdf(1));
    final bytes = preparePrintDocument(source, PrintSettings(pages: [0]));
    final copies =
        preparePrintDocument(source, PrintSettings(pages: [0], copies: 99));
    final output = PdfDocument.open(copies);
    expect(copies.length - bytes.length, lessThan(30000));
    final first = output.page(0).dict['Contents'];
    for (var page = 1; page < output.pageCount; page++) {
      expect(output.page(page).dict['Contents'], first);
    }
  });

  test('paper dimensions and UserUnit preserve real physical size', () {
    final source =
        _fixture(rotation: 90, unit: 2, box: const PdfRect(20, 30, 220, 330));
    final printed = prepare(source, PrintSettings(pages: [0]));
    expect(printed.page(0).cropBox, const PdfRect(0, 0, 600, 400));
    expect(printed.page(0).rotation, 0);
    final letter = prepare(
        source,
        PrintSettings(
            pages: [0],
            paperSize: PrintPaperSize.letter,
            orientation: PrintOrientation.landscape));
    expect(letter.page(0).cropBox, const PdfRect(0, 0, 792, 612));
    final cropped = prepare(
        source,
        PrintSettings(
            pages: [0],
            region: const PdfRect(30, 40, 130, 90),
            rotation: PrintRotation.none));
    expect(cropped.page(0).cropBox, const PdfRect(0, 0, 200, 100));
  });

  test('custom scale, fit and reduce-only produce distinct text geometry', () {
    final source = PdfDocument.open(buildMultiPagePdf(1));
    final base = PrintSettings(
        pages: [0],
        rotation: PrintRotation.none,
        paperSize: PrintPaperSize.tabloid,
        center: false);
    double textWidth(PrintSettings settings) =>
        PdfTextExtractor.extract(prepare(source, settings), 0)
            .runs
            .single
            .bounds
            .width;
    final original = textWidth(base);
    expect(
        textWidth(base.copyWith(scaling: PrintScaling.custom, customScale: 50)),
        closeTo(original / 2, 0.001));
    expect(textWidth(base.copyWith(scaling: PrintScaling.reducePaper)),
        closeTo(original, 0.001));
    expect(textWidth(base.copyWith(scaling: PrintScaling.fitPaper)),
        greaterThan(original));
    expect(
        textWidth(base.copyWith(scaling: PrintScaling.fitMargins, margin: 100)),
        lessThan(textWidth(base.copyWith(scaling: PrintScaling.fitPaper))));
  });

  test('print flags, NoView, widgets and content choices match paper semantics',
      () {
    final source = _fixture(annotations: [
      _annotation('Shown', flags: 4),
      _annotation('PrintOnly', flags: 4 | 32),
      _annotation('ScreenOnly', flags: 0),
      _annotation('Hidden', flags: 4 | 2),
      _annotation('FieldValue', flags: 4, subtype: 'Widget'),
    ]);
    final before = source.page(0).dict.toString();
    final settings = PrintSettings(pages: [0]);
    final all = texts(prepare(source, settings)).single;
    expect(all, contains('Page content'));
    expect(all, contains('Shown'));
    expect(all, contains('PrintOnly'));
    expect(all, contains('FieldValue'));
    expect(all, isNot(contains('ScreenOnly')));
    expect(all, isNot(contains('Hidden')));
    final document = texts(prepare(
            source, settings.copyWith(content: PrintContent.documentOnly)))
        .single;
    expect(document, contains('Page content'));
    expect(document, contains('FieldValue'));
    expect(document, isNot(contains('Shown')));
    final markups = texts(prepare(
            source, settings.copyWith(content: PrintContent.markupsOnly)))
        .single;
    expect(markups, contains('Shown'));
    expect(markups, isNot(contains('Page content')));
    expect(markups, isNot(contains('FieldValue')));
    expect(source.page(0).dict.toString(), before);
    expect(source.page(0).annotations, hasLength(5));
  });

  test('encrypted source opens as an unencrypted printable copy', () {
    for (final revision in [2, 3, 4, 6]) {
      final source = PdfDocument.open(
          buildEncryptedPdf(revision: revision, userPassword: 'private'),
          password: 'private');
      final output = prepare(source, PrintSettings(pages: [0]));
      expect(output.cos.isEncrypted, isFalse);
      expect(texts(output).single, 'Hello, world!');
      expect(source.cos.isEncrypted, isTrue);
    }
  });

  test('optional-content visibility survives the new document catalog', () {
    final source = _fixture(
        hideContent: true,
        annotations: [_annotation('Visible markup', flags: 4)]);
    final output = prepare(source, PrintSettings(pages: [0]));
    expect(texts(output).single, contains('Visible markup'));
    expect(texts(output).single, isNot(contains('Page content')));
    expect(output.cos.resolve(output.catalog['OCProperties']),
        isA<CosDictionary>());
  });

  test('fallback annotations retain independent fill and stroke opacity', () {
    final shape = _annotation('', flags: 4, subtype: 'Square')
      ..['C'] = CosArray(
          [const CosInteger(1), const CosInteger(0), const CosInteger(0)])
      ..['IC'] = CosArray(
          [const CosInteger(1), const CosInteger(0), const CosInteger(0)])
      ..['CA'] = const CosReal(0.2)
      ..['ca'] = const CosReal(0.6);
    final source = _fixture(annotations: [shape]);
    final original = RecordingPdfDevice();
    PdfInterpreter(cos: source.cos, device: original)
        .drawAnnotations(source.page(0), forPrint: true);
    final output = prepare(source, PrintSettings(pages: [0]));
    final printed = RecordingPdfDevice();
    PdfInterpreter(cos: output.cos, device: printed).drawPage(output.page(0));
    expect(original.commands.whereType<PdfFillPathCommand>().single.alpha, 0.6);
    expect(
        original.commands.whereType<PdfStrokePathCommand>().single.alpha, 0.2);
    expect(printed.commands.whereType<PdfFillPathCommand>().single.alpha, 0.6);
    expect(
        printed.commands.whereType<PdfStrokePathCommand>().single.alpha, 0.2);
  });

  test('fallback highlight opacity uses declared values before its default',
      () {
    for (final opacity in [null, 0.7]) {
      final highlight = _annotation('', flags: 4, subtype: 'Highlight')
        ..['QuadPoints'] = CosArray([
          for (final value in [50, 500, 400, 500, 50, 400, 400, 400])
            CosInteger(value)
        ]);
      if (opacity != null) highlight['CA'] = CosReal(opacity);
      final source = _fixture(annotations: [highlight]);
      final output = prepare(source, PrintSettings(pages: [0]));
      final printed = RecordingPdfDevice();
      PdfInterpreter(cos: output.cos, device: printed).drawPage(output.page(0));
      expect(printed.commands.whereType<PdfFillPathCommand>().single.alpha,
          opacity ?? 0.35);
    }
  });

  test('interleaved form widgets and markups retain annotation paint order',
      () {
    final source = _fixture(annotations: [
      _appearanceAnnotation('Square', 0xFF0000),
      _appearanceAnnotation('Widget', 0x0000FF),
      _appearanceAnnotation('Square', 0x00FF00),
    ]);
    final original = RecordingPdfDevice();
    PdfInterpreter(cos: source.cos, device: original)
        .drawAnnotations(source.page(0), forPrint: true);
    final expected = original.commands
        .whereType<PdfFillPathCommand>()
        .map((command) => command.color)
        .toList();
    expect(expected, [
      const PdfColor(1, 0, 0),
      const PdfColor(0, 0, 1),
      const PdfColor(0, 1, 0),
    ]);
    for (final content in PrintContent.values) {
      final output =
          prepare(source, PrintSettings(pages: [0], content: content));
      final printed = RecordingPdfDevice();
      PdfInterpreter(cos: output.cos, device: printed).drawPage(output.page(0));
      expect(
          printed.commands.whereType<PdfFillPathCommand>().map((c) => c.color),
          switch (content) {
            PrintContent.documentAndMarkups => expected,
            PrintContent.documentOnly => [expected[1]],
            PrintContent.markupsOnly => [expected[0], expected[2]],
          });
    }
  });

  test('print layer usage is frozen identically for preview and native print',
      () {
    for (final printVisible in [true, false]) {
      final source =
          _fixture(hideContent: printVisible, printVisible: printVisible);
      final output = prepare(source, PrintSettings(pages: [0]));
      expect(texts(output).single.contains('Page content'), printVisible);
      final properties =
          output.cos.resolve(output.catalog['OCProperties']) as CosDictionary;
      final config = output.cos.resolve(properties['D']) as CosDictionary;
      expect(config['AS'], isNull);
      final groups = output.cos.resolve(properties['OCGs']) as CosArray;
      final group = output.cos.resolve(groups[0]) as CosDictionary;
      expect(group['Usage'], isNull);
    }
  });

  test('whole-job validation catches margins on a smaller later sheet', () {
    final source = PdfDocument.open(buildVariedHeightPdf(3));
    final settings = PrintSettings(
        pages: [0, 1, 2], scaling: PrintScaling.fitMargins, margin: 200);
    expect(() => prepare(source, settings, sheetIndex: 0), returnsNormally);
    expect(() => validatePrintSettings(source, settings), throwsArgumentError);
    expect(() => validatePrintSettings(source, settings.copyWith(margin: 10)),
        returnsNormally);
  });

  test('validation rejects empty, invalid, nonfinite and impossible jobs', () {
    final source = PdfDocument.open(buildMultiPagePdf(1));
    for (final settings in [
      PrintSettings(pages: []),
      PrintSettings(pages: [1]),
      PrintSettings(pages: [0], copies: 0),
      PrintSettings(pages: [0], customScale: double.nan),
      PrintSettings(pages: [0], offsetX: double.infinity),
      PrintSettings(pages: [0], scaling: PrintScaling.fitMargins, margin: 999),
      PrintSettings(pages: [0], region: const PdfRect(1000, 1000, 1100, 1100)),
    ]) {
      expect(() => prepare(source, settings), throwsArgumentError);
    }
    expect(() => prepare(source, PrintSettings(pages: [0]), sheetIndex: 1),
        throwsRangeError);
  });

  for (final name in [
    'pdfkit_compressed.pdf',
    'openoffice.pdf',
    'cmykjpeg.pdf',
    'xobject-image.pdf'
  ]) {
    test('checked-in corpus keeps text and encoded image content: $name', () {
      final source = PdfDocument.open(
          File('../test_corpora/pdfjs/$name').readAsBytesSync());
      final before = source.page(0).contentBytes();
      final output = prepare(
          source,
          PrintSettings(
              pages: [0],
              content: PrintContent.documentOnly,
              rotation: PrintRotation.none));
      final original = RecordingPdfDevice();
      PdfInterpreter(cos: source.cos, device: original)
          .drawPageContent(source.page(0), before);
      final printed = RecordingPdfDevice();
      PdfInterpreter(cos: output.cos, device: printed).drawPage(output.page(0));
      expect(printed.imageRequests.length, original.imageRequests.length);
      for (var i = 0; i < original.imageRequests.length; i++) {
        final input = original.imageRequests[i].stream;
        final copied = printed.imageRequests[i].stream;
        expect(copied.rawBytes, input.rawBytes);
        expect(output.cos.resolve(copied.dictionary['Filter']).toString(),
            source.cos.resolve(input.dictionary['Filter']).toString());
      }
      expect(PdfTextExtractor.extract(output, 0).text,
          PdfTextExtractor.extract(source, 0).text);
      expect(source.page(0).contentBytes(), before);
    });
  }
}

PdfDocument _fixture({
  int rotation = 0,
  double unit = 1,
  bool hideContent = false,
  bool? printVisible,
  PdfRect box = const PdfRect(0, 0, 612, 792),
  List<CosDictionary> annotations = const [],
}) {
  final builder = CosDocumentBuilder();
  final pages = CosDictionary({'Type': const CosName('Pages')});
  final root = builder.add(pages);
  final layer = builder.add(CosDictionary({
    'Type': const CosName('OCG'),
    'Name': CosString.fromText('Hidden'),
    if (printVisible != null)
      'Usage': CosDictionary({
        'Print': CosDictionary({
          'PrintState': CosName(printVisible ? 'ON' : 'OFF'),
        })
      }),
  }));
  final content = (ContentWriter()
        ..op('/OC /Layer BDC')
        ..beginText()
        ..font('F1', 12)
        ..textAt(box.left + 20, box.top - 30)
        ..showText('Page content')
        ..endText()
        ..endMarkedContent())
      .takeBytes();
  for (final annotation in annotations) {
    final appearance = annotation['AP'];
    if (appearance is CosDictionary && appearance['N'] is CosStream) {
      appearance['N'] = builder.add(appearance['N']!);
    }
  }
  final page = builder.add(CosDictionary({
    'Type': const CosName('Page'),
    'Parent': root,
    'MediaBox': CosArray([
      CosReal(box.left),
      CosReal(box.bottom),
      CosReal(box.right),
      CosReal(box.top)
    ]),
    'Rotate': CosInteger(rotation),
    'UserUnit': CosReal(unit),
    'Contents': builder.add(CosStream(
        CosDictionary({'Length': CosInteger(content.length)}), content)),
    'Resources': CosDictionary({
      'Properties': CosDictionary({'Layer': layer}),
      'Font': CosDictionary({
        'F1': CosDictionary({
          'Type': const CosName('Font'),
          'Subtype': const CosName('Type1'),
          'BaseFont': const CosName('Helvetica'),
        })
      })
    }),
    'Annots': CosArray(
        [for (final annotation in annotations) builder.add(annotation)]),
  }));
  pages['Kids'] = CosArray([page]);
  pages['Count'] = const CosInteger(1);
  return PdfDocument.open(builder.build(
      root: builder.add(CosDictionary({
    'Type': const CosName('Catalog'),
    'Pages': root,
    'OCProperties': CosDictionary({
      'OCGs': CosArray([layer]),
      'D': CosDictionary({
        'BaseState': const CosName('ON'),
        'OFF': CosArray([if (hideContent) layer]),
        if (printVisible != null)
          'AS': CosArray([
            CosDictionary({
              'Event': const CosName('Print'),
              'Category': CosArray([const CosName('Print')]),
              'OCGs': CosArray([layer]),
            })
          ]),
      }),
    }),
  }))));
}

CosDictionary _annotation(String text,
        {required int flags, String subtype = 'FreeText'}) =>
    CosDictionary({
      'Type': const CosName('Annot'),
      'Subtype': CosName(subtype),
      'Rect': CosArray([
        const CosInteger(50),
        const CosInteger(400),
        const CosInteger(400),
        const CosInteger(500)
      ]),
      'F': CosInteger(flags),
      'Contents': CosString.fromText(text),
      'DA': CosString.fromText('/Helv 12 Tf 0 g'),
      if (subtype == 'Widget') ...{
        'FT': const CosName('Tx'),
        'T': CosString.fromText('field'),
        'V': CosString.fromText(text),
      },
    });

CosDictionary _appearanceAnnotation(String subtype, int color) {
  final content = (ContentWriter()
        ..fillColor(color)
        ..rect(0, 0, 350, 100)
        ..fill())
      .takeBytes();
  return _annotation('', flags: 4, subtype: subtype)
    ..['AP'] = CosDictionary({
      'N': CosStream(
          CosDictionary({
            'Type': const CosName('XObject'),
            'Subtype': const CosName('Form'),
            'BBox': CosArray([
              const CosInteger(0),
              const CosInteger(0),
              const CosInteger(350),
              const CosInteger(100),
            ]),
            'Resources': CosDictionary(),
            'Length': CosInteger(content.length),
          }),
          content),
    });
}
