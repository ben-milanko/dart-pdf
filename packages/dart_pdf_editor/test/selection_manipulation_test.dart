// Selection manipulation without a widget: grab a handle at a view point,
// drag it to another, and check that the preview the drag paints is what the
// commit leaves - on every page /Rotate, rotated annotations included.

import 'dart:math' as math;

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:dart_pdf_editor/src/editing/handle_layout.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';

const _rotations = [0, 90, 180, 270];

PdfPageGeometry _geometry(PdfEditingController editing, [int page = 0]) {
  final p = editing.pageAt(page);
  final box = p.cropBox;
  const scale = 1.5;
  final sideways = p.rotation == 90 || p.rotation == 270;
  return PdfPageGeometry(
    cropBox: box,
    rotation: p.rotation,
    viewSize: sideways
        ? Size(box.height * scale, box.width * scale)
        : Size(box.width * scale, box.height * scale),
  );
}

/// The selected annotation's chrome frame as the overlay draws it.
(Rect, double) _frame(PdfEditingController editing, PdfPageGeometry geometry) {
  final annotation = editing.selectedAnnotation!;
  final quad = annotation.appearanceQuad;
  return pdfSelectionFrame(
    geometry.toViewRect(annotation.calloutBox ?? annotation.rect),
    quad: quad == null
        ? null
        : [for (final (x, y) in quad) geometry.toViewOffset(x, y)],
    rotation: annotation.appearanceRotation,
  );
}

/// Where [handle] sits on [frame], view space.
Offset _handlePoint((Rect, double) frame, SelectionHandle handle) {
  final (rect, angle) = frame;
  final local = rect.center +
      Offset(handle.dx * rect.width / 2, handle.dy * rect.height / 2);
  return HandleLayout.rotatePoint(local, rect.center, angle);
}

/// [rect] spun by [angle] about its center, as the chrome paints it.
List<Offset> _corners(Rect rect, double angle) => [
      for (final c in [
        rect.topLeft,
        rect.topRight,
        rect.bottomRight,
        rect.bottomLeft
      ])
        HandleLayout.rotatePoint(c, rect.center, angle),
    ];

/// The same four corners, in any order (a frame can name its box from a
/// different edge and still paint the same rectangle).
Matcher _sameCorners(List<Offset> expected) => predicate<List<Offset>>(
    (actual) => expected.every((e) => actual.any((a) => (a - e).distance < 1)),
    'the corners $expected');

Matcher _rectNear(Rect expected, [double tolerance = 0.75]) => isA<Rect>()
    .having((r) => r.left, 'left', closeTo(expected.left, tolerance))
    .having((r) => r.top, 'top', closeTo(expected.top, tolerance))
    .having((r) => r.right, 'right', closeTo(expected.right, tolerance))
    .having((r) => r.bottom, 'bottom', closeTo(expected.bottom, tolerance));

Matcher _pointNear(Offset expected, [double tolerance = 0.5]) => isA<Offset>()
    .having((p) => p.dx, 'dx', closeTo(expected.dx, tolerance))
    .having((p) => p.dy, 'dy', closeTo(expected.dy, tolerance));

PdfEditingController _withRectangle(int rotation, {double angle = 0}) {
  final editing = PdfEditingController(buildMultiPagePdf(1, rotation: rotation))
    ..addRectangle(0, const PdfRect(200, 300, 320, 380));
  expect(editing.selectAnnotation(0, 0), isTrue);
  if (angle != 0) editing.rotateSelected(angle);
  return editing;
}

void main() {
  group('resize: preview == committed', () {
    for (final rotation in _rotations) {
      for (final angle in [0.0, 30.0]) {
        for (final handle in const [
          (dx: 1, dy: 1),
          (dx: -1, dy: 0),
          (dx: 0, dy: -1),
        ]) {
          test('/Rotate $rotation, annotation at $angle°, handle $handle', () {
            final editing = _withRectangle(rotation, angle: angle);
            final geometry = _geometry(editing);
            final frame = _frame(editing, geometry);
            final p = _handlePoint(frame, handle);
            final drag = PdfResizeDrag(handle, frame.$1, p, angle: frame.$2);
            drag.update(p + const Offset(30, 24));

            editing.applySelectionEdit(drag.commit(geometry));

            final after = _frame(editing, geometry);
            expect(after.$1, _rectNear(drag.rect));
            expect(after.$2, closeTo(frame.$2, 1e-6));
          });
        }
      }
    }
  });

  group('move: preview == committed', () {
    for (final rotation in _rotations) {
      test('/Rotate $rotation', () {
        final editing = _withRectangle(rotation);
        final geometry = _geometry(editing);
        final before = _frame(editing, geometry).$1;
        final drag = PdfMoveDrag(before.center)
          ..current = before.center + const Offset(-40, 55);

        editing.applySelectionEdit(
            drag.commit(geometry, page: 0) ?? (throw 'a click'));

        expect(
            _frame(editing, geometry).$1, _rectNear(before.shift(drag.delta)));
      });
    }

    test('a drop over another page re-homes, a short drag is a click', () {
      final editing = _withRectangle(0);
      final geometry = _geometry(editing);
      final drag = PdfMoveDrag(const Offset(10, 10))
        ..current = const Offset(11, 10);
      expect(drag.commit(geometry, page: 0), isNull);
      drag.current = const Offset(100, 10);
      final start = geometry.toPagePoint(const Offset(10, 10));
      expect(drag.commit(geometry, page: 0, drop: (1, 50, 60)),
          PdfRehomeEdit(1, 50 - start.$1, 60 - start.$2));
      expect(
          drag.commit(geometry, page: 0, drop: (1, 50, 60), canRehome: false),
          isA<PdfMoveEdit>());
    });
  });

  group('rotate: preview == committed', () {
    for (final rotation in _rotations) {
      test('/Rotate $rotation', () {
        final editing = _withRectangle(rotation);
        final geometry = _geometry(editing);
        final frame = _frame(editing, geometry);
        final center = frame.$1.center;
        final drag = PdfRotateDrag(center + const Offset(0, -60), center);
        // a quarter-ish turn clockwise on screen
        drag.update(center + Offset(60 * math.cos(-0.6), 60 * math.sin(-0.6)));
        expect(drag.delta, isNot(0));

        editing.applySelectionEdit(drag.commit());

        // the painted box: the resting frame spun by the drag
        final preview = _corners(frame.$1, frame.$2 + drag.delta);
        final after = _frame(editing, geometry);
        expect(_corners(after.$1, after.$2), _sameCorners(preview));
      });
    }

    test('the total snaps to 45° near a multiple', () {
      final drag = PdfRotateDrag(const Offset(0, -10), Offset.zero);
      drag.update(Offset(10 * math.cos(-math.pi / 4 + 0.02),
          10 * math.sin(-math.pi / 4 + 0.02)));
      expect(drag.delta, closeTo(math.pi / 4, 1e-9));
    });
  });

  group('reshape: the handle names its target', () {
    test('a callout exposes a terminus and a base per leader', () {
      final editing = PdfEditingController(buildMultiPagePdf(1))
        ..addCallout(0, const PdfRect(300, 500, 420, 540), 'Note', (150, 650));
      expect(editing.selectAnnotation(0, 0), isTrue);
      expect(editing.addSelectedCalloutLeader((450, 650)), isTrue);
      final handles = pdfReshapeHandlesOf(editing.selectedAnnotation!)!;
      expect([
        for (final h in handles)
          (
            h.runtimeType,
            h is PdfCalloutTerminusHandle
                ? h.leader
                : (h as PdfCalloutBaseHandle).leader
          )
      ], [
        (PdfCalloutTerminusHandle, 0),
        (PdfCalloutBaseHandle, 0),
        (PdfCalloutTerminusHandle, 1),
        (PdfCalloutBaseHandle, 1),
      ]);
      final pairs = pdfCalloutLeaderPairs(
          handles, [for (var i = 0; i < 4; i++) Offset(i.toDouble(), 0)]);
      expect(pairs, [
        (const Offset(0, 0), const Offset(1, 0)),
        (const Offset(2, 0), const Offset(3, 0)),
      ]);
    });

    for (final rotation in _rotations) {
      test(
          'dragging a callout terminus lands where it was dropped, '
          '/Rotate $rotation', () {
        final editing =
            PdfEditingController(buildMultiPagePdf(1, rotation: rotation))
              ..addCallout(
                  0, const PdfRect(300, 500, 420, 540), 'Note', (150, 650));
        expect(editing.selectAnnotation(0, 0), isTrue);
        expect(editing.addSelectedCalloutLeader((450, 650)), isTrue);
        final geometry = _geometry(editing);
        final handles = pdfReshapeHandlesOf(editing.selectedAnnotation!)!;
        final points = [
          for (final h in handles) geometry.toViewOffset(h.point.$1, h.point.$2)
        ];
        // the second leader's terminus
        final drag = PdfReshapeDrag(handles, 2, points)
          ..update(points[2] + const Offset(25, -35));

        editing.applySelectionEdit(drag.commit(geometry));

        final after = pdfReshapeHandlesOf(editing.selectedAnnotation!)!;
        final tip = after[2];
        expect(tip, isA<PdfCalloutTerminusHandle>());
        expect(geometry.toViewOffset(tip.point.$1, tip.point.$2),
            _pointNear(drag.points[2]));
        // the other leader did not move
        expect(after[0].point.$1, closeTo(handles[0].point.$1, 1e-6));
        expect(after[0].point.$2, closeTo(handles[0].point.$2, 1e-6));
      });

      test(
          'dragging a line endpoint lands where it was dropped, '
          '/Rotate $rotation', () {
        final editing =
            PdfEditingController(buildMultiPagePdf(1, rotation: rotation))
              ..addLine(0, (100, 100), (300, 200));
        expect(editing.selectAnnotation(0, 0), isTrue);
        final geometry = _geometry(editing);
        final handles = pdfReshapeHandlesOf(editing.selectedAnnotation!)!;
        expect(handles, everyElement(isA<PdfLineVertexHandle>()));
        final points = [
          for (final h in handles) geometry.toViewOffset(h.point.$1, h.point.$2)
        ];
        final drag = PdfReshapeDrag(handles, 1, points)
          ..update(points[1] + const Offset(-50, 15));

        editing.applySelectionEdit(drag.commit(geometry));

        final line = editing.selectedAnnotation!.line!;
        expect(geometry.toViewOffset(line.$2.$1, line.$2.$2),
            _pointNear(drag.points[1]));
      });
    }
  });

  group('content-element move: the preview is tethered like the commit', () {
    const box = PdfRect(0, 0, 612, 792);
    const bounds = PdfRect(500, 700, 580, 720);
    for (final rotation in _rotations) {
      test('/Rotate $rotation', () {
        final sideways = rotation == 90 || rotation == 270;
        final geometry = PdfPageGeometry(
            cropBox: box,
            rotation: rotation,
            viewSize: sideways ? const Size(792, 612) : const Size(612, 792));
        final start = geometry.toViewOffset(540, 710);
        final drag = PdfElementMoveDrag(start, bounds: bounds, cropBox: box)
          ..current = start + const Offset(900, -900);
        final edit = drag.commit(geometry, page: 0)! as PdfElementMoveEdit;
        // a strip of the drawing stays on the paper
        final moved = PdfRect(bounds.left + edit.dx, bounds.bottom + edit.dy,
            bounds.right + edit.dx, bounds.top + edit.dy);
        expect(moved.right > box.left && moved.left < box.right, isTrue);
        expect(moved.top > box.bottom && moved.bottom < box.top, isTrue);
        // and the preview paints exactly that displacement
        final preview = drag.previewDelta(geometry, page: 0);
        final (x0, y0) = geometry.toPagePoint(start);
        expect(start + preview,
            _pointNear(geometry.toViewOffset(x0 + edit.dx, y0 + edit.dy)));
      });
    }

    test('aimed at another page, it follows the pointer and re-homes', () {
      const geometry =
          PdfPageGeometry(cropBox: box, rotation: 0, viewSize: Size(612, 792));
      final drag = PdfElementMoveDrag(const Offset(540, 80),
          bounds: bounds, cropBox: box)
        ..current = const Offset(540, 900)
        ..drop = (1, 540, 700);
      expect(drag.previewDelta(geometry, page: 0), const Offset(0, 820));
      expect(drag.commit(geometry, page: 0), isA<PdfElementRehomeEdit>());
    });
  });

  test('a view delta maps to page space like the geometry does', () {
    for (final rotation in _rotations) {
      final geometry = PdfPageGeometry(
          cropBox: const PdfRect(0, 0, 612, 792),
          rotation: rotation,
          viewSize: rotation == 90 || rotation == 270
              ? const Size(792, 612)
              : const Size(612, 792));
      final a = geometry.toPagePoint(const Offset(100, 100));
      final b = geometry.toPagePoint(const Offset(107, 95));
      expect(pdfViewDeltaToPage(rotation, 7, -5),
          (closeTo(b.$1 - a.$1, 1e-9), closeTo(b.$2 - a.$2, 1e-9)).matcher);
    }
  });
}

extension on (Matcher, Matcher) {
  Matcher get matcher => isA<(double, double)>()
      .having((r) => r.$1, 'x', $1)
      .having((r) => r.$2, 'y', $2);
}
