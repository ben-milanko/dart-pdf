// Where the inline free-text editor actually *paints* at deep zoom.
//
// The macOS caret defect (#692) survived a regression that asserted
// `RenderEditable.cursorOffset` and the local caret rectangles, because the
// caret was never wrong relative to the editor's own text - the whole live
// line was drifting off the box. Everything here is therefore measured from
// the composited frame, in physical pixels, with the editor inside the
// viewer's zoom transform.
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One run of ink in a captured row: first and last inked column.
typedef Ink = (int lo, int hi);

const _noInk = (1 << 30, -1);

void main() {
  const editorKey = ValueKey('pdf-freetext-editor');
  const boundaryKey = ValueKey('pdf-caret-zoom-frame');

  // A box centred in the viewport at fit-width, so it stays on screen when
  // the transform magnifies about the viewport centre: an 800x800 logical
  // viewport over a 612x792 page shows the top 612pt, centred on (306, 486).
  const rect = PdfRect(291, 477, 321, 494.7585);
  const rectWidth = 321 - 291.0;
  const fontSize = 8.0;
  const text = 'UB';

  Future<(PdfEditingController, PdfViewerController)> pumpEditor(
      WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final editing = PdfEditingController(buildMultiPagePdf(1));
    final viewer = PdfViewerController();
    addTearDown(editing.dispose);
    addTearDown(viewer.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RepaintBoundary(
          key: boundaryKey,
          child: ListenableBuilder(
            listenable: editing,
            builder: (context, _) => PdfViewer(
              initialFit: PdfViewerFit.width,
              document: editing.document,
              controller: viewer,
              editing: editing,
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
    return (editing, viewer);
  }

  /// Splits the ink inside [region] of the composited frame into the glyph
  /// run and the caret, in physical pixels.
  ///
  /// The two are told apart by width: the caret is a hairline a couple of
  /// logical pixels across at any zoom, the glyphs are a whole line of text,
  /// and (on Apple platforms) the caret is drawn taller than the text, so it
  /// owns rows of its own above and below the run.
  Future<(Ink glyphs, Ink caret)> paintedInk(
      WidgetTester tester, Rect region, Rect wash) async {
    final boundary =
        tester.renderObject<RenderRepaintBoundary>(find.byKey(boundaryKey));
    final dpr = tester.view.devicePixelRatio;
    final (image, data) = (await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: dpr);
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      return (image, data);
    }))!;
    final width = image.width;
    final height = image.height;
    final bytes = data!.buffer.asUint8List();
    final x0 = (region.left * dpr).floor().clamp(0, width - 1);
    final x1 = (region.right * dpr).ceil().clamp(0, width - 1);
    final y0 = (region.top * dpr).floor().clamp(0, height - 1);
    final y1 = (region.bottom * dpr).ceil().clamp(0, height - 1);
    // The box wash is the modal colour over the whole box interior - a band
    // tight around one line of text can be more glyph than background.
    final counts = <int, int>{};
    final wx0 = (wash.left * dpr).floor().clamp(0, width - 1);
    final wx1 = (wash.right * dpr).ceil().clamp(0, width - 1);
    final wy0 = (wash.top * dpr).floor().clamp(0, height - 1);
    final wy1 = (wash.bottom * dpr).ceil().clamp(0, height - 1);
    for (var x = wx0; x <= wx1; x++) {
      for (var y = wy0; y <= wy1; y++) {
        final i = (y * width + x) * 4;
        final key = (bytes[i] << 16) | (bytes[i + 1] << 8) | bytes[i + 2];
        counts[key] = (counts[key] ?? 0) + 1;
      }
    }
    var background = 0, seen = -1;
    counts.forEach((colour, count) {
      if (count > seen) {
        seen = count;
        background = colour;
      }
    });
    final bgR = (background >> 16) & 0xff;
    final bgG = (background >> 8) & 0xff;
    final bgB = background & 0xff;
    var glyphs = _noInk, caret = _noInk;
    for (var y = y0; y <= y1; y++) {
      int? lo, hi;
      for (var x = x0; x <= x1; x++) {
        final i = (y * width + x) * 4;
        if ((bytes[i] - bgR).abs() > 40 ||
            (bytes[i + 1] - bgG).abs() > 40 ||
            (bytes[i + 2] - bgB).abs() > 40) {
          lo ??= x;
          hi = x;
        }
      }
      if (lo == null) continue;
      // a caret-only row is a few pixels wide; a text row is a whole line
      final isText = hi! - lo > 8 * dpr;
      final grown = isText ? glyphs : caret;
      final merged = (
        lo < grown.$1 ? lo : grown.$1,
        hi > grown.$2 ? hi : grown.$2,
      );
      if (isText) {
        glyphs = merged;
      } else {
        caret = merged;
      }
    }
    image.dispose();
    return (glyphs, caret);
  }

  /// Opens the inline editor over a free-text box of [align]ment, zoomed to
  /// [zoom] logical pixels per point, and reports what the frame shows.
  Future<
      ({
        Ink glyphs,
        Ink caretAtStart,
        Ink caretAtEnd,
        Rect textArea,
        double caretHeight,
        double lineHeight,
        double dpr,
      })> measure(
    WidgetTester tester, {
    required PdfTextAlign align,
    required double zoom,
  }) async {
    final (editing, viewer) = await pumpEditor(tester);
    editing.preferences
      ..fontSize = fontSize
      ..textAlign = align;
    editing
      ..addFreeText(0, rect, text)
      ..selectAnnotation(0, 0);
    await tester.pump();
    viewer.setZoom(zoom);
    await tester.pump();
    expect(editing.requestEditSelectedTextInline(), isTrue);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));

    final finder = find.byKey(editorKey);
    final field = tester.widget<TextField>(finder);
    final editable =
        find.descendant(of: finder, matching: find.byType(EditableText));
    final render = tester.state<EditableTextState>(editable).renderEditable;
    // screen pixels per point, straight off the viewer (the transform
    // clamps, so this is the zoom the user got, not the one asked for)
    final perPoint = viewer.zoom;
    // the editor's content box is the annotation rect: the chrome border
    // lives in the gutter the box inflates itself by
    final box = tester.getRect(finder);
    // what the committed appearance aligns inside: less its 3pt text inset
    final textArea = Rect.fromLTRB(box.left + 3 * perPoint, box.top,
        box.left + (rectWidth - 3) * perPoint, box.bottom);
    // everything is read inside the box and inside the window, clear of the
    // chrome border and of the viewer's scrollbar gutter
    final view = tester.view;
    final screen = Rect.fromLTWH(0, 0,
        view.physicalSize.width / view.devicePixelRatio - 20,
        view.physicalSize.height / view.devicePixelRatio);
    // the box interior, for the wash colour
    final wash = box.deflate(4).intersect(screen);
    // the line's own band, for the ink
    final region = Rect.fromPoints(
            render.localToGlobal(Offset.zero),
            render.localToGlobal(render.size.bottomRight(Offset.zero)))
        .intersect(wash);

    var caretHeight = 0.0;
    Future<(Ink, Ink)> at(int offset) async {
      field.controller!.selection = TextSelection.collapsed(offset: offset);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      final caret = render.getLocalRectForCaret(TextPosition(offset: offset));
      final top = render.localToGlobal(caret.topLeft);
      final bottom = render.localToGlobal(caret.bottomLeft);
      caretHeight = (bottom.dy - top.dy).abs();
      return paintedInk(tester, region, wash);
    }

    // the caret parked mid-word never extends the run, so this reads the
    // glyphs alone
    final (glyphs, _) = await at(1);
    final (_, caretAtStart) = await at(0);
    final (_, caretAtEnd) = await at(text.length);
    return (
      glyphs: glyphs,
      caretAtStart: caretAtStart,
      caretAtEnd: caretAtEnd,
      textArea: textArea,
      caretHeight: caretHeight,
      lineHeight: fontSize * 1.2 * perPoint,
      dpr: tester.view.devicePixelRatio,
    );
  }

  group('the inline free-text caret at deep zoom', () {
    for (final align in PdfTextAlign.values) {
      // 4 px/pt is an ordinary reading zoom; the deep one is the viewer's
      // ceiling, where a constant in layout pixels turns into a visible gap
      for (final zoom in const <double>[4, 40]) {
        testWidgets('$align free text: painted caret hugs the glyphs at '
            '${zoom.toInt()} px/pt', (tester) async {
          tester.view.physicalSize = const Size(1600, 1600);
          tester.view.devicePixelRatio = 2;
          addTearDown(tester.view.reset);

          final shot = await measure(tester, align: align, zoom: zoom);
          expect(shot.glyphs.$2, greaterThan(shot.glyphs.$1),
              reason: 'the live text should be on screen');

          // The caret at either end of the line sits on the glyph it marks -
          // in physical pixels of the composited frame, at any zoom. Two
          // physical pixels of that is Flutter's own Apple-platform nudge.
          expect(shot.caretAtStart.$1, closeTo(shot.glyphs.$1, 4),
              reason: 'caret at offset 0 left the first glyph behind');
          expect(shot.caretAtEnd.$2, closeTo(shot.glyphs.$2 + 2 * shot.dpr, 4),
              reason: 'caret at text.length landed inside the last glyph');
          expect(shot.caretHeight, closeTo(shot.lineHeight + 2, 1.5),
              reason: 'the Apple caret overhang must stay two screen pixels, '
                  'not grow with page zoom');

          // ...and the line itself is laid out on the appearance's text area,
          // not on what is left of the field after Flutter reserves its caret
          // gutter. Left-aligned text never noticed that gutter; centred text
          // lost half of it and right-aligned text all of it, as a constant
          // number of *layout* pixels that the transform magnified - a gap
          // that grew with zoom until the caret sat inside the last glyph.
          final area = shot.textArea;
          final left = shot.glyphs.$1 / shot.dpr;
          final right = shot.glyphs.$2 / shot.dpr;
          switch (align) {
            case PdfTextAlign.left:
              expect(left, closeTo(area.left, 2));
            case PdfTextAlign.center:
              expect((left + right) / 2, closeTo(area.center.dx, 2));
            case PdfTextAlign.right:
              expect(right, closeTo(area.right, 2));
          }
        }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
      }
    }
  });
}
