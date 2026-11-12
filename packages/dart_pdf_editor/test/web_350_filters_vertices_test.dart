// Flutter 3.50 web-engine adaptations (#1274, #1275): interned colour
// filters and the vertex-index range check the engine now enforces.
import 'dart:ui';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:dart_pdf_editor/src/vertex_indices.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('interned colour filters (#1274)', () {
    test('a stencil colour maps to one filter instance', () {
      const red = Color(0xFFFF0000);
      final a = CanvasPdfDevice.debugStencilFilter(red);
      expect(identical(a, CanvasPdfDevice.debugStencilFilter(red)), isTrue);
      expect(a, const ColorFilter.mode(red, BlendMode.srcIn));
      expect(
          identical(
              a, CanvasPdfDevice.debugStencilFilter(const Color(0x80FF0000))),
          isFalse,
          reason: 'alpha is part of the key');
    });

    test('a soft-mask transfer maps to one filter instance', () {
      final a = CanvasPdfDevice.debugTransferFilter(true, 0.5, 0.25);
      expect(identical(a, CanvasPdfDevice.debugTransferFilter(true, 0.5, 0.25)),
          isTrue);
      expect(
          identical(a, CanvasPdfDevice.debugTransferFilter(false, 0.5, 0.25)),
          isFalse);
    });

    test('the cache stays bounded and still answers after eviction', () {
      final first = CanvasPdfDevice.debugStencilFilter(const Color(0xFF000001));
      for (var i = 2; i < 200; i++) {
        CanvasPdfDevice.debugStencilFilter(Color(0xFF000000 | i));
      }
      final again = CanvasPdfDevice.debugStencilFilter(const Color(0xFF000001));
      expect(again, first, reason: 'equal value after eviction');
    });
  });

  group('pdfVertexIndicesInRange (#1275)', () {
    test('accepts indices below the vertex count', () {
      expect(pdfVertexIndicesInRange(const [0, 1, 2, 2, 1, 3], 4), isTrue);
      expect(pdfVertexIndicesInRange(const <int>[], 0), isTrue);
    });

    test('rejects an index at or past the vertex count', () {
      // 3.47 CanvasKit accepted [count, 2*count); 3.50 throws on it.
      expect(pdfVertexIndicesInRange(const [0, 1, 4], 4), isFalse);
      expect(pdfVertexIndicesInRange(const [0, 1, 7], 4), isFalse);
      expect(pdfVertexIndicesInRange(const [-1, 0, 1], 4), isFalse);
    });
  });
}
