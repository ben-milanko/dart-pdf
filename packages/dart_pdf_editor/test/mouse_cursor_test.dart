import 'dart:ui' as ui;

import 'package:dart_pdf_editor/src/mouse_cursor.dart';
import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
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

    final region = tester.renderObject<RenderPdfMouseCursorRegion>(
      find.byType(PdfMouseCursorRegion),
    );
    expect(region.cursor, SystemMouseCursors.none);
    expect(region.kind, PdfMouseCursorKind.resizeColumn);
    expect(region.cursorPosition, const Offset(70, 45));
    expect(region.scale, 0.5);

    await gesture.moveTo(const Offset(10, 10));
    await tester.pump();
    expect(region.cursorPosition, isNull);
  });

  testWidgets('cursor motion only repaints and live configuration is applied',
      (tester) async {
    var builds = 0, enters = 0, hovers = 0, exits = 0;
    var kind = PdfMouseCursorKind.grab;
    var scale = 1.0;
    late StateSetter rebuild;
    final child = Builder(builder: (context) {
      builds++;
      return const ColoredBox(color: Colors.white);
    });
    await tester.pumpWidget(MaterialApp(
      home: Center(
        child: SizedBox(
          width: 120,
          height: 80,
          child: StatefulBuilder(builder: (context, setState) {
            rebuild = setState;
            return PdfMouseCursorRegion(
              kind: kind,
              scale: scale,
              onEnter: (_) => enters++,
              onHover: (_) => hovers++,
              onExit: (_) => exits++,
              child: child,
            );
          }),
        ),
      ),
    ));
    final region = tester.renderObject<RenderPdfMouseCursorRegion>(
      find.byType(PdfMouseCursorRegion),
    );
    final initialBuilds = builds;
    final gesture = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
      pointer: 20,
    );
    addTearDown(gesture.removePointer);
    await gesture.addPointer(location: const Offset(350, 270));
    await tester.pump();
    await gesture.moveTo(const Offset(360, 280));
    await tester.pump();
    expect(enters, 1);
    expect(hovers, greaterThan(0));
    expect(region.cursorPosition, const Offset(20, 20));

    await gesture.down(const Offset(360, 280));
    await gesture.moveTo(const Offset(410, 305));
    await tester.pump();
    expect(region.cursorPosition, const Offset(70, 45));
    expect(builds, initialBuilds, reason: 'pointer motion rebuilt the child');
    await gesture.up();

    rebuild(() {
      kind = PdfMouseCursorKind.grabbing;
      scale = 0.5;
    });
    await tester.pump();
    expect(
        tester.renderObject(find.byType(PdfMouseCursorRegion)), same(region));
    expect(region.kind, PdfMouseCursorKind.grabbing);
    expect(region.scale, 0.5);
    expect(region.cursorPosition, const Offset(70, 45));
    expect(builds, initialBuilds);

    await gesture.moveTo(const Offset(10, 10));
    await tester.pump();
    expect(exits, 1);
    expect(region.cursorPosition, isNull);
  });
}
