import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<int> _alphaAt(ui.Picture picture, ui.Offset point) async {
  final image = await PdfPageRenderer.rasterizeRegion(
    picture,
    ui.Rect.fromCenter(center: point, width: 1, height: 1),
    2,
  );
  try {
    final bytes = (await image.toByteData())!;
    return bytes.getUint8(3);
  } finally {
    image.dispose();
  }
}

Future<Uint8List> _rgbaRegion(
  ui.Picture picture,
  ui.Rect region,
) async {
  final image = await PdfPageRenderer.rasterizeRegion(picture, region, 2);
  try {
    final bytes = (await image.toByteData())!;
    return Uint8List.fromList(bytes.buffer.asUint8List());
  } finally {
    image.dispose();
  }
}

ui.Picture _combine(Iterable<ui.Picture> pictures) {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  for (final picture in pictures) {
    canvas.drawPicture(picture);
  }
  return recorder.endRecording();
}

void _disposeAll(Iterable<ui.Picture> pictures) {
  for (final picture in pictures) {
    picture.dispose();
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('a wrapped Highlight records one clipped picture per markup quad',
      () async {
    final editing = PdfEditingController(
      buildTextLinesPdf(
        const ['First highlighted line', 'Second highlighted line'],
        size: 12,
      ),
    );
    addTearDown(editing.dispose);
    editing.apply(
      (editor) => editor.addHighlight(
        0,
        const [
          PdfRect(36, 716, 180, 732),
          PdfRect(36, 692, 205, 708),
        ],
        color: 0xFFFF00,
        opacity: 1,
      ),
    );

    final page = editing.document.page(0);
    final annotation = page.annotations.single;
    final pictures = await PdfPageRenderer.renderAnnotationPictures(
      page,
      annotation,
    );
    addTearDown(() => _disposeAll(pictures));

    expect(pictures, hasLength(2));

    // Annotation pictures use rotated page-raster space (y down). For a
    // 792-point page these are the centres of the first quad, second quad,
    // and the vertical gap between them.
    const first = ui.Offset(80, 68);
    const second = ui.Offset(80, 92);
    const gap = ui.Offset(80, 80);

    expect(await _alphaAt(pictures[0], first), greaterThan(0));
    expect(await _alphaAt(pictures[0], second), 0);
    expect(await _alphaAt(pictures[0], gap), 0);

    expect(await _alphaAt(pictures[1], first), 0);
    expect(await _alphaAt(pictures[1], second), greaterThan(0));
    expect(await _alphaAt(pictures[1], gap), 0);

    final legacy = await PdfPageRenderer.renderAnnotationPicture(
      page,
      annotation,
    );
    final combined = _combine(pictures);
    addTearDown(legacy!.dispose);
    addTearDown(combined.dispose);
    const union = ui.Rect.fromLTRB(34, 58, 207, 102);
    expect(
      await _rgbaRegion(combined, union),
      await _rgbaRegion(legacy, union),
      reason: 'splitting must not alter colour, alpha, or Multiply pixels',
    );
  });

  test('a single-quad Highlight keeps the one-picture path', () async {
    final editing = PdfEditingController(buildTextLinesPdf(const ['One line']));
    addTearDown(editing.dispose);
    editing.apply(
      (editor) => editor.addHighlight(
        0,
        const [PdfRect(36, 716, 120, 732)],
        opacity: 1,
      ),
    );

    final page = editing.document.page(0);
    final pictures = await PdfPageRenderer.renderAnnotationPictures(
      page,
      page.annotations.single,
    );
    addTearDown(() => _disposeAll(pictures));

    expect(pictures, hasLength(1));
  });

  test('multi-quad non-Highlight markup keeps the one-picture path', () async {
    final editing = PdfEditingController(buildTextLinesPdf(const ['A', 'B']));
    addTearDown(editing.dispose);
    editing.apply(
      (editor) => editor.addUnderline(
        0,
        const [
          PdfRect(36, 716, 80, 732),
          PdfRect(36, 692, 80, 708),
        ],
      ),
    );

    final page = editing.document.page(0);
    final pictures = await PdfPageRenderer.renderAnnotationPictures(
      page,
      page.annotations.single,
    );
    addTearDown(() => _disposeAll(pictures));

    expect(pictures, hasLength(1));
  });
}
