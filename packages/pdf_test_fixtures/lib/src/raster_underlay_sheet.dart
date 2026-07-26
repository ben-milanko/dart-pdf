import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:pdf_cos/pdf_cos.dart';

/// One raster underlay on the sheet: a large [width]x[height] `DeviceRGB`
/// image with a same-size grayscale soft mask.
///
/// [payload], when supplied, is the pre-encoded `DCTDecode` (JPEG) base -
/// produced by an external encoder (`cjpeg`), because this library has no
/// `dart:io` and ships no JPEG encoder. When null the base is emitted as a
/// `FlateDecode` `DeviceRGB` image instead, so the common case (and every CI
/// that lacks `cjpeg`) stays fully hermetic.
///
/// The soft mask is **always** a non-DCT (`FlateDecode`) `DeviceGray` image,
/// exactly as the profiled drawing carries it - that pairing (a JPEG base
/// under a Flate soft mask) is what forces the platform-codec decode path.
class PdfUnderlaySpec {
  const PdfUnderlaySpec({
    required this.width,
    required this.height,
    this.payload,
  });

  final int width;
  final int height;
  final Uint8List? payload;
}

/// Builds the deterministic synthetic **raster-underlay CAD sheet**: one large
/// page carrying a handful of enormous `DeviceRGB` image underlays, each with
/// its own full-size grayscale soft mask, plus a stack of optional-content
/// layers (OCGs) and vector linework tagged into them.
///
/// The shape is taken from a real ~8 MB single-page survey/CAD drawing,
/// profiled rather than guessed:
///
/// ```
/// pages: 1                          media: A1-ish landscape
/// images: 2 base (9460x2918 DeviceRGB, DCTDecode) + 2 soft masks
///         (9460x2918 DeviceGray, FlateDecode, non-DCT)
/// decoded: ~82.8 MB RGBA per base + ~27.6 MB per mask -> ~220 MB resident
/// layers: 71 OCGs
/// content: ~90 streams
/// ```
///
/// That base/mask pairing is the point of the fixture. A non-CMYK `DCTDecode`
/// base cannot be decoded purely (it needs the platform JPEG codec), and the
/// Flate soft mask forces the base to be pulled back to RGBA and alpha-multiplied
/// per pixel - at native resolution, which for a 9460-wide underlay is ~28 M
/// pixels the decoder must not touch when the sheet is shown at a fraction of
/// that size. It is also the only committed document whose single image exceeds
/// the common 8192-px GPU max texture dimension.
///
/// [underlays] describes each underlay in draw order (background first).
/// [layers] optional-content groups are declared and [ops] vector primitives
/// are distributed across them, so toggling a layer or panning crosses tagged
/// content the way the real sheet is read. Output is deterministic: seeded
/// PRNG, no timestamps.
Uint8List buildSyntheticRasterUnderlaySheet({
  required List<PdfUnderlaySpec> underlays,
  int layers = 71,
  int ops = 6000,
  int seed = 20260722,
  double pageW = 2384.0,
  double pageH = 1684.0,
}) {
  assert(underlays.isNotEmpty);
  assert(layers > 0);
  const zlib = ZLibEncoder();
  final builder = CosDocumentBuilder();
  final random = _Lcg(seed);

  // Soft mask + base image objects, in that order per underlay so the base can
  // reference the mask it was just given a number for.
  final baseRefs = <CosReference>[];
  for (final u in underlays) {
    final maskRef = builder.add(_softMask(u.width, u.height, zlib, random));
    baseRefs.add(builder.add(_baseImage(u, maskRef, zlib)));
  }

  // Optional-content groups: one dictionary per layer.
  final ocgRefs = <CosReference>[
    for (var i = 0; i < layers; i++)
      builder.add(CosDictionary({
        'Type': const CosName('OCG'),
        'Name': CosString.fromText('Layer ${i + 1}'),
      })),
  ];

  final font = builder.add(CosDictionary({
    'Type': const CosName('Font'),
    'Subtype': const CosName('Type1'),
    'BaseFont': const CosName('Helvetica'),
  }));

  // Content: title block, then each underlay drawn full-bleed, then linework
  // tagged into the layers via marked-content (`/OCx BDC ... EMC`). Split
  // across several streams like a real multi-pass export.
  final content = StringBuffer()
    ..writeln('1 w 0 0 0 RG')
    ..writeln('20 20 ${_f(pageW - 40)} ${_f(pageH - 40)} re S');
  for (var i = 0; i < underlays.length; i++) {
    // Full-bleed placement; the unit square maps to the whole sheet.
    content.writeln('q ${_f(pageW)} 0 0 ${_f(pageH)} 0 0 cm /Im$i Do Q');
  }
  for (var i = 0; i < ops; i++) {
    final layer = random.intBelow(layers);
    final x = random.range(30, pageW - 60);
    final y = random.range(30, pageH - 40);
    content
      ..write('/OC$layer BDC ')
      ..write('${_f(random.range(0.2, 1.2))} w ')
      ..write('${_f(x)} ${_f(y)} m '
          '${_f(x + random.range(-60, 60))} ${_f(y + random.range(-40, 40))} l S ')
      ..writeln('EMC');
  }

  final raw = Uint8List.fromList(content.toString().codeUnits);
  final deflated = Uint8List.fromList(zlib.encode(raw));
  final contentRef = builder.add(CosStream(
    CosDictionary({
      'Filter': const CosName('FlateDecode'),
      'Length': CosInteger(deflated.length),
    }),
    deflated,
  ));

  // Registered empty, then closed once the page ref exists (§ the builder
  // supports this to break the page<->tree reference cycle).
  final tree = CosDictionary({'Type': const CosName('Pages')});
  final treeRef = builder.add(tree);
  final pageRef = builder.add(CosDictionary({
    'Type': const CosName('Page'),
    'Parent': treeRef,
    'MediaBox': CosArray([
      const CosInteger(0),
      const CosInteger(0),
      CosReal(pageW),
      CosReal(pageH),
    ]),
    'Resources': CosDictionary({
      'XObject': CosDictionary({
        for (var i = 0; i < baseRefs.length; i++) 'Im$i': baseRefs[i],
      }),
      'Properties': CosDictionary({
        for (var i = 0; i < ocgRefs.length; i++) 'OC$i': ocgRefs[i],
      }),
      'Font': CosDictionary({'F1': font}),
    }),
    'Contents': contentRef,
  }));
  // Close the tree now that the page ref exists.
  tree
    ..['Kids'] = CosArray([pageRef])
    ..['Count'] = const CosInteger(1);

  final catalog = builder.add(CosDictionary({
    'Type': const CosName('Catalog'),
    'Pages': treeRef,
    'OCProperties': CosDictionary({
      'OCGs': CosArray(ocgRefs),
      'D': CosDictionary({
        'Order': CosArray(ocgRefs),
        'ON': CosArray(ocgRefs),
        'OFF': CosArray(const []),
      }),
    }),
  }));

  return builder.build(root: catalog);
}

String _f(double v) => v.toStringAsFixed(2);

/// The `DeviceRGB` base image: a DCT payload when the tool supplied one, else a
/// hermetic `FlateDecode` scanned-drawing tile (mostly-white paper, sparse
/// dark linework - the shape that compresses like a real scan rather than
/// noise).
CosStream _baseImage(PdfUnderlaySpec u, CosReference maskRef, ZLibEncoder zlib) {
  final w = u.width, h = u.height;
  final payload = u.payload;
  if (payload != null) {
    return CosStream(
      CosDictionary({
        'Type': const CosName('XObject'),
        'Subtype': const CosName('Image'),
        'Width': CosInteger(w),
        'Height': CosInteger(h),
        'ColorSpace': const CosName('DeviceRGB'),
        'BitsPerComponent': const CosInteger(8),
        'Filter': const CosName('DCTDecode'),
        'SMask': maskRef,
        'Length': CosInteger(payload.length),
      }),
      payload,
    );
  }

  final rgb = Uint8List(w * h * 3)..fillRange(0, w * h * 3, 0xF8);
  void mark(int x, int y) {
    if (x < 0 || x >= w || y < 0 || y >= h) return;
    final i = (y * w + x) * 3;
    rgb[i] = 0x20;
    rgb[i + 1] = 0x24;
    rgb[i + 2] = 0x30;
  }

  for (var y = 0; y < h; y += 97) {
    for (var x = 0; x < w; x++) {
      mark(x, y);
    }
  }
  for (var x = 0; x < w; x += 131) {
    for (var y = 0; y < h; y++) {
      mark(x, y);
    }
  }
  final deflated = Uint8List.fromList(zlib.encode(rgb));
  return CosStream(
    CosDictionary({
      'Type': const CosName('XObject'),
      'Subtype': const CosName('Image'),
      'Width': CosInteger(w),
      'Height': CosInteger(h),
      'ColorSpace': const CosName('DeviceRGB'),
      'BitsPerComponent': const CosInteger(8),
      'Filter': const CosName('FlateDecode'),
      'SMask': maskRef,
      'Length': CosInteger(deflated.length),
    }),
    deflated,
  );
}

/// A same-size `DeviceGray` soft mask, non-DCT (`FlateDecode`). Mostly opaque
/// (0xFF) with a sparse transparent border and cut-outs, so it stays highly
/// compressible - a few tens of KB for tens of megapixels, like the real file.
CosStream _softMask(int w, int h, ZLibEncoder zlib, _Lcg random) {
  final alpha = Uint8List(w * h)..fillRange(0, w * h, 0xFF);
  // Transparent margin, so the mask actually does something on composite.
  const margin = 24;
  void clear(int x, int y) {
    if (x < 0 || x >= w || y < 0 || y >= h) return;
    alpha[y * w + x] = 0;
  }

  for (var y = 0; y < h; y++) {
    for (var x = 0; x < margin; x++) {
      clear(x, y);
      clear(w - 1 - x, y);
    }
  }
  for (var x = 0; x < w; x++) {
    for (var y = 0; y < margin; y++) {
      clear(x, y);
      clear(x, h - 1 - y);
    }
  }
  final deflated = Uint8List.fromList(zlib.encode(alpha));
  return CosStream(
    CosDictionary({
      'Type': const CosName('XObject'),
      'Subtype': const CosName('Image'),
      'Width': CosInteger(w),
      'Height': CosInteger(h),
      'ColorSpace': const CosName('DeviceGray'),
      'BitsPerComponent': const CosInteger(8),
      'Filter': const CosName('FlateDecode'),
      'Length': CosInteger(deflated.length),
    }),
    deflated,
  );
}

/// Deterministic 64-bit LCG (VM-only fixture tool; no web number concerns).
class _Lcg {
  _Lcg(this._state);
  int _state;

  int _next() =>
      _state = (_state * 6364136223846793005 + 1442695040888963407) &
          0x7FFFFFFFFFFFFFFF;

  double unit() => (_next() >> 11) * (1.0 / (1 << 52));

  double range(double lo, double hi) => lo + unit() * (hi - lo);

  int intBelow(int n) => (unit() * n).floor();
}
