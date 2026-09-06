import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:image/image.dart' as image;
import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_document/src/compressor_images.dart';
import 'package:test/test.dart';

void main() {
  test('downsizing a placed RGB Flate image preserves its orientation', () {
    final fixture = _fixture(contents: ['72 0 0 36 0 0 cm /Im Do']);
    final old = fixture.stream;
    final stats =
        optimizePdfImages(fixture.document, targetDpi: 72, jpegQuality: 85);
    final result = fixture.stream;
    expect(stats.imagesRecompressed, 1);
    expect(stats.bytesSaved, old.rawBytes.length - result.rawBytes.length);
    expect(stats.bytesSaved, greaterThan(0));
    expect(stats.warnings, isEmpty);
    expect(_dimensions(result), (72, 36));
    expect(result.dictionary['Filter'], const CosName('DCTDecode'));
    expect(_dimensions(old), (400, 200), reason: 'source object is untouched');
    final raster = image.decodeJpg(result.rawBytes)!;
    expect((raster.width, raster.height), (72, 36));
    expect(raster.getPixel(60, 18).r, greaterThan(raster.getPixel(10, 18).r));
    expect(raster.getPixel(35, 30).g, greaterThan(raster.getPixel(35, 5).g));
  });

  test('a reused image retains the resolution of its largest placement', () {
    final fixture = _fixture(contents: [
      '72 0 0 36 0 0 cm /Im Do',
      'q 288 0 0 144 0 0 cm /Im Do Q '
          'q 36 0 0 18 0 0 cm /Im Do Q',
    ]);
    optimizePdfImages(fixture.document, targetDpi: 72, jpegQuality: 80);
    expect(_dimensions(fixture.stream), (288, 144));
  });

  test('nested Forms compose matrices in PDF order and include UserUnit', () {
    // Image: 18 x 36. Inner Form rotates it, outer Form scales its new x-axis
    // by 2, and UserUnit doubles physical dimensions: x=36pt, y=144pt.
    final fixture = _fixture(
      contents: ['/Outer Do'],
      userUnit: 2,
      resources: (builder, imageRef) {
        final inner = builder.add(CosStream(
            CosDictionary({
              'Type': const CosName('XObject'),
              'Subtype': const CosName('Form'),
              'BBox': _array([0, 0, 36, 36]),
              'Matrix': _array([0, 1, -1, 0, 0, 0]),
              'Resources': CosDictionary({
                'XObject': CosDictionary({'Local': imageRef}),
              }),
            }),
            _bytes('18 0 0 36 0 0 cm /Local Do')));
        final outer = builder.add(CosStream(
            CosDictionary({
              'Type': const CosName('XObject'),
              'Subtype': const CosName('Form'),
              'BBox': _array([0, 0, 72, 36]),
              'Matrix': _array([2, 0, 0, 1, 0, 0]),
              'Resources': CosDictionary({
                'XObject': CosDictionary({'Inner': inner}),
              }),
            }),
            _bytes('/Inner Do')));
        return CosDictionary({
          'XObject': CosDictionary({'Outer': outer}),
        });
      },
    );
    optimizePdfImages(fixture.document, targetDpi: 72, jpegQuality: 80);
    // Keep the original raster's 2:1 aspect: 144px on its demanding y-axis.
    expect(_dimensions(fixture.stream), (288, 144));
  });

  test('rotations and shears use basis-vector lengths, not axis bounds', () {
    final fixture = _fixture(contents: ['0 144 -72 54 0 0 cm /Im Do']);
    optimizePdfImages(fixture.document, targetDpi: 72, jpegQuality: 80);
    // x length=144, y length=90. y dictates the uniform 0.45 scale.
    expect(_dimensions(fixture.stream), (180, 90));
  });

  test('grayscale remains DeviceGray and does not acquire RGB components', () {
    final fixture = _fixture(gray: true, contents: ['72 0 0 36 0 0 cm /Im Do']);
    final stats =
        optimizePdfImages(fixture.document, targetDpi: 72, jpegQuality: 60);
    expect(stats.imagesRecompressed, 1);
    expect(_dimensions(fixture.stream), (72, 36));
    expect(
        fixture.stream.dictionary['ColorSpace'], const CosName('DeviceGray'));
    expect(fixture.stream.dictionary['Filter'], const CosName('FlateDecode'));
    expect(
        fixture.document.cos.decodeStreamData(fixture.stream).length, 72 * 36);
  });

  test('JPEG recompression honors size and accepts a decodable smaller result',
      () {
    final fixture =
        _fixture(jpeg: true, contents: ['144 0 0 72 0 0 cm /Im Do']);
    final before = fixture.stream.rawBytes.length;
    final stats =
        optimizePdfImages(fixture.document, targetDpi: 72, jpegQuality: 50);
    expect(stats.imagesRecompressed, 1);
    expect(fixture.stream.rawBytes.length, lessThan(before));
    expect(_dimensions(fixture.stream), (144, 72));
    final decoded = image.decodeJpg(fixture.stream.rawBytes)!;
    expect((decoded.width, decoded.height), (144, 72));
  });

  test('an undersampled image is never enlarged', () {
    final fixture = _fixture(contents: ['800 0 0 400 0 0 cm /Im Do']);
    optimizePdfImages(fixture.document, targetDpi: 300, jpegQuality: 70);
    expect(_dimensions(fixture.stream), (400, 200));
  });

  test('an already tiny lossless payload is retained when JPEG is larger', () {
    final fixture = _fixture(
        width: 16,
        height: 8,
        solid: true,
        contents: ['16 0 0 8 0 0 cm /Im Do']);
    final before = fixture.stream;
    final stats =
        optimizePdfImages(fixture.document, targetDpi: 72, jpegQuality: 85);
    expect(stats.imagesRecompressed, 0);
    expect(stats.bytesSaved, 0);
    expect(fixture.stream, same(before));
  });

  test('masked, CMYK, ICC, one-bit, and Decode images remain byte-identical',
      () {
    final cases = <Map<String, CosObject>>[
      {'SMask': CosNull.instance},
      {
        'Mask': _array([0, 0, 0, 0, 0, 0])
      },
      {'ColorSpace': const CosName('DeviceCMYK')},
      {
        'ColorSpace': CosArray([const CosName('ICCBased'), CosDictionary()])
      },
      {'BitsPerComponent': const CosInteger(1)},
      {
        'Decode': _array([1, 0, 1, 0, 1, 0])
      },
      {'Filter': const CosName('JBIG2Decode')},
      {
        'DecodeParms': CosDictionary({'Predictor': const CosInteger(12)})
      },
    ];
    for (final properties in cases) {
      final fixture = _fixture(
          properties: properties, contents: ['72 0 0 36 0 0 cm /Im Do']);
      final before = fixture.stream;
      final stats =
          optimizePdfImages(fixture.document, targetDpi: 72, jpegQuality: 60);
      expect(stats.imagesRecompressed, 0, reason: properties.toString());
      expect(fixture.stream, same(before), reason: properties.toString());
      expect(stats.warnings, isNotEmpty);
    }
  });

  test('a shared image in a tiling pattern is protected from downsampling', () {
    final fixture = _fixture(
        contents: ['72 0 0 36 0 0 cm /Im Do'],
        resources: (builder, imageRef) {
          final pattern = builder.add(CosStream(
              CosDictionary({
                'Type': const CosName('Pattern'),
                'PatternType': const CosInteger(1),
                'BBox': _array([0, 0, 1, 1]),
                'Resources': CosDictionary({
                  'XObject': CosDictionary({'Im': imageRef}),
                }),
              }),
              _bytes('/Im Do')));
          return CosDictionary({
            'XObject': CosDictionary({'Im': imageRef}),
            'Pattern': CosDictionary({'P': pattern}),
          });
        });
    final before = fixture.stream;
    final stats =
        optimizePdfImages(fixture.document, targetDpi: 72, jpegQuality: 60);
    expect(stats.imagesRecompressed, 0);
    expect(fixture.stream, same(before));
    expect(stats.warnings.single, contains('placement'));
  });

  test('appearance use protects an image even when also painted on a page', () {
    final fixture =
        _fixture(appearance: true, contents: ['72 0 0 36 0 0 cm /Im Do']);
    final before = fixture.stream;
    expect(
        optimizePdfImages(fixture.document, targetDpi: 72, jpegQuality: 60)
            .imagesRecompressed,
        0);
    expect(fixture.stream, same(before));
  });

  test('malformed page state protects an image shared with a valid page', () {
    final fixture = _fixture(contents: [
      '72 0 0 36 0 0 cm /Im Do',
      'q 400 0 0 200 0 0 cm /Im Do', // Unknown final graphics state.
    ]);
    final before = fixture.stream;
    expect(
        optimizePdfImages(fixture.document, targetDpi: 72, jpegQuality: 60)
            .imagesRecompressed,
        0);
    expect(fixture.stream, same(before));
  });

  test('device-space default overrides prevent unsafe color conversion', () {
    final fixture = _fixture(
        contents: ['72 0 0 36 0 0 cm /Im Do'],
        resources: (builder, imageRef) => CosDictionary({
              'XObject': CosDictionary({'Im': imageRef}),
              'ColorSpace': CosDictionary({
                'DefaultRGB':
                    CosArray([const CosName('CalRGB'), CosDictionary()]),
              }),
            }));
    final before = fixture.stream;
    expect(
        optimizePdfImages(fixture.document, targetDpi: 72, jpegQuality: 60)
            .imagesRecompressed,
        0);
    expect(fixture.stream, same(before));
  });

  test('EXIF mirrors do not get silently baked into PDF image pixels', () {
    final fixture = _fixture(
        jpeg: true, exifOrientation: 2, contents: ['72 0 0 36 0 0 cm /Im Do']);
    final before = fixture.stream;
    final stats =
        optimizePdfImages(fixture.document, targetDpi: 72, jpegQuality: 60);
    expect(stats.imagesRecompressed, 0);
    expect(fixture.stream, same(before));
    expect(stats.warnings.single, contains('EXIF'));
  });

  test('bad JPEG headers are preserved without allocating the claimed raster',
      () {
    final fixture = _fixture(
        jpeg: true,
        properties: {'Width': const CosInteger(300)},
        contents: ['72 0 0 36 0 0 cm /Im Do']);
    final before = fixture.stream;
    final stats =
        optimizePdfImages(fixture.document, targetDpi: 72, jpegQuality: 60);
    expect(stats.imagesRecompressed, 0);
    expect(fixture.stream, same(before));
    expect(stats.warnings.single, contains('dimensions or components'));
  });

  test('validates settings before touching the document', () {
    final fixture = _fixture(contents: ['/Im Do']);
    for (final dpi in [0.0, -1.0, double.nan, double.infinity]) {
      expect(
          () => optimizePdfImages(fixture.document,
              targetDpi: dpi, jpegQuality: 80),
          throwsArgumentError);
    }
    expect(
        () =>
            optimizePdfImages(fixture.document, targetDpi: 72, jpegQuality: 0),
        throwsRangeError);
    expect(
        () => optimizePdfImages(fixture.document,
            targetDpi: 72, jpegQuality: 101),
        throwsRangeError);
  });
}

typedef _Resources = CosDictionary Function(CosDocumentBuilder, CosReference);

({PdfDocument document, CosReference imageRef}) _buildFixture({
  required List<String> contents,
  int width = 400,
  int height = 200,
  bool gray = false,
  bool jpeg = false,
  bool solid = false,
  bool appearance = false,
  int? exifOrientation,
  double? userUnit,
  Map<String, CosObject> properties = const {},
  _Resources? resources,
}) {
  final random = math.Random(1234);
  final channels = gray ? 1 : 3;
  final samples = Uint8List(width * height * channels);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final offset = (y * width + x) * channels;
      samples[offset] = solid ? 120 : (x * 220 ~/ width + random.nextInt(32));
      if (!gray) {
        samples[offset + 1] =
            solid ? 120 : (y * 220 ~/ height + random.nextInt(32));
        samples[offset + 2] = solid ? 120 : random.nextInt(256);
      }
    }
  }
  final Uint8List payload;
  if (jpeg) {
    final raster = image.Image.fromBytes(
        width: width,
        height: height,
        bytes: samples.buffer,
        numChannels: channels);
    raster.exif.imageIfd.orientation = exifOrientation;
    payload = image.encodeJpg(raster, quality: 100);
  } else {
    payload = Uint8List.fromList(const ZLibEncoder().encodeBytes(samples));
  }
  final builder = CosDocumentBuilder();
  final imageRef = builder.add(CosStream(
      CosDictionary({
        'Type': const CosName('XObject'),
        'Subtype': const CosName('Image'),
        'Width': CosInteger(width),
        'Height': CosInteger(height),
        'BitsPerComponent': const CosInteger(8),
        'ColorSpace': CosName(gray ? 'DeviceGray' : 'DeviceRGB'),
        'Filter': CosName(jpeg ? 'DCTDecode' : 'FlateDecode'),
        ...properties,
      }),
      payload));
  final pageTree = CosDictionary({'Type': const CosName('Pages')});
  final pageTreeRef = builder.add(pageTree);
  final pageResources = resources?.call(builder, imageRef) ??
      CosDictionary({
        'XObject': CosDictionary({'Im': imageRef}),
      });
  final pages = <CosReference>[];
  for (final content in contents) {
    final page = CosDictionary({
      'Type': const CosName('Page'),
      'Parent': pageTreeRef,
      'MediaBox': _array([0, 0, 612, 792]),
      'Resources': pageResources,
      'Contents': builder.add(CosStream(CosDictionary(), _bytes(content))),
      if (userUnit != null) 'UserUnit': CosReal(userUnit),
    });
    if (appearance) {
      final ap = builder.add(CosStream(
          CosDictionary({
            'Type': const CosName('XObject'),
            'Subtype': const CosName('Form'),
            'BBox': _array([0, 0, 1, 1]),
            'Resources': pageResources,
          }),
          _bytes('/Im Do')));
      page['Annots'] = CosArray([
        builder.add(CosDictionary({
          'Type': const CosName('Annot'),
          'Subtype': const CosName('Stamp'),
          'Rect': _array([0, 0, 500, 250]),
          'AP': CosDictionary({'N': ap}),
        }))
      ]);
    }
    pages.add(builder.add(page));
  }
  pageTree
    ..['Kids'] = CosArray(pages)
    ..['Count'] = CosInteger(pages.length);
  final root = builder.add(CosDictionary({
    'Type': const CosName('Catalog'),
    'Pages': pageTreeRef,
  }));
  return (
    document: PdfDocument.open(builder.build(root: root)),
    imageRef: imageRef
  );
}

_Fixture _fixture({
  required List<String> contents,
  int width = 400,
  int height = 200,
  bool gray = false,
  bool jpeg = false,
  bool solid = false,
  bool appearance = false,
  int? exifOrientation,
  double? userUnit,
  Map<String, CosObject> properties = const {},
  _Resources? resources,
}) {
  final built = _buildFixture(
      contents: contents,
      width: width,
      height: height,
      gray: gray,
      jpeg: jpeg,
      solid: solid,
      appearance: appearance,
      exifOrientation: exifOrientation,
      userUnit: userUnit,
      properties: properties,
      resources: resources);
  return _Fixture(built.document, built.imageRef);
}

class _Fixture {
  _Fixture(this.document, this.imageRef);
  final PdfDocument document;
  final CosReference imageRef;
  CosStream get stream => document.cos.resolve(imageRef) as CosStream;
}

(int, int) _dimensions(CosStream stream) => (
      (stream.dictionary['Width'] as CosInteger).value,
      (stream.dictionary['Height'] as CosInteger).value,
    );

CosArray _array(List<num> numbers) => CosArray([
      for (final n in numbers) n is int ? CosInteger(n) : CosReal(n.toDouble()),
    ]);

Uint8List _bytes(String source) => Uint8List.fromList(source.codeUnits);
