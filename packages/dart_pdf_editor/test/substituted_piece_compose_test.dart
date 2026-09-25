// Exact placement (#649) draws each word piece of a substituted run at the
// PDF's own offset. A piece inside #454's kern-free gate - digits, capitals
// beside digits or spaces, plain punctuation - is laid out from cached glyph
// layouts end to end instead of shaping a paragraph for it, which is what keeps
// a page of unique CAD labels from shaping every label. That is only exact in a
// face that kerns none of the gate's pairs: TeX Gyre Heros, Termes and Cursor
// don't; Adventor, Carlito and the system faces a host without the bundled
// assets falls back to do. These tests register real faces, which is
// process-wide, so they live in a file of their own.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_graphics/pdf_graphics.dart';

const _fonts = '../dart_pdf_editor_assets/assets/fonts';

Future<void> _register(String family, String file) async {
  final bytes = File('$_fonts/$file').readAsBytesSync();
  await (FontLoader(family)..addFont(Future.value(ByteData.sublistView(bytes))))
      .load();
}

/// Draws [labels] as exactly placed runs in [fontName], each character at the
/// advance [widths] gives it (em), and returns the TextPainter builds spent.
int _buildsFor(String fontName, List<String> labels, double Function(int) em) {
  CanvasPdfDevice.clearTextLayoutCache();
  CanvasPdfDevice.debugResetTextShape();
  final recorder = ui.PictureRecorder();
  final device = CanvasPdfDevice(ui.Canvas(recorder));
  for (final label in labels) {
    device.drawText(_placed(label, fontName, em));
  }
  recorder.endRecording().dispose();
  return CanvasPdfDevice.debugTextPainterBuilds;
}

PdfTextRun _placed(String text, String fontName, double Function(int) em,
    {double x = 20}) {
  final offsets = <double>[0];
  for (final cu in text.codeUnits) {
    offsets.add(offsets.last + em(cu));
  }
  return PdfTextRun(
    text: text,
    charOffsets: offsets,
    transform: PdfMatrix(24, 0, 0, 24, x, 60),
    color: const PdfColor(0, 0, 0),
    width: offsets.last,
    fontName: fontName,
    fontSize: 24,
  );
}

/// The natural advance of each character in [family], in em - what a face
/// that agrees with the PDF would put there, so no piece is cut short.
double Function(int) _advancesOf(String family) {
  final cache = <int, double>{};
  return (cu) => cache.putIfAbsent(cu, () {
        final painter = TextPainter(
          text: TextSpan(
              text: String.fromCharCode(cu),
              style: TextStyle(fontFamily: family, fontSize: 100)),
          textDirection: TextDirection.ltr,
        )..layout();
        final width = painter.width / 100;
        painter.dispose();
        return width;
      });
}

double _shapedWidth(String family, String text) {
  final painter = TextPainter(
    text: TextSpan(
        text: text, style: TextStyle(fontFamily: family, fontSize: 100)),
    textDirection: TextDirection.ltr,
  )..layout();
  final width = painter.width;
  painter.dispose();
  return width;
}

Future<Uint8List> _raster(PdfTextRun run) async {
  CanvasPdfDevice.clearTextLayoutCache();
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder)
    ..drawColor(const Color(0xFFFFFFFF), BlendMode.src);
  CanvasPdfDevice(canvas).drawText(run);
  final image = await recorder.endRecording().toImage(640, 90);
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    return Uint8List.fromList(data!.buffer.asUint8List());
  } finally {
    image.dispose();
  }
}

/// Unique labels made of gate-admitted pieces only.
final _labels = [
  for (var i = 0; i < 40; i++) 'N${1234 + i}.${567 - i} E${7654 + 3 * i}.1',
];

void main() {
  setUpAll(() async {
    // As the app registers them: under the package-qualified family the
    // renderer asks for first.
    await _register(PdfBundledSubstitute.heros.packageFamily,
        PdfBundledSubstitute.heros.assetFile());
    await _register(PdfBundledSubstitute.adventor.packageFamily,
        PdfBundledSubstitute.adventor.assetFile());
    // A face that kerns, answering for Times where the bundled Termes would -
    // what a host that leaves the assets out gets from its own fonts. It has
    // to take Termes' own name: the test engine answers any family it doesn't
    // know with its kern-free test font, so a fallback name is never reached.
    await _register(PdfBundledSubstitute.termes.packageFamily,
        PdfBundledSubstitute.adventor.assetFile());
  });

  tearDown(() {
    CanvasPdfDevice.exactSubstitutedGlyphPlacement = true;
    CanvasPdfDevice.perGlyphSubstitutedText = true;
    CanvasPdfDevice.clearTextLayoutCache();
  });

  testWidgets('unique labels in a kern-free face are not shaped one by one',
      (tester) async {
    await tester.runAsync(() async {
      final heros = _advancesOf(PdfBundledSubstitute.heros.packageFamily);
      final builds = _buildsFor('Helvetica', _labels, heros);
      // The alphabet (digits, '.', 'N', 'E') plus the face's one-off kerning
      // check - not one paragraph per piece of 40 labels (80+).
      expect(builds, lessThan(20),
          reason: 'kern-free pieces must come from the glyph cache');
    });
  });

  testWidgets('a composed piece is pixel-identical to the piece shaped whole',
      (tester) async {
    await tester.runAsync(() async {
      // With each character at the face's own advance nothing is cut, and the
      // whole-run path (placement and #454 composition off) shapes each label
      // as one paragraph - the reference a composed piece must match exactly.
      final heros = _advancesOf(PdfBundledSubstitute.heros.packageFamily);
      for (final label in [_labels.first, '12/48 - 3.5% (7) #10', 'A3 B7']) {
        final run = _placed(label, 'Helvetica', heros);
        final placed = await _raster(run);
        CanvasPdfDevice.exactSubstitutedGlyphPlacement = false;
        CanvasPdfDevice.perGlyphSubstitutedText = false;
        final shaped = await _raster(run);
        CanvasPdfDevice.exactSubstitutedGlyphPlacement = true;
        CanvasPdfDevice.perGlyphSubstitutedText = true;
        expect(placed, equals(shaped), reason: label);
      }
    });
  });

  testWidgets('a bundled face that kerns inside the gate never composes',
      (tester) async {
    await tester.runAsync(() async {
      final family = PdfBundledSubstitute.adventor.packageFamily;
      final adventor = _advancesOf(family);
      // The premise: Adventor (Century Gothic / Avant Garde) really does kern
      // a pair the gate admits, so composing it would move glyphs.
      expect(_shapedWidth(family, '7.'),
          lessThan(_shapedWidth(family, '7') + _shapedWidth(family, '.')));
      // So every unique label still shapes its pieces.
      final builds = _buildsFor('CenturyGothic', _labels, adventor);
      expect(builds, greaterThanOrEqualTo(_labels.length * 2),
          reason: 'Adventor pieces must be shaped, kerning intact');
    });
  });

  testWidgets('a kerning face standing in for a bundled one never composes',
      (tester) async {
    await tester.runAsync(() async {
      // Times resolves to Termes when the assets are bundled; here it reaches
      // a face that kerns, which the one-off check has to notice.
      final stand = _advancesOf(PdfBundledSubstitute.termes.packageFamily);
      final builds = _buildsFor('Times-Roman', _labels, stand);
      expect(builds, greaterThanOrEqualTo(_labels.length * 2),
          reason: 'a face that kerns the gate pairs must keep shaping');
      // Courier resolves to nothing registered here but the test font, which
      // has no kerning at all - so it composes.
      final courier = _buildsFor('Courier', _labels, (_) => 1);
      expect(courier, lessThan(20));
    });
  });
}
