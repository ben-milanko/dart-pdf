// The viewport projection as pure maths: capture o place is the identity
// across zooms, page sizes and positions, and framing respects the clamps.

import 'dart:math' as math;

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:dart_pdf_editor/src/viewport_frame.dart';
import 'package:flutter_test/flutter_test.dart';

/// A single-column layout: pages stacked along the main axis with [spacing],
/// centred on the cross axis of a [crossView]-wide view.
class _Column implements PdfViewportLayout {
  _Column(this.sizes, {this.spacing = 8, required this.crossView});

  /// (main, cross) extent per page.
  final List<(double, double)> sizes;
  final double spacing;
  final double crossView;

  @override
  int get pageCount => sizes.length;

  @override
  int pageAt(double listMain, double listCross) {
    var start = 0.0;
    for (var i = 0; i < sizes.length; i++) {
      if (listMain < start + sizes[i].$1 + spacing || i == sizes.length - 1) {
        return i;
      }
      start += sizes[i].$1 + spacing;
    }
    return sizes.length - 1;
  }

  @override
  double mainStartOf(int page) {
    var start = 0.0;
    for (var i = 0; i < page; i++) {
      start += sizes[i].$1 + spacing;
    }
    return start;
  }

  @override
  double crossStartOf(int page) => (crossView - sizes[page].$2) / 2;

  @override
  double mainExtentOf(int page) => sizes[page].$1;

  @override
  double crossExtentOf(int page) => sizes[page].$2;

  double get total => mainStartOf(sizes.length - 1) + sizes.last.$1;
}

void main() {
  const mainView = 700.0, crossView = 500.0;

  test('projection and unprojection are inverses', () {
    const frame = PdfViewportFrame(
        scroll: 1200, scale: 2.5, mainTranslate: -310, crossTranslate: -90);
    for (final p in [0.0, 17.5, 333.0, 699.0]) {
      expect(frame.viewMainOf(frame.listMainAt(p)), closeTo(p, 1e-9));
      expect(frame.viewCrossOf(frame.listCrossAt(p)), closeTo(p, 1e-9));
    }
  });

  test('capture o place is the identity away from the clamps', () {
    final random = math.Random(7);
    for (var trial = 0; trial < 200; trial++) {
      final layout = _Column([
        for (var i = 0; i < 6; i++)
          (400 + random.nextDouble() * 600, 300 + random.nextDouble() * 200),
      ], crossView: crossView);
      // from 3x the cross clamp leaves the whole sampled range reachable
      final zoom = random.nextBool() ? 1.0 : 3 + random.nextDouble() * 5;
      final page = 1 + random.nextInt(3); // keep clear of the scroll ends
      final viewport = PdfViewport(
        page: page,
        top: random.nextDouble() * 0.9,
        // the cross clamp only allows positions the zoomed view can reach
        left: zoom == 1 ? 0 : 0.1 + random.nextDouble() * 0.3,
        zoom: zoom,
      );
      final frame = placePdfViewport(viewport, page, layout,
          scale: zoom,
          mainView: mainView,
          crossView: crossView,
          maxScroll: layout.total);
      final captured = capturePdfViewport(frame, layout, zoom: zoom);
      expect(captured.page, viewport.page, reason: 'trial $trial');
      expect(captured.top, closeTo(viewport.top, 1e-9), reason: 'trial $trial');
      if (zoom > 1) {
        expect(captured.left, closeTo(viewport.left, 1e-9),
            reason: 'trial $trial');
      }
    }
  });

  test('at fit the transform is the identity and only scroll moves', () {
    final frame = PdfViewportFrame.showing(
        listMain: 900,
        listCross: 40,
        scale: 0.6, // below fit: the layout shrinks, not the transform
        mainView: mainView,
        crossView: crossView,
        maxScroll: 5000);
    expect(frame, const PdfViewportFrame(scroll: 900));
  });

  test('scroll clamps to the list; the transform absorbs the rest', () {
    // a point near the end of the list, at 3x: the scroll stops at its end
    // and the main translation carries the remainder
    final frame = PdfViewportFrame.showing(
        listMain: 1000,
        listCross: 100,
        scale: 3,
        mainView: mainView,
        crossView: crossView,
        maxScroll: 900);
    expect(frame.scroll, 900);
    expect(frame.listMainAt(0), closeTo(1000, 1e-9));
    expect(frame.listCrossAt(0), closeTo(100, 1e-9));
  });

  test('the transform never pulls the content edge inside the view', () {
    final frame = PdfViewportFrame.showing(
        listMain: 0,
        listCross: 10000, // far past the cross edge
        scale: 2,
        mainView: mainView,
        crossView: crossView,
        maxScroll: 0);
    expect(frame.crossTranslate, crossView * (1 - 2));
    final leading = PdfViewportFrame.showing(
        listMain: 0,
        listCross: -50,
        scale: 2,
        mainView: mainView,
        crossView: crossView,
        maxScroll: 0);
    expect(leading.crossTranslate, 0);
  });

  test('framing about the view centre puts the point there', () {
    final frame = PdfViewportFrame.showing(
        listMain: 2000,
        listCross: 250,
        scale: 4,
        mainView: mainView,
        crossView: crossView,
        maxScroll: 10000,
        atMain: mainView / 2,
        atCross: crossView / 2);
    expect(frame.viewMainOf(2000), closeTo(mainView / 2, 1e-9));
    expect(frame.viewCrossOf(250), closeTo(crossView / 2, 1e-9));
  });

  test('capture past the last page lands on it', () {
    final layout = _Column([(500, 400), (500, 400)], crossView: crossView);
    final captured = capturePdfViewport(
        const PdfViewportFrame(scroll: 5000), layout,
        zoom: 1);
    expect(captured.page, 1);
  });
}
