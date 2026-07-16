import 'dart:ui' show Color;

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';

void main() {
  late PdfPage page;

  setUp(() {
    page = PdfDocument.open(buildMultiPagePdf(1)).page(0);
  });

  PdfPageRenderIntent intent({
    PdfPage? source,
    int pageIndex = 0,
    int pageEpoch = 0,
    int contentStamp = 0,
    int destructiveStamp = 0,
    bool trustContentStamp = false,
    int? rotation,
    Color pageColor = const Color(0xFFFFFFFF),
    bool showAnnotations = true,
    double scale = 1,
    int settleGeneration = 0,
  }) =>
      PdfPageRenderIntent(
        page: source ?? page,
        pageIndex: pageIndex,
        pageEpoch: pageEpoch,
        contentStamp: contentStamp,
        destructiveStamp: destructiveStamp,
        trustContentStamp: trustContentStamp,
        rotation: rotation,
        pageColor: pageColor,
        showAnnotations: showAnnotations,
        scale: scale,
        settleGeneration: settleGeneration,
      );

  test('viewport changes request a reraster without dropping caches', () {
    final session = PdfPageRenderSession(intent());

    final transition = session.update(intent(scale: 2));

    expect(transition.scheduleRender, isTrue);
    expect(transition.dropPicture, isFalse);
    expect(transition.dropBaseRaster, isFalse);
    expect(transition.dropPreview, isFalse);
    expect(transition.dropDetail, isFalse);
  });

  test(
    'additive content keeps the old base and detail while replacing data',
    () {
      final session = PdfPageRenderSession(intent());

      final transition = session.update(intent(contentStamp: 1));

      expect(transition.scheduleRender, isTrue);
      expect(transition.dropPicture, isTrue);
      expect(transition.dropBaseRaster, isFalse);
      expect(transition.dropPreview, isFalse);
      expect(transition.dropDetail, isFalse);
    },
  );

  test('destructive content invalidates every visible cache layer', () {
    final session = PdfPageRenderSession(intent());

    final transition = session.update(intent(destructiveStamp: 1));

    expect(transition.scheduleRender, isTrue);
    expect(transition.dropPicture, isTrue);
    expect(transition.dropBaseRaster, isTrue);
    expect(transition.dropPreview, isTrue);
    expect(transition.dropDetail, isTrue);
  });

  test('new intent rejects stale full and detail results immediately', () {
    final session = PdfPageRenderSession(intent());
    final full = session.beginFull();
    final detail = session.beginDetail();
    expect(session.acceptsFull(full, 0), isTrue);
    expect(session.acceptsDetail(detail), isTrue);

    session.update(intent(pageColor: const Color(0xFFEEEEEE)));

    expect(session.acceptsFull(full, 0), isFalse);
    expect(session.acceptsDetail(detail), isFalse);
  });

  test('standalone hold defers exactly until release', () async {
    final session = PdfPageRenderSession(intent());
    final hold = ValueNotifier<bool>(true);
    var renders = 0;
    addTearDown(() {
      session.dispose();
      hold.dispose();
    });

    await session.request(
      owner: Object(),
      hasPicture: false,
      scheduler: null,
      hold: hold,
      render: () async => renders++,
    );
    expect(renders, 0);
    expect(session.hasPendingHold, isTrue);

    hold.value = false;
    expect(session.releaseHold(), isTrue);
    await session.request(
      owner: Object(),
      hasPicture: false,
      scheduler: null,
      hold: hold,
      render: () async => renders++,
    );
    expect(renders, 1);
    expect(session.releaseHold(), isFalse);
  });

  testWidgets('scheduler adapter owns pacing without changing the outcome',
      (tester) async {
    final session = PdfPageRenderSession(intent());
    final scheduler = PdfPageRenderScheduler()..holding = true;
    var renders = 0;
    addTearDown(() {
      session.dispose();
      scheduler.dispose();
    });

    await session.request(
      owner: session,
      hasPicture: false,
      scheduler: scheduler,
      hold: null,
      render: () async => renders++,
    );
    expect(scheduler.hasPending, isTrue);
    expect(renders, 0);

    scheduler.holding = false;
    await tester.pump();
    expect(renders, 1);
    expect(scheduler.hasPending, isFalse);
  });
}
