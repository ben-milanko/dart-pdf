// Pixel-identity gate for the record/replay render split.
//
// [PdfPageRenderer.renderPictureRecorded] interprets a page into a portable
// command buffer ([RecordingPdfDevice]) and replays it onto the canvas, where
// [renderPicture] interprets straight onto the canvas. The two must rasterize
// to byte-identical pixels — the replay issues exactly the same canvas calls.
//
// Unlike the Ghent/PDF.js golden suites this needs no stored baseline and is
// platform-independent: both renders happen in the same process this run, so
// font/antialiasing differences cancel and the comparison is the identity of
// the two code paths, nothing else.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';

import 'render_smoke_test.dart' show loadSystemFonts;

const _pixelRatio = 2.0;

Uint8List _buildPdf(String content, {String mediaBox = '0 0 200 200'}) {
  final objects = <String>[
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [$mediaBox] /Contents 4 0 R '
        '/Resources << /Font << /F1 5 0 R >> >> >>',
    '<< /Length ${content.length} >>\nstream\n$content\nendstream',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
  ];
  final buffer = StringBuffer('%PDF-1.4\n');
  final offsets = <int>[];
  for (var i = 0; i < objects.length; i++) {
    offsets.add(buffer.length);
    buffer.write('${i + 1} 0 obj\n${objects[i]}\nendobj\n');
  }
  final xref = buffer.length;
  buffer.write('xref\n0 ${objects.length + 1}\n0000000000 65535 f \n');
  for (final o in offsets) {
    buffer.write('${o.toString().padLeft(10, '0')} 00000 n \n');
  }
  buffer.write('trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\n'
      'startxref\n$xref\n%%EOF\n');
  return Uint8List.fromList(buffer.toString().codeUnits);
}

/// Renders [page] both ways and returns the differing-pixel fraction at an
/// exact (zero-tolerance) comparison.
Future<double> _compare(PdfPage page) async {
  final direct = await PdfPageRenderer.renderPicture(page);
  final recorded = await PdfPageRenderer.renderPictureRecorded(page);
  final size = PdfPageRenderer.pageSize(page);
  try {
    final a = await PdfPageRenderer.rasterize(direct, size, _pixelRatio);
    final b = await PdfPageRenderer.rasterize(recorded, size, _pixelRatio);
    try {
      expect('${a.width}x${a.height}', '${b.width}x${b.height}',
          reason: 'recorded raster size differs');
      final ap = (await a.toByteData(format: ui.ImageByteFormat.rawStraightRgba))!
          .buffer
          .asUint8List();
      final bp = (await b.toByteData(format: ui.ImageByteFormat.rawStraightRgba))!
          .buffer
          .asUint8List();
      return PdfPageComparison.comparePixels(ap, bp,
              width: a.width, height: a.height, channelTolerance: 0)
          .differenceFraction;
    } finally {
      a.dispose();
      b.dispose();
    }
  } finally {
    direct.dispose();
    recorded.dispose();
  }
}

void main() {
  group('synthetic pages', () {
    final cases = <String, String>{
      'fills, strokes, dashes': 'q 0 0 1 rg 20 20 120 80 re f '
          '1 0 0 RG 6 w [10 6] 0 d 20 160 m 180 40 l S Q',
      'clip and curves': '0 0 1 0 k 30 30 140 140 re W n '
          '20 20 m 60 180 140 180 180 20 c f',
      'text': 'BT /F1 32 Tf 20 100 Td (Recorded!) Tj ET',
      'inline image': 'q 100 0 0 100 50 50 cm '
          'BI /W 4 /H 4 /CS /RGB /BPC 8 /F /AHx ID\n'
          'e63030 ffffff e63030 ffffff\n'
          'ffffff e63030 ffffff e63030\n'
          'e63030 ffffff e63030 ffffff\n'
          'ffffff e63030 ffffff e63030 >\nEI Q',
      'alpha group': 'q /GShere gs 0 0 1 rg 20 20 100 100 re f Q',
    };
    cases.forEach((name, content) {
      testWidgets(name, (tester) async {
        await tester.runAsync(() async {
          await loadSystemFonts();
          final doc = PdfDocument.open(_buildPdf(content));
          expect(await _compare(doc.page(0)), 0.0,
              reason: '$name: recorded render is not pixel-identical');
        });
      });
    });
  });

  // Real pages drive the callbacks the synthetic fixtures can't: transparency
  // groups, luminosity + alpha soft masks (with their mask content), blend
  // modes, axial/radial + mesh shadings, and decoded images.
  group('corpus pages', () {
    final files = <String>[
      '../../test_corpora/ghent/1-CMYK/GWG168_Softmasks_Vector_part1_X4.pdf',
      '../../test_corpora/ghent/1-CMYK/GWG166_Softmasks_Images_DeviceCMYK_X4.pdf',
      '../../test_corpora/ghent/1-CMYK/'
          'GWG160_Transp_Basic_BM_DeviceCMYK_Non-knockout_X4.pdf',
      '../../test_corpora/ghent/1-CMYK/'
          'GWG161_Transp_Basic_BM_DeviceCMYK_Knockout_X4.pdf',
      '../../test_corpora/ghent/1-CMYK/GWG061_Shading_x1a.pdf',
    ];
    for (final path in files) {
      final file = File(path);
      final name = path.split('/').last;
      testWidgets(name, (tester) async {
        if (!file.existsSync()) {
          markTestSkipped('$path not found');
          return;
        }
        await tester.runAsync(() async {
          await loadSystemFonts();
          final doc = PdfDocument.open(file.readAsBytesSync());
          for (var i = 0; i < doc.pageCount; i++) {
            expect(await _compare(doc.page(i)), 0.0,
                reason: '$name page $i: recorded render not pixel-identical');
          }
        });
      }, timeout: const Timeout(Duration(minutes: 2)));
    }
  });
}
