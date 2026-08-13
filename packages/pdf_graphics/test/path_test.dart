import 'package:pdf_graphics/pdf_graphics.dart';
import 'package:test/test.dart';

void main() {
  test('packed path cursor and compatibility segments agree', () {
    final builder = PdfPathBuilder(verbCapacity: 1, coordinateCapacity: 2)
      ..moveTo(1, 2)
      ..lineTo(3, 4)
      ..cubicTo(5, 6, 7, 8, 9, 10)
      ..close();
    final path = builder.takePath();

    expect(path.segmentCount, 4);
    expect(path.isEmpty, isFalse);

    final cursor = path.cursor();
    expect(cursor.moveNext(), isTrue);
    expect((cursor.verb, cursor.x1, cursor.y1), (PdfPathVerb.moveTo, 1, 2));
    expect(cursor.moveNext(), isTrue);
    expect((cursor.verb, cursor.x1, cursor.y1), (PdfPathVerb.lineTo, 3, 4));
    expect(cursor.moveNext(), isTrue);
    expect(
      (
        cursor.verb,
        cursor.x1,
        cursor.y1,
        cursor.x2,
        cursor.y2,
        cursor.x3,
        cursor.y3
      ),
      (PdfPathVerb.cubicTo, 5, 6, 7, 8, 9, 10),
    );
    expect(cursor.moveNext(), isTrue);
    expect(cursor.verb, PdfPathVerb.close);
    expect(cursor.moveNext(), isFalse);

    expect(path.segments, hasLength(4));
    expect(path.segments[0], isA<PdfMoveTo>());
    expect((path.segments[0] as PdfMoveTo).x, 1);
    expect(path.segments[1], isA<PdfLineTo>());
    expect(path.segments[2], isA<PdfCubicTo>());
    expect(path.segments[3], isA<PdfClosePath>());
    expect(identical(path.segments, path.segments), isTrue);
  });

  test('takePath copies immutable storage and reuses the builder', () {
    final builder = PdfPathBuilder()..moveTo(1, 2);
    final first = builder.takePath();
    expect(builder.isEmpty, isTrue);

    builder
      ..moveTo(10, 20)
      ..lineTo(30, 40);
    final second = builder.takePath();

    final firstCursor = first.cursor()..moveNext();
    final secondCursor = second.cursor()..moveNext();
    expect((first.segmentCount, firstCursor.x1, firstCursor.y1), (1, 1, 2));
    expect(
        (second.segmentCount, secondCursor.x1, secondCursor.y1), (2, 10, 20));
  });

  test('ordinary const paths retain their supplied segment list', () {
    const segments = <PdfPathSegment>[
      PdfMoveTo(1, 2),
      PdfLineTo(3, 4),
    ];
    const path = PdfPath(segments);
    expect(identical(path.segments, segments), isTrue);
    expect(path.segmentCount, 2);
  });
}
