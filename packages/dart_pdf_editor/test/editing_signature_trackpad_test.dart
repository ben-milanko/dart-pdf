// Preview-style trackpad signatures: the host streams absolute finger
// positions (PdfTrackpadSignatureCapture) and the pad maps the trackpad
// surface onto itself. The macOS capture itself lives in the app runner;
// these tests drive the pad with a fake one.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';

class _FakeTrackpad implements PdfTrackpadSignatureCapture {
  StreamController<PdfTrackpadSignatureEvent>? controller;
  var cancelled = 0;

  @override
  Stream<PdfTrackpadSignatureEvent> capture() {
    final controller = StreamController<PdfTrackpadSignatureEvent>(
        onCancel: () => cancelled++);
    this.controller = controller;
    return controller.stream;
  }

  void touch(PdfTrackpadSignaturePhase phase, double x, double y) =>
      controller!.add(PdfTrackpadSignatureEvent(phase, x: x, y: y));
}

void main() {
  const trackpadButton = ValueKey('pdf-signature-trackpad');
  const hint = ValueKey('pdf-signature-trackpad-hint');

  testWidgets('no capture, no trackpad button', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: PdfSignatureDialog()),
    ));
    expect(find.byKey(trackpadButton), findsNothing);
  });

  testWidgets('draws strokes from trackpad touches until finished',
      (tester) async {
    final trackpad = _FakeTrackpad();
    PdfInkSignature? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Center(
          child: FilledButton(
            onPressed: () async {
              result =
                  await showPdfSignatureDialog(context, trackpad: trackpad);
            },
            child: const Text('sign'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('sign'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(trackpadButton));
    await tester.pump();
    expect(trackpad.controller, isNotNull);
    expect(find.byKey(hint), findsOneWidget);

    // two strokes: a diagonal across the surface, then a short tick
    trackpad.touch(PdfTrackpadSignaturePhase.down, 0.1, 0.2);
    trackpad.touch(PdfTrackpadSignaturePhase.move, 0.3, 0.4);
    trackpad.touch(PdfTrackpadSignaturePhase.up, 0.5, 0.6);
    trackpad.touch(PdfTrackpadSignaturePhase.down, 0.9, 0.2);
    trackpad.touch(PdfTrackpadSignaturePhase.up, 0.9, 0.6);
    trackpad.controller!
        .add(const PdfTrackpadSignatureEvent(PdfTrackpadSignaturePhase.finish));
    await tester.pump();
    expect(find.byKey(hint), findsNothing);
    expect(trackpad.cancelled, 1);

    await tester.tap(find.widgetWithText(FilledButton, 'Done'));
    await tester.pumpAndSettle();
    final signature = result!;
    expect(signature.strokes, hasLength(2));
    expect(signature.strokes[0], hasLength(3));
    expect(signature.strokes[1], hasLength(2));
    expect(signature.pressures, [null, null]);
    // the bounding box spans x 0.1-0.9 of the surface and y 0.2-0.6, and the
    // surface maps onto the 2:1 pad
    expect(signature.aspect, closeTo((0.8 * 360) / (0.4 * 180), 1e-9));
    expect(signature.strokes[0].first, (0.0, 0.0));
    expect(signature.strokes[0][1].$1, closeTo(0.25, 1e-9));
    expect(signature.strokes[1].last, (1.0, 1.0));
  });

  testWidgets('closing the pad mid-capture releases the trackpad',
      (tester) async {
    final trackpad = _FakeTrackpad();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: PdfSignatureDialog(trackpad: trackpad)),
    ));
    await tester.tap(find.byKey(trackpadButton));
    await tester.pump();
    trackpad.touch(PdfTrackpadSignaturePhase.down, 0.5, 0.5);
    await tester.pump();

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    expect(trackpad.cancelled, 1);
  });

  testWidgets('a capture the host ends on its own stops the mode',
      (tester) async {
    final trackpad = _FakeTrackpad();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: PdfSignatureDialog(trackpad: trackpad)),
    ));
    await tester.tap(find.byKey(trackpadButton));
    await tester.pump();
    trackpad.touch(PdfTrackpadSignaturePhase.down, 0.2, 0.2);
    trackpad.touch(PdfTrackpadSignaturePhase.move, 0.6, 0.7);
    await trackpad.controller!.close();
    await tester.pump();
    expect(find.byKey(hint), findsNothing);
    // the half-drawn stroke is kept, so Done is live
    final done =
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Done'));
    expect(done.onPressed, isNotNull);
  });
}
