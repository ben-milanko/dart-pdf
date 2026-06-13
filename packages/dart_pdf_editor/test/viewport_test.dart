import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Reopening a document where the user left it: the resolution-independent
// PdfViewport snapshot, the viewer's capture/restore, the per-document
// store in preferences, and the shells wiring them together.
void main() {
  group('PdfViewport', () {
    test('round-trips through JSON', () {
      const vp = PdfViewport(page: 3, top: 0.25, left: 0.1, zoom: 2.5);
      final decoded = PdfViewport.decode(vp.encode());
      expect(decoded, vp);
      expect(decoded!.page, 3);
      expect(decoded.top, 0.25);
      expect(decoded.left, 0.1);
      expect(decoded.zoom, 2.5);
    });

    test('omits zero offsets but keeps them parseable', () {
      const vp = PdfViewport(page: 0, zoom: 1);
      final json = vp.toJson();
      expect(json.containsKey('top'), isFalse);
      expect(json.containsKey('left'), isFalse);
      expect(PdfViewport.fromJson(json), vp);
      expect(PdfViewport.fromJson(json)!.top, 0);
    });

    test('rejects malformed input', () {
      expect(PdfViewport.decode('not json'), isNull);
      expect(PdfViewport.decode('[]'), isNull);
      expect(PdfViewport.fromJson(<String, Object?>{}), isNull);
      expect(PdfViewport.fromJson(<String, Object?>{'page': -1}), isNull);
    });
  });

  group('pdfDocumentKey', () {
    test('is stable for identical bytes and differs across documents', () {
      final a = buildMultiPagePdf(3);
      final b = buildMultiPagePdf(7);
      expect(pdfDocumentKey(a), pdfDocumentKey(a));
      expect(pdfDocumentKey(Uint8List.fromList(a)), pdfDocumentKey(a));
      expect(pdfDocumentKey(a), isNot(pdfDocumentKey(b)));
    });
  });

  group('PdfEditingPreferences viewport store', () {
    test('remembers a viewport per document and a fresh instance restores it',
        () async {
      SharedPreferences.setMockInitialValues({});
      final a = PdfEditingPreferences();
      await a.ready;
      const vp = PdfViewport(page: 5, top: 0.3, zoom: 1.5);
      a.setViewport('doc-a', vp);
      a.setViewport('doc-b', const PdfViewport(page: 2));
      expect(a.viewportFor('doc-a'), vp);
      await pumpEventQueue();

      final b = PdfEditingPreferences();
      await b.ready;
      expect(b.viewportFor('doc-a'), vp);
      expect(b.viewportFor('doc-b'), const PdfViewport(page: 2));
      expect(b.viewportFor('missing'), isNull);
    });

    test('null forgets a document', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = PdfEditingPreferences();
      await prefs.ready;
      prefs.setViewport('doc', const PdfViewport(page: 1));
      expect(prefs.viewportFor('doc'), isNotNull);
      prefs.setViewport('doc', null);
      expect(prefs.viewportFor('doc'), isNull);
    });

    test('evicts the least-recently-touched past the cap', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = PdfEditingPreferences();
      await prefs.ready;
      // the cap is 64; write 70 distinct documents
      for (var i = 0; i < 70; i++) {
        prefs.setViewport('doc-$i', PdfViewport(page: i));
      }
      // the first six are gone, the last 64 remain
      expect(prefs.viewportFor('doc-0'), isNull);
      expect(prefs.viewportFor('doc-5'), isNull);
      expect(prefs.viewportFor('doc-6'), isNotNull);
      expect(prefs.viewportFor('doc-69'), isNotNull);
    });

    test('a viewport set before loading survives the disk read', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = PdfEditingPreferences();
      // set before awaiting ready — _store is still null
      prefs.setViewport('early', const PdfViewport(page: 9));
      await prefs.ready;
      await pumpEventQueue();
      expect(prefs.viewportFor('early'), const PdfViewport(page: 9));

      final fresh = PdfEditingPreferences();
      await fresh.ready;
      expect(fresh.viewportFor('early'), const PdfViewport(page: 9));
    });
  });

  group('PdfViewer capture/restore', () {
    Widget viewer(PdfViewerController controller, Uint8List bytes,
            {PdfViewport? initialViewport}) =>
        MaterialApp(
          home: Scaffold(
            body: PdfViewer(
              initialFit: PdfViewerFit.width,
              document: PdfDocument.open(bytes),
              controller: controller,
              initialViewport: initialViewport,
            ),
          ),
        );

    // pump a fresh viewer element (initState, not didUpdateWidget) by
    // clearing the tree first — same-shape rebuilds reuse the State and
    // would skip the initialViewport.
    Future<void> reopen(WidgetTester tester, Widget next) async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold()));
      await tester.pump();
      await tester.pumpWidget(next);
    }

    testWidgets('captures the scrolled position and reopens at it',
        (tester) async {
      final bytes = buildMultiPagePdf(8);
      final c1 = PdfViewerController();
      await tester.pumpWidget(viewer(c1, bytes));
      await tester.pump();

      unawaited(c1.jumpToPage(4));
      await tester.pumpAndSettle();
      expect(c1.currentPage, 4);

      final snapshot = c1.captureViewport();
      expect(snapshot, isNotNull);
      expect(snapshot!.page, 4);
      expect(snapshot.zoom, moreOrLessEquals(1, epsilon: 0.01));

      // reopen a fresh viewer with the captured snapshot
      final c2 = PdfViewerController();
      await reopen(tester, viewer(c2, bytes, initialViewport: snapshot));
      await tester.pump(); // first layout consumes the pending viewport
      await tester.pump(); // post-frame placement scrolls
      await tester.pump();
      expect(c2.currentPage, 4);
    });

    testWidgets('restoreViewport scrolls a live viewer', (tester) async {
      final bytes = buildMultiPagePdf(8);
      final controller = PdfViewerController();
      await tester.pumpWidget(viewer(controller, bytes));
      await tester.pump();
      expect(controller.currentPage, 0);

      controller.restoreViewport(const PdfViewport(page: 6));
      await tester.pump();
      await tester.pump();
      expect(controller.currentPage, 6);
    });

    testWidgets('restores a zoomed-in viewport', (tester) async {
      final bytes = buildMultiPagePdf(5);
      final c1 = PdfViewerController();
      await tester.pumpWidget(viewer(c1, bytes));
      await tester.pump();

      // double-tap to zoom past fit-width
      await tester.tapAt(const Offset(400, 300));
      await tester.pump(const Duration(milliseconds: 80));
      await tester.tapAt(const Offset(400, 300));
      await tester.pumpAndSettle(const Duration(milliseconds: 300));
      expect(c1.zoom, greaterThan(1));

      final snapshot = c1.captureViewport();
      expect(snapshot!.zoom, greaterThan(1));

      final c2 = PdfViewerController();
      await reopen(tester, viewer(c2, bytes, initialViewport: snapshot));
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(c2.zoom, moreOrLessEquals(snapshot.zoom, epsilon: 0.05));
    });
  });

  group('shell viewport memory', () {
    testWidgets('PdfReader saves on scroll and reopens at the saved position',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = PdfEditingPreferences();
      await prefs.ready;
      addTearDown(prefs.dispose);
      final bytes = buildMultiPagePdf(8);

      // thumbnails off: their raster loop never settles in a plain widget
      // test (no runAsync); this test is about the viewport wiring
      Widget reader(PdfViewerController controller) => MaterialApp(
            home: Scaffold(
              body: PdfReader(
                bytes: bytes,
                documentId: 'doc-1',
                preferences: prefs,
                controller: controller,
                initialFit: PdfViewerFit.width,
                features: const PdfReaderFeatures(thumbnails: false),
              ),
            ),
          );

      final v1 = PdfViewerController();
      await tester.pumpWidget(reader(v1));
      await tester.pump();

      unawaited(v1.jumpToPage(4));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300)); // finish the jump
      expect(v1.currentPage, 4);

      // the save debounce (400ms) writes the position to preferences
      await tester.pump(const Duration(milliseconds: 500));
      expect(prefs.viewportFor('doc-1')?.page, 4);

      // reopen a fresh reader (fresh State) sharing the same preferences
      await tester.pumpWidget(const MaterialApp(home: Scaffold()));
      await tester.pump();
      final v2 = PdfViewerController();
      await tester.pumpWidget(reader(v2));
      await tester.pump(); // build attaches the viewer; restore is queued
      await tester.pump(); // restore applies the saved layout zoom
      await tester.pump(); // post-frame placement scrolls
      await tester.pump(const Duration(milliseconds: 500)); // clear timers
      expect(v2.currentPage, 4);
    });

    testWidgets(
        'PdfEditorView with an external controller + documentId restores zoom',
        (tester) async {
      // mirrors the example app: editor mode, external session/viewer
      // controllers, documentId, default initialFit (page)
      SharedPreferences.setMockInitialValues({});
      final prefs = PdfEditingPreferences();
      await prefs.ready;
      addTearDown(prefs.dispose);
      final bytes = buildMultiPagePdf(5);

      PdfEditingController? session;
      Widget editor(PdfEditingController s, PdfViewerController v) => MaterialApp(
            home: Scaffold(
              body: PdfEditorView(
                controller: s,
                viewerController: v,
                documentId: 'doc-x',
                features: const PdfEditorFeatures(
                  thumbnails: false,
                  toolbar: false,
                  headerBar: false,
                ),
              ),
            ),
          );

      session = PdfEditingController(bytes, preferences: prefs);
      final v1 = PdfViewerController();
      await tester.pumpWidget(editor(session, v1));
      await tester.pump();

      // zoom in with ctrl+wheel (works regardless of editing overlays)
      final pointer = TestPointer(7, PointerDeviceKind.mouse);
      pointer.hover(const Offset(400, 300));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      for (var i = 0; i < 3; i++) {
        await tester.sendEventToBinding(pointer.scroll(const Offset(0, -150)));
        await tester.pump();
      }
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle(const Duration(milliseconds: 300));
      expect(v1.zoom, greaterThan(1));

      // debounce → save
      await tester.pump(const Duration(milliseconds: 500));
      final saved = prefs.viewportFor('doc-x');
      expect(saved, isNotNull);
      expect(saved!.zoom, greaterThan(1));

      // reopen fresh (fresh State), same preferences + documentId
      await tester.pumpWidget(const MaterialApp(home: Scaffold()));
      await tester.pump();
      session.dispose();
      session = PdfEditingController(bytes, preferences: prefs);
      final v2 = PdfViewerController();
      addTearDown(session.dispose);
      await tester.pumpWidget(editor(session, v2));
      await tester.pump();
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(v2.zoom, greaterThan(1));
    });

    testWidgets('app going hidden flushes the position before the debounce',
        (tester) async {
      // the web case: a tab is closed/hidden without disposing the widget,
      // and faster than the 400ms save debounce — the lifecycle flush must
      // still persist the position
      SharedPreferences.setMockInitialValues({});
      final prefs = PdfEditingPreferences();
      await prefs.ready;
      addTearDown(prefs.dispose);
      final v = PdfViewerController();

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: PdfReader(
            bytes: buildMultiPagePdf(6),
            documentId: 'doc-hide',
            preferences: prefs,
            controller: v,
            initialFit: PdfViewerFit.width,
            features: const PdfReaderFeatures(thumbnails: false),
          ),
        ),
      ));
      await tester.pump();

      unawaited(v.jumpToPage(3));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(v.currentPage, 3);

      // go hidden well within the debounce window — nothing written yet
      expect(prefs.viewportFor('doc-hide'), isNull);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      await tester.pump();
      expect(prefs.viewportFor('doc-hide')?.page, 3);
    });
  });
}
