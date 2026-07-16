import 'dart:ui' as ui;

import 'package:dart_pdf_editor/src/mouse_cursor.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('every cursor kind paints visible vector artwork', (
    tester,
  ) async {
    for (final kind in PdfMouseCursorKind.values) {
      final paintedPixels = await tester.runAsync(() async {
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        paintPdfMouseCursor(canvas, const Offset(24, 24), kind);
        final picture = recorder.endRecording();
        final image = await picture.toImage(56, 56);
        final bytes =
            await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        expect(bytes, isNotNull, reason: '$kind did not rasterize');
        var count = 0;
        for (var i = 3; i < bytes!.lengthInBytes; i += 4) {
          if (bytes.getUint8(i) != 0) count++;
        }
        image.dispose();
        picture.dispose();
        return count;
      });
      expect(
        paintedPixels,
        greaterThan(20),
        reason: '$kind produced no useful cursor artwork',
      );
    }
  });

  testWidgets('cursor region hides the native cursor and follows hover', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: SizedBox(
            width: 120,
            height: 80,
            child: PdfMouseCursorRegion(
              kind: PdfMouseCursorKind.resizeColumn,
              scale: 0.5,
              child: ColoredBox(color: Colors.white),
            ),
          ),
        ),
      ),
    );

    final gesture = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
      pointer: 19,
    );
    addTearDown(gesture.removePointer);
    await gesture.addPointer(location: const Offset(360, 280));
    await tester.pump();
    await gesture.moveTo(const Offset(410, 305));
    await tester.pump();

    final region = tester.widget<MouseRegion>(
      find.descendant(
        of: find.byType(PdfMouseCursorRegion),
        matching: find.byType(MouseRegion),
      ),
    );
    final paint = tester.widget<CustomPaint>(
      find.descendant(
        of: find.byType(PdfMouseCursorRegion),
        matching: find.byType(CustomPaint),
      ),
    );
    final painter = paint.foregroundPainter! as PdfMouseCursorPainter;
    expect(region.cursor, SystemMouseCursors.none);
    expect(painter.kind, PdfMouseCursorKind.resizeColumn);
    expect(painter.position, const Offset(70, 45));
    expect(painter.scale, 0.5);

    await gesture.moveTo(const Offset(10, 10));
    await tester.pump();
    final exited = tester
        .widget<CustomPaint>(
          find.descendant(
            of: find.byType(PdfMouseCursorRegion),
            matching: find.byType(CustomPaint),
          ),
        )
        .foregroundPainter! as PdfMouseCursorPainter;
    expect(exited.position, isNull);
  });
}
