import 'dart:math';
import 'dart:typed_data';

import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:test/test.dart';

void main() {
  test('presets keep image processing opt-in and use the advertised DPI', () {
    expect(PdfCompressionPreset.lossless.options.targetDpi, isNull);
    expect(PdfCompressionPreset.screen.options.targetDpi, 72);
    expect(PdfCompressionPreset.ebook.options.targetDpi, 150);
    expect(PdfCompressionPreset.printer.options.targetDpi, 300);
  });

  test('cleans unused resources without mutating the source or its bytes', () {
    final input = _resourcePdf();
    final before = Uint8List.fromList(input);
    final document = PdfDocument.open(input);
    final result = PdfCompressor.optimize(document);
    final output = PdfDocument.open(result.bytes);
    final xobjects = output.cos.resolve(output.page(0).resources['XObject'])
        as CosDictionary;
    expect(xobjects.containsKey('Unused'), isFalse);
    expect(xobjects.containsKey('Photo'), isTrue);
    expect(result.resourcesRemoved, greaterThan(0));
    expect(result.bytesSaved, greaterThan(0));
    expect(result.steps.fold<int>(0, (sum, s) => sum + s.bytesSaved),
        result.bytesSaved);
    expect(input, before);
    final originals = document.cos
        .resolve(document.page(0).resources['XObject']) as CosDictionary;
    expect(originals.containsKey('Unused'), isTrue);
    expect(output.page(0).contentBytes(), document.page(0).contentBytes());
  });

  test('duplicate image streams share one object, different semantics do not',
      () {
    final result = PdfCompressor.optimize(PdfDocument.open(_resourcePdf()));
    final doc = PdfDocument.open(result.bytes);
    final xobjects =
        doc.cos.resolve(doc.page(0).resources['XObject']) as CosDictionary;
    expect(xobjects['Photo'], xobjects['Copy']);
    expect(xobjects['Other'], isNot(xobjects['Photo']));
    expect(result.duplicatesRemoved, 1);
    final before = PdfDocument.open(_resourcePdf());
    final source = before.cos.resolve(
        (before.cos.resolve(before.page(0).resources['XObject'])
            as CosDictionary)['Photo']) as CosStream;
    final kept = doc.cos.resolve(xobjects['Photo']) as CosStream;
    expect(doc.cos.decodeStreamData(kept), before.cos.decodeStreamData(source),
        reason: 'lossless defaults preserve every image sample');
  });

  test('duplicate images keep distinct optional-content group identities', () {
    final input = PdfDocument.open(_resourcePdf());
    final updater = CosIncrementalUpdater(input.cos);
    final groupA = updater.addObject(CosDictionary({
      'Type': const CosName('OCG'),
      'Name': CosString.fromText('Layer'),
    }));
    final groupB = updater.addObject(CosDictionary({
      'Type': const CosName('OCG'),
      'Name': CosString.fromText('Layer'),
    }));
    input.catalog['OCProperties'] = CosDictionary({
      'OCGs': CosArray([groupA, groupB]),
      'D': CosDictionary({
        'ON': CosArray([groupA]),
        'OFF': CosArray([groupB])
      }),
    });
    updater.markChanged(input.catalog);
    final xobjects =
        input.cos.resolve(input.page(0).resources['XObject']) as CosDictionary;
    for (final entry in {'Photo': groupA, 'Copy': groupB}.entries) {
      final ref = xobjects[entry.key] as CosReference;
      final image = input.cos.resolve(ref) as CosStream;
      final dictionary =
          CosDictionary({...image.dictionary.entries, 'OC': entry.value});
      updater.replaceObject(
          ref.objectNumber, CosStream(dictionary, image.rawBytes));
    }
    final result = PdfCompressor.optimize(PdfDocument.open(updater.save()));
    final output = PdfDocument.open(result.bytes);
    final objects = output.cos.resolve(output.page(0).resources['XObject'])
        as CosDictionary;
    expect(objects['Photo'], isNot(objects['Copy']));
    final a = output.cos.resolve(objects['Photo']) as CosStream;
    final b = output.cos.resolve(objects['Copy']) as CosStream;
    expect(a.dictionary['OC'], isNot(b.dictionary['OC']));
  });

  test('coalesces identical embedded font programs and ICC profiles', () {
    final document = PdfDocument.open(buildMultiPagePdf(4));
    final updater = CosIncrementalUpdater(document.cos);
    final random = Random(368);
    final payload =
        Uint8List.fromList(List.generate(2048, (_) => random.nextInt(256)));
    CosReference file(CosDictionary dict) =>
        updater.addObject(CosStream(dict, payload));
    document.catalog['TestFontDescriptors'] = CosArray([
      for (var i = 0; i < 2; i++)
        CosDictionary({
          'Type': const CosName('FontDescriptor'),
          'FontFile2':
              file(CosDictionary({'Length1': CosInteger(payload.length)})),
        }),
    ]);
    document.catalog['TestColorSpaces'] = CosArray([
      for (var i = 0; i < 2; i++)
        CosArray([
          const CosName('ICCBased'),
          file(CosDictionary({'N': const CosInteger(3)})),
        ]),
    ]);
    updater.markChanged(document.catalog);
    final result = PdfCompressor.optimize(PdfDocument.open(updater.save()));
    final output = PdfDocument.open(result.bytes);
    final fonts =
        output.cos.resolve(output.catalog['TestFontDescriptors']) as CosArray;
    expect((fonts[0] as CosDictionary)['FontFile2'],
        (fonts[1] as CosDictionary)['FontFile2']);
    final spaces =
        output.cos.resolve(output.catalog['TestColorSpaces']) as CosArray;
    expect((spaces[0] as CosArray)[1], (spaces[1] as CosArray)[1]);
    expect(result.duplicatesRemoved, 2);
  });

  test('independent switches preserve unused and duplicated resource objects',
      () {
    final result = PdfCompressor.optimize(PdfDocument.open(_resourcePdf()),
        options: const PdfCompressionOptions(
          removeUnusedResources: false,
          deduplicate: false,
          subsetFonts: false,
          recompressStreams: false,
        ));
    final doc = PdfDocument.open(result.bytes);
    final xobjects =
        doc.cos.resolve(doc.page(0).resources['XObject']) as CosDictionary;
    expect(xobjects.containsKey('Unused'), isTrue);
    expect(xobjects['Photo'], isNot(xobjects['Copy']));
    expect(result.streamsDeflated, 0);
    expect(result.steps.map((s) => s.kind), [PdfCompressionKind.structure]);
  });

  test('keeps resources used by appearance states and inherited forms', () {
    final input = _resourcePdf(appearances: true);
    final result = PdfCompressor.optimize(PdfDocument.open(input));
    final doc = PdfDocument.open(result.bytes);
    final xobjects =
        doc.cos.resolve(doc.page(0).resources['XObject']) as CosDictionary;
    expect(xobjects.containsKey('Unused'), isTrue,
        reason: 'the resource-less appearance uses its page resource');
    expect(doc.page(0).annotations, hasLength(1));
  });

  test('keeps AcroForm default resources for subsequent editing', () {
    final input = _resourcePdf(formResources: true);
    final result = PdfCompressor.optimize(PdfDocument.open(input));
    final doc = PdfDocument.open(result.bytes);
    final form = doc.cos.resolve(doc.catalog['AcroForm']) as CosDictionary;
    final res = doc.cos.resolve(form['DR']) as CosDictionary;
    final fonts = doc.cos.resolve(res['Font']) as CosDictionary;
    expect(fonts.containsKey('FutureInput'), isTrue);
  });

  test('invalid content conservatively preserves all resource aliases', () {
    final result = PdfCompressor.optimize(
        PdfDocument.open(_resourcePdf(brokenContent: true)));
    final doc = PdfDocument.open(result.bytes);
    final res =
        doc.cos.resolve(doc.page(0).resources['XObject']) as CosDictionary;
    expect(res.containsKey('Unused'), isTrue);
    expect(result.warnings.join(' '), contains('could not be analysed'));
  });

  test('rejects incomplete source buffers and invalid options', () {
    final bytes = buildMultiPagePdf(2);
    expect(
        () => PdfCompressor.optimize(
            PdfDocument.open(bytes, populatedRanges: [0, bytes.length])),
        throwsArgumentError);
    for (final dpi in [0.0, -1.0, double.nan, double.infinity, 2401.0]) {
      expect(
          () => PdfCompressor.optimize(PdfDocument.open(bytes),
              options: PdfCompressionOptions(targetDpi: dpi)),
          throwsArgumentError);
    }
    expect(
        () => PdfCompressor.optimize(PdfDocument.open(bytes),
            options: const PdfCompressionOptions(jpegQuality: 101)),
        throwsRangeError);
  });

  test('signed copies require an explicit signature invalidation option', () {
    final input = PdfDocument.open(buildMultiPagePdf(8));
    final updater = CosIncrementalUpdater(input.cos);
    final field = updater.addObject(CosDictionary({
      'FT': const CosName('Sig'),
      'T': CosString.fromText('Signature'),
      'V': CosDictionary({'Type': const CosName('Sig')}),
    }));
    input.catalog['AcroForm'] = CosDictionary({
      'Fields': CosArray([field])
    });
    updater.markChanged(input.catalog);
    final signed = PdfDocument.open(updater.save());
    expect(() => PdfCompressor.optimize(signed), throwsArgumentError);
    final result = PdfCompressor.optimize(signed,
        options: const PdfCompressionOptions(allowInvalidateSignatures: true));
    expect(result.warnings.join(' '), contains('signatures'));
  });
}

Uint8List _resourcePdf(
    {bool appearances = false,
    bool formResources = false,
    bool brokenContent = false}) {
  final builder = CosDocumentBuilder();
  final random = Random(368);
  final pixels = Uint8List.fromList(
      List.generate(32 * 32 * 3, (_) => random.nextInt(256)));
  CosReference image({bool inverse = false}) => builder.add(CosStream(
      CosDictionary({
        'Type': const CosName('XObject'),
        'Subtype': const CosName('Image'),
        'Width': const CosInteger(32),
        'Height': const CosInteger(32),
        'ColorSpace': const CosName('DeviceRGB'),
        'BitsPerComponent': const CosInteger(8),
        if (inverse)
          'Decode': CosArray([
            const CosInteger(1),
            const CosInteger(0),
            const CosInteger(1),
            const CosInteger(0),
            const CosInteger(1),
            const CosInteger(0),
          ]),
      }),
      pixels));
  final xobjects = builder.add(CosDictionary({
    'Photo': image(),
    'Copy': image(),
    'Other': image(inverse: true),
    'Unused': builder.add(CosStream(
        CosDictionary({
          'Type': const CosName('XObject'),
          'Subtype': const CosName('Form'),
          'BBox': CosArray([
            const CosInteger(0),
            const CosInteger(0),
            const CosInteger(100),
            const CosInteger(100)
          ]),
        }),
        Uint8List.fromList(('0 0 10 10 re f\n' * 200).codeUnits))),
  }));
  final resources = builder.add(CosDictionary({
    'XObject': xobjects,
    if (formResources)
      'Font': CosDictionary({
        'FutureInput': builder.add(CosDictionary({
          'Type': const CosName('Font'),
          'Subtype': const CosName('Type1'),
          'BaseFont': const CosName('Helvetica'),
        })),
      }),
  }));
  final pages =
      CosDictionary({'Type': const CosName('Pages'), 'Resources': resources});
  final pagesRef = builder.add(pages);
  final content = builder.add(CosStream(
      CosDictionary(),
      Uint8List.fromList((brokenContent
              ? '<< /Broken'
              : 'q 100 0 0 100 0 0 cm /Photo Do /Copy Do /Other Do Q')
          .codeUnits)));
  final page = builder.add(CosDictionary({
    'Type': const CosName('Page'),
    'Parent': pagesRef,
    'Contents': content,
    'MediaBox': CosArray([
      const CosInteger(0),
      const CosInteger(0),
      const CosInteger(200),
      const CosInteger(200)
    ]),
    if (appearances)
      'Annots': CosArray([
        builder.add(CosDictionary({
          'Type': const CosName('Annot'),
          'Subtype': const CosName('Stamp'),
          'Rect': CosArray([
            const CosInteger(0),
            const CosInteger(0),
            const CosInteger(100),
            const CosInteger(100)
          ]),
          'AP': CosDictionary({
            'N': builder.add(CosStream(
                CosDictionary({
                  'Type': const CosName('XObject'),
                  'Subtype': const CosName('Form'),
                  'BBox': CosArray([
                    const CosInteger(0),
                    const CosInteger(0),
                    const CosInteger(100),
                    const CosInteger(100)
                  ]),
                }),
                Uint8List.fromList('/Unused Do'.codeUnits)))
          }),
        })),
      ]),
  }));
  pages['Kids'] = CosArray([page]);
  pages['Count'] = const CosInteger(1);
  final root = builder.add(CosDictionary({
    'Type': const CosName('Catalog'),
    'Pages': pagesRef,
    if (formResources)
      'AcroForm': CosDictionary({'Fields': CosArray(), 'DR': resources}),
  }));
  return builder.build(root: root);
}
