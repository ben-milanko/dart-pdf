// Flutter 3.50 web engine (#1275): the vertex-index range check it now
// enforces on every backend.
import 'package:dart_pdf_editor/src/vertex_indices.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
