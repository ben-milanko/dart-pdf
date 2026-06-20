// Record/replay equivalence — the foundation of the background-isolate render
// split. A page interpreted straight into a device must produce the EXACT same
// sequence of device callbacks as the same page recorded into a
// [RecordingPdfDevice] and then replayed via [replayCommands]. This is the
// pure-Dart oracle (no dart:ui): it proves the recorder captures every call
// faithfully, in order, and that the soft-mask `drawMask` closure round-trips
// through the nested command list.
import 'dart:io';
import 'dart:typed_data';

import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:test/test.dart';

/// Logs a detailed, deterministic transcript of every device call, recursing
/// into soft-mask `drawMask` content so the transcript captures the full tree.
class _TranscriptDevice implements PdfDevice {
  final List<String> log = [];

  static String _path(PdfPath p) {
    final first = p.segments.isEmpty ? '' : p.segments.first.runtimeType;
    return 'segs=${p.segments.length},first=$first';
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
      log.add('gradient ${_path(path)} ${rule.name} '
          'radial=${gradient.isRadial} coords=${gradient.coords} $alpha');

  @override
  void fillMesh(PdfMesh mesh, double alpha) =>
      log.add('mesh verts=${mesh.vertices.length} tris=${mesh.triangles.length} '
          '$alpha');

  @override
  void strokePath(
          PdfPath path, PdfColor color, PdfStroke stroke, double alpha) =>
      log.add('stroke ${_path(path)} ${_color(color)} w=${stroke.width} '
          'cap=${stroke.cap} join=${stroke.join} dash=${stroke.dashArray} '
          '$alpha');

  @override
  void clipPath(PdfPath path, PdfFillRule rule) =>
      log.add('clip ${_path(path)} ${rule.name}');

  @override
  void drawText(PdfTextRun run) => log.add('text "${run.text}" '
      '${_matrix(run.transform)} ${_color(run.color)} fill=${run.fill} '
      'invisible=${run.invisible} glyphs=${run.glyphs?.length}');

  @override
  void drawImage(PdfImageRequest request) =>
      log.add('image ${_matrix(request.transform)} a=${request.alpha} '
          'stencil=${request.isStencil} inline=${request.isInline}');

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
        'ts=$transferScale to=$transferOffset {');
    drawMask();
    log.add('}');
  }
}

/// Interprets [content] straight into a transcript device.
List<String> _direct(String content) {
  final doc = CosDocument.open(buildClassicPdf());
  final device = _TranscriptDevice();
  PdfInterpreter(cos: doc, device: device).run(
    ContentStreamParser.parse(Uint8List.fromList(content.codeUnits)),
    CosDictionary(),
  );
  return device.log;
}

/// Interprets [content] into a recorder, then replays the buffer into a
/// transcript device.
List<String> _recorded(String content) {
  final doc = CosDocument.open(buildClassicPdf());
  final recorder = RecordingPdfDevice();
  PdfInterpreter(cos: doc, device: recorder).run(
    ContentStreamParser.parse(Uint8List.fromList(content.codeUnits)),
    CosDictionary(),
  );
  final device = _TranscriptDevice();
  replayCommands(recorder.commands, device);
  return device.log;
}

void main() {
  group('synthetic content', () {
    final cases = <String, String>{
      'fills and strokes':
          'q 2 0 0 2 10 10 cm 0 0 1 rg 5 5 20 30 re f 1 0 0 RG 4 w '
              '0 0 10 10 re S Q',
      'dashed stroke': '[3 2] 0 d 1 w 10 10 m 90 90 l S',
      'clip then fill': '0 0 5 5 re W n 0 0 1 rg 0 0 10 10 re f',
      'text': 'BT /F1 24 Tf 72 720 Td (Hello, world!) Tj ET',
      'nested q/Q': 'q q 0 0 1 1 re f Q q 1 1 2 2 re f Q Q',
      'curves': '10 10 m 20 30 40 30 50 10 c f',
    };
    cases.forEach((name, content) {
      test(name, () {
        final direct = _direct(content);
        expect(direct, isNotEmpty, reason: 'fixture should paint something');
        expect(_recorded(content), equals(direct));
      });
    });
  });

  // Real pages exercise the serialization-fragile callbacks the synthetic
  // cases can't reach: transparency groups, soft masks (luminosity + alpha,
  // with their drawMask content), blend modes, mesh and axial/radial shadings,
  // images, and knockout groups.
  group('corpus pages', () {
    final files = <String>[
      '../../test_corpora/ghent/1-CMYK/GWG168_Softmasks_Vector_part1_X4.pdf',
      '../../test_corpora/ghent/1-CMYK/GWG1610_Softmasks_Text_part1_X4.pdf',
      '../../test_corpora/ghent/1-CMYK/GWG166_Softmasks_Images_DeviceCMYK_X4.pdf',
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

          final direct = _TranscriptDevice();
          PdfInterpreter(cos: doc.cos, device: direct)
              .drawPageOperations(page, ops);

          final recorder = RecordingPdfDevice();
          PdfInterpreter(cos: doc.cos, device: recorder)
              .drawPageOperations(page, ops);
          final replayed = _TranscriptDevice();
          replayCommands(recorder.commands, replayed);

          expect(replayed.log, equals(direct.log),
              reason: '$name page $i transcript diverged');
        }
      });
    }
  });
}
