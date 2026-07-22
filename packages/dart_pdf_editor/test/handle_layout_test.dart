import 'dart:math' as math;
import 'dart:ui';

import 'package:dart_pdf_editor/src/editing/handle_layout.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // A 100x60 selection box centered at (150, 130): left 100, top 100.
  const rect = Rect.fromLTWH(100, 100, 100, 60);

  group('handleCenter', () {
    test('corners and edges sit on the box, from its center', () {
      const layout = HandleLayout(rect: rect);
      expect(layout.handleCenter((dx: -1, dy: -1)), const Offset(100, 100));
      expect(layout.handleCenter((dx: 1, dy: 1)), const Offset(200, 160));
      expect(layout.handleCenter((dx: 0, dy: -1)), const Offset(150, 100));
      expect(layout.handleCenter((dx: 1, dy: 0)), const Offset(200, 130));
    });

    test('there are eight distinct handles', () {
      final centers = {
        for (final h in selectionHandles) const HandleLayout(rect: rect).handleCenter(h),
      };
      expect(centers.length, 8);
    });
  });

  group('handleAt', () {
    test('a pointer on a corner hits that corner', () {
      const layout = HandleLayout(rect: rect);
      expect(layout.handleAt(const Offset(100, 100)), (dx: -1, dy: -1));
      expect(layout.handleAt(const Offset(200, 160)), (dx: 1, dy: 1));
    });

    test('within the hit radius still hits; just outside misses', () {
      const layout = HandleLayout(rect: rect, hitRadius: 12);
      // 11px off the top-left corner -> inside the 12px radius
      expect(layout.handleAt(const Offset(100 + 11, 100)), (dx: -1, dy: -1));
      // 13px off -> outside, and far from every other handle
      expect(layout.handleAt(const Offset(100 + 13, 100)), isNull);
    });

    test('the hit radius scales with chromeScale', () {
      const zoomedIn = HandleLayout(rect: rect, hitRadius: 12, chromeScale: 0.5);
      // 8px away is inside 12px at 1x but outside the 6px radius at 0.5x
      expect(zoomedIn.handleAt(const Offset(108, 100)), isNull);
      const oneX = HandleLayout(rect: rect, hitRadius: 12);
      expect(oneX.handleAt(const Offset(108, 100)), (dx: -1, dy: -1));
    });

    test('a pointer in open space hits nothing', () {
      const layout = HandleLayout(rect: rect);
      expect(layout.handleAt(const Offset(150, 130)), isNull); // box center
    });
  });

  group('rotate knob', () {
    test('floats above the top edge when unrotated', () {
      const layout = HandleLayout(rect: rect, rotateHandleDistance: 22);
      expect(layout.rotateHandleCenter, const Offset(150, 100 - 22));
    });

    test('the distance scales with chromeScale', () {
      const layout = HandleLayout(
          rect: rect, rotateHandleDistance: 22, chromeScale: 2);
      expect(layout.rotateHandleCenter, const Offset(150, 100 - 44));
    });

    test('spins about the box center with the resting rotation', () {
      // 90° CCW-in-screen (y-down): the knob above center swings to the right.
      final layout = HandleLayout(
          rect: rect, rotation: math.pi / 2, rotateHandleDistance: 22);
      final knob = layout.rotateHandleCenter;
      // center (150,130); unrotated knob (150, 78) is 52 above center.
      // rotating (0,-52) by +pi/2 -> (52, 0): (202, 130).
      expect(knob.dx, closeTo(202, 1e-9));
      expect(knob.dy, closeTo(130, 1e-9));
    });

    test('hitsRotateHandle is true on the knob, false at the top edge', () {
      const layout = HandleLayout(rect: rect, rotateHandleDistance: 22);
      expect(layout.hitsRotateHandle(const Offset(150, 78)), isTrue);
      expect(layout.hitsRotateHandle(const Offset(150, 100)), isFalse);
    });
  });

  group('toLocal / rotatePoint', () {
    test('toLocal undoes the resting rotation about the center', () {
      final layout = HandleLayout(rect: rect, rotation: 0.7);
      // a point placed by rotating the top-left corner forward maps back to it
      final rotatedCorner =
          HandleLayout.rotatePoint(const Offset(100, 100), rect.center, 0.7);
      final local = layout.toLocal(rotatedCorner);
      expect(local.dx, closeTo(100, 1e-9));
      expect(local.dy, closeTo(100, 1e-9));
      // and a rotated selection then hit-tests its axis-aligned corner
      expect(layout.handleAt(local), (dx: -1, dy: -1));
    });

    test('rotatePoint by zero is the identity', () {
      expect(HandleLayout.rotatePoint(const Offset(5, 9), Offset.zero, 0),
          const Offset(5, 9));
    });
  });
}
