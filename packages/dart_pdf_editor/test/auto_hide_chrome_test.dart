import 'package:flutter/gestures.dart'
    show
        PointerDownEvent,
        PointerScrollEvent,
        PointerUpEvent,
        kDoubleTapTimeout;
import 'package:flutter/services.dart' show SystemChannels;
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:dart_pdf_editor/src/design/auto_hide_chrome.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Phone chrome steps aside for reading: on a compact layout the header and
// the docked toolbar slide off as the user scrolls on through the document,
// and come back on a scroll back or a tap on the page.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pump(WidgetTester tester, Widget body) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: body)));
    await tester.pumpAndSettle();
  }

  void screen(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  const phone = Size(400, 800);
  final controls = find.byKey(const ValueKey('pdf-shell-controls'));
  final undo = find.byKey(const ValueKey('pdf-undo'));

  // a hidden header has slid up past the top edge
  bool headerShown(WidgetTester tester) => tester.getRect(controls).bottom > 0;
  // a hidden toolbar has slid down past the bottom edge
  bool toolbarShown(WidgetTester tester) =>
      tester.getRect(undo).top < phone.height;

  Future<void> scroll(WidgetTester tester, double dy) async {
    await tester.drag(find.byType(PdfViewer), Offset(0, dy));
    await tester.pumpAndSettle();
  }

  Future<void> tapPage(WidgetTester tester) async {
    await tester.tap(find.byType(PdfViewer));
    // a single tap resolves once the double-tap (zoom) window has passed
    await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 50));
    await tester.pumpAndSettle();
  }

  testWidgets('reader: scrolling on hides the header, back shows it',
      (tester) async {
    screen(tester, phone);
    await pump(tester,
        PdfReader(bytes: buildMultiPagePdf(6), initialFit: PdfViewerFit.width));
    expect(headerShown(tester), isTrue);

    await scroll(tester, -300);
    expect(headerShown(tester), isFalse);

    await scroll(tester, 120);
    expect(headerShown(tester), isTrue);
  });

  testWidgets('reader: hidden chrome takes the status bar, no band left',
      (tester) async {
    screen(tester, phone);
    tester.view.padding = const FakeViewPadding(top: 47);
    addTearDown(tester.view.resetPadding);
    final modes = <Object?>[];
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'SystemChrome.setEnabledSystemUIMode') {
        modes.add(call.arguments);
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    await pump(tester,
        PdfReader(bytes: buildMultiPagePdf(6), initialFit: PdfViewerFit.width));
    expect(modes, isEmpty);

    await tapPage(tester);
    expect(headerShown(tester), isFalse);
    expect(modes, ['SystemUiMode.immersiveSticky']);
    // the page runs to the top edge, not under an empty status-bar band
    expect(tester.getTopLeft(find.byType(PdfViewer)).dy, 0);

    await tapPage(tester);
    expect(headerShown(tester), isTrue);
    expect(modes, ['SystemUiMode.immersiveSticky', 'SystemUiMode.edgeToEdge']);

    // closing the reader while it is full screen gives the status bar back
    await tapPage(tester);
    await tester.pumpWidget(const SizedBox());
    expect(modes.last, 'SystemUiMode.edgeToEdge');
    expect(modes, hasLength(4));
  });

  testWidgets('reader: a tap on the page toggles the header', (tester) async {
    screen(tester, phone);
    await pump(tester,
        PdfReader(bytes: buildMultiPagePdf(6), initialFit: PdfViewerFit.width));

    await tapPage(tester);
    expect(headerShown(tester), isFalse);
    await tapPage(tester);
    expect(headerShown(tester), isTrue);
  });

  testWidgets('editor: the header and docked toolbar hide together',
      (tester) async {
    screen(tester, phone);
    await pump(
        tester,
        PdfEditorView(
            bytes: buildMultiPagePdf(6), initialFit: PdfViewerFit.width));
    expect(headerShown(tester), isTrue);
    expect(toolbarShown(tester), isTrue);

    await scroll(tester, -300);
    expect(headerShown(tester), isFalse);
    expect(toolbarShown(tester), isFalse);

    await tapPage(tester);
    expect(headerShown(tester), isTrue);
    expect(toolbarShown(tester), isTrue);
  });

  // The app and the example open the editor with Select armed. Select is
  // reading, not a tool in use - and with it armed the viewer scrolls by its
  // own touch pan (no UserScrollNotification), so this is its own path.
  testWidgets('editor with Select armed: scrolling hides, a tap toggles',
      (tester) async {
    screen(tester, phone);
    final editing = PdfEditingController(buildMultiPagePdf(6))
      ..tool = PdfEditTool.select;
    addTearDown(editing.dispose);
    await pump(tester,
        PdfEditorView(controller: editing, initialFit: PdfViewerFit.width));
    expect(headerShown(tester), isTrue);

    await scroll(tester, -300);
    expect(headerShown(tester), isFalse);
    expect(toolbarShown(tester), isFalse);

    await scroll(tester, 120);
    expect(headerShown(tester), isTrue);

    await tapPage(tester);
    expect(headerShown(tester), isFalse);
    await tapPage(tester);
    expect(headerShown(tester), isTrue);
  });

  testWidgets('editor: an armed tool keeps the chrome up', (tester) async {
    screen(tester, phone);
    final editing = PdfEditingController(buildMultiPagePdf(6));
    addTearDown(editing.dispose);
    await pump(tester,
        PdfEditorView(controller: editing, initialFit: PdfViewerFit.width));

    await scroll(tester, -300);
    expect(toolbarShown(tester), isFalse);

    // arming a tool brings the hidden chrome straight back
    editing.tool = PdfEditTool.ink;
    await tester.pumpAndSettle();
    expect(headerShown(tester), isTrue);
    expect(toolbarShown(tester), isTrue);
  });

  testWidgets('the feature can be turned off', (tester) async {
    screen(tester, phone);
    await pump(
        tester,
        PdfReader(
          bytes: buildMultiPagePdf(6),
          initialFit: PdfViewerFit.width,
          features: const PdfReaderFeatures(autoHideChrome: false),
        ));

    await scroll(tester, -300);
    expect(headerShown(tester), isTrue);
    await tapPage(tester);
    expect(headerShown(tester), isTrue);
  });

  testWidgets('a wide layout never hides its chrome', (tester) async {
    screen(tester, const Size(1200, 800));
    await pump(tester,
        PdfReader(bytes: buildMultiPagePdf(6), initialFit: PdfViewerFit.width));
    final header = find.byKey(const ValueKey('pdf-page-number-field'));
    final top = tester.getRect(header).top;

    await scroll(tester, -300);
    expect(tester.getRect(header).top, top);
  });

  group('PdfAutoHideBar', () {
    Widget bar(PdfChromeAutoHide chrome, {bool enabled = true}) =>
        Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topCenter,
            child: PdfAutoHideBar(
              controller: chrome,
              edge: AxisDirection.up,
              enabled: enabled,
              child: const SizedBox(
                height: 40,
                child: Focus(child: SizedBox.expand()),
              ),
            ),
          ),
        );
    double height(WidgetTester tester) =>
        tester.getSize(find.byType(PdfAutoHideBar)).height;

    testWidgets('focus inside the bar keeps it up', (tester) async {
      final chrome = PdfChromeAutoHide();
      addTearDown(chrome.dispose);
      await tester.pumpWidget(bar(chrome));
      final focus = Focus.of(tester.element(find.byType(SizedBox).last));
      focus.requestFocus();
      await tester.pump();

      chrome.hide();
      await tester.pumpAndSettle();
      expect(height(tester), 40, reason: 'typing in the bar pins it');

      focus.unfocus();
      await tester.pumpAndSettle();
      expect(height(tester), 0, reason: 'losing focus lets it go');
    });

    testWidgets('a pinned controller ignores hide and toggle', (tester) async {
      final chrome = PdfChromeAutoHide()..pinned = true;
      addTearDown(chrome.dispose);
      chrome.hide();
      chrome.toggle();
      expect(chrome.visible, isTrue);
      chrome.pinned = false;
      expect(chrome.visible, isTrue, reason: 'unpinning leaves it showing');
      // past the grace for the tap that unpinned it, a tap toggles again
      await tester.pump(const Duration(seconds: 1));
      chrome.toggle();
      expect(chrome.visible, isFalse);
    });

    testWidgets('a swapped controller drives the bar', (tester) async {
      final first = PdfChromeAutoHide();
      final second = PdfChromeAutoHide();
      addTearDown(first.dispose);
      addTearDown(second.dispose);
      await tester.pumpWidget(bar(first));
      await tester.pumpWidget(bar(second));

      first.hide();
      await tester.pumpAndSettle();
      expect(height(tester), 40, reason: 'the old controller is detached');
      second.hide();
      await tester.pumpAndSettle();
      expect(height(tester), 0);
    });

    testWidgets('disabling snaps the bar back without animating',
        (tester) async {
      final chrome = PdfChromeAutoHide();
      addTearDown(chrome.dispose);
      await tester.pumpWidget(bar(chrome));
      chrome.hide();
      await tester.pumpAndSettle();
      expect(height(tester), 0);

      await tester.pumpWidget(bar(chrome, enabled: false));
      expect(height(tester), 40);
    });
  });

  group('PdfChromeAutoHide', () {
    late BuildContext context;
    Future<PdfChromeAutoHide> setUp(WidgetTester tester) async {
      await tester.pumpWidget(Builder(builder: (c) {
        context = c;
        return const SizedBox();
      }));
      final chrome = PdfChromeAutoHide();
      addTearDown(chrome.dispose);
      return chrome;
    }

    ScrollUpdateNotification update(double delta) => ScrollUpdateNotification(
          metrics: FixedScrollMetrics(
            minScrollExtent: 0,
            maxScrollExtent: 5000,
            pixels: 1000,
            viewportDimension: 600,
            axisDirection: AxisDirection.down,
            devicePixelRatio: 1,
          ),
          context: context,
          scrollDelta: delta,
        );
    void feed(PdfChromeAutoHide chrome, double delta, {int frames = 4}) {
      for (var i = 0; i < frames; i++) {
        chrome.handleScrollNotification(update(delta));
      }
    }

    testWidgets('programmatic scrolling leaves the chrome alone',
        (tester) async {
      final chrome = await setUp(tester);
      feed(chrome, 40);
      expect(chrome.visible, isTrue);
    });

    testWidgets('a finger-driven scroll and its fling count', (tester) async {
      final chrome = await setUp(tester);
      chrome.handlePointerDown(const PointerDownEvent(pointer: 1));
      feed(chrome, 10);
      expect(chrome.visible, isFalse);
      chrome.handlePointerUp(const PointerUpEvent(pointer: 1));
      // the fling carries on after lift-off
      feed(chrome, -10);
      expect(chrome.visible, isTrue);
      // ...but not forever
      await tester.pump(const Duration(seconds: 2));
      feed(chrome, 40);
      expect(chrome.visible, isTrue);
    });

    testWidgets('a pinch is a zoom, not a scroll', (tester) async {
      final chrome = await setUp(tester);
      chrome.handlePointerDown(const PointerDownEvent(pointer: 1));
      chrome.handlePointerDown(const PointerDownEvent(pointer: 2));
      feed(chrome, 20);
      chrome.handlePointerUp(const PointerUpEvent(pointer: 2));
      chrome.handlePointerUp(const PointerUpEvent(pointer: 1));
      feed(chrome, 20);
      expect(chrome.visible, isTrue);
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('a wheel scroll counts; a jump never does', (tester) async {
      final chrome = await setUp(tester);
      chrome.handlePointerSignal(
          const PointerScrollEvent(scrollDelta: Offset(0, 40)));
      chrome.handleScrollNotification(update(400));
      expect(chrome.visible, isTrue, reason: 'a 400px jump is not reading');
      feed(chrome, 10);
      expect(chrome.visible, isFalse);
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('the tap that clears a selection does not toggle',
        (tester) async {
      final chrome = PdfChromeAutoHide()..pinned = true;
      addTearDown(chrome.dispose);
      chrome.pinned = false;
      chrome.toggle();
      expect(chrome.visible, isTrue);
      chrome.toggle();
      expect(chrome.visible, isFalse, reason: 'only the one tap is swallowed');
      await tester.pump(const Duration(seconds: 1));
    });
  });
}
