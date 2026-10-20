import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:test/test.dart';

/// Counts device calls; enough to prove generated appearance streams run
/// end to end through the interpreter.
class CountingDevice implements PdfDevice {
  final fills = <PdfColor>[];
  final fillPaths = <PdfPath>[];
  final strokes = <PdfColor>[];
  final texts = <PdfTextRun>[];
  final blendModes = <PdfBlendMode>[];
  final groupAlphas = <double>[];
  var alphas = <double>[];

  @override
  void fillPath(PdfPath path, PdfColor color, PdfFillRule rule, double alpha) {
    fills.add(color);
    fillPaths.add(path);
    alphas.add(alpha);
  }

  @override
  void fillMesh(PdfMesh mesh, double a) {}

  @override
  void strokePath(
      PdfPath path, PdfColor color, PdfStroke stroke, double alpha) {
    strokes.add(color);
  }

  @override
  void drawText(PdfTextRun run) => texts.add(run);

  @override
  void setBlendMode(PdfBlendMode mode) => blendModes.add(mode);

  @override
  void setOverprint(
      {required bool fill, required bool stroke, required int mode}) {}

  @override
  void save() {}
  @override
  void restore() {}
  @override
  void clipPath(PdfPath path, PdfFillRule rule) {}
  @override
  void fillPathGradient(
      PdfPath path, PdfFillRule rule, PdfGradient gradient, double alpha) {}
  @override
  void drawImage(PdfImageRequest request) {}
  @override
  void beginGroup(double alpha, {bool knockout = false}) =>
      groupAlphas.add(alpha);
  @override
  void endGroup() {}
  @override
  void beginSoftMasked() {}
  @override
  void endSoftMasked(
      {required bool luminosity,
      required PdfRect backdrop,
      required void Function() drawMask,
      double backdropLuminance = 0,
      double transferScale = 1,
      double transferOffset = 0}) {}
}

/// Serializes fills as color plus path geometry, so flattened output can be
/// compared with live annotation rendering point for point.
String dump(CountingDevice d) {
  String pt(double v) => v.toStringAsFixed(2);
  final lines = <String>[];
  for (var i = 0; i < d.fills.length; i++) {
    final c = d.fills[i];
    final segments = [
      for (final s in d.fillPaths[i].segments)
        switch (s) {
          PdfMoveTo(:final x, :final y) => 'M${pt(x)},${pt(y)}',
          PdfLineTo(:final x, :final y) => 'L${pt(x)},${pt(y)}',
          PdfCubicTo(:final x3, :final y3) => 'C${pt(x3)},${pt(y3)}',
          _ => 'Z',
        },
    ].join(' ');
    lines.add('fill ${pt(c.red)} ${pt(c.green)} ${pt(c.blue)}: $segments');
  }
  return lines.join('\n');
}

void main() {
  PdfDocument annotated(void Function(PdfEditor) edit) {
    final editor = PdfEditor(PdfDocument.open(buildClassicPdf()));
    edit(editor);
    return PdfDocument.open(editor.save());
  }

  CountingDevice render(PdfDocument doc) {
    final device = CountingDevice();
    final page = doc.page(0);
    PdfInterpreter(cos: doc.cos, device: device)
      ..drawPage(page)
      ..drawAnnotations(page);
    return device;
  }

  test('a generated highlight fills in its color with Multiply blending', () {
    final device = render(annotated((e) => e.addHighlight(
        0, const [PdfRect(72, 700, 200, 712)],
        color: 0xFF0000)));
    expect(
        device.fills.any((c) => c.red > 0.99 && c.green < 0.01), isTrue);
    expect(device.blendModes, contains(PdfBlendMode.multiply));
  });

  test('reduced-opacity ink strokes composite once through a group', () {
    // The per-pressure segments overlap at their round caps; without the
    // transparency group each would composite separately at 0.5 alpha and
    // darken every join into a dot. The group makes them one object faded
    // once - the interpreter opens exactly one group at the ink's opacity.
    final device = render(annotated((e) => e.addInk(
          0,
          [
            [(100, 100), (150, 130), (200, 100)],
          ],
          strokeWidth: 6,
          opacity: 0.5,
          pressures: [
            [0.2, 0.6, 1.0],
          ],
        )));
    expect(device.groupAlphas, [closeTo(0.5, 1e-9)]);
    // the strokes still reach the device (inside the group, at full alpha)
    expect(device.strokes, isNotEmpty);
  });

  test('full-opacity ink strokes render without a group', () {
    final device = render(annotated((e) => e.addInk(
          0,
          [
            [(100, 100), (150, 130), (200, 100)],
          ],
          strokeWidth: 6,
          pressures: [
            [0.2, 0.6, 1.0],
          ],
        )));
    expect(device.groupAlphas, isEmpty);
    expect(device.strokes, isNotEmpty);
  });

  test('drawAnnotations skip omits the matched annotation, keeps the rest', () {
    final doc = annotated((e) {
      e.addHighlight(0, const [PdfRect(72, 700, 200, 712)], color: 0xFF0000);
      e.addHighlight(0, const [PdfRect(72, 680, 200, 692)], color: 0x00FF00);
    });
    final page = doc.page(0);
    // skip by /NM - a stable handle that survives re-parsing the page
    final targetName = page.annotations.first.name; // the red highlight
    expect(targetName, isNotNull);

    final device = CountingDevice();
    PdfInterpreter(cos: doc.cos, device: device)
      ..drawPage(page)
      ..drawAnnotations(page, skip: (a) => a.name == targetName);

    // the green highlight still fills; the skipped red one does not
    expect(device.fills.any((c) => c.green > 0.99 && c.red < 0.01), isTrue);
    expect(device.fills.any((c) => c.red > 0.99 && c.green < 0.01), isFalse);
  });

  test('a generated square strokes and fills at the requested opacity', () {
    final device = render(annotated((e) => e.addSquare(
        0, const PdfRect(100, 100, 200, 150),
        strokeColor: 0x0000FF, fillColor: 0x00FF00, opacity: 0.5)));
    expect(device.strokes.any((c) => c.blue > 0.99), isTrue);
    expect(device.fills.any((c) => c.green > 0.99), isTrue);
    expect(device.alphas, contains(closeTo(0.5, 1e-9)));
  });

  test('generated free text reaches the device as text runs', () {
    final device = render(annotated((e) => e.addFreeText(
        0, const PdfRect(72, 600, 300, 660), 'Generated note',
        fontSize: 14)));
    final shown = device.texts.map((t) => t.text).join();
    expect(shown, contains('Generated note'));
  });

  test('Arabic free text renders through interpreter with correct Unicode', () {
    PdfInterpreter.clearFontCache();
    final device = render(annotated((e) => e.addFreeText(
        0, const PdfRect(72, 600, 300, 660), 'مرحبا',
        fontSize: 14)));
    final shown = device.texts.map((t) => t.text).join();
    // pdfVisualText reverses RTL runs for content-stream painting order;
    // the renderer's BiDi re-reverses for correct on-screen display
    for (final c in 'مرحبا'.runes) {
      expect(shown, contains(String.fromCharCode(c)));
    }
    expect(shown, isNot(contains('?')));
    // the Type0 font has no outlines → substitution path (glyphs null)
    final annTexts = device.texts.where((t) => t.text.runes
        .any((r) => r >= 0x0600 && r <= 0x06FF));
    expect(annTexts, isNotEmpty);
    expect(annTexts.first.glyphs, isNull);
  });

  test('mixed Latin+Arabic free text preserves both scripts', () {
    PdfInterpreter.clearFontCache();
    final device = render(annotated((e) => e.addFreeText(
        0, const PdfRect(72, 600, 400, 660), 'hello مرحبا world',
        fontSize: 14)));
    final shown = device.texts.map((t) => t.text).join();
    expect(shown, contains('hello'));
    expect(shown, contains('world'));
    for (final c in 'مرحبا'.runes) {
      expect(shown, contains(String.fromCharCode(c)));
    }
  });

  test('flattened pages paint exactly like live annotation rendering', () {
    // the fixture exercises the hard appearance cases: a BBox that scales
    // ×10/×5 onto its rect, a 90°-rotation /Matrix, and an /AS state
    final live = CountingDevice();
    final liveDoc = PdfDocument.open(buildAppearanceAnnotationsPdf());
    final livePage = liveDoc.page(0);
    PdfInterpreter(cos: liveDoc.cos, device: live)
      ..drawPage(livePage)
      ..drawAnnotations(livePage);

    final editor = PdfEditor(PdfDocument.open(buildAppearanceAnnotationsPdf()))
      ..flattenAnnotations(0);
    final flatDoc = PdfDocument.open(editor.save());
    final flat = CountingDevice();
    PdfInterpreter(cos: flatDoc.cos, device: flat).drawPage(flatDoc.page(0));

    expect(flat.fills.length, live.fills.length);
    expect(dump(flat), dump(live));
  });

  test('a filled form field renders its value as text runs', () {
    final editor = PdfEditor(PdfDocument.open(buildAcroFormPdf()));
    editor.setTextValue(editor.acroForm!.fieldNamed('name')!, 'Jane Roe');
    editor.setCheckBoxValue(editor.acroForm!.fieldNamed('agree')!, true);
    final doc = PdfDocument.open(editor.save());

    final device = render(doc);
    final shown = device.texts.map((t) => t.text).join();
    expect(shown, contains('Jane Roe'));
    // the checkbox flipped to its /Yes state, whose stream fills 0.5 gray
    expect(
        device.fills.any((c) =>
            (c.red - 0.5).abs() < 0.01 &&
            (c.green - 0.5).abs() < 0.01 &&
            (c.blue - 0.5).abs() < 0.01),
        isTrue);
  });

  test('a generated stamp shows its caption in Helvetica-Bold', () {
    final device = render(annotated(
        (e) => e.addStamp(0, const PdfRect(100, 500, 260, 540), 'DRAFT')));
    final stamp =
        device.texts.where((t) => t.text.contains('DRAFT')).toList();
    expect(stamp, isNotEmpty);
    expect(stamp.first.fontName, contains('Helvetica-Bold'));
  });
}
