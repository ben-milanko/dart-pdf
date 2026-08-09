// Exact placement of substituted glyphs (#649). Matching only a run's total
// advance pins its two endpoints and lets everything between land wherever the
// substitute's own advances put it - up to ~4.4pt of drift on a 12pt line, zero
// at both ends and worst mid-run. Selection bands, search highlights, markup
// placed over a selection and content-element hit boxes are all computed from
// the PDF's advances, so they read as offset against the glyphs by that much.
//
// The device is handed those advances as PdfTextRun.charOffsets and must paint
// each character at its own offset. These tests drive the ink directly: they
// render a run whose PDF offsets deliberately disagree with the substitute's
// natural distribution, and look at where the glyphs actually landed.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_graphics/pdf_graphics.dart';

const _width = 400;
const _height = 120;

/// Renders one run and returns the x of every column carrying ink.
Future<List<int>> _inkColumns(PdfTextRun run) async {
  CanvasPdfDevice.clearTextLayoutCache();
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder)
    ..drawColor(const Color(0xFFFFFFFF), BlendMode.src);
  CanvasPdfDevice(canvas).drawText(run);
  final image = await recorder.endRecording().toImage(_width, _height);
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final pixels = Uint8List.view(data!.buffer);
    final columns = <int>[];
    for (var x = 0; x < _width; x++) {
      for (var y = 0; y < _height; y++) {
        if (pixels[(y * _width + x) * 4] != 0xFF) {
          columns.add(x);
          break;
        }
      }
    }
    return columns;
  } finally {
    image.dispose();
  }
}

/// A two-character run drawn at 20pt from the page origin-ish, with the PDF
/// claiming [offsets] for its character boundaries.
PdfTextRun _run(String text, List<double>? offsets, double width) => PdfTextRun(
      text: text,
      transform: const PdfMatrix(20, 0, 0, 20, 20, 60),
      color: const PdfColor(0, 0, 0),
      width: width,
      charOffsets: offsets,
      fontName: 'Helvetica',
      fontSize: 20,
    );

void main() {
  tearDown(() {
    CanvasPdfDevice.exactSubstitutedGlyphPlacement = true;
    CanvasPdfDevice.clearTextLayoutCache();
  });

  testWidgets('each glyph lands on its own PDF advance, not a scaled share',
      (tester) async {
    await tester.runAsync(() async {
      // The test font is fixed-pitch, so "natural" placement puts the two
      // characters flush against each other. The PDF says the second starts at
      // 1.6 em - the kind of interior disagreement a real substitute produces
      // as accumulated drift. Placement must follow the PDF, opening a gap;
      // matching the 2.6 em total alone would keep them flush and only stretch
      // both glyphs.
      final columns = await _inkColumns(_run('AA', [0, 1.6, 2.6], 2.6));
      expect(columns, isNotEmpty);

      // 2.6 em of PDF advance across 2 em of natural glyph = a 1.3x squeeze,
      // so each glyph is 20 * 1.3 = 26pt wide, starting at 20 and at
      // 20 + 1.6 * 20 = 52.
      expect(columns.first, closeTo(20, 2));
      expect(columns.last, closeTo(52 + 26, 2));
      // The gap between them is real ink-free space, which the whole-run path
      // cannot produce.
      final gap = [
        for (var x = columns.first; x <= columns.last; x++)
          if (!columns.contains(x)) x,
      ];
      expect(gap, isNotEmpty, reason: 'the second glyph must start at 1.6 em');
      expect(gap.first, closeTo(46, 3)); // 20 + 26
      expect(gap.last, closeTo(52, 3));

      // The whole-run path, for contrast: one solid block from 20 to the run's
      // 2.6 em end at 72. Both endpoints are exact and every interior boundary
      // is wrong - which is the defect. Placement makes the reverse trade: each
      // character's origin is exact, and the last glyph's *shape* (drawn at the
      // run's average squeeze, not its own) may overhang the run's end.
      CanvasPdfDevice.exactSubstitutedGlyphPlacement = false;
      final whole = await _inkColumns(_run('AA', [0, 1.6, 2.6], 2.6));
      expect(whole.first, closeTo(20, 2));
      expect(whole.last, closeTo(72, 2));
      expect(whole.length, whole.last - whole.first + 1,
          reason: 'whole-run shaping leaves no gap to find the drift by');
    });
  });

  testWidgets('a word whose interior already holds is shaped whole',
      (tester) async {
    await tester.runAsync(() async {
      // The test font is fixed-pitch, so offsets of exactly one em per
      // character are what it would draw anyway. Nothing needs taking apart,
      // and the result must be identical to whole-run shaping - the tolerance
      // is what keeps ordinary text off the per-character path.
      final held = await _inkColumns(_run('AA', [0, 1, 2], 2));
      CanvasPdfDevice.exactSubstitutedGlyphPlacement = false;
      final whole = await _inkColumns(_run('AA', [0, 1, 2], 2));
      expect(held, whole);
    });
  });

  testWidgets('word origins are exact even when the interiors hold',
      (tester) async {
    await tester.runAsync(() async {
      // Two one-em words with a space between them, and the PDF putting the
      // second word a full em later than the substitute's own space would.
      // Each word holds internally, so each is one shaped part - but the
      // second still starts exactly where the PDF says, which is the drift
      // that accumulates across a line of prose.
      final columns = await _inkColumns(_run('A A', [0, 1, 3, 4], 4));
      final gap = [
        for (var x = columns.first; x <= columns.last; x++)
          if (!columns.contains(x)) x,
      ];
      expect(gap, isNotEmpty);
      // The shape scale comes from the ink alone - 2 em of glyph against 2 em
      // of PDF advance, so 1x - and the space absorbs the rest: the first word
      // spans 20-40 and the second starts at 20 + 3 * 20 = 80.
      expect(columns.first, closeTo(20, 2));
      expect(gap.first, closeTo(40, 3));
      expect(gap.last, closeTo(79, 3));
    });
  });

  testWidgets('the kill switch restores whole-run distribution',
      (tester) async {
    await tester.runAsync(() async {
      CanvasPdfDevice.exactSubstitutedGlyphPlacement = false;
      final off = await _inkColumns(_run('AA', [0, 1.6, 2.6], 2.6));
      final none = await _inkColumns(_run('AA', null, 2.6));
      expect(off, none,
          reason: 'with placement off, an offset table changes nothing');
    });
  });

  testWidgets('a run with no offset table keeps whole-run shaping',
      (tester) async {
    await tester.runAsync(() async {
      // Vertical writing mode and RTL runs get no table and must be untouched.
      final placed = await _inkColumns(_run('AA', null, 2.6));
      CanvasPdfDevice.exactSubstitutedGlyphPlacement = false;
      final plain = await _inkColumns(_run('AA', null, 2.6));
      expect(placed, plain);
    });
  });

  testWidgets('a complex script keeps whole-run shaping', (tester) async {
    await tester.runAsync(() async {
      // Arabic needs joining and reorders; one glyph per character is not a
      // valid rendering of it, so the offsets must be declined.
      const arabic = 'مرحبا';
      final offsets = [0.0, 0.9, 1.6, 2.4, 3.1, 3.8];
      final placed = await _inkColumns(_run(arabic, offsets, 3.8));
      CanvasPdfDevice.exactSubstitutedGlyphPlacement = false;
      final plain = await _inkColumns(_run(arabic, offsets, 3.8));
      expect(placed, plain);
    });
  });

  testWidgets('a table of the wrong length is declined', (tester) async {
    await tester.runAsync(() async {
      // One entry per character plus the closing boundary, or nothing: a
      // mismatched table would index off the end of the run.
      final placed = await _inkColumns(_run('AA', [0, 1.6], 2.6));
      CanvasPdfDevice.exactSubstitutedGlyphPlacement = false;
      final plain = await _inkColumns(_run('AA', null, 2.6));
      expect(placed, plain);
    });
  });

  testWidgets('leading whitespace still opens its gap once', (tester) async {
    await tester.runAsync(() async {
      // A leading space carrying a large Tw is how tabular content reaches its
      // column. The device translates by leadingSpace and paints the trimmed
      // core, so the core's offsets must be rebased by exactly that much -
      // double-counting it would push the glyphs a whole column right.
      final spaced = PdfTextRun(
        text: ' AA',
        transform: const PdfMatrix(20, 0, 0, 20, 20, 60),
        color: const PdfColor(0, 0, 0),
        width: 4.6,
        leadingSpace: 2.0,
        visibleWidth: 4.6,
        charOffsets: const [0, 2.0, 3.6, 4.6],
        fontName: 'Helvetica',
        fontSize: 20,
      );
      final columns = await _inkColumns(spaced);
      expect(columns, isNotEmpty);
      // First visible glyph at 2.0 em: 20 + 2.0 * 20 = 60.
      expect(columns.first, closeTo(60, 2));
    });
  });
}
