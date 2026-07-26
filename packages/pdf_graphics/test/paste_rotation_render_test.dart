// Rendering-level proof that PdfEditor.pasteAnnotation re-orients an
// annotation for the destination page's /Rotate: the geometry tests in
// pdf_document assert the /Matrix and /Rect, but only the interpreter -
// which applies the page's display rotation - shows what the user actually
// sees. A text run's transform maps em-space (baseline advance along +x) to
// device space, so its first two components are the on-screen baseline
// direction: (+,0) upright, (-,0) flipped 180, (0,±) rotated 90.

import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:test/test.dart';

class _TextCapture implements PdfDevice {
  final runs = <PdfTextRun>[];
  @override
  void drawText(PdfTextRun run) => runs.add(run);
  @override
  void fillPath(PdfPath p, PdfColor c, PdfFillRule r, double a) {}
  @override
  void fillMesh(PdfMesh m, double a) {}
  @override
  void strokePath(PdfPath p, PdfColor c, PdfStroke s, double a) {}
  @override
  void setBlendMode(PdfBlendMode m) {}
  @override
  void setOverprint(
      {required bool fill, required bool stroke, required int mode}) {}
  @override
  void save() {}
  @override
  void restore() {}
  @override
  void clipPath(PdfPath p, PdfFillRule r) {}
  @override
  void fillPathGradient(PdfPath p, PdfFillRule r, PdfGradient g, double a) {}
  @override
  void drawImage(PdfImageRequest r) {}
  @override
  void beginGroup(double a, {bool knockout = false}) {}
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

PdfDocument _edited(PdfDocument doc, void Function(PdfEditor) edit) {
  final editor = PdfEditor(doc);
  edit(editor);
  return PdfDocument.open(editor.save());
}

/// The on-screen baseline direction of the first text run on [page] after
/// the interpreter applies the page's display rotation.
(double, double) _baselineDirection(PdfDocument doc, int page) {
  final device = _TextCapture();
  final p = doc.page(page);
  PdfInterpreter(cos: doc.cos, device: device)
    ..drawPage(p)
    ..drawAnnotations(p);
  expect(device.runs, isNotEmpty, reason: 'expected a rendered text run');
  final m = device.runs.first.transform.toList(); // [a, b, c, d, e, f]
  return (m[0], m[1]);
}

void main() {
  const rect = PdfRect(120, 600, 460, 660);

  Matcher upright() => predicate<(double, double)>(
        (d) => d.$1 > 1e-6 && d.$2.abs() < 1e-6,
        'an upright (+x) text baseline',
      );

  test('a FreeText pasted onto a 90° page renders upright, not spun', () {
    // Source authored on an unrotated page; destination page is /Rotate 90.
    final doc = _edited(PdfDocument.open(buildMultiPagePdf(2)), (e) {
      e.rotatePage(1, 90);
      e.addFreeText(0, rect, 'Hello');
    });
    // Sanity: the source reads upright on its unrotated page.
    expect(_baselineDirection(doc, 0), upright());

    final snapshot = PdfAnnotationSnapshot.capture(
        doc, doc.page(0).annotations.single,
        sourcePageRotation: doc.page(0).rotation)!;
    final out = _edited(doc, (e) => e.pasteAnnotation(1, snapshot));

    // The whole point: on the rotated page the copy is still upright. Before
    // the fix this baseline was vertical (spun 90° by the page rotation); a
    // wrong-signed counter-rotation would read (-x) - flipped 180°.
    expect(_baselineDirection(out, 1), upright());
  });

  test('a FreeText captured from a 90° page pastes upright onto a flat page',
      () {
    // The mirror case: the source appearance already carries addFreeText's
    // own rotated-page compensation, so the paste must not double-rotate.
    final rotated = _edited(PdfDocument.open(buildMultiPagePdf(1)), (e) {
      e.rotatePage(0, 90);
      e.addFreeText(0, rect, 'Hello');
    });
    expect(_baselineDirection(rotated, 0), upright());

    final snapshot = PdfAnnotationSnapshot.capture(
        rotated, rotated.page(0).annotations.single,
        sourcePageRotation: rotated.page(0).rotation)!;
    expect(snapshot.sourceRotation, 90);

    final flat = _edited(PdfDocument.open(buildMultiPagePdf(1)),
        (e) => e.pasteAnnotation(0, snapshot));
    expect(_baselineDirection(flat, 0), upright());
  });
}
