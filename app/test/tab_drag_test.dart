import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dart_pdf_editor_app/document_tab.dart';
import 'package:dart_pdf_editor_app/editor_screen.dart';
import 'package:dart_pdf_editor_app/tab_drag.dart';
import 'package:dart_pdf_editor_app/window_support.dart';

class _FakeLocator implements TabDropLocator {
  TabDropLocation? location;
  Object? failure;
  int calls = 0;

  @override
  Future<TabDropLocation?> locate(Iterable<int> windowHandles) async {
    calls++;
    if (failure case final error?) throw error;
    return location;
  }
}

class _FakeWindow implements TabDragWindow {
  _FakeWindow(this.windowHandle, {this.events});

  @override
  final int windowHandle;
  final List<String>? events;
  final List<DocumentTab> tabs = <DocumentTab>[];
  final List<DocumentHandoff> inserted = <DocumentHandoff>[];
  int? insertionIndex = 0;
  bool acceptInsert = true;
  bool acceptNewWindow = true;
  int? reorderedTo;
  int newWindows = 0;
  int closeRequests = 0;

  @override
  void closeWindowIfEmpty() {
    if (tabs.isNotEmpty) return;
    events?.add('close');
    closeRequests++;
  }

  @override
  bool containsTab(DocumentTab tab) => tabs.contains(tab);

  @override
  bool insertTab(DocumentHandoff handoff, int insertionIndex) {
    events?.add('insert');
    if (!acceptInsert) return false;
    inserted.add(handoff);
    return true;
  }

  @override
  bool openTabInNewWindow(DocumentHandoff handoff) {
    events?.add('open');
    if (!acceptNewWindow) return false;
    newWindows++;
    return true;
  }

  @override
  bool removeTab(DocumentTab tab) {
    events?.add('remove');
    return tabs.remove(tab);
  }

  @override
  bool reorderTab(DocumentTab tab, int insertionIndex) {
    if (!tabs.contains(tab)) return false;
    reorderedTo = insertionIndex;
    return true;
  }

  @override
  int? tabInsertionIndex(Offset localPoint) => insertionIndex;
}

DocumentHandoff _handoff([String title = 'dragged.pdf']) {
  final bytes = buildClassicPdf();
  return DocumentHandoff(
    bytes: bytes,
    title: title,
    savedLength: bytes.length,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('native locator sends window handles and decodes the local point',
      () async {
    const channel = MethodChannel('dev.milanko.dartpdf/window_geometry');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'locateDrop');
      expect(call.arguments, {
        'handles': [11, 22],
      });
      return {'handle': 22, 'x': 75.5, 'y': 20.25};
    });

    final location = await const NativeTabDropLocator().locate([11, 22]);

    expect(location?.windowHandle, 22);
    expect(location?.localPoint, const Offset(75.5, 20.25));
  });

  testWidgets('native window accepts drops in full and compact title chrome',
      (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(680, 600);
    SharedPreferences.setMockInitialValues({});
    final prefs = PdfEditingPreferences();
    final locator = _FakeLocator();
    final coordinator = TabDragCoordinator(locator: locator);
    var closeRequests = 0;
    await tester.pumpWidget(DartPdfNativeWindowScope(
      windowHandle: 22,
      child: DartPdfWindowCloseScope(
        coordinator: DartPdfWindowCloseCoordinator(
          closeWindow: () async => closeRequests++,
        ),
        child: MaterialApp(
          home: EditorScreen(
            prefs: prefs,
            tabDragCoordinator: coordinator,
            onNewWindow: (_, {document}) => true,
            ownsApplicationSession: false,
          ),
        ),
      ),
    ));
    await tester.pump();

    locator.location = TabDropLocation(
      windowHandle: 22,
      localPoint: tester.getCenter(find.descendant(
        of: find.byType(AppBar),
        matching: find.text('DartPDF'),
      )),
    );
    final source = _FakeWindow(11);
    final tab = DocumentTab.error(title: 'source.pdf', error: 'fixture');
    source.tabs.add(tab);
    coordinator.register(source);
    final token = coordinator.begin(source, tab, () => _handoff('dragged.pdf'));

    expect(
      await coordinator.finish(
        token,
        userCancelled: false,
      ),
      TabDragResult.movedToWindow,
    );
    // Widen before the accepted document builds its editor chrome. The first
    // drop still hit the compact title geometry from the preceding frame.
    tester.view.physicalSize = const Size(800, 600);
    await tester.pump();

    expect(
      find.descendant(
        of: find.byKey(const ValueKey('tab-strip')),
        matching: find.text('dragged.pdf'),
      ),
      findsOneWidget,
    );
    expect(source.tabs, isEmpty);

    locator.location = TabDropLocation(
      windowHandle: 22,
      // The add button sits after the rendered list but inside the strip, so
      // this deterministically appends instead of landing on a midpoint tie.
      localPoint: tester
          .getCenter(find.byKey(const ValueKey('desktop-tab-add-button'))),
    );
    final compactSource = _FakeWindow(33);
    final compactTab =
        DocumentTab.error(title: 'compact.pdf', error: 'fixture');
    compactSource.tabs.add(compactTab);
    coordinator.register(compactSource);
    final compactToken = coordinator.begin(
      compactSource,
      compactTab,
      () => _handoff('compact.pdf'),
    );

    expect(
      await coordinator.finish(
        compactToken,
        userCancelled: false,
      ),
      TabDragResult.movedToWindow,
    );
    await tester.pump();
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('tab-strip')),
        matching: find.text('compact.pdf'),
      ),
      findsOneWidget,
    );
    expect(compactSource.tabs, isEmpty);

    // A drag owned by another native view paints its feedback in this view's
    // Overlay (the source Overlay is clipped to its own native window) and
    // opens a real animated gap at the resolved insertion slot.
    final incomingSource = _FakeWindow(55);
    final incomingTab =
        DocumentTab.error(title: 'incoming.pdf', error: 'fixture');
    incomingSource.tabs.add(incomingTab);
    coordinator.register(incomingSource);
    final firstTabBefore = tester.getCenter(find.descendant(
      of: find.byKey(const ValueKey('tab-strip')),
      matching: find.text('dragged.pdf'),
    ));
    final targetListRect =
        tester.getRect(find.byKey(const ValueKey('tab-strip')));
    locator.location = TabDropLocation(
      windowHandle: 22,
      localPoint: Offset(targetListRect.left + 6, firstTabBefore.dy),
    );
    final incomingToken = coordinator.begin(
      incomingSource,
      incomingTab,
      () => _handoff('incoming.pdf'),
    );
    coordinator.update(incomingToken);
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 180));
    expect(
      find.byKey(const ValueKey('tab-drag-destination-feedback')),
      findsOneWidget,
    );
    final destinationFeedback =
        find.byKey(const ValueKey('tab-drag-destination-feedback'));
    final feedbackLeft = tester.getTopLeft(destinationFeedback).dx;
    locator.location = TabDropLocation(
      windowHandle: 22,
      localPoint: Offset(targetListRect.left + 46, firstTabBefore.dy),
    );
    coordinator.update(incomingToken);
    await tester.pump();
    await tester.pump();
    expect(tester.getTopLeft(destinationFeedback).dx,
        greaterThan(feedbackLeft + 20));
    expect(
      tester
          .getCenter(find.descendant(
            of: find.byKey(const ValueKey('tab-strip')),
            matching: find.text('dragged.pdf'),
          ))
          .dx,
      greaterThan(firstTabBefore.dx + 100),
    );
    coordinator.cancel(incomingToken);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 180));
    expect(
      find.byKey(const ValueKey('tab-drag-destination-feedback')),
      findsNothing,
    );

    // Exercise the actual pointer source and live destination marker, not just
    // the coordinator. Dragging the second tab before the first is the
    // regression for replacing the ReorderableListView handle with a plain
    // Draggable without restoring same-strip routing.
    final compactLabel = find.descendant(
      of: find.byKey(const ValueKey('tab-strip')),
      matching: find.text('compact.pdf'),
    );
    final draggedLabel = find.descendant(
      of: find.byKey(const ValueKey('tab-strip')),
      matching: find.text('dragged.pdf'),
    );
    final firstRect = tester.getRect(draggedLabel);
    final firstCenterBeforeReorder = tester.getCenter(draggedLabel);
    final tabListRect = tester.getRect(find.byKey(const ValueKey('tab-strip')));
    locator.location = TabDropLocation(
      windowHandle: 22,
      localPoint: Offset(tabListRect.left + 6, firstRect.center.dy),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(compactLabel),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveBy(const Offset(-80, 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 180));
    expect(
      find.byKey(const ValueKey('tab-drag-feedback-over-strip')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('tab-drag-insertion-indicator')),
      findsOneWidget,
    );
    expect(tester.getCenter(draggedLabel).dx,
        greaterThan(firstCenterBeforeReorder.dx + 100));

    // Crossing off the tab strip changes both the feedback card and the
    // destination chrome before release.
    locator.location = const TabDropLocation(
      windowHandle: 22,
      localPoint: Offset(300, 300),
    );
    await gesture.moveBy(const Offset(-10, 10));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 180));
    expect(
      find.byKey(const ValueKey('tab-drag-feedback-detached')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('tab-drag-insertion-indicator')),
      findsNothing,
    );

    locator.location = TabDropLocation(
      windowHandle: 22,
      localPoint: Offset(tabListRect.left + 6, firstRect.center.dy),
    );
    await gesture.moveBy(const Offset(-10, 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 180));
    expect(coordinator.preview?.insertionIndex, 0);
    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.getCenter(compactLabel).dx,
        lessThan(tester.getCenter(draggedLabel).dx));

    // Moving both tabs to another registered window closes this source only
    // after the second accepted handoff empties it.
    final target = _FakeWindow(44);
    coordinator.register(target);
    locator.location = const TabDropLocation(
      windowHandle: 44,
      localPoint: Offset(40, 20),
    );
    for (final title in ['compact.pdf', 'dragged.pdf']) {
      final label = find.descendant(
        of: find.byKey(const ValueKey('tab-strip')),
        matching: find.text(title),
      );
      final move = await tester.startGesture(
        tester.getCenter(label),
        kind: PointerDeviceKind.mouse,
      );
      await move.moveBy(const Offset(40, 0));
      await tester.pump();
      await move.up();
      await tester.pump();
      await tester.pump();
      if (title == 'compact.pdf') expect(closeRequests, 0);
    }
    expect(target.inserted, hasLength(2));
    expect(closeRequests, 1);

    await tester.pumpWidget(const SizedBox.shrink());
    coordinator.dispose();
    prefs.dispose();
  });

  test('drop in the source strip reorders without rebuilding the document',
      () async {
    final locator = _FakeLocator()
      ..location = const TabDropLocation(
        windowHandle: 11,
        localPoint: Offset(220, 20),
      );
    final coordinator = TabDragCoordinator(locator: locator);
    final source = _FakeWindow(11)..insertionIndex = 2;
    final tab = DocumentTab.error(title: 'dragged.pdf', error: 'fixture');
    source.tabs.add(tab);
    coordinator.register(source);

    var snapshots = 0;
    final token = coordinator.begin(source, tab, () {
      snapshots++;
      return _handoff();
    });
    final result = await coordinator.finish(
      token,
      userCancelled: false,
    );

    expect(result, TabDragResult.reordered);
    expect(source.reorderedTo, 2);
    expect(source.tabs, contains(tab));
    expect(source.inserted, isEmpty);
    expect(snapshots, 0);
    coordinator.dispose();
  });

  test('cross-window move inserts before removing the live source', () async {
    final events = <String>[];
    final locator = _FakeLocator()
      ..location = const TabDropLocation(
        windowHandle: 22,
        localPoint: Offset(80, 20),
      );
    final coordinator = TabDragCoordinator(locator: locator);
    final source = _FakeWindow(11, events: events);
    final target = _FakeWindow(22, events: events)..insertionIndex = 1;
    final tab = DocumentTab.error(title: 'dragged.pdf', error: 'fixture');
    source.tabs.add(tab);
    coordinator
      ..register(source)
      ..register(target);

    final handoff = _handoff();
    final token = coordinator.begin(source, tab, () => handoff);
    final result = await coordinator.finish(
      token,
      userCancelled: false,
    );

    expect(result, TabDragResult.movedToWindow);
    expect(events, ['insert', 'remove', 'close']);
    expect(target.inserted, [same(handoff)]);
    expect(source.tabs, isEmpty);
    expect(source.closeRequests, 1);
    coordinator.dispose();
  });

  test('rejected destination keeps the source tab', () async {
    final locator = _FakeLocator()
      ..location = const TabDropLocation(
        windowHandle: 22,
        localPoint: Offset(80, 20),
      );
    final coordinator = TabDragCoordinator(locator: locator);
    final source = _FakeWindow(11);
    final target = _FakeWindow(22)..acceptInsert = false;
    final tab = DocumentTab.error(title: 'dragged.pdf', error: 'fixture');
    source.tabs.add(tab);
    coordinator
      ..register(source)
      ..register(target);

    final token = coordinator.begin(source, tab, () => _handoff());
    final result = await coordinator.finish(
      token,
      userCancelled: false,
    );

    expect(result, TabDragResult.failed);
    expect(source.tabs, [same(tab)]);
    expect(target.inserted, isEmpty);
    coordinator.dispose();
  });

  test('drop outside every app window opens a window before source removal',
      () async {
    final events = <String>[];
    final locator = _FakeLocator();
    final coordinator = TabDragCoordinator(locator: locator);
    final source = _FakeWindow(11, events: events);
    final tab = DocumentTab.error(title: 'dragged.pdf', error: 'fixture');
    source.tabs.add(tab);
    coordinator.register(source);

    final token = coordinator.begin(source, tab, () => _handoff());
    final result = await coordinator.finish(
      token,
      userCancelled: false,
    );

    expect(result, TabDragResult.openedNewWindow);
    expect(events, ['open', 'remove', 'close']);
    expect(source.newWindows, 1);
    expect(source.tabs, isEmpty);
    expect(source.closeRequests, 1);
    coordinator.dispose();
  });

  test('drop off a tab strip opens a new window and failures retain source',
      () async {
    final locator = _FakeLocator();
    final coordinator = TabDragCoordinator(locator: locator);
    final source = _FakeWindow(11)..acceptNewWindow = false;
    final target = _FakeWindow(22)..insertionIndex = null;
    final tab = DocumentTab.error(title: 'dragged.pdf', error: 'fixture');
    source.tabs.add(tab);
    coordinator
      ..register(source)
      ..register(target);

    var token = coordinator.begin(source, tab, () => _handoff());
    expect(
      await coordinator.finish(
        token,
        userCancelled: false,
      ),
      TabDragResult.failed,
    );
    expect(source.tabs, [same(tab)]);

    source.acceptNewWindow = true;
    locator.location = const TabDropLocation(
      windowHandle: 22,
      localPoint: Offset(300, 500),
    );
    token = coordinator.begin(source, tab, () => _handoff());
    expect(
      await coordinator.finish(
        token,
        userCancelled: false,
      ),
      TabDragResult.openedNewWindow,
    );
    expect(source.tabs, isEmpty);
    expect(source.newWindows, 1);
    expect(source.closeRequests, 1);
    coordinator.dispose();
  });

  test('live preview distinguishes tab strips from detached drops', () async {
    final locator = _FakeLocator()
      ..location = const TabDropLocation(
        windowHandle: 22,
        localPoint: Offset(80, 20),
      );
    final coordinator = TabDragCoordinator(locator: locator);
    final source = _FakeWindow(11);
    final target = _FakeWindow(22)..insertionIndex = 1;
    final tab = DocumentTab.error(title: 'dragged.pdf', error: 'fixture');
    source.tabs.add(tab);
    coordinator
      ..register(source)
      ..register(target);

    final token = coordinator.begin(source, tab, () => _handoff());
    coordinator.update(token);
    await pumpEventQueue();
    expect(coordinator.previewFor(tab)?.isOverTabStrip, isTrue);
    expect(coordinator.preview?.targetWindowHandle, 22);
    expect(coordinator.insertionIndexFor(22), 1);

    target.insertionIndex = null;
    locator.location = const TabDropLocation(
      windowHandle: 22,
      localPoint: Offset(80, 400),
    );
    coordinator.update(token);
    await pumpEventQueue();
    expect(coordinator.previewFor(tab)?.isOverTabStrip, isFalse);
    expect(coordinator.preview?.targetWindowHandle, isNull);
    expect(coordinator.insertionIndexFor(22), isNull);

    coordinator.cancel(token);
    expect(coordinator.preview, isNull);
    coordinator.dispose();
  });

  test('native locator failure retains the source tab', () async {
    final locator = _FakeLocator()..failure = StateError('channel failed');
    final coordinator = TabDragCoordinator(locator: locator);
    final source = _FakeWindow(11);
    final tab = DocumentTab.error(title: 'dragged.pdf', error: 'fixture');
    source.tabs.add(tab);
    coordinator.register(source);

    final token = coordinator.begin(source, tab, () => _handoff());
    expect(
      await coordinator.finish(
        token,
        userCancelled: false,
      ),
      TabDragResult.failed,
    );
    expect(source.tabs, [same(tab)]);
    expect(source.newWindows, 0);
    coordinator.dispose();
  });

  test('handoff is captured at drop time and a snapshot failure is safe',
      () async {
    final locator = _FakeLocator()
      ..location = const TabDropLocation(
        windowHandle: 22,
        localPoint: Offset(80, 20),
      );
    final coordinator = TabDragCoordinator(locator: locator);
    final source = _FakeWindow(11);
    final target = _FakeWindow(22);
    final tab = DocumentTab.error(title: 'dragged.pdf', error: 'fixture');
    source.tabs.add(tab);
    coordinator
      ..register(source)
      ..register(target);

    var latest = _handoff('before.pdf');
    var token = coordinator.begin(source, tab, () => latest);
    latest = _handoff('after.pdf');
    expect(
      await coordinator.finish(
        token,
        userCancelled: false,
      ),
      TabDragResult.movedToWindow,
    );
    expect(target.inserted.single.title, 'after.pdf');

    source.tabs.add(tab);
    token = coordinator.begin(
      source,
      tab,
      () => throw StateError('snapshot failed'),
    );
    expect(
      await coordinator.finish(
        token,
        userCancelled: false,
      ),
      TabDragResult.failed,
    );
    expect(source.tabs, [same(tab)]);
    expect(target.inserted, hasLength(1));
    coordinator.dispose();
  });

  test('Escape and duplicate completion are side-effect free', () async {
    final locator = _FakeLocator();
    final coordinator = TabDragCoordinator(locator: locator);
    final source = _FakeWindow(11);
    final tab = DocumentTab.error(title: 'dragged.pdf', error: 'fixture');
    source.tabs.add(tab);
    coordinator.register(source);

    final token = coordinator.begin(source, tab, () => _handoff());
    expect(
      await coordinator.finish(
        token,
        userCancelled: true,
      ),
      TabDragResult.cancelled,
    );
    expect(locator.calls, 0);
    expect(source.tabs, [same(tab)]);

    expect(
      await coordinator.finish(
        token,
        userCancelled: false,
      ),
      TabDragResult.cancelled,
    );
    expect(source.newWindows, 0);
    coordinator.dispose();
  });
}
