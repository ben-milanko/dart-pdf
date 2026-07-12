import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('pointer samples do not notify or allocate transition state', () {
    final session = PdfEditingInteractionSession();
    addTearDown(session.dispose);
    var notifications = 0;
    session.addListener(() => notifications++);

    session.begin(PdfEditingInteractionIntent.ink,
        pageIndex: 2, pointerKind: PointerDeviceKind.stylus);
    expect(notifications, 1);
    for (var i = 0; i < 10000; i++) {
      session.sample();
    }
    expect(notifications, 1, reason: 'pointer samples never notify');
    expect(session.state.sampleCount, 10000);
    expect(session.state.phase, PdfEditingInteractionPhase.active);

    session.commit();
    expect(notifications, 2);
    expect(session.state.effect, PdfEditingInteractionEffect.committed);
    expect(session.state.phase, PdfEditingInteractionPhase.awaitingRaster);

    session.rasterReady();
    expect(notifications, 3);
    expect(session.state.effect, PdfEditingInteractionEffect.rasterReady);
    expect(session.state.phase, PdfEditingInteractionPhase.idle);
  });

  test('cancel is a terminal transition without a raster handoff', () {
    final session = PdfEditingInteractionSession();
    addTearDown(session.dispose);
    session.begin(PdfEditingInteractionIntent.resize, pageIndex: 0);
    session.sample();
    session.cancel();
    expect(session.state.intent, PdfEditingInteractionIntent.resize);
    expect(session.state.effect, PdfEditingInteractionEffect.canceled);
    expect(session.state.phase, PdfEditingInteractionPhase.idle);
    session.rasterReady();
    expect(session.state.effect, PdfEditingInteractionEffect.canceled);
  });

  Future<PdfEditingController> pumpViewer(
      WidgetTester tester, PdfEditingInteractionSession session) async {
    final editing = PdfEditingController(buildMultiPagePdf(1));
    addTearDown(editing.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ListenableBuilder(
          listenable: editing,
          builder: (context, _) => PdfViewer(
            initialFit: PdfViewerFit.width,
            document: editing.document,
            editing: editing,
            interactionSession: session,
          ),
        ),
      ),
    ));
    await tester.pump();
    return editing;
  }

  testWidgets('stylus events expose ink intent without per-move notifications',
      (tester) async {
    final session = PdfEditingInteractionSession();
    addTearDown(session.dispose);
    final editing = await pumpViewer(tester, session);
    editing.tool = PdfEditTool.ink;
    await tester.pump();
    var notifications = 0;
    session.addListener(() => notifications++);

    final gesture = await tester.startGesture(const Offset(200, 220),
        kind: PointerDeviceKind.stylus);
    expect(session.state.intent, PdfEditingInteractionIntent.ink);
    expect(session.state.phase, PdfEditingInteractionPhase.active);
    expect(notifications, 1);

    for (var i = 0; i < 20; i++) {
      await gesture.moveBy(const Offset(2, 0));
    }
    expect(session.state.sampleCount, 20);
    expect(notifications, 1);

    await gesture.up();
    expect(session.state.effect, PdfEditingInteractionEffect.completed);
    expect(session.state.phase, PdfEditingInteractionPhase.idle);
    expect(notifications, 2);
    // Let the controller's normal ink auto-commit timer finish.
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets('drag commit hands its preview to the page raster',
      (tester) async {
    final session = PdfEditingInteractionSession();
    addTearDown(session.dispose);
    final editing = await pumpViewer(tester, session);
    editing.tool = PdfEditTool.rectangle;
    await tester.pump();

    final gesture = await tester.startGesture(const Offset(120, 160),
        kind: PointerDeviceKind.mouse);
    await gesture.moveBy(const Offset(120, 80));
    expect(session.state.intent, PdfEditingInteractionIntent.create);
    expect(session.state.sampleCount, greaterThan(0));
    await gesture.up();

    expect(editing.document.page(0).annotations, hasLength(1));
    expect(session.state.effect, PdfEditingInteractionEffect.committed);
    expect(session.state.phase, PdfEditingInteractionPhase.awaitingRaster);

    await tester.pump();
    await tester.pumpAndSettle();
    expect(session.state.effect, PdfEditingInteractionEffect.rasterReady);
    expect(session.state.phase, PdfEditingInteractionPhase.idle);
  });
}
