// The viewport projection as pure maths: capture o place is the identity
// across zooms, page sizes and positions, and framing respects the clamps.

import 'dart:math' as math;

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:dart_pdf_editor/src/viewport_frame.dart';
import 'package:flutter_test/flutter_test.dart';

/// A single-column layout: pages stacked along the main axis with [spacing],
/// centred on the cross axis of a [crossView]-wide view.
class _Column implements PdfViewportLayout {
  _Column(this.sizes, {required this.crossView});

  /// (main, cross) extent per page.
  final List<(double, double)> sizes;
  static const spacing = 8.0;
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
      final captured = capturePdfViewport(frame, layout);
      expect(captured.page, viewport.page, reason: 'trial $trial');
      expect(captured.top, closeTo(viewport.top, 1e-9), reason: 'trial $trial');
      expect(captured.zoom, zoom, reason: 'trial $trial');
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
    final captured =
        capturePdfViewport(const PdfViewportFrame(scroll: 5000), layout);
    expect(captured.page, 1);
  });

  group('zoom about a focal point', () {
    test('the content under the pointer stays under it', () {
      final random = math.Random(11);
      for (var trial = 0; trial < 200; trial++) {
        final before = PdfViewportFrame(
          scroll: random.nextDouble() * 4000,
          scale: 2 + random.nextDouble() * 2,
          mainTranslate: -random.nextDouble() * mainView,
          crossTranslate: -random.nextDouble() * crossView,
        );
        // a pointer well inside the view, zooming in from 2-4x to 4-8x keeps
        // every translation clear of the clamps
        final atMain = mainView * (0.3 + random.nextDouble() * 0.4);
        final atCross = crossView * (0.3 + random.nextDouble() * 0.4);
        final listMain = before.listMainAt(atMain);
        final listCross = before.listCrossAt(atCross);
        final scale = before.scale * 2;
        final after = PdfViewportFrame.zoomedAbout(
            scroll: before.scroll,
            listMain: listMain,
            listCross: listCross,
            scale: scale,
            atMain: atMain,
            atCross: atCross,
            mainView: mainView,
            crossView: crossView);
        expect(after.scroll, before.scroll, reason: 'trial $trial');
        expect(after.scale, scale);
        expect(after.viewMainOf(listMain), closeTo(atMain, 1e-9),
            reason: 'trial $trial');
        expect(after.viewCrossOf(listCross), closeTo(atCross, 1e-9),
            reason: 'trial $trial');
      }
    });

    test('clamps at the content edge, or leaves the cross axis free', () {
      PdfViewportFrame zoom({bool clampCross = true}) =>
          PdfViewportFrame.zoomedAbout(
              scroll: 0,
              listMain: 0,
              listCross: -100, // left of the content
              scale: 3,
              atMain: 0,
              atCross: 0,
              mainView: mainView,
              crossView: crossView,
              clampCross: clampCross);
      expect(zoom().crossTranslate, 0);
      expect(zoom(clampCross: false).crossTranslate, 300);
      expect(zoom().mainTranslate, 0);
    });

    test('within 1% of fit it snaps to the identity', () {
      expect(
          PdfViewportFrame.zoomedAbout(
              scroll: 120,
              listMain: 400,
              listCross: 90,
              scale: 1.005,
              atMain: 300,
              atCross: 200,
              mainView: mainView,
              crossView: crossView),
          const PdfViewportFrame(scroll: 120));
    });
  });

  group('layout zoom', () {
    final random = math.Random(5);
    final extents = [
      for (var i = 0; i < 12; i++) 500 + random.nextDouble() * 900
    ];
    final axis = PdfLayoutZoomAxis(
      slotCount: extents.length,
      unitExtentOf: (i) => extents[i],
      spacing: 12,
      crossView: crossView,
    );
    double startAt(int slot, double zoom) {
      var start = 0.0;
      for (var i = 0; i < slot; i++) {
        start += extents[i] * zoom + axis.spacing;
      }
      return start;
    }

    test('a point keeps its fraction into its page', () {
      for (var trial = 0; trial < 200; trial++) {
        final from = 0.2 + random.nextDouble() * 0.8;
        final to = 0.2 + random.nextDouble() * 0.8;
        final slot = random.nextInt(extents.length);
        final fraction = random.nextDouble();
        final main = startAt(slot, from) + fraction * extents[slot] * from;
        final mapped = axis.remapMain(main, from, to);
        expect(mapped,
            closeTo(startAt(slot, to) + fraction * extents[slot] * to, 1e-6),
            reason: 'trial $trial');
        expect(axis.remapMain(mapped, to, from), closeTo(main, 1e-6),
            reason: 'round trip, trial $trial');
      }
    });

    test('the spacing does not scale', () {
      // the start of page 10 moves by the pages' growth alone
      final main = startAt(10, 0.5);
      expect(axis.remapMain(main, 0.5, 1), closeTo(startAt(10, 1), 1e-9));
      expect(main * 2, isNot(closeTo(startAt(10, 1), 1)),
          reason: 'a plain ratio would drift a gap per page');
    });

    test('the cross axis scales about the view centre', () {
      expect(axis.remapCross(crossView / 2, 0.5, 1), crossView / 2);
      expect(axis.remapCross(crossView / 2 + 40, 0.5, 1), crossView / 2 + 80);
      expect(axis.remapCross(axis.remapCross(123, 0.4, 0.9), 0.9, 0.4),
          closeTo(123, 1e-9));
    });

    test('the scroll keeps the content at the anchor', () {
      for (var trial = 0; trial < 100; trial++) {
        final from = 0.3 + random.nextDouble() * 0.7;
        final to = 0.3 + random.nextDouble() * 0.7;
        final content = startAt(4, from) + random.nextDouble() * 3000;
        final anchor = random.nextDouble() * mainView;
        final scroll =
            axis.scrollKeeping(content, from: from, to: to, anchor: anchor);
        expect(
            axis.remapMain(content, from, to) - scroll, closeTo(anchor, 1e-6),
            reason: 'trial $trial');
      }
      expect(axis.scrollKeeping(10, from: 1, to: 0.5, anchor: 300), 0,
          reason: 'never before the start of the list');
    });
  });
  group('the frame as one value', () {
    test('the effective zoom combines layout zoom and transform', () {
      expect(const PdfViewportFrame(scroll: 0, layoutZoom: 0.5).zoom, 0.5);
      expect(const PdfViewportFrame(scroll: 0, scale: 3).zoom, 3);
      // within 1% of the identity the transform defers to the layout
      expect(
          const PdfViewportFrame(scroll: 0, scale: 1.005, layoutZoom: 0.5).zoom,
          0.5);
      // a sub-fit transform mid-gesture combines with it
      expect(
          const PdfViewportFrame(scroll: 0, scale: 0.5, layoutZoom: 0.8).zoom,
          closeTo(0.4, 1e-12));
      expect(const PdfViewportFrame(scroll: 0, scale: 1.02).zoomed, isTrue);
      expect(const PdfViewportFrame(scroll: 0, scale: 1.01).zoomed, isFalse);
    });

    test('zoom splits into exactly one regime', () {
      const limits = (minZoom: 0.25, maxZoom: 8.0);
      for (final (zoom, parts) in [
        (0.5, (0.5, 1.0)),
        (0.1, (0.25, 1.0)),
        (1.0, (1.0, 1.0)),
        (3.0, (1.0, 3.0)),
        (20.0, (1.0, 8.0)),
      ]) {
        expect(
            PdfViewportFrame.zoomParts(zoom,
                minZoom: limits.minZoom, maxZoom: limits.maxZoom),
            parts,
            reason: 'zoom $zoom');
      }
    });

    test('capture o place is the identity across layout zooms', () {
      final random = math.Random(23);
      for (var trial = 0; trial < 200; trial++) {
        final unit = [
          for (var i = 0; i < 6; i++)
            (400 + random.nextDouble() * 600, 300 + random.nextDouble() * 200),
        ];
        final zoom = 0.3 + random.nextDouble() * 0.7;
        final (layoutZoom, scale) =
            PdfViewportFrame.zoomParts(zoom, minZoom: 0.1, maxZoom: 8);
        // the list laid out at the layout zoom
        final layout = _Column([
          for (final (main, cross) in unit)
            (main * layoutZoom, cross * layoutZoom)
        ], crossView: crossView);
        final page = 1 + random.nextInt(3);
        final viewport =
            PdfViewport(page: page, top: random.nextDouble() * 0.9, zoom: zoom);
        final frame = placePdfViewport(viewport, page, layout,
            scale: scale,
            layoutZoom: layoutZoom,
            mainView: mainView,
            crossView: crossView,
            maxScroll: layout.total);
        expect(frame.layoutZoom, layoutZoom);
        final captured = capturePdfViewport(frame, layout);
        expect(captured.page, page, reason: 'trial $trial');
        expect(captured.top, closeTo(viewport.top, 1e-9),
            reason: 'trial $trial');
        expect(captured.zoom, closeTo(zoom, 1e-12), reason: 'trial $trial');
      }
    });
  });

  group('zoom across the fit boundary', () {
    final random = math.Random(31);
    final extents = [
      for (var i = 0; i < 12; i++) 500 + random.nextDouble() * 900
    ];
    final axis = PdfLayoutZoomAxis(
      slotCount: extents.length,
      unitExtentOf: (i) => extents[i],
      spacing: 12,
      crossView: crossView,
    );

    test('the content under the pointer stays under it', () {
      for (var trial = 0; trial < 300; trial++) {
        // anywhere from well below fit to well above it, both ways
        double pick() => random.nextBool()
            ? 0.3 + random.nextDouble() * 0.7
            : 1.5 + random.nextDouble() * 4;
        final fromZoom = pick();
        final toZoom = pick();
        final (layoutZoom, scale) =
            PdfViewportFrame.zoomParts(fromZoom, minZoom: 0.1, maxZoom: 8);
        // deep in the document, with a centred transform, keeps every
        // scroll and translation clear of its clamp
        final before = PdfViewportFrame(
          scroll: 4000 + random.nextDouble() * 2000,
          scale: scale,
          mainTranslate: mainView * (1 - scale) / 2,
          crossTranslate: crossView * (1 - scale) / 2,
          layoutZoom: layoutZoom,
        );
        final atMain = mainView * (0.4 + random.nextDouble() * 0.2);
        final atCross = crossView * (0.45 + random.nextDouble() * 0.1);
        final listMain = before.listMainAt(atMain);
        final listCross = before.listCrossAt(atCross);
        final after = before.zoomedTo(toZoom,
            listMain: listMain,
            listCross: listCross,
            axis: axis,
            mainView: mainView,
            crossView: crossView);
        expect(after.zoom, closeTo(toZoom, 1e-9), reason: 'trial $trial');
        expect(after.layoutZoom, toZoom <= 1 ? toZoom : 1.0);
        expect(after.scale, toZoom <= 1 ? 1.0 : toZoom);
        // where the relayout put that content
        final main = axis.remapMain(listMain, layoutZoom, after.layoutZoom);
        final cross = axis.remapCross(listCross, layoutZoom, after.layoutZoom);
        expect(after.viewMainOf(main), closeTo(atMain, 1e-6),
            reason: 'trial $trial: $fromZoom -> $toZoom');
        if (toZoom > 1) {
          // below fit the layout centres the pages; there is no cross pan
          expect(after.viewCrossOf(cross), closeTo(atCross, 1e-6),
              reason: 'trial $trial: $fromZoom -> $toZoom');
        }
      }
    });

    test('zooming to fit drops the transform but not a gesture in flight', () {
      const zoomedIn = PdfViewportFrame(
          scroll: 900, scale: 3, mainTranslate: -400, crossTranslate: -300);
      expect(
          zoomedIn.zoomedTo(1,
              listMain: 1000,
              listCross: 200,
              axis: axis,
              mainView: mainView,
              crossView: crossView),
          const PdfViewportFrame(scroll: 900));
      const pinching = PdfViewportFrame(
          scroll: 900, scale: 0.8, mainTranslate: 70, crossTranslate: 50);
      final out = pinching.zoomedTo(0.6,
          listMain: 1000,
          listCross: 200,
          axis: axis,
          mainView: mainView,
          crossView: crossView);
      expect(out.sameTransformAs(pinching), isTrue,
          reason: 'its settle folds it');
      expect(out.layoutZoom, 0.6);
    });

    group('a settled gesture', () {
      test('at or below fit becomes layout zoom about the centre', () {
        for (var trial = 0; trial < 100; trial++) {
          final layoutZoom = 0.4 + random.nextDouble() * 0.6;
          final scale = 0.5 + random.nextDouble() * (1 / layoutZoom - 0.5);
          final before = PdfViewportFrame(
            scroll: 3000 + random.nextDouble() * 3000,
            scale: scale,
            mainTranslate: mainView * (1 - scale) / 2,
            crossTranslate: crossView * (1 - scale) / 2,
            layoutZoom: layoutZoom,
          );
          final centre = before.listMainAt(mainView / 2);
          final after = before.settled(
              axis: axis,
              mainView: mainView,
              crossView: crossView,
              minZoom: 0.1);
          expect(after.scale, 1);
          expect(after.layoutZoom, closeTo(scale * layoutZoom, 1e-12));
          expect(
              after.viewMainOf(
                  axis.remapMain(centre, layoutZoom, after.layoutZoom)),
              closeTo(mainView / 2, 1e-6),
              reason: 'trial $trial');
        }
      });

      test('above fit folds the layout zoom into the transform', () {
        for (var trial = 0; trial < 100; trial++) {
          final layoutZoom = 0.4 + random.nextDouble() * 0.5;
          // a total of 1.5-4x
          final scale = (1.5 + random.nextDouble() * 2.5) / layoutZoom;
          final before = PdfViewportFrame(
            scroll: 3000 + random.nextDouble() * 3000,
            scale: scale,
            mainTranslate: mainView * (1 - scale) / 2,
            crossTranslate: crossView * (1 - scale) / 2,
            layoutZoom: layoutZoom,
          );
          final atCross = crossView * (0.3 + random.nextDouble() * 0.4);
          final cross = before.listCrossAt(atCross);
          final centre = before.listMainAt(mainView / 2);
          final after = before.settled(
              axis: axis,
              mainView: mainView,
              crossView: crossView,
              minZoom: 0.1);
          expect(after.layoutZoom, 1);
          expect(after.scale, closeTo(scale * layoutZoom, 1e-9));
          expect(after.viewMainOf(axis.remapMain(centre, layoutZoom, 1)),
              closeTo(mainView / 2, 1e-6),
              reason: 'trial $trial');
          // every cross point stays put: the relayout and the fold scale
          // about the same centre
          expect(after.viewCrossOf(axis.remapCross(cross, layoutZoom, 1)),
              closeTo(atCross, 1e-6),
              reason: 'trial $trial');
        }
      });

      test('at fit clamps only the main axis', () {
        const before = PdfViewportFrame(
            scroll: 500, scale: 2, mainTranslate: 80, crossTranslate: 120);
        expect(
            before.settled(
                axis: axis,
                mainView: mainView,
                crossView: crossView,
                minZoom: 0.1),
            const PdfViewportFrame(
                scroll: 500, scale: 2, mainTranslate: 0, crossTranslate: 120));
      });
    });
  });
}
