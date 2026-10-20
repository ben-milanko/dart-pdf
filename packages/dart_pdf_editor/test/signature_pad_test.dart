// PdfSignaturePad + PdfSignaturePadController on their own, outside the
// stock dialog: pointer drawing, the controller's stroke API, and trackpad
// capture through a fake source. Widgets-only host (no MaterialApp).

import 'dart:async';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeTrackpad extends PdfTrackpadSignatureCapture {
  final events = StreamController<PdfTrackpadSignatureEvent>();
  var listened = false;

  @override
  Stream<PdfTrackpadSignatureEvent> capture() {
    listened = true;
    return events.stream;
  }
}

void main() {
  Widget host(PdfSignaturePadController controller,
          {PdfTrackpadSignatureCapture? trackpad, Size? size}) =>
      WidgetsApp(
        color: const Color(0xFFFFFFFF),
        localizationsDelegates:
            DartPdfEditorLocalizations.localizationsDelegates,
        builder: (context, _) => Center(
          child: PdfSignaturePad(
            controller: controller,
            trackpad: trackpad,
            size: size ?? const Size(360, 180),
          ),
        ),
      );

  final pad = find.byKey(const ValueKey('pdf-signature-pad'));

  testWidgets('drawing on the pad fills the controller', (tester) async {
    final controller = PdfSignaturePadController();
    addTearDown(controller.dispose);
    var notified = 0;
    controller.addListener(() => notified++);
    await tester.pumpWidget(host(controller));
    expect(controller.isEmpty, isTrue);
    expect(controller.toSignature(), isNull);

    await tester.drag(pad, const Offset(120, 30));
    await tester.pump();
    expect(controller.isEmpty, isFalse);
    expect(controller.strokes, hasLength(1));
    expect(controller.activeStroke, isNull);
    expect(notified, greaterThan(0));
    final signature = controller.toSignature()!;
    expect(signature.strokes, hasLength(1));
    expect(signature.color, 0x000000);

    controller.clear();
    await tester.pump();
    expect(controller.isEmpty, isTrue);
  });

  testWidgets('the stroke API, ink and pen', (tester) async {
    final controller = PdfSignaturePadController(
        color: const Color(0xFF1A3E8C), strokeWidth: 999);
    addTearDown(controller.dispose);
    expect(controller.strokeWidth, PdfInkSignature.maxStrokeWidth);
    controller
      ..beginStroke(const Offset(10, 10), pressure: 0.5)
      ..addPoint(const Offset(20, 20))
      ..addPoint(const Offset(30, 10), pressure: 0.9);
    expect(controller.activeStroke, hasLength(3));
    // an open stroke still counts
    expect(controller.toSignature()!.strokes, hasLength(1));
    controller.endStroke();
    expect(controller.pressures.single, [0.5, 0.5, 0.9]);
    controller.strokeWidth = 2;
    final signature = controller.toSignature()!;
    expect(signature.color, 0x1A3E8C);
    expect(signature.strokeWidth, 2);
  });

  testWidgets('trackpad capture maps the trackpad onto the pad',
      (tester) async {
    final controller = PdfSignaturePadController();
    final trackpad = _FakeTrackpad();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
        host(controller, trackpad: trackpad, size: const Size(200, 100)));
    await tester.pump();
    expect(controller.trackpadAvailable, isTrue);
    expect(controller.trackpadActive, isFalse);

    controller.startTrackpad();
    await tester.pump();
    expect(trackpad.listened, isTrue);
    expect(controller.trackpadActive, isTrue);
    expect(find.byKey(const ValueKey('pdf-signature-trackpad-hint')),
        findsOneWidget);

    trackpad.events
      ..add(const PdfTrackpadSignatureEvent(PdfTrackpadSignaturePhase.down,
          x: 0, y: 0))
      ..add(const PdfTrackpadSignatureEvent(PdfTrackpadSignaturePhase.move,
          x: 0.5, y: 0.5))
      ..add(const PdfTrackpadSignatureEvent(PdfTrackpadSignaturePhase.up,
          x: 1, y: 1));
    await tester.pump();
    expect(controller.strokes.single,
        [Offset.zero, const Offset(100, 50), const Offset(200, 100)]);

    // any key finishes the capture
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(controller.trackpadActive, isFalse);
    expect(find.byKey(const ValueKey('pdf-signature-trackpad-hint')),
        findsNothing);
    unawaited(trackpad.events.close());
  });
}
