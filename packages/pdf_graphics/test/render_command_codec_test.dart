// Byte-codec round-trip for the recorded command buffer - the wire format the
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
/// content - the same shape as render_command_test's oracle.
class _TranscriptDevice implements PdfDevice {
  final List<String> log = [];

  // Path coordinates ride the wire as float32 (the codec stores geometry at
  // f32 precision - see _writePath in render_command_codec.dart). The render
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
      'ls=${run.letterSpacing} ws=${run.wordSpacing} '
      'ld=${run.leadingSpace} vw=${run.visibleWidth} '
      'glyphs=${run.glyphs?.length}');

  @override
  void drawImage(PdfImageRequest request) =>
      log.add('image ${_matrix(request.transform)} a=${request.alpha}');

  @override
  void setBlendMode(PdfBlendMode mode) => log.add('blend ${mode.name}');
  @override
  void setOverprint(
          {required bool fill, required bool stroke, required int mode}) =>
      log.add('overprint $fill $stroke $mode');

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
      // Word spacing (Tw) with leading and trailing spaces exercises the
      // letterSpacing/wordSpacing/leadingSpace/visibleWidth wire fields.
      'word-spaced tabular text':
          'BT /F1 10 Tf 5 Tw 0.2 Tc 72 700 Td ( ab ) Tj ET',
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

  group('worker state-scope compaction', () {
    test('drops clip-free scopes but preserves clip-owning scopes', () {
      final doc = CosDocument.open(buildClassicPdf());
      final recorder = _record(
          doc,
          'q 0 0 10 10 re f Q '
          'q 0 0 5 5 re W n 0 0 10 10 re f Q '
          'q q 1 1 4 4 re W n 0 0 10 10 re f Q Q');

      final bytes = serializeCommands(
        recorder.commands,
        compactStateScopes: true,
      )!;
      final compacted = deserializeCommands(bytes);

      expect(compacted.whereType<PdfFillPathCommand>(), hasLength(3));
      expect(compacted.whereType<PdfClipPathCommand>(), hasLength(2));
      expect(compacted.whereType<PdfSaveCommand>(), hasLength(2));
      expect(compacted.whereType<PdfRestoreCommand>(), hasLength(2));
      expect(compacted.first, isA<PdfFillPathCommand>(),
          reason: 'the first clip-free q/Q pair should disappear');
    });

    test('keeps unmatched state commands in a command-limited prefix', () {
      final recorder =
          _record(CosDocument.open(buildClassicPdf()), 'q 0 0 10 10 re f Q');
      final bytes = serializeCommands(
        recorder.commands,
        commandLimit: 2,
        compactStateScopes: true,
      )!;
      final compacted = deserializeCommands(bytes);

      expect(compacted, hasLength(2));
      expect(compacted[0], isA<PdfSaveCommand>());
      expect(compacted[1], isA<PdfFillPathCommand>());
    });

    test('keeps explicit blend restoration while dropping its scope', () {
      const path = PdfPath([
        PdfMoveTo(0, 0),
        PdfLineTo(1, 0),
        PdfLineTo(1, 1),
        PdfClosePath(),
      ]);
      final commands = <PdfRenderCommand>[
        const PdfSaveCommand(),
        const PdfSetBlendModeCommand(PdfBlendMode.multiply),
        const PdfFillPathCommand(path, PdfColor.black, PdfFillRule.nonzero, 1),
        const PdfSetBlendModeCommand(PdfBlendMode.normal),
        const PdfRestoreCommand(),
      ];

      final restored = deserializeCommands(
        serializeCommands(commands, compactStateScopes: true)!,
      );
      expect(restored, hasLength(3));
      expect(restored[0], isA<PdfSetBlendModeCommand>());
      expect(restored[1], isA<PdfFillPathCommand>());
      expect(restored[2], isA<PdfSetBlendModeCommand>());
    });

    test('round-trips overprint state (fill/stroke/mode) through the codec', () {
      final commands = <PdfRenderCommand>[
        const PdfSetOverprintCommand(fill: true, stroke: false, mode: 1),
        const PdfSetOverprintCommand(fill: false, stroke: true, mode: 0),
      ];
      final restored = deserializeCommands(serializeCommands(commands)!);
      expect(restored, hasLength(2));
      expect(restored[0], isA<PdfSetOverprintCommand>());
      final first = restored[0] as PdfSetOverprintCommand;
      expect((first.fill, first.stroke, first.mode), (true, false, 1));
      final second = restored[1] as PdfSetOverprintCommand;
      expect((second.fill, second.stroke, second.mode), (false, true, 0));
    });

    test('compacts soft-mask callback commands recursively', () {
      const path = PdfPath([
        PdfMoveTo(0, 0),
        PdfLineTo(1, 0),
        PdfLineTo(1, 1),
        PdfClosePath(),
      ]);
      final commands = <PdfRenderCommand>[
        PdfEndSoftMaskedCommand(
          luminosity: false,
          backdrop: const PdfRect(0, 0, 1, 1),
          maskCommands: const [
            PdfSaveCommand(),
            PdfFillPathCommand(path, PdfColor.black, PdfFillRule.nonzero, 1),
            PdfRestoreCommand(),
          ],
        ),
      ];

      final restored = deserializeCommands(
        serializeCommands(commands, compactStateScopes: true)!,
      );
      final mask = (restored.single as PdfEndSoftMaskedCommand).maskCommands;
      expect(mask, hasLength(1));
      expect(mask.single, isA<PdfFillPathCommand>());
    });
  });

  // Real pages exercise the fragile callbacks: transparency groups, soft masks
  // (their drawMask content), blend modes, gradients, knockout - and images,
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
                reason: '$name page $i draws images - declines without a cos');
          } else {
            expect(noCos, isNotNull, reason: '$name page $i has no images');
          }

          // With the document, image XObjects serialize via their inlined
          // stream subgraph; the buffer round-trips to the same transcript.
          // (An inline image would still decline - none in these fixtures.)
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

  test('an inline ImageMask (stencil) serializes - Type3 pages reach the '
      'worker (#554)', () {
    final doc = PdfDocument.open(_inlineStencilPdf());
    final page = doc.page(0);
    final ops = ContentStreamParser.parse(page.contentBytes());
    final recorder = RecordingPdfDevice();
    PdfInterpreter(cos: doc.cos, device: recorder).drawPageOperations(page, ops);
    final request = recorder.imageRequests.single;
    expect(request.isInline, isTrue);
    expect(request.isStencil, isTrue);

    // Unlike a colour inline image, a stencil has no /CS to resolve, so it does
    // NOT decline - the whole point of #554 (Type3 bitmap-glyph pages).
    final bytes = serializeCommands(recorder.commands, cos: doc.cos);
    expect(bytes, isNotNull,
        reason: 'a self-contained stencil inline image must not decline');

    final restored = _imageCommands(deserializeCommands(bytes!)).single.request;
    expect(restored.isStencil, isTrue);
    expect(restored.isInline, isTrue);
    expect(restored.stencilColor, request.stencilColor,
        reason: 'the stencil paint colour round-trips');
  });

  test('the stencil inline image also decodes off-thread (#554)', () {
    final doc = PdfDocument.open(_inlineStencilPdf());
    final page = doc.page(0);
    final ops = ContentStreamParser.parse(page.contentBytes());
    final recorder = RecordingPdfDevice();
    PdfInterpreter(cos: doc.cos, device: recorder).drawPageOperations(page, ops);

    final bytes = serializeCommands(recorder.commands,
        cos: doc.cos, decodeImages: true);
    expect(bytes, isNotNull);
    final restored = _imageCommands(deserializeCommands(bytes!)).single.request;
    expect(restored.isStencil, isTrue);
    expect(restored.decoded, isNotNull,
        reason: 'the worker embeds the decoded stencil mask');
  });

  // The worker path: serializeCommands(decodeImages: true) decodes each image
  // off-thread and embeds the premultiplied RGBA, so the reconstructed request
  // carries pixels that match the pure-Dart decode - and the replay transcript
  // is unchanged (the decode never alters the command shape).
  // A glyph outline rides on every *placement*, so text-heavy records used to
  // carry one copy of a letter's geometry per occurrence: 151.7 MB of 394 MB
  // over a 62-page book, 85% of it repetition (#451). The writer now emits the
  // geometry once and references it by id.
  //
  // The transcript oracle above cannot police this - it logs `glyphs.length`
  // and never looks at outline geometry - so these compare the paths directly.
  group('glyph outline deduplication (#451)', () {
    // One glyph's geometry, deliberately chunky so repetition is measurable.
    PdfPath outline(double seed) => PdfPath([
          PdfMoveTo(seed, 0),
          for (var i = 0; i < 40; i++)
            PdfCubicTo(seed + i, 1.5, seed + i + 0.25, 2.5, seed + i + 0.5, 3),
          const PdfClosePath(),
        ]);

    List<PdfRenderCommand> run(List<PdfPath?> outlines) => [
          PdfDrawTextCommand(PdfTextRun(
            text: 'x' * outlines.length,
            transform: PdfMatrix.identity,
            color: PdfColor.black,
            width: outlines.length.toDouble(),
            glyphs: [
              for (final (i, o) in outlines.indexed)
                PdfGlyphPlacement(offset: i.toDouble(), outline: o),
            ],
          )),
        ];

    List<PdfPath?> restoredOutlines(Uint8List bytes) => [
          for (final c in deserializeCommands(bytes))
            if (c is PdfDrawTextCommand)
              ...?c.run.glyphs?.map((g) => g.outline),
        ];

    void expectSamePath(PdfPath? actual, PdfPath? expected, String reason) {
      if (expected == null) {
        expect(actual, isNull, reason: reason);
        return;
      }
      expect(actual, isNotNull, reason: reason);
      expect(actual!.segments.length, expected.segments.length, reason: reason);
      for (var i = 0; i < expected.segments.length; i++) {
        final a = actual.segments[i], b = expected.segments[i];
        expect(a.runtimeType, b.runtimeType, reason: '$reason seg $i');
        if (a is PdfMoveTo && b is PdfMoveTo) {
          expect(a.x, closeTo(b.x, 1e-3), reason: '$reason seg $i');
          expect(a.y, closeTo(b.y, 1e-3), reason: '$reason seg $i');
        } else if (a is PdfCubicTo && b is PdfCubicTo) {
          expect(a.x1, closeTo(b.x1, 1e-3), reason: '$reason seg $i');
          expect(a.y3, closeTo(b.y3, 1e-3), reason: '$reason seg $i');
          expect(a.x3, closeTo(b.x3, 1e-3), reason: '$reason seg $i');
        }
      }
    }

    test('a repeated glyph costs its geometry once', () {
      final glyph = outline(1);
      final one = serializeCommands(run([glyph]))!;
      final many = serializeCommands(run(List.filled(200, glyph)))!;

      // The 199 extra placements must not each carry the geometry. Budget a
      // generous 32 bytes of per-placement bookkeeping (tag + id + offsets);
      // the geometry itself is ~1 KB.
      expect(many.length, lessThan(one.length + 199 * 32),
          reason: 'repeated placements should reference, not re-emit');

      // The control: 200 separately-constructed paths with identical geometry.
      // The table keys on identity, so these do not collapse - which is what
      // the format cost before this change, measured through the same writer.
      final unshared =
          serializeCommands(run([for (var i = 0; i < 200; i++) outline(1)]))!;
      expect(many.length * 10, lessThan(unshared.length),
          reason: 'sharing one glyph should cost <10% of emitting it 200x');
    });

    test('every placement reads back with its own geometry intact', () {
      // Distinct shapes, interleaved and repeated, so a table that returned
      // the wrong entry (or the most recent one) is caught.
      final a = outline(1), b = outline(2), c = outline(3);
      final order = <PdfPath?>[a, b, a, c, null, b, c, c, a, null, b];
      final restored = restoredOutlines(serializeCommands(run(order))!);

      expect(restored.length, order.length);
      for (var i = 0; i < order.length; i++) {
        expectSamePath(restored[i], order[i], 'placement $i');
      }
    });

    test('repeated placements share one instance after the round trip', () {
      // The dedup exists to shrink the record, but sharing on read-back also
      // means the replayed commands hold one path per glyph instead of N -
      // the same shape they had before serialization.
      final glyph = outline(1);
      final restored =
          restoredOutlines(serializeCommands(run(List.filled(50, glyph)))!);
      expect(restored, hasLength(50));
      for (final o in restored) {
        expect(identical(o, restored.first), isTrue,
            reason: 'one glyph should deserialize to one shared PdfPath');
      }
    });

    test('a truncated record throws rather than replaying a wrong glyph', () {
      // Records cross an isolate/worker boundary, where a short read is a real
      // failure mode. It must fail loudly, not hand back plausible geometry.
      final glyph = outline(1);
      final bytes = serializeCommands(run([glyph, glyph, glyph]))!;
      expect(() => deserializeCommands(bytes.sublist(0, bytes.length - 4)),
          throwsA(anything));
    });
  });

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

    test('large decoded pixel planes stay zero-copy on deserialize', () {
      final cos = CosDocument.open(buildClassicPdf());
      final stream = CosStream(
        CosDictionary({
          'Width': const CosInteger(512),
          'Height': const CosInteger(512),
          'BitsPerComponent': const CosInteger(8),
          'ColorSpace': const CosName('DeviceRGB'),
          'Filter': const CosName('DCTDecode'),
        }),
        Uint8List.fromList([0xff, 0xd8, 0xff, 0xd9]),
      );
      final decoded = PdfDecodedPixels(Uint8List(512 * 512 * 4), 512, 512);
      final command = PdfDrawImageCommand(PdfImageRequest(
        stream: stream,
        transform: PdfMatrix.identity,
        decoded: decoded,
      ));

      final bytes = serializeCommands([command], cos: cos, decodeImages: true)!;
      final restored = _imageCommands(deserializeCommands(bytes)).single;
      expect(restored.request.decoded!.rgba.buffer.lengthInBytes,
          bytes.buffer.lengthInBytes,
          reason: 'a large pixel payload should view the transferred buffer '
              'instead of copying it again on the UI isolate');
      // The public result remains growable after the pre-sizing optimization.
      final commands = deserializeCommands(bytes);
      commands.add(const PdfSaveCommand());
      expect(commands, hasLength(2));
    });

    test('imageDecodeRegion crops pixels and retargets the image transform',
        () {
      final cos = CosDocument.open(buildClassicPdf());
      final raw = <int>[];
      for (var y = 0; y < 4; y++) {
        for (var x = 0; x < 4; x++) {
          raw.addAll([x * 40, y * 50, 7]);
        }
      }
      final stream = CosStream(
        CosDictionary({
          'Width': const CosInteger(4),
          'Height': const CosInteger(4),
          'BitsPerComponent': const CosInteger(8),
          'ColorSpace': const CosName('DeviceRGB'),
          'Filter': const CosName('FlateDecode'),
        }),
        Uint8List.fromList(zlib.encode(raw)),
      );
      final command = PdfDrawImageCommand(PdfImageRequest(
        stream: stream,
        transform: const PdfMatrix(400, 0, 0, 400, 100, 200),
      ));

      final bytes = serializeCommands([command],
          cos: cos,
          decodeImages: true,
          maxImagePixelRatio: 100,
          imageDecodeRegion: const PdfRect(200, 300, 300, 400));

      expect(bytes, isNotNull);
      final restored = _imageCommands(deserializeCommands(bytes!)).single;
      final transform = restored.request.transform;
      expect(transform.a, 100);
      expect(transform.b, 0);
      expect(transform.c, 0);
      expect(transform.d, 100);
      expect(transform.e, 200);
      expect(transform.f, 300);

      final decoded = restored.request.decoded!;
      expect(decoded.width, 1);
      expect(decoded.height, 1);
      expect(decoded.rgba, [40, 100, 7, 255]);
    });

    test('imageDecodeRegion skips off-region images with transparent pixels',
        () {
      final cos = CosDocument.open(buildClassicPdf());
      final stream = CosStream(
        CosDictionary({
          'Width': const CosInteger(1),
          'Height': const CosInteger(1),
          'BitsPerComponent': const CosInteger(8),
          'ColorSpace': const CosName('DeviceRGB'),
          'Filter': const CosName('FlateDecode'),
        }),
        Uint8List.fromList(zlib.encode([255, 0, 0])),
      );
      final command = PdfDrawImageCommand(PdfImageRequest(
        stream: stream,
        transform: const PdfMatrix(10, 0, 0, 10, 0, 0),
      ));

      final bytes = serializeCommands([command],
          cos: cos,
          decodeImages: true,
          maxImagePixelRatio: 1,
          imageDecodeRegion: const PdfRect(100, 100, 110, 110));

      expect(bytes, isNotNull);
      final decoded =
          _imageCommands(deserializeCommands(bytes!)).single.request.decoded!;
      expect(decoded.width, 1);
      expect(decoded.height, 1);
      expect(decoded.rgba, [0, 0, 0, 0]);
    });

    test('imageDecodeRegion sharpens images the fast path declines (SMask)',
        () {
      // An /SMask'd image (a transparent logo, say) is exactly the kind the
      // fast region decoder bails on, so before the general-decoder fallback it
      // would drop through to the full-page cap and stay soft under deep zoom.
      // Here the visible slice must still come back cropped + region-keyed.
      final cos = CosDocument.open(buildClassicPdf());
      final baseRaw = <int>[];
      for (var y = 0; y < 4; y++) {
        for (var x = 0; x < 4; x++) {
          baseRaw.addAll([x * 40, y * 50, 7]);
        }
      }
      final smask = CosStream(
        CosDictionary({
          'Type': const CosName('XObject'),
          'Subtype': const CosName('Image'),
          'Width': const CosInteger(4),
          'Height': const CosInteger(4),
          'BitsPerComponent': const CosInteger(8),
          'ColorSpace': const CosName('DeviceGray'),
          'Filter': const CosName('FlateDecode'),
        }),
        Uint8List.fromList(zlib.encode(List<int>.filled(16, 128))),
      );
      final stream = CosStream(
        CosDictionary({
          'Width': const CosInteger(4),
          'Height': const CosInteger(4),
          'BitsPerComponent': const CosInteger(8),
          'ColorSpace': const CosName('DeviceRGB'),
          'Filter': const CosName('FlateDecode'),
          'SMask': smask,
        }),
        Uint8List.fromList(zlib.encode(baseRaw)),
      );
      // The fast Flate region path must decline this (SMask present), so the
      // fallback under test is the only way a region result comes back.
      expect(
        decodePdfImagePixelsRegionScaled(cos, stream, 1, 2, 1, 1, 1, 1),
        isNull,
      );
      final command = PdfDrawImageCommand(PdfImageRequest(
        stream: stream,
        transform: const PdfMatrix(400, 0, 0, 400, 100, 200),
      ));

      final bytes = serializeCommands([command],
          cos: cos,
          decodeImages: true,
          maxImagePixelRatio: 100,
          imageDecodeRegion: const PdfRect(200, 300, 300, 400));

      expect(bytes, isNotNull);
      final restored = _imageCommands(deserializeCommands(bytes!)).single;
      // Retargeted to the cropped slice, same as the fast-path region case.
      expect(restored.request.transform.a, 100);
      expect(restored.request.transform.d, 100);
      final decoded = restored.request.decoded!;
      expect(decoded.width, 1);
      expect(decoded.height, 1);
      // Base [40,100,7] premultiplied by the mask's alpha 128.
      expect(decoded.rgba, [20, 50, 3, 128]);
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
                  reason: '$name page $i image $k needs the platform codec - '
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
  // crosses the worker boundary - the fix for raster-thread jank on CAD sheets
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
            reason: '$name capped no image - the test proved nothing');
      });
    }
  });

  // imageBudgetFactor bounds the TOTAL decoded pixels of a page to a multiple
  // of the page raster cap, on top of the per-image cap - the fix for sheets
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
            reason: '$name page budget bound no page - proved nothing');
      });
    }
  });

  // #603: a thumbnail warm shipped ~10 MB records to fill a 256px tile,
  // because the page image budget was a multiple of the full-page raster CAP
  // (17 MP) rather than of the raster the buffer is actually drawn into. Every
  // one of those pixels is then paid for again as main-thread ui.Image work at
  // replay, which is the half of the cost no worker priority can move.
  group('pageRasterPixels', () {
    test('is page area x ratio^2, and declines degenerate input', () {
      expect(pdfPageRasterPixels(const PdfRect(0, 0, 200, 400), 1.0), 80000);
      expect(pdfPageRasterPixels(const PdfRect(0, 0, 200, 400), 0.5), 20000);
      // 256px wide tile of a US-Letter page: ~85 Kpx, against the 17 MP cap
      // the budget used to assume for it.
      expect(pdfPageRasterPixels(const PdfRect(0, 0, 612, 792), 256 / 612),
          lessThan(90000));
      expect(pdfPageRasterPixels(const PdfRect(0, 0, 200, 200), null), isNull);
      expect(pdfPageRasterPixels(const PdfRect(0, 0, 200, 200), 0), isNull);
      expect(pdfPageRasterPixels(const PdfRect(0, 0, 200, 200), -1), isNull);
      expect(pdfPageRasterPixels(const PdfRect(0, 0, 0, 200), 1.0), isNull);
    });

    test('holds a layered page to what the tile can show', () {
      // Four full-bleed 512x512 images on a 200pt page - the layered shape a
      // scanned book page has, and the one the per-image cap cannot bound
      // (each image IS its own footprint; only their sum is the problem).
      final doc = PdfDocument.open(_layeredImagePdf(draws: 4));
      final page = doc.page(0);
      final recorder = RecordingPdfDevice();
      PdfInterpreter(cos: doc.cos, device: recorder).drawPageOperations(
          page, ContentStreamParser.parse(page.contentBytes()));

      // A 256px-wide tile, exactly what the thumbnail warm asks for.
      final box = page.cropBox;
      final ratio = 256 / box.width;
      final raster = pdfPageRasterPixels(box, ratio)!;

      final unbudgeted = serializeCommands(recorder.commands,
          cos: doc.cos, decodeImages: true, maxImagePixelRatio: ratio)!;
      final budgeted = serializeCommands(recorder.commands,
          cos: doc.cos,
          decodeImages: true,
          maxImagePixelRatio: ratio,
          pageRasterPixels: raster)!;

      // Pixels only - the command stream is identical either way, so the tile
      // replays the same drawing at a resolution it can actually show.
      expect(_transcript(deserializeCommands(budgeted)),
          equals(_transcript(deserializeCommands(unbudgeted))));

      final before = _decodedPixelSum(deserializeCommands(unbudgeted));
      final after = _decodedPixelSum(deserializeCommands(budgeted));
      // The per-image 2x headroom alone ships 4 raster-fulls PER image; the
      // page budget is that headroom squared for the whole page.
      expect(before, 4 * 512 * 512);
      expect(after, lessThanOrEqualTo(4 * raster + 4 * 16 + 64));
      expect(after * 4, lessThanOrEqualTo(before),
          reason: 'the tile-sized budget did not bind');
      // The record crossing the worker seam sheds every one of those pixels
      // (4 bytes of premultiplied RGBA each). What it does NOT shed is the
      // source streams written beside them to key the decode by content -
      // that floor is #451's, not this one's.
      expect(unbudgeted.length - budgeted.length,
          greaterThanOrEqualTo(4 * (before - after) - 1024));
    });

    test('never scales a lone underlay a page render legitimately wants', () {
      final doc = PdfDocument.open(_layeredImagePdf(draws: 1));
      final page = doc.page(0);
      final recorder = RecordingPdfDevice();
      PdfInterpreter(cos: doc.cos, device: recorder).drawPageOperations(
          page, ContentStreamParser.parse(page.contentBytes()));
      final box = page.cropBox;
      for (final ratio in const [2.0, 1.28, 0.5]) {
        final plain = serializeCommands(recorder.commands,
            cos: doc.cos, decodeImages: true, maxImagePixelRatio: ratio);
        final budgeted = serializeCommands(recorder.commands,
            cos: doc.cos,
            decodeImages: true,
            maxImagePixelRatio: ratio,
            pageRasterPixels: pdfPageRasterPixels(box, ratio));
        expect(budgeted, equals(plain),
            reason: 'ratio $ratio: the raster-derived budget must leave the '
                'per-image cap alone for a single full-bleed image');
      }
    });

    test('is a floor under the 17 MP cap, never a raise', () {
      final doc = PdfDocument.open(_layeredImagePdf(draws: 4));
      final page = doc.page(0);
      final recorder = RecordingPdfDevice();
      PdfInterpreter(cos: doc.cos, device: recorder).drawPageOperations(
          page, ContentStreamParser.parse(page.contentBytes()));
      final plain = serializeCommands(recorder.commands,
          cos: doc.cos, decodeImages: true, maxImagePixelRatio: 1e6);
      final huge = serializeCommands(recorder.commands,
          cos: doc.cos,
          decodeImages: true,
          maxImagePixelRatio: 1e6,
          pageRasterPixels: 1 << 30);
      expect(huge, equals(plain));
    });
  });
}

/// A one-page 200x200 pt PDF that draws one 512x512 raw DeviceRGB image
/// [draws] times, full bleed. The layered-raster shape the page image budget
/// exists to bound: every draw is at its own on-screen footprint, so only
/// their SUM is out of proportion to the raster.
Uint8List _layeredImagePdf({required int draws}) {
  const size = 512;
  final pixels = Uint8List(size * size * 3);
  for (var i = 0; i < pixels.length; i++) {
    pixels[i] = (i * 7) & 0xff;
  }
  final content = StringBuffer();
  for (var i = 0; i < draws; i++) {
    content.write('q 200 0 0 200 0 0 cm /Im0 Do Q\n');
  }
  final contentBytes = Uint8List.fromList(content.toString().codeUnits);

  final out = BytesBuilder();
  final offsets = <int>[];
  void obj(int number, String head, [Uint8List? stream]) {
    offsets.add(out.length);
    out.add(Uint8List.fromList('$number 0 obj\n$head\n'.codeUnits));
    if (stream != null) {
      out.add(Uint8List.fromList('stream\n'.codeUnits));
      out.add(stream);
      out.add(Uint8List.fromList('\nendstream\n'.codeUnits));
    }
    out.add(Uint8List.fromList('endobj\n'.codeUnits));
  }

  out.add(Uint8List.fromList('%PDF-1.4\n'.codeUnits));
  obj(1, '<< /Type /Catalog /Pages 2 0 R >>');
  obj(2, '<< /Type /Pages /Kids [3 0 R] /Count 1 >>');
  obj(
      3,
      '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] '
          '/Resources << /XObject << /Im0 5 0 R >> >> /Contents 4 0 R >>');
  obj(4, '<< /Length ${contentBytes.length} >>', contentBytes);
  obj(
      5,
      '<< /Type /XObject /Subtype /Image /Width $size /Height $size '
          '/ColorSpace /DeviceRGB /BitsPerComponent 8 '
          '/Length ${pixels.length} >>',
      pixels);

  final xref = out.length;
  final tail = StringBuffer('xref\n0 ${offsets.length + 1}\n')
    ..write('0000000000 65535 f \n');
  for (final off in offsets) {
    tail.write('${off.toString().padLeft(10, '0')} 00000 n \n');
  }
  tail
    ..write('trailer << /Size ${offsets.length + 1} /Root 1 0 R >>\n')
    ..write('startxref\n$xref\n%%EOF\n');
  out.add(Uint8List.fromList(tail.toString().codeUnits));
  return out.takeBytes();
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
/// into soft-mask groups - the same order serializeCommands writes them.
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
Uint8List _inlineImagePdf() => _inlinePdf('q 100 0 0 100 50 50 cm '
    'BI /W 4 /H 4 /CS /RGB /BPC 8 /F /AHx ID\n'
    'e63030 ffffff e63030 ffffff\n'
    'ffffff e63030 ffffff e63030\n'
    'e63030 ffffff e63030 ffffff\n'
    'ffffff e63030 ffffff e63030 >\nEI Q\n');

// A 4x4 1-bit ImageMask (stencil) inline image painted in blue. No /CS, so its
// stream is self-contained (#554).
Uint8List _inlineStencilPdf() => _inlinePdf('q 0 0 1 rg 100 0 0 100 50 50 cm '
    'BI /W 4 /H 4 /IM true /BPC 1 /F /AHx ID\n'
    'f0f0f0f0 >\nEI Q\n');

Uint8List _inlinePdf(String content) {
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
