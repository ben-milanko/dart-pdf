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

  static String _path(PdfPath p) {
    final b = StringBuffer('segs=${p.segments.length}[');
    for (final s in p.segments) {
      switch (s) {
        case PdfMoveTo(:final x, :final y):
          b.write('M$x,$y;');
        case PdfLineTo(:final x, :final y):
          b.write('L$x,$y;');
        case PdfCubicTo(:final x1, :final y1, :final x2, :final y2, :final x3, :final y3):
          b.write('C$x1,$y1,$x2,$y2,$x3,$y3;');
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
      log.add('gradient ${_path(path)} ${rule.name} radial=${gradient.isRadial} '
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

  // The worker path: serializeCommands(decodeImages: true) decodes each image
  // off-thread and embeds the premultiplied RGBA, so the reconstructed request
  // carries pixels that match the pure-Dart decode — and the replay transcript
  // is unchanged (the decode never alters the command shape).
  group('image decode offload', () {
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
