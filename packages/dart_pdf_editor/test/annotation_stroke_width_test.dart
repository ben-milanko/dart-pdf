// #660: a committed annotation appearance must keep its page-space stroke
// widths, because `renderAnnotationPicture` records a *scale-independent*
// picture that the viewer's annotation layer replays at every zoom.
//
// It used to record through a `CanvasPdfDevice` at the default pixelRatio 1,
// so #426's one-device-pixel floor turned every positive width under 1 pt
// into a Skia hairline at record time - and a hairline is one device pixel at
// *any* replay scale. Pressure-sensitive ink is exactly that case: a 1.5 pt
// pen at zero pressure draws pdfInkStrokeWidth(1.5, 0) = 0.6 pt, which looked
// right in the live overlay (view px = width x zoom, unfloored) and then
// snapped to a one-pixel hairline the moment the appearance picture replaced
// it - still one pixel at 333% zoom.
//
// The measurements below are coverage sums, not pixel hits: a column of the
// rasterized stroke, summing alpha (or ink darkness for page content) over
// 0-1 per pixel, which totals the stroke's device width whatever the
// antialiasing does with it. That is what distinguishes a 2 px stroke from a
// 1 px hairline reliably.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 333% zoom - the reported viewer scale, and the scale at which a 0.6 pt
/// stroke should be ~2 device pixels rather than 1.
const zoom = 10 / 3;

/// The page-space y of every line these fixtures draw, and the raster-space
/// y it lands on in a 792 pt tall page (raster space is y-down).
const lineY = 700.0;
const rasterY = 792.0 - lineY;

/// Assembles [objects] (1-indexed, in order) into a one-page PDF with a
/// correct xref table - offsets are computed, never hand-written.
Uint8List _assemble(List<String> objects) {
  final buffer = StringBuffer('%PDF-1.7\n');
  final offsets = <int>[];
  for (var i = 0; i < objects.length; i++) {
    offsets.add(buffer.length);
    buffer.write('${i + 1} 0 obj\n${objects[i]}\nendobj\n');
  }
  final xrefOffset = buffer.length;
  buffer
    ..write('xref\n0 ${objects.length + 1}\n')
    ..write('0000000000 65535 f \n');
  for (final offset in offsets) {
    buffer.write('${offset.toString().padLeft(10, '0')} 00000 n \n');
  }
  buffer
    ..write('trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\n')
    ..write('startxref\n$xrefOffset\n%%EOF\n');
  return Uint8List.fromList(buffer.toString().codeUnits);
}

String _stream(String dict, String content) =>
    '<< $dict /Length ${content.length} >>\nstream\n$content\nendstream';

/// A 612x792 page carrying one Square annotation per entry in [widths]: a
/// horizontal red line from x=100 to x=200 at [lineY], stroked at that
/// explicit `w` inside the annotation's own appearance stream.
///
/// The appearance /BBox equals the annotation /Rect, so §12.5.5's BBox-to-Rect
/// mapping is the identity and the recorded picture carries the authored width
/// unscaled.
Uint8List buildAnnotationWidthPdf(List<double> widths) {
  final annots = [for (var i = 0; i < widths.length; i++) '${5 + i * 2} 0 R'];
  final objects = <String>[
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R '
        '/Annots [${annots.join(' ')}] >>',
    _stream('', ''),
  ];
  const box = '[90 690 210 710]';
  for (final width in widths) {
    objects
      ..add('<< /Type /Annot /Subtype /Square /F 4 /Rect $box '
          '/AP << /N ${objects.length + 2} 0 R >> >>')
      ..add(_stream(
        '/Type /XObject /Subtype /Form /BBox $box',
        'q 1 0 0 RG $width w 100 $lineY m 200 $lineY l S Q',
      ));
  }
  return _assemble(objects);
}

/// A 612x792 page whose *content stream* strokes a black horizontal line at
/// [width] - the #426 case (CAD producers emit 0.06 pt meaning "hairline").
Uint8List buildContentWidthPdf(double width) => _assemble([
      '<< /Type /Catalog /Pages 2 0 R >>',
      '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
      '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R >>',
      _stream('', '0 0 0 RG $width w 100 $lineY m 200 $lineY l S'),
    ]);

/// An empty [width] x [height] pt page - the substrate for a drawn stroke.
Uint8List buildBlankPdf(double width, double height) => _assemble([
      '<< /Type /Catalog /Pages 2 0 R >>',
      '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
      '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 $width $height] '
          '/Contents 4 0 R >>',
      _stream('', ''),
    ]);

/// The stroke's device-space thickness at ([x], [y]) in page raster space,
/// measured by replaying [picture] at [scale] and summing one pixel column's
/// coverage. [coverage] reads 0-1 from a pixel's RGBA.
Future<double> measureThickness(
  ui.Picture picture,
  double scale, {
  double x = 150,
  double y = rasterY,
  required double Function(int r, int g, int b, int a) coverage,
}) async {
  final region = Rect.fromCenter(center: Offset(x, y), width: 8, height: 24);
  final image = await PdfPageRenderer.rasterizeRegion(picture, region, scale);
  final data = (await image.toByteData())!;
  final column = image.width ~/ 2;
  var total = 0.0;
  for (var row = 0; row < image.height; row++) {
    final i = ((row * image.width) + column) * 4;
    total += coverage(
      data.getUint8(i),
      data.getUint8(i + 1),
      data.getUint8(i + 2),
      data.getUint8(i + 3),
    );
  }
  image.dispose();
  return total;
}

/// Coverage of an annotation picture: transparent everywhere but the stroke.
double alphaCoverage(int r, int g, int b, int a) => a / 255;

/// Coverage of a page picture: black ink over the white paper background.
double inkCoverage(int r, int g, int b, int a) => (255 - r) / 255;

Future<double> annotationThickness(PdfDocument document, int slot, double scale,
    {double x = 150, double y = rasterY}) async {
  final page = document.page(0);
  final picture = await PdfPageRenderer.renderAnnotationPicture(
      page, page.annotations[slot]);
  expect(picture, isNotNull);
  final thickness = await measureThickness(picture!, scale,
      x: x, y: y, coverage: alphaCoverage);
  picture.dispose();
  return thickness;
}

/// A rasterized frame of the widget under [boundary], at 1 device px per
/// logical px.
Future<ByteData> capture(WidgetTester tester, GlobalKey boundary) async {
  final image = await tester.runAsync(() async {
    final render =
        boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    return render.toImage();
  });
  final data = (await tester.runAsync(image!.toByteData))!;
  image.dispose();
  return data;
}

/// The horizontal red stroke's thickness at ([x], [y]) of a captured
/// [width]-wide frame: the summed ink coverage of one pixel column, read off
/// the green channel (red ink over white paper).
double columnThickness(ByteData frame,
    {required double x, required double y, int width = 800, int span = 12}) {
  var total = 0.0;
  for (var row = (y - span).round(); row <= (y + span).round(); row++) {
    final i = ((row * width) + x.round()) * 4;
    total += (255 - frame.getUint8(i + 1)) / 255;
  }
  return total;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('strokeWidthFor', () {
    /// A device painting into a throwaway recorder - these only exercise the
    /// width conversion, nothing is drawn.
    CanvasPdfDevice device({double pixelRatio = 1}) {
      final recorder = ui.PictureRecorder();
      addTearDown(() => recorder.endRecording().dispose());
      return CanvasPdfDevice(Canvas(recorder), pixelRatio: pixelRatio);
    }

    test('a known output scale keeps the one-device-pixel floor (#426)', () {
      // pixelRatio 1 is the page picture's identity assumption, 2 a retina
      // raster: sub-pixel widths floor to Skia's hairline, so CAD linework
      // paints solid instead of at 6% alpha.
      final page = device();
      expect(page.strokeWidthFor(0.06), 0);
      expect(page.strokeWidthFor(0.6), 0);
      expect(page.strokeWidthFor(1), 1);
      expect(page.strokeWidthFor(1.5), 1.5);

      final retina = device(pixelRatio: 2);
      expect(retina.strokeWidthFor(0.06), 0);
      expect(retina.strokeWidthFor(0.6), 0.6); // 1.2 device px, above the floor
    });

    test('pixelRatio 0 preserves every positive page-space width', () {
      final scaleFree = device(pixelRatio: 0);
      expect(scaleFree.strokeWidthFor(pdfInkStrokeWidth(1.5, 0)),
          closeTo(0.6, 1e-9));
      expect(scaleFree.strokeWidthFor(0.06), 0.06);
      expect(scaleFree.strokeWidthFor(1.5), 1.5);
      // a genuine `0 w` stroke still asks for the device's thinnest line
      expect(scaleFree.strokeWidthFor(0), 0);
    });
  });

  group('the recorded annotation picture', () {
    test('scales positive widths below, at and above 1 pt with the replay '
        'scale', () async {
      final document = PdfDocument.open(buildAnnotationWidthPdf([0.6, 1, 1.5]));

      for (final (slot, width) in [(0, 0.6), (1, 1.0), (2, 1.5)]) {
        expect(await annotationThickness(document, slot, 1),
            closeTo(width, 0.35),
            reason: '$width pt should measure $width px at 1:1');
        expect(await annotationThickness(document, slot, zoom),
            closeTo(width * zoom, 0.35),
            reason: '$width pt should grow to ${width * zoom} px at 333% - '
                'a baked hairline would stay at 1');
      }
    });

    test('an exact zero-width stroke stays a device hairline at every scale',
        () async {
      final document = PdfDocument.open(buildAnnotationWidthPdf([0]));

      expect(await annotationThickness(document, 0, 1), closeTo(1, 0.35));
      expect(await annotationThickness(document, 0, zoom), closeTo(1, 0.35),
          reason: '`0 w` is §8.4.3.2 thinnest-line, not a page-space width');
    });
  });

  test('the page raster keeps the device-pixel floor for thin linework (#426)',
      () async {
    final document = PdfDocument.open(buildContentWidthPdf(0.06));
    final picture = await PdfPageRenderer.renderPicture(document.page(0));

    // Unfloored, 0.06 pt would cover 0.06 px (6% alpha) at 1:1 and 0.2 px at
    // 333% - the pale washed-out linework #426 fixed. Floored, it is a solid
    // device pixel at both.
    expect(await measureThickness(picture, 1, coverage: inkCoverage),
        closeTo(1, 0.35));
    expect(await measureThickness(picture, zoom, coverage: inkCoverage),
        closeTo(1, 0.35));
    picture.dispose();
  });

  group('the live-ink to committed-appearance transition', () {
    /// Commits one horizontal ink stroke drawn with [pressure] at both ends
    /// through the editing controller's own auto-commit path, and returns the
    /// controller plus the effective page-space width the live overlay drew.
    (PdfEditingController, double) commitPressuredStroke(double pressure) {
      final editing = PdfEditingController(buildBlankPdf(612, 792));
      addTearDown(editing.dispose);
      editing.preferences.strokeWidth = 1.5;
      editing
        ..color = const Color(0xFFFF0000)
        ..addInkStroke(0, [(100, lineY), (200, lineY)],
            pressures: [pressure, pressure])
        ..finishInk();
      expect(editing.document.page(0).annotations, hasLength(1));
      return (editing, pdfInkStrokeWidth(1.5, pressure));
    }

    test('pressure 0 commits 0.6 pt and replays it at 2 px at 333%', () async {
      final (editing, width) = commitPressuredStroke(0);
      expect(width, closeTo(0.6, 1e-9)); // below 1 pt: the hairline case

      // the live overlay paints width x zoom view pixels, unfloored; the
      // committed appearance has to measure the same
      expect(await annotationThickness(editing.document, 0, zoom),
          closeTo(width * zoom, 0.4));
    });

    test('pressure 0.5 and 1 keep their widths too', () async {
      for (final pressure in [0.5, 1.0]) {
        final (editing, width) = commitPressuredStroke(pressure);
        expect(await annotationThickness(editing.document, 0, zoom),
            closeTo(width * zoom, 0.5),
            reason: 'pressure $pressure commits $width pt');
      }
    });

    testWidgets('a stroke drawn at zero pressure keeps its live width once '
        'committed', (tester) async {
      // A 240 pt wide page fills the 800 px viewport at fit-width, so it is
      // displayed at 800/240 = 3.33 device px per point - the reported 333%,
      // without a zoom transform to map coordinates through.
      final editing = PdfEditingController(buildBlankPdf(240, 320));
      addTearDown(editing.dispose);
      editing.preferences.strokeWidth = 1.5;
      editing
        ..color = const Color(0xFFFF0000)
        ..tool = PdfEditTool.ink;
      final boundary = GlobalKey();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: RepaintBoundary(
            key: boundary,
            child: ListenableBuilder(
              listenable: editing,
              builder: (context, _) => PdfViewer(
                initialFit: PdfViewerFit.width,
                document: editing.document,
                editing: editing,
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      // Raw pointer events, because TestGesture cannot set pressure - and
      // pressure is the whole point here.
      Offset view(double x, double y) => Offset(x * zoom, (320 - y) * zoom);
      const stylus = PointerDeviceKind.stylus;
      var at = view(40, 200);
      await tester.sendEventToBinding(PointerDownEvent(
          pointer: 7,
          kind: stylus,
          position: at,
          pressure: 0,
          pressureMin: 0,
          pressureMax: 1));
      await tester.pump();
      for (final x in [80.0, 120.0, 160.0, 200.0]) {
        final next = view(x, 200);
        await tester.sendEventToBinding(PointerMoveEvent(
            pointer: 7,
            kind: stylus,
            position: next,
            delta: next - at,
            pressure: 0,
            pressureMin: 0,
            pressureMax: 1));
        await tester.pump();
        at = next;
      }

      // mid-stroke: the live overlay owns the pixels, unfloored
      final live = columnThickness(await capture(tester, boundary),
          x: view(120, 200).dx, y: view(120, 200).dy);
      expect(live, closeTo(pdfInkStrokeWidth(1.5, 0) * zoom, 0.4),
          reason: 'live ink draws 0.6 pt x 3.33 = 2 device px');

      await tester.sendEventToBinding(PointerUpEvent(
          pointer: 7,
          kind: stylus,
          position: at,
          pressure: 0,
          pressureMin: 0,
          pressureMax: 1));
      await tester.pump();
      editing.finishInk();
      await tester.pump();

      final annotation = editing.document.page(0).annotations.single;
      expect(annotation.subtype, 'Ink');

      // and the appearance the annotation layer replays has to match it: it
      // used to be a one-pixel hairline whatever the scale.
      final committed = await tester.runAsync(() =>
          annotationThickness(editing.document, 0, zoom, x: 120, y: 320 - 200));
      expect(committed, closeTo(live, 0.5),
          reason: 'the committed appearance must not thin the stroke');

      // let the commit afterimage's debounce and the tap recognizers expire
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
    });
  });
}
