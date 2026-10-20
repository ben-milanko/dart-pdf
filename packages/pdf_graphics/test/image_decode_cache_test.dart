// #451: a worker records the same page several times in one scroll, and each
// serialize re-decoded every image - one device page paid ~900ms of pure-Dart
// CMYK decode three times. These pin that the cache reuses a decode, that reuse
// is byte-identical to decoding again, and that it never serves the wrong
// pixels for a different target size.
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:pdf_graphics/pdf_graphics.dart';
import 'package:test/test.dart';

CosStream _stream(int marker) => CosStream(
      CosDictionary({
        'Width': const CosInteger(2),
        'Height': const CosInteger(2),
        'Marker': CosInteger(marker),
      }),
      Uint8List.fromList([marker]),
    );

PdfDecodedPixels _pixels(int fill, {int width = 2, int height = 2}) =>
    PdfDecodedPixels(
      Uint8List.fromList(List.filled(width * height * 4, fill)),
      width,
      height,
    );

/// A 200pt page under a PDF/X (CMYK) OutputIntent that draws one gray JPEG
/// twice: as page content, and inside the form of an `/SMask /S /Luminosity`
/// group that masks a red fill. Under the OutputIntent the page draw is
/// colour-managed gray while the mask reads the raw samples, so the two
/// decodes of the one stream differ.
PdfDocument _luminosityMaskDocument() {
  const width = 96;
  const height = 64;
  final gray = img.Image(width: width, height: height);
  for (final pixel in gray) {
    final value = (pixel.x * 255 ~/ (width - 1) + pixel.y * 3) % 256;
    pixel
      ..r = value
      ..g = value
      ..b = value;
  }
  CosStream content(String ops) =>
      CosStream(CosDictionary(), Uint8List.fromList(ops.codeUnits));

  final builder = CosDocumentBuilder();
  final jpeg = builder.add(CosStream(
    CosDictionary({
      'Type': const CosName('XObject'),
      'Subtype': const CosName('Image'),
      'Width': const CosInteger(width),
      'Height': const CosInteger(height),
      'BitsPerComponent': const CosInteger(8),
      'ColorSpace': const CosName('DeviceGray'),
      'Filter': const CosName('DCTDecode'),
    }),
    img.encodeJpg(gray, quality: 90),
  ));
  final maskForm = builder.add(CosStream(
    CosDictionary({
      'Type': const CosName('XObject'),
      'Subtype': const CosName('Form'),
      'BBox': CosArray(const [
        CosInteger(0),
        CosInteger(0),
        CosInteger(200),
        CosInteger(200),
      ]),
      'Group': CosDictionary({
        'S': const CosName('Transparency'),
        'CS': const CosName('DeviceGray'),
      }),
      'Resources': CosDictionary({
        'XObject': CosDictionary({'Im0': jpeg}),
      }),
    }),
    Uint8List.fromList('q 200 0 0 200 0 0 cm /Im0 Do Q'.codeUnits),
  ));
  final profile = builder.add(
      CosStream(CosDictionary({'N': const CosInteger(4)}), genericCmykIcc()));
  final pages = CosDictionary({
    'Type': const CosName('Pages'),
    'Count': const CosInteger(1),
  });
  final pagesRef = builder.add(pages);
  final page = builder.add(CosDictionary({
    'Type': const CosName('Page'),
    'Parent': pagesRef,
    'MediaBox': CosArray(const [
      CosInteger(0),
      CosInteger(0),
      CosInteger(200),
      CosInteger(200),
    ]),
    'Resources': CosDictionary({
      'XObject': CosDictionary({'Im0': jpeg}),
      'ExtGState': CosDictionary({
        'GS0': CosDictionary({
          'Type': const CosName('ExtGState'),
          'SMask': CosDictionary({
            'Type': const CosName('Mask'),
            'S': const CosName('Luminosity'),
            'G': maskForm,
          }),
        }),
      }),
    }),
    'Contents': builder.add(content('q 200 0 0 200 0 0 cm /Im0 Do Q '
        'q /GS0 gs 1 0 0 rg 0 0 200 200 re f Q')),
  }));
  pages['Kids'] = CosArray([page]);
  final catalog = builder.add(CosDictionary({
    'Type': const CosName('Catalog'),
    'Pages': pagesRef,
    'OutputIntents': CosArray([
      CosDictionary({
        'Type': const CosName('OutputIntent'),
        'S': const CosName('GTS_PDFX'),
        'DestOutputProfile': profile,
      }),
    ]),
  }));
  return PdfDocument.open(builder.build(root: catalog));
}

/// The decoded pixels of every image command in [bytes], depth-first.
List<PdfDecodedPixels> _decodedImages(Uint8List bytes) {
  final out = <PdfDecodedPixels>[];
  void walk(List<PdfRenderCommand> commands) {
    for (final command in commands) {
      switch (command) {
        case PdfDrawImageCommand(:final request):
          out.add(request.decoded!);
        case PdfEndSoftMaskedCommand(:final maskCommands):
          walk(maskCommands);
        default:
          break;
      }
    }
  }

  walk(deserializeCommands(bytes));
  return out;
}

/// A [pageWidth]x[pageHeight] page that draws one uncompressed
/// [width]x[height] image over the whole page, recorded.
(PdfDocument, PdfPage, RecordingPdfDevice) _singleImagePage(
    int width,
    int height,
    int components,
    String colorSpace,
    int pageWidth,
    int pageHeight,
    int Function(int) sample) {
  final builder = CosDocumentBuilder();
  final image = builder.add(CosStream(
    CosDictionary({
      'Type': const CosName('XObject'),
      'Subtype': const CosName('Image'),
      'Width': CosInteger(width),
      'Height': CosInteger(height),
      'BitsPerComponent': const CosInteger(8),
      'ColorSpace': CosName(colorSpace),
    }),
    Uint8List.fromList(
        List.generate(width * height * components, sample, growable: false)),
  ));
  final pages = CosDictionary({
    'Type': const CosName('Pages'),
    'Count': const CosInteger(1),
  });
  final pagesRef = builder.add(pages);
  final pageRef = builder.add(CosDictionary({
    'Type': const CosName('Page'),
    'Parent': pagesRef,
    'MediaBox': CosArray([
      const CosInteger(0),
      const CosInteger(0),
      CosInteger(pageWidth),
      CosInteger(pageHeight),
    ]),
    'Resources': CosDictionary({
      'XObject': CosDictionary({'Im0': image}),
    }),
    'Contents': builder.add(CosStream(
        CosDictionary(),
        Uint8List.fromList(
            'q $pageWidth 0 0 $pageHeight 0 0 cm /Im0 Do Q'.codeUnits))),
  }));
  pages['Kids'] = CosArray([pageRef]);
  final catalog = builder.add(CosDictionary({
    'Type': const CosName('Catalog'),
    'Pages': pagesRef,
  }));
  final document = PdfDocument.open(builder.build(root: catalog));
  final page = document.page(0);
  final recorder = RecordingPdfDevice();
  PdfInterpreter(cos: document.cos, device: recorder).drawPage(page);
  return (document, page, recorder);
}

void main() {
  group('PdfImageDecodeCache (#451)', () {
    test('a second record of the same page reuses the first decode', () {
      final cache = PdfImageDecodeCache();
      final stream = _stream(1);
      var decodes = 0;
      PdfDecodedPixels? decode() {
        decodes++;
        return _pixels(7);
      }

      final first = cache.decode(stream, 64, 64, decode);
      final second = cache.decode(stream, 64, 64, decode);

      expect(decodes, 1, reason: 'the second record must not decode again');
      expect(identical(first, second), isTrue);
      expect(cache.hits, 1);
      expect(cache.misses, 1);
    });

    test('a different target size decodes separately', () {
      final cache = PdfImageDecodeCache();
      final stream = _stream(1);
      var decodes = 0;
      // A thumbnail tile asks for a smaller target than the full-page record.
      // Serving it the page-sized entry would ship the wrong pixel count.
      final page = cache.decode(stream, 64, 64, () {
        decodes++;
        return _pixels(1, width: 64, height: 64);
      });
      final tile = cache.decode(stream, 8, 8, () {
        decodes++;
        return _pixels(2, width: 8, height: 8);
      });

      expect(decodes, 2);
      expect(page!.width, 64);
      expect(tile!.width, 8);
    });

    test('native resolution is its own key, distinct from a sized target', () {
      final cache = PdfImageDecodeCache();
      final stream = _stream(1);
      var decodes = 0;
      cache.decode(stream, null, null, () {
        decodes++;
        return _pixels(1);
      });
      cache.decode(stream, 2, 2, () {
        decodes++;
        return _pixels(2);
      });
      expect(decodes, 2);
    });

    test('two streams of identical shape do not share an entry', () {
      // CosStream has no ==, so the key is object identity - two loaded
      // streams that happen to look alike are different images.
      final cache = PdfImageDecodeCache();
      var decodes = 0;
      final a = cache.decode(_stream(1), 2, 2, () {
        decodes++;
        return _pixels(1);
      });
      final b = cache.decode(_stream(1), 2, 2, () {
        decodes++;
        return _pixels(2);
      });
      expect(decodes, 2);
      expect(a!.rgba.first, 1);
      expect(b!.rgba.first, 2);
    });

    test('a decline is not cached', () {
      final cache = PdfImageDecodeCache();
      final stream = _stream(1);
      var decodes = 0;
      final first = cache.decode(stream, 2, 2, () {
        decodes++;
        return null;
      });
      final second = cache.decode(stream, 2, 2, () {
        decodes++;
        return _pixels(3);
      });
      expect(first, isNull);
      expect(decodes, 2, reason: 'a decline must not pin the failure');
      expect(second, isNotNull);
    });

    test('evicts least-recently-used once over budget', () {
      // 4 pixels x 4 bytes = 16 bytes per entry; hold two.
      final cache = PdfImageDecodeCache(maxBytes: 40);
      final a = _stream(1), b = _stream(2), c = _stream(3);
      cache.decode(a, 2, 2, () => _pixels(1));
      cache.decode(b, 2, 2, () => _pixels(2));
      // Touch a so b becomes the least recently used.
      cache.decode(a, 2, 2, () => fail('a should still be cached'));
      cache.decode(c, 2, 2, () => _pixels(3));

      expect(cache.bytes, lessThanOrEqualTo(40));
      var decoded = 0;
      cache.decode(a, 2, 2, () {
        decoded++;
        return _pixels(1);
      });
      expect(decoded, 0, reason: 'a was touched most recently, so it survives');
      cache.decode(b, 2, 2, () {
        decoded++;
        return _pixels(2);
      });
      expect(decoded, 1, reason: 'b was the least recently used, so it went');
    });

    test('a transient image bigger than its cap is not cached', () {
      final cache =
          PdfImageDecodeCache(maxBytes: 1024, maxTransientEntryBytes: 64);
      final stream = _stream(1);
      var decodes = 0;
      PdfDecodedPixels? decode() {
        decodes++;
        return _pixels(1, width: 8, height: 8); // 256 bytes
      }

      expect(cache.decode(stream, 8, 8, decode, reusable: false), isNotNull);
      expect(cache.decode(stream, 8, 8, decode, reusable: false), isNotNull);
      // It still decodes correctly - one exact target size is just not worth
      // holding at this size.
      expect(decodes, 2);
      expect(cache.bytes, 0);
    });

    test('a transient decode never displaces a reusable one', () {
      // 16 bytes per entry; room for two.
      final cache = PdfImageDecodeCache(maxBytes: 40);
      final a = _stream(1), b = _stream(2), c = _stream(3);
      cache.decode(a, null, null, () => _pixels(1));
      cache.decode(b, null, null, () => _pixels(2));
      var decodes = 0;
      PdfDecodedPixels? decodeC() {
        decodes++;
        return _pixels(3);
      }

      // No transient entry to make room from: C is served, not retained, and
      // neither reusable entry moves.
      expect(cache.decode(c, 2, 2, decodeC, reusable: false), isNotNull);
      expect(cache.decode(c, 2, 2, decodeC, reusable: false), isNotNull);
      expect(decodes, 2);
      expect(cache.length, 2);
      cache.decode(a, null, null, () => fail('a is reusable and stays'));
      cache.decode(b, null, null, () => fail('b is reusable and stays'));
    });

    test('a transient decode makes room from older transient entries', () {
      final cache = PdfImageDecodeCache(maxBytes: 40);
      final a = _stream(1), b = _stream(2), c = _stream(3), d = _stream(4);
      cache.decode(a, null, null, () => _pixels(1)); // reusable
      cache.decode(b, 2, 2, () => _pixels(2), reusable: false);
      // Over budget: b (the only transient entry) goes, a stays.
      cache.decode(c, 2, 2, () => _pixels(3), reusable: false);
      expect(cache.length, 2);
      cache.decode(a, null, null, () => fail('a is reusable and stays'));
      cache.decode(c, 2, 2, () => fail('c was just admitted'), reusable: false);
      var decodes = 0;
      cache.decode(b, 2, 2, () {
        decodes++;
        return _pixels(2);
      }, reusable: false);
      expect(decodes, 1, reason: 'b was displaced by c');
      // A reusable decode displaces whatever is least recently used - here
      // the transient b, once a is touched.
      cache.decode(a, null, null, () => fail('a is still cached'));
      cache.decode(d, null, null, () => _pixels(4));
      expect(cache.bytes, lessThanOrEqualTo(40));
      cache.decode(a, null, null, () => fail('a was used more recently'));
    });

    test('one reusable decode past the budget is kept alone, as the newest',
        () {
      // An 8 MP+ JPEG under a mobile budget: deep zoom crops every detail
      // tile from this one native decode, so refusing it would repeat the
      // whole decode per tile.
      final cache = PdfImageDecodeCache(maxBytes: 40);
      final small = _stream(1), big = _stream(2), next = _stream(3);
      cache.decode(small, null, null, () => _pixels(1));
      final bigPixels = _pixels(7, width: 8, height: 8); // 256 bytes
      cache.decode(big, null, null, () => bigPixels);
      expect(cache.length, 1, reason: 'everything else made room');
      expect(cache.bytes, 256);
      expect(cache.decode(big, null, null, () => fail('kept past the budget')),
          same(bigPixels));
      // Transient entries cannot push it out; they are simply not retained.
      cache.decode(next, 2, 2, () => _pixels(3), reusable: false);
      expect(cache.length, 1);
      // The next reusable decode takes its place (least recently used).
      cache.decode(next, null, null, () => _pixels(3));
      expect(cache.length, 1);
      expect(cache.bytes, 16);
    });

    test('a reusable decode past the old flat budget is not cached', () {
      final cache = PdfImageDecodeCache(maxBytes: 40);
      final stream = _stream(1);
      final huge = PdfDecodedPixels(
          Uint8List(PdfImageDecodeCache.maxOversizeEntryBytes + 4), 1, 1);
      var decodes = 0;
      cache.decode(stream, null, null, () {
        decodes++;
        return huge;
      });
      cache.decode(stream, null, null, () {
        decodes++;
        return huge;
      });
      expect(decodes, 2);
      expect(cache.bytes, 0);
    });

    test('get/put serve the async browser-codec path', () {
      // The web worker's codec decode is asynchronous, so it cannot run
      // through decode()'s synchronous callback - it uses get/put around its
      // own await. Native resolution, so one entry serves every record.
      final cache = PdfImageDecodeCache();
      final stream = _stream(1);
      expect(cache.get(stream, null, null), isNull);
      cache.put(stream, null, null, _pixels(9));
      expect(cache.get(stream, null, null)!.rgba.first, 9);
      // Re-putting the same key must not double-count the bytes.
      cache.put(stream, null, null, _pixels(9));
      expect(cache.bytes, 16);
    });

    test('clear drops everything and keeps the counters', () {
      final cache = PdfImageDecodeCache();
      final stream = _stream(1);
      cache.decode(stream, 2, 2, () => _pixels(1));
      cache.decode(stream, 2, 2, () => fail('cached'));
      cache.clear();
      expect(cache.bytes, 0);
      expect(cache.length, 0);
      expect((cache.hits, cache.misses), (1, 1),
          reason: 'a memory-pressure trim clears in place; the worker '
              'diagnostics read these across it');
      var decodes = 0;
      cache.decode(stream, 2, 2, () {
        decodes++;
        return _pixels(1);
      });
      expect(decodes, 1);
    });
  });

  // A scan page past native resolution: every record at or past its native
  // ratio decodes the same native key, so that decode serves more than the
  // record that made it - retained like any reusable decode, whatever the
  // format, even past the transient cap a 1-bit or Flate page blows through.
  test('a non-DCT native decode is reused across past-native ratios', () {
    const side = 1024; // 4 MB of RGBA, past a mobile budget's transient cap
    final (document, page, recorder) = _singleImagePage(
        side, side, 1, 'DeviceGray', 400, 400, (i) => (i * 7) & 0xff);

    Uint8List record(double ratio, PdfImageDecodeCache? cache) =>
        serializeCommands(recorder.commands,
            cos: document.cos,
            decodeImages: true,
            maxImagePixelRatio: ratio,
            pageRasterPixels: pdfPageRasterPixels(page.cropBox, ratio),
            imageCache: cache,
            compactStateScopes: true)!;

    // 400pt at ratio 3 and 4 is 1200 and 1600 px: both past the 1024 px
    // native size, so both are native decodes.
    final cache = PdfImageDecodeCache(maxBytes: 4 << 20);
    final zoomed = record(3, cache);
    expect((cache.hits, cache.misses), (0, 1));
    final further = record(4, cache);
    expect((cache.hits, cache.misses), (1, 1),
        reason: 'the second past-native zoom level reuses the native decode');
    expect(cache.bytes, side * side * 4);
    expect(zoomed, record(3, null));
    expect(further, record(4, null));
  });

  // An edit or an undo bumps the revision, so the host's record cache misses
  // and the worker re-records the page at the ratio it was just recorded at,
  // with its decode cache still warm. A downscaled image's target-size decode
  // is what that re-record needs: under the desktop budget it must be
  // retained, or every edit on a scan/underlay page pays the decode again.
  test('a downscaled decode is reused by a same-ratio re-record', () {
    // 2400 px RGB over a letter page: ratio 2 asks for ~1224x1584, a
    // target-size decode of ~7.8 MB of RGBA (past the old 2 MB cap).
    final (document, page, recorder) = _singleImagePage(
        2400, 2400, 3, 'DeviceRGB', 612, 792, (i) => (i * 31) & 0xff);

    Uint8List record(PdfImageDecodeCache? cache) =>
        serializeCommands(recorder.commands,
            cos: document.cos,
            decodeImages: true,
            maxImagePixelRatio: 2,
            pageRasterPixels: pdfPageRasterPixels(page.cropBox, 2),
            imageCache: cache,
            compactStateScopes: true)!;

    final cache = PdfImageDecodeCache(); // the desktop 64 MB
    final first = record(cache);
    expect((cache.hits, cache.misses), (0, 1));
    expect(cache.bytes, greaterThan(2 << 20),
        reason: 'the target-size decode is retained');
    final again = record(cache);
    expect((cache.hits, cache.misses), (1, 1),
        reason: 'the re-record after an edit reuses the downscaled decode');
    final uncached = record(null);
    expect(first, uncached);
    expect(again, uncached);
  });

  // Luminosity masks used to bypass the cache, so every record re-decoded
  // each mask at native size. Their decode ignores target and region for
  // every format, so one native entry, cropped or downsampled per record, is
  // byte-identical to decoding again.
  group('luminosity masks', () {
    test('a luminosity decode is keyed apart from the ordinary decode', () {
      final cache = PdfImageDecodeCache();
      final stream = _stream(1);
      var decodes = 0;
      final ordinary = cache.decode(stream, null, null, () {
        decodes++;
        return _pixels(1);
      });
      final mask = cache.decode(stream, null, null, luminosityMask: true, () {
        decodes++;
        return _pixels(2);
      });

      expect(decodes, 2);
      expect(ordinary!.rgba.first, 1);
      expect(mask!.rgba.first, 2);
      expect(
          cache
              .decode(stream, null, null, luminosityMask: true, () => null)!
              .rgba
              .first,
          2);
      expect(cache.decode(stream, null, null, () => null)!.rgba.first, 1);
      expect(cache.get(stream, null, null)!.rgba.first, 1,
          reason: 'get/put serve ordinary decodes only');
      expect(cache.length, 2);
    });

    test('records reuse one native decode, byte-identical to decoding again',
        () {
      final document = _luminosityMaskDocument();
      final page = document.page(0);
      final recorder = RecordingPdfDevice();
      PdfInterpreter(cos: document.cos, device: recorder).drawPage(page);
      final masked = recorder.commands
          .whereType<PdfEndSoftMaskedCommand>()
          .single
          .maskCommands
          .whereType<PdfDrawImageCommand>()
          .single
          .request;
      expect(masked.isLuminosityMask, isTrue);

      Uint8List record(double ratio, PdfImageDecodeCache? cache,
              {PdfRect? region}) =>
          serializeCommands(recorder.commands,
              cos: document.cos,
              decodeImages: true,
              maxImagePixelRatio: ratio,
              pageRasterPixels: pdfPageRasterPixels(page.cropBox, ratio),
              imageDecodeRegion: region,
              imageCache: cache,
              compactStateScopes: true)!;

      // A worker's usual sequence: the full page, a thumbnail tile, then a
      // deep-zoom detail patch.
      const region = PdfRect(0, 0, 100, 100);
      final cache = PdfImageDecodeCache();
      final full = record(2, cache);
      expect((cache.hits, cache.misses), (0, 2),
          reason: 'the page draw and the mask each decode once');
      final thumbnail = record(0.25, cache);
      expect((cache.hits, cache.misses), (2, 2));
      final detail = record(4, cache, region: region);
      expect((cache.hits, cache.misses), (4, 2));
      expect(cache.length, 2,
          reason: 'one native entry per decode of the stream, not per record');

      expect(full, record(2, null));
      expect(thumbnail, record(0.25, null));
      expect(detail, record(4, null, region: region));

      // The page draw is managed gray and the mask raw gray: had the two
      // shared an entry, one of them would have shipped the other's pixels.
      final [pageImage, maskImage] = _decodedImages(full);
      expect(pageImage.rgba.length, maskImage.rgba.length);
      expect(pageImage.rgba, isNot(maskImage.rgba));
      // Each record really took its own route off the one native entry: the
      // full page at native size, the thumbnail downsampled, the detail patch
      // cropped to the lower-left quarter of the JPEG.
      (int, int) size(Uint8List bytes) {
        final mask = _decodedImages(bytes).last;
        return (mask.width, mask.height);
      }

      expect(size(full), (96, 64));
      expect(size(thumbnail).$1, lessThan(96));
      expect(size(detail), (48, 32));
    });
  });

  group('pdfImageDecodeIgnoresTarget (#451)', () {
    CosStream streamWith(CosObject filter) => CosStream(
          CosDictionary({
            'Width': const CosInteger(4),
            'Height': const CosInteger(4),
            'Filter': filter,
          }),
          Uint8List(0),
        );

    // Decides whether a retained native decode may be downsampled to serve a
    // smaller request. True only where the decoder has no scaled fast path and
    // already does a full decode plus downsample itself.
    test('true for DCTDecode - it has no scaled decode path', () {
      final cos = CosDocument.open(buildClassicPdf());
      expect(
          pdfImageDecodeIgnoresTarget(
              cos, streamWith(const CosName('DCTDecode'))),
          isTrue);
      expect(
          pdfImageDecodeIgnoresTarget(
              cos,
              streamWith(CosArray([
                const CosName('FlateDecode'),
                const CosName('DCTDecode'),
              ]))),
          isTrue,
          reason: 'a wrapped DCT stream still ends at the DCT decoder');
    });

    test('CMYK DCT honours targets after entropy decode', () {
      final cos = CosDocument.open(buildClassicPdf());
      final stream = CosStream(
        CosDictionary({
          'Width': const CosInteger(4),
          'Height': const CosInteger(4),
          'Filter': const CosName('DCTDecode'),
          'ColorSpace': const CosName('DeviceCMYK'),
        }),
        Uint8List(0),
      );

      expect(pdfImageDecodeIgnoresTarget(cos, stream), isFalse);
      expect(pdfImageDecodeIgnoresRegion(cos, stream), isTrue);
    });

    test('false where a scaled decode path exists', () {
      // Serving these from a downsample would substitute different pixels for
      // the ones their own scaled decoder produces.
      final cos = CosDocument.open(buildClassicPdf());
      for (final filter in ['FlateDecode', 'CCITTFaxDecode', 'JPXDecode']) {
        expect(pdfImageDecodeIgnoresTarget(cos, streamWith(CosName(filter))),
            isFalse,
            reason: filter);
      }
    });
  });
}
