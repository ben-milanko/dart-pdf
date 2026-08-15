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
    await tester.pumpWidget(DartPdfNativeWindowScope(
      windowHandle: 22,
      child: MaterialApp(
        home: EditorScreen(
          prefs: prefs,
          tabDragCoordinator: coordinator,
          onNewWindow: (_, {document}) => true,
          ownsApplicationSession: false,
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
      localPoint: tester.getCenter(find.descendant(
        of: find.byKey(const ValueKey('tab-strip')),
        matching: find.text('dragged.pdf'),
      )),
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

    // Exercise the actual pointer source, not just the coordinator. This is
    // the regression for native drag plugins binding to the bootstrap view
    // instead of the engine-owned window that contains this tab.
    final compactLabel = find.descendant(
      of: find.byKey(const ValueKey('tab-strip')),
      matching: find.text('compact.pdf'),
    );
    final callsBeforeDrag = locator.calls;
    locator.location = TabDropLocation(
      windowHandle: 22,
      localPoint: tester.getCenter(compactLabel),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(compactLabel),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveBy(const Offset(-80, 0));
    await tester.pump();
    await gesture.up();
    await tester.pump();
    expect(locator.calls, callsBeforeDrag + 1);

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
    expect(events, ['insert', 'remove']);
    expect(target.inserted, [same(handoff)]);
    expect(source.tabs, isEmpty);
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
    expect(events, ['open', 'remove']);
    expect(source.newWindows, 1);
    expect(source.tabs, isEmpty);
    coordinator.dispose();
  });

  test('failed new window and drop below another tab strip retain source',
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
      TabDragResult.cancelled,
    );
    expect(source.tabs, [same(tab)]);
    expect(source.newWindows, 0);
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
