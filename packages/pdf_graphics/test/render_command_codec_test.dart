// Byte-codec round-trip for the recorded command buffer — the wire format the
// background-isolate / Web-Worker render path crosses. A recorded buffer
// serialized to bytes and read back must replay into the EXACT same device
// transcript as the original buffer. Pure Dart, no dart:ui: it proves the
// codec preserves every command and value type (paths, colours, strokes,
// gradients, meshes, text runs with glyph outlines, nested soft-mask groups).
//
// Image XObjects serialize too (given the source document via `cos`):
// serializeCommands inline-resolves the image's stream subgraph, so the buffer
// round-trips to the same transcript (the transcript captures the image's
// transform + alpha, which survive). Without a `cos`, or for an inline image,
// the buffer still declines to null and the caller renders that page locally.
import 'dart:io';
import 'dart:typed_data';

import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:test/test.dart';

/// Deterministic transcript of every device call, recursing into soft-mask
/// content — the same shape as render_command_test's oracle.
class _TranscriptDevice implements PdfDevice {
  final List<String> log = [];

  // Path coordinates ride the wire as float32 (the codec stores geometry at
  // f32 precision — see _writePath in render_command_codec.dart). The render
  // engine truncates every coordinate to f32 regardless, and that truncation is
  // idempotent, so a page renders pixel-identically whether the codec shipped
  // the original f64 or its f32 image; the only observable effect is here, in
  // the transcript. Quantizing both sides to f32 compares paths at the codec's
  // actual precision rather than asserting an f64 round-trip the format never
  // promised. Everything else (matrices, colours, widths, text positions) stays
  // f64 and is compared verbatim.
  static final Float32List _f32cell = Float32List(1);
  static double _f32(double v) {
    _f32cell[0] = v;
    return _f32cell[0];
  }

  static String _path(PdfPath p) {
    final b = StringBuffer('segs=${p.segments.length}[');
    for (final s in p.segments) {
      switch (s) {
        case PdfMoveTo(:final x, :final y):
          b.write('M${_f32(x)},${_f32(y)};');
        case PdfLineTo(:final x, :final y):
          b.write('L${_f32(x)},${_f32(y)};');
        case PdfCubicTo(
            :final x1,
            :final y1,
            :final x2,
            :final y2,
            :final x3,
            :final y3
          ):
          b.write('C${_f32(x1)},${_f32(y1)},${_f32(x2)},${_f32(y2)},'
              '${_f32(x3)},${_f32(y3)};');
        case PdfClosePath():
          b.write('Z;');
      }
    }
    return (b..write(']')).toString();
  }

  static String _matrix(PdfMatrix m) =>
      '[${m.a},${m.b},${m.c},${m.d},${m.e},${m.f}]';

  static String _color(PdfColor c) => '${c.red},${c.green},${c.blue}';

  @override
  void save() => log.add('save');

  @override
  void restore() => log.add('restore');

  @override
  void fillPath(PdfPath path, PdfColor color, PdfFillRule rule, double alpha) =>
      log.add('fill ${_path(path)} ${_color(color)} ${rule.name} $alpha');

  @override
  void fillPathGradient(
          PdfPath path, PdfFillRule rule, PdfGradient gradient, double alpha) =>
      log.add(
          'gradient ${_path(path)} ${rule.name} radial=${gradient.isRadial} '
          'coords=${gradient.coords} stops=${gradient.stops} '
          'colors=${gradient.colors.length} '
          'ext=${gradient.extendStart},${gradient.extendEnd} '
          'm=${_matrix(gradient.transform)} $alpha');

  @override
  void fillMesh(PdfMesh mesh, double alpha) => log.add(
      'mesh verts=${mesh.vertices.length} tris=${mesh.triangles.length} $alpha');

  @override
  void strokePath(
          PdfPath path, PdfColor color, PdfStroke stroke, double alpha) =>
      log.add('stroke ${_path(path)} ${_color(color)} w=${stroke.width} '
          'cap=${stroke.cap} join=${stroke.join} ml=${stroke.miterLimit} '
          'dash=${stroke.dashArray} phase=${stroke.dashPhase} $alpha');

  @override
  void clipPath(PdfPath path, PdfFillRule rule) =>
      log.add('clip ${_path(path)} ${rule.name}');

  @override
  void drawText(PdfTextRun run) => log.add('text "${run.text}" '
      '${_matrix(run.transform)} ${_color(run.color)} w=${run.width} '
      'font=${run.fontName} size=${run.fontSize} fill=${run.fill} '
      'invisible=${run.invisible} sw=${run.strokeWidth} '
      'glyphs=${run.glyphs?.length}');

  @override
  void drawImage(PdfImageRequest request) =>
      log.add('image ${_matrix(request.transform)} a=${request.alpha}');

  @override
  void setBlendMode(PdfBlendMode mode) => log.add('blend ${mode.name}');

  @override
  void beginGroup(double alpha, {bool knockout = false}) =>
      log.add('beginGroup $alpha knockout=$knockout');

  @override
  void endGroup() => log.add('endGroup');

  @override
  void beginSoftMasked() => log.add('beginSoftMasked');

  @override
  void endSoftMasked(
      {required bool luminosity,
      required PdfRect backdrop,
      required void Function() drawMask,
      double backdropLuminance = 0,
      double transferScale = 1,
      double transferOffset = 0}) {
    log.add('endSoftMasked lum=$luminosity bd=$backdropLuminance '
        'ts=$transferScale to=$transferOffset back=${backdrop.left},'
        '${backdrop.bottom},${backdrop.right},${backdrop.top} {');
    drawMask();
    log.add('}');
  }
}

List<String> _transcript(List<PdfRenderCommand> commands) {
  final device = _TranscriptDevice();
  replayCommands(commands, device);
  return device.log;
}

RecordingPdfDevice _record(CosDocument doc, String content) {
  final recorder = RecordingPdfDevice();
  PdfInterpreter(cos: doc, device: recorder).run(
    ContentStreamParser.parse(Uint8List.fromList(content.codeUnits)),
    CosDictionary(),
  );
  return recorder;
}

void main() {
  group('synthetic round-trip', () {
    final cases = <String, String>{
      'fills and strokes':
          'q 2 0 0 2 10 10 cm 0 0 1 rg 5 5 20 30 re f 1 0 0 RG 4 w '
              '0 0 10 10 re S Q',
      'dashed stroke': '[3 2] 1.5 d 1 w 10 10 m 90 90 l S',
      'clip then fill': '0 0 5 5 re W n 0 0 1 rg 0 0 10 10 re f',
      'text': 'BT /F1 24 Tf 72 720 Td (Hello, world!) Tj ET',
      'nested q/Q': 'q q 0 0 1 1 re f Q q 1 1 2 2 re f Q Q',
      'curves': '10 10 m 20 30 40 30 50 10 c f',
      'even-odd fill': '0 0 10 10 re 2 2 6 6 re f*',
    };
    cases.forEach((name, content) {
      test(name, () {
        final recorder = _record(CosDocument.open(buildClassicPdf()), content);
        final original = _transcript(recorder.commands);
        expect(original, isNotEmpty);

        final bytes = serializeCommands(recorder.commands);
        expect(bytes, isNotNull, reason: 'no images, should serialize');
        final restored = deserializeCommands(bytes!);
        expect(_transcript(restored), equals(original));
      });
    });

    test('byte output is stable across two serializations', () {
      final recorder = _record(CosDocument.open(buildClassicPdf()),
          'q 0 0 1 rg 5 5 20 30 re f Q BT /F1 12 Tf 10 10 Td (hi) Tj ET');
      final a = serializeCommands(recorder.commands)!;
      final b = serializeCommands(recorder.commands)!;
      expect(a, equals(b));
    });
  });

  // Real pages exercise the fragile callbacks: transparency groups, soft masks
  // (their drawMask content), blend modes, gradients, knockout — and images,
  // which round-trip through the inline-resolved stream subgraph (given `cos`)
  // to the same transcript, or decline to null without a `cos`.
  group('corpus round-trip', () {
    final files = <String>[
      '../../test_corpora/ghent/1-CMYK/GWG168_Softmasks_Vector_part1_X4.pdf',
      '../../test_corpora/ghent/1-CMYK/GWG1610_Softmasks_Text_part1_X4.pdf',
      '../../test_corpora/ghent/1-CMYK/'
          'GWG160_Transp_Basic_BM_DeviceCMYK_Non-knockout_X4.pdf',
      '../../test_corpora/ghent/1-CMYK/'
          'GWG161_Transp_Basic_BM_DeviceCMYK_Knockout_X4.pdf',
      '../../test_corpora/ghent/1-CMYK/GWG060_Shading_x1a.pdf',
      '../../test_corpora/ghent/1-CMYK/GWG061_Shading_x1a.pdf',
    ];
    for (final path in files) {
      final file = File(path);
      final name = path.split('/').last;
      test(name, () {
        if (!file.existsSync()) {
          markTestSkipped('$path not found');
          return;
        }
        final doc = PdfDocument.open(file.readAsBytesSync());
        for (var i = 0; i < doc.pageCount; i++) {
          final page = doc.page(i);
          final ops = ContentStreamParser.parse(page.contentBytes());
          final recorder = RecordingPdfDevice();
          PdfInterpreter(cos: doc.cos, device: recorder)
              .drawPageOperations(page, ops);

          // Without a `cos`, image pages decline (null); image-free pages still
          // serialize.
          final noCos = serializeCommands(recorder.commands);
          if (recorder.imageRequests.isNotEmpty) {
            expect(noCos, isNull,
                reason: '$name page $i draws images — declines without a cos');
          } else {
            expect(noCos, isNotNull, reason: '$name page $i has no images');
          }

          // With the document, image XObjects serialize via their inlined
          // stream subgraph; the buffer round-trips to the same transcript.
          // (An inline image would still decline — none in these fixtures.)
          final bytes = serializeCommands(recorder.commands, cos: doc.cos);
          expect(bytes, isNotNull,
              reason: '$name page $i should serialize with a cos');
          final restored = deserializeCommands(bytes!);
          expect(_transcript(restored), equals(_transcript(recorder.commands)),
              reason: '$name page $i transcript diverged after round-trip');
        }
      });
    }
  });

  test('inline images can be placeholders in vector-only buffers', () {
    final doc = PdfDocument.open(_inlineImagePdf());
    final page = doc.page(0);
    final ops = ContentStreamParser.parse(page.contentBytes());
    final recorder = RecordingPdfDevice();
    PdfInterpreter(cos: doc.cos, device: recorder)
        .drawPageOperations(page, ops);
    expect(recorder.imageRequests.single.isInline, isTrue);

    expect(serializeCommands(recorder.commands, cos: doc.cos), isNull,
        reason: 'full/default serialization still declines inline images');

    final bytes = serializeCommands(recorder.commands,
        cos: doc.cos, imagePlaceholders: true);
    expect(bytes, isNotNull,
        reason: 'vector-only buffers preserve an image placeholder');

    final restored = deserializeCommands(bytes!);
    expect(_transcript(restored), equals(_transcript(recorder.commands)));
    expect(_imageCommands(restored).single.request.decoded, isNull);
  });

  // The worker path: serializeCommands(decodeImages: true) decodes each image
  // off-thread and embeds the premultiplied RGBA, so the reconstructed request
  // carries pixels that match the pure-Dart decode — and the replay transcript
  // is unchanged (the decode never alters the command shape).
  group('image decode offload', () {
    test('uses predecoded image request pixels', () {
      final cos = CosDocument.open(buildClassicPdf());
      final stream = CosStream(
        CosDictionary({
          'Width': const CosInteger(1),
          'Height': const CosInteger(1),
          'BitsPerComponent': const CosInteger(8),
          'ColorSpace': const CosName('DeviceRGB'),
          'Filter': const CosName('DCTDecode'),
        }),
        Uint8List.fromList([0xff, 0xd8, 0xff, 0xd9]),
      );
      final decoded = PdfDecodedPixels(
        Uint8List.fromList([11, 22, 33, 255]),
        1,
        1,
      );
      final command = PdfDrawImageCommand(PdfImageRequest(
        stream: stream,
        transform: PdfMatrix.identity,
        decoded: decoded,
      ));

      final bytes = serializeCommands([command], cos: cos, decodeImages: true);
      expect(bytes, isNotNull);
      final restored = _imageCommands(deserializeCommands(bytes!)).single;
      expect(restored.request.decoded, isNotNull);
      expect(restored.request.decoded!.width, 1);
      expect(restored.request.decoded!.height, 1);
      expect(restored.request.decoded!.rgba, decoded.rgba);
    });

    final files = <String>[
      '../../test_corpora/ghent/1-CMYK/'
          'GWG166_Softmasks_Images_DeviceCMYK_X4.pdf',
      '../../test_corpora/ghent/1-CMYK/GWG168_Softmasks_Vector_part1_X4.pdf',
    ];
    for (final path in files) {
      final file = File(path);
      final name = path.split('/').last;
      test(name, () {
        if (!file.existsSync()) {
          markTestSkipped('$path not found');
          return;
        }
        final doc = PdfDocument.open(file.readAsBytesSync());
        var sawDecoded = false;
        for (var i = 0; i < doc.pageCount; i++) {
          final page = doc.page(i);
          final ops = ContentStreamParser.parse(page.contentBytes());
          final recorder = RecordingPdfDevice();
          PdfInterpreter(cos: doc.cos, device: recorder)
              .drawPageOperations(page, ops);
          final originals = recorder.imageRequests.toList();

          final bytes = serializeCommands(recorder.commands,
              cos: doc.cos, decodeImages: true);
          if (bytes == null) continue; // inline image on the page: declines
          final restored = deserializeCommands(bytes);
          // The off-thread decode must not change what gets painted.
          expect(_transcript(restored), equals(_transcript(recorder.commands)),
              reason: '$name page $i transcript diverged with decodeImages');

          final images = _imageCommands(restored);
          expect(images.length, originals.length,
              reason: '$name page $i image count diverged');
          for (var k = 0; k < originals.length; k++) {
            final expected = decodePdfImagePixels(doc.cos, originals[k].stream);
            final got = images[k].request.decoded;
            if (expected == null) {
              expect(got, isNull,
                  reason: '$name page $i image $k needs the platform codec — '
                      'ships no pixels');
            } else {
              expect(got, isNotNull,
                  reason: '$name page $i image $k should carry decoded pixels');
              expect(got!.width, expected.width);
              expect(got.height, expected.height);
              expect(got.rgba, equals(expected.rgba),
                  reason: '$name page $i image $k pixels diverged');
              sawDecoded = true;
            }
          }
        }
        expect(sawDecoded, isTrue,
            reason: '$name exercised no off-thread image decode');
      });
    }
  });

  // maxImagePixelRatio caps each decoded image to ~display resolution before it
  // crosses the worker boundary — the fix for raster-thread jank on CAD sheets
  // whose embedded underlays are 100+ megapixels. A tiny ratio must shrink
  // them; a null/huge ratio must leave them at native resolution; and the
  // command transcript must be untouched either way (only the pixels change).
  group('image resolution cap', () {
    final files = <String>[
      '../../test_corpora/ghent/1-CMYK/'
          'GWG166_Softmasks_Images_DeviceCMYK_X4.pdf',
      '../../test_corpora/ghent/1-CMYK/GWG168_Softmasks_Vector_part1_X4.pdf',
    ];
    for (final path in files) {
      final file = File(path);
      final name = path.split('/').last;
      test(name, () {
        if (!file.existsSync()) {
          markTestSkipped('$path not found');
          return;
        }
        final doc = PdfDocument.open(file.readAsBytesSync());
        var sawCapped = false;
        for (var i = 0; i < doc.pageCount; i++) {
          final page = doc.page(i);
          final ops = ContentStreamParser.parse(page.contentBytes());
          final recorder = RecordingPdfDevice();
          PdfInterpreter(cos: doc.cos, device: recorder)
              .drawPageOperations(page, ops);

          final uncapped = serializeCommands(recorder.commands,
              cos: doc.cos, decodeImages: true);
          if (uncapped == null) continue; // inline image: page declines
          // A tiny ratio drives every image to display resolution; a huge ratio
          // can never downscale (the cap never upscales).
          final capped = serializeCommands(recorder.commands,
              cos: doc.cos, decodeImages: true, maxImagePixelRatio: 0.002);
          final huge = serializeCommands(recorder.commands,
              cos: doc.cos, decodeImages: true, maxImagePixelRatio: 1e6);
          expect(capped, isNotNull);
          expect(huge, isNotNull);

          final native = _imageCommands(deserializeCommands(uncapped));
          final small = _imageCommands(deserializeCommands(capped!));
          final big = _imageCommands(deserializeCommands(huge!));

          // The cap only changes pixels, never the command stream.
          expect(_transcript(deserializeCommands(capped)),
              equals(_transcript(deserializeCommands(uncapped))),
              reason: '$name page $i transcript diverged under the cap');

          for (var k = 0; k < native.length; k++) {
            final nat = native[k].request.decoded;
            final cap = small[k].request.decoded;
            final hg = big[k].request.decoded;
            if (nat == null) {
              // Platform-codec image: ships no pixels regardless of the ratio.
              expect(cap, isNull);
              expect(hg, isNull);
              continue;
            }
            expect(cap, isNotNull);
            expect(hg, isNotNull);
            // A huge ratio leaves native resolution untouched.
            expect(hg!.width, nat.width);
            expect(hg.height, nat.height);
            // A tiny ratio never exceeds native and never under-runs 1px.
            expect(cap!.width, lessThanOrEqualTo(nat.width));
            expect(cap.height, lessThanOrEqualTo(nat.height));
            expect(cap.width, greaterThanOrEqualTo(1));
            expect(cap.height, greaterThanOrEqualTo(1));
            expect(cap.rgba.length, cap.width * cap.height * 4);
            if (cap.width < nat.width || cap.height < nat.height) {
              sawCapped = true;
            }
          }
        }
        expect(sawCapped, isTrue,
            reason: '$name capped no image — the test proved nothing');
      });
    }
  });

  // imageBudgetFactor bounds the TOTAL decoded pixels of a page to a multiple
  // of the page raster cap, on top of the per-image cap — the fix for sheets
  // layered from dozens of overlapping raster tiles, where each image is near
  // its own footprint yet their sum dwarfs the raster. A tiny factor forces
  // the page budget to bind even on these small pages: total decoded pixels
  // must drop below the budget, while the command transcript stays identical.
  group('page image budget', () {
    final files = <String>[
      '../../test_corpora/ghent/1-CMYK/'
          'GWG166_Softmasks_Images_DeviceCMYK_X4.pdf',
    ];
    for (final path in files) {
      final file = File(path);
      final name = path.split('/').last;
      test(name, () {
        if (!file.existsSync()) {
          markTestSkipped('$path not found');
          return;
        }
        final doc = PdfDocument.open(file.readAsBytesSync());
        var sawBudgeted = false;
        for (var i = 0; i < doc.pageCount; i++) {
          final page = doc.page(i);
          final ops = ContentStreamParser.parse(page.contentBytes());
          final recorder = RecordingPdfDevice();
          PdfInterpreter(cos: doc.cos, device: recorder)
              .drawPageOperations(page, ops);

          // Huge per-image ratio => the per-image cap is a no-op, isolating the
          // page-budget effect. Default budget leaves these small pages native.
          final native = serializeCommands(recorder.commands,
              cos: doc.cos, decodeImages: true, maxImagePixelRatio: 1e6);
          if (native == null) continue; // inline image: page declines
          // A tiny budget (0.0005 * 16.78 MP ~ 8.4 Kpx) forces the page total
          // down regardless of how the images are laid out.
          const factor = 0.0005;
          final budgeted = serializeCommands(recorder.commands,
              cos: doc.cos,
              decodeImages: true,
              maxImagePixelRatio: 1e6,
              imageBudgetFactor: factor);
          expect(budgeted, isNotNull);

          // The budget changes pixels only, never the command stream.
          expect(_transcript(deserializeCommands(budgeted!)),
              equals(_transcript(deserializeCommands(native))),
              reason: '$name page $i transcript diverged under the budget');

          final nativePixels = _decodedPixelSum(deserializeCommands(native));
          final budgetedPixels =
              _decodedPixelSum(deserializeCommands(budgeted));
          if (nativePixels == 0) {
            continue; // platform-codec only: nothing decoded
          }
          final budgetPixels = (factor * (1 << 24)).round();
          // Total decoded pixels sit under the budget, plus a per-image ceil
          // slop (each image rounds its target edges up).
          final imageCount =
              _imageCommands(deserializeCommands(budgeted)).length;
          expect(budgetedPixels,
              lessThanOrEqualTo(budgetPixels + imageCount * 16 + 64),
              reason: '$name page $i total decoded pixels ($budgetedPixels) '
                  'exceed the page budget ($budgetPixels)');
          expect(budgetedPixels, lessThan(nativePixels),
              reason: '$name page $i budget did not shrink the page total');
          sawBudgeted = true;
        }
        expect(sawBudgeted, isTrue,
            reason: '$name page budget bound no page — proved nothing');
      });
    }
  });
}

/// Sum of decoded pixels across every image draw (DFS, soft-mask groups too).
int _decodedPixelSum(List<PdfRenderCommand> commands) {
  var total = 0;
  for (final c in _imageCommands(commands)) {
    final d = c.request.decoded;
    if (d != null) total += d.width * d.height;
  }
  return total;
}

/// Every image draw command in [commands], in replay (DFS) order, descending
/// into soft-mask groups — the same order serializeCommands writes them.
List<PdfDrawImageCommand> _imageCommands(List<PdfRenderCommand> commands) {
  final out = <PdfDrawImageCommand>[];
  void walk(List<PdfRenderCommand> cs) {
    for (final c in cs) {
      if (c is PdfDrawImageCommand) {
        out.add(c);
      } else if (c is PdfEndSoftMaskedCommand) {
        walk(c.maskCommands);
      }
    }
  }

  walk(commands);
  return out;
}

/// A one-page PDF whose only content is a 4x4 inline image (BI .. ID .. EI).
Uint8List _inlineImagePdf() {
  const content = 'q 100 0 0 100 50 50 cm '
      'BI /W 4 /H 4 /CS /RGB /BPC 8 /F /AHx ID\n'
      'e63030 ffffff e63030 ffffff\n'
      'ffffff e63030 ffffff e63030\n'
      'e63030 ffffff e63030 ffffff\n'
      'ffffff e63030 ffffff e63030 >\nEI Q\n';
  final objects = <String>[
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] /Contents 4 0 R >>',
    '<< /Length ${content.length} >>\nstream\n$content\nendstream',
  ];
  final buffer = StringBuffer('%PDF-1.4\n');
  final offsets = <int>[];
  for (var i = 0; i < objects.length; i++) {
    offsets.add(buffer.length);
    buffer.write('${i + 1} 0 obj\n${objects[i]}\nendobj\n');
  }
  final xref = buffer.length;
  buffer.write('xref\n0 ${objects.length + 1}\n');
  buffer.write('0000000000 65535 f \n');
  for (final off in offsets) {
    buffer.write('${off.toString().padLeft(10, '0')} 00000 n \n');
  }
  buffer.write('trailer << /Size ${objects.length + 1} /Root 1 0 R >>\n');
  buffer.write('startxref\n$xref\n%%EOF\n');
  return Uint8List.fromList(buffer.toString().codeUnits);
}
