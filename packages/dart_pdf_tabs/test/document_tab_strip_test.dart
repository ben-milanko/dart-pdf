import 'package:dart_pdf_tabs/dart_pdf_tabs.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

class _Tab with DocumentTabEntry {
  _Tab(this.title, {this.dirty = false});

  @override
  final String title;
  bool dirty;
}

class _Host extends StatefulWidget {
  const _Host({required this.tabs, this.width = 800, this.onContextMenu});

  final DocumentTabs<_Tab> tabs;
  final double width;
  final void Function(int index, Offset position)? onContextMenu;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  final controller = DocumentTabStripController();
  int adds = 0;
  int showAlls = 0;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: widget.width,
            child: ListenableBuilder(
              listenable: widget.tabs,
              builder: (context, _) => DocumentTabStrip<_Tab>(
                tabs: widget.tabs.tabs,
                activeIndex: widget.tabs.activeIndex,
                controller: controller,
                titleOf: (tab) => tab.title,
                isDirtyOf: (tab) => tab.dirty,
                onActivate: widget.tabs.activate,
                onClose: (i) {
                  controller.holdWidthForClose();
                  widget.tabs.remove([widget.tabs[i]]);
                },
                onReorder: widget.tabs.reorder,
                onContextMenu: widget.onContextMenu,
                onAdd: () => adds++,
                onShowAll: () => showAlls++,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Finds a [MiddleEllipsisText] by its full value (it paints, not a Text).
Finder _label(String value) => find.byWidgetPredicate(
      (widget) => widget is MiddleEllipsisText && widget.data == value,
    );

DocumentTabs<_Tab> _tabs(List<String> titles) {
  final tabs = DocumentTabs<_Tab>(afterFrame: (callback) => callback());
  for (final title in titles) {
    tabs.add(_Tab(title));
  }
  return tabs;
}

double _tabWidth(WidgetTester tester, String title) => tester
    .getSize(find
        .ancestor(
          of: _label(title),
          matching: find.byType(AnimatedContainer),
        )
        .first)
    .width;

void main() {
  test('tabs share the strip equally between the min and max width', () {
    const metrics = DocumentTabStripMetrics();
    expect(metrics.tabWidthFor(1000, 2), 240);
    expect(metrics.tabWidthFor(600, 4), 150);
    expect(metrics.tabWidthFor(300, 20), 56);
    expect(metrics.tabWidthFor(300, 0), 0);
  });

  testWidgets('draws every tab, hiding .pdf, and taps activate', (
    tester,
  ) async {
    final tabs = _tabs(['first.pdf', 'second.pdf']);
    await tester.pumpWidget(_Host(tabs: tabs));

    expect(_label('first.pdf'), findsOneWidget);
    expect(_label('second.pdf'), findsOneWidget);
    expect(tabs.activeIndex, 1);

    await tester.tap(_label('first.pdf'));
    await tester.pump();
    expect(tabs.activeIndex, 0);
  });

  testWidgets('an empty title reads as untitled; a dirty tab shows a dot', (
    tester,
  ) async {
    final tabs = DocumentTabs<_Tab>()..add(_Tab('', dirty: true));
    await tester.pumpWidget(_Host(tabs: tabs));

    expect(_label('Untitled'), findsOneWidget);
    expect(find.byIcon(Icons.circle), findsOneWidget);
  });

  testWidgets('narrow inactive tabs drop their close button', (tester) async {
    final tabs = _tabs([for (var i = 0; i < 8; i++) 'tab $i']);
    await tester.pumpWidget(_Host(tabs: tabs, width: 600));
    await tester.pumpAndSettle();

    // Eight tabs in 520px are ~64px each: only the active one keeps a close.
    expect(find.byTooltip('Close tab'), findsOneWidget);
    expect(find.byKey(const ValueKey('tab-close-7')), findsOneWidget);
  });

  testWidgets('add and view-all buttons call back', (tester) async {
    final tabs = _tabs(['a']);
    await tester.pumpWidget(_Host(tabs: tabs));
    final state = tester.state<_HostState>(find.byType(_Host));

    await tester.tap(find.byKey(const ValueKey('desktop-tab-add-button')));
    await tester.tap(find.byKey(const ValueKey('desktop-tabs-button')));
    expect(state.adds, 1);
    expect(state.showAlls, 1);
  });

  testWidgets('closing while hovered holds the width until the pointer leaves',
      (tester) async {
    final tabs = _tabs([for (var i = 0; i < 6; i++) 'tab $i']);
    await tester.pumpWidget(_Host(tabs: tabs, width: 600));
    await tester.pumpAndSettle();
    final before = _tabWidth(tester, 'tab 0');

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: tester.getCenter(_label('tab 0')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('tab-close-5')));
    await tester.pumpAndSettle();
    expect(tabs.length, 5);
    expect(_tabWidth(tester, 'tab 0'), before);

    await mouse.moveTo(const Offset(5, 400));
    await tester.pumpAndSettle();
    expect(_tabWidth(tester, 'tab 0'), greaterThan(before));
    await mouse.removePointer();
  });

  testWidgets('a secondary click opens the context menu, never a drag', (
    tester,
  ) async {
    final tabs = _tabs(['a', 'b']);
    int? menuIndex;
    await tester.pumpWidget(
      _Host(tabs: tabs, onContextMenu: (i, _) => menuIndex = i),
    );

    await tester.tap(_label('a'), buttons: kSecondaryButton);
    await tester.pump();
    expect(menuIndex, 0);
  });

  testWidgets('drag reorder moves a tab and keeps the active one active', (
    tester,
  ) async {
    final tabs = _tabs(['a', 'b', 'c']);
    await tester.pumpWidget(_Host(tabs: tabs));
    expect(tabs.active!.title, 'c');

    final mouse = await tester.startGesture(
      tester.getCenter(_label('a')),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    for (var i = 0; i < 14; i++) {
      await mouse.moveBy(const Offset(50, 0));
      await tester.pump();
    }
    await mouse.up();
    await tester.pumpAndSettle();

    expect([for (final tab in tabs.tabs) tab.title], ['b', 'c', 'a']);
    expect(tabs.active!.title, 'c');
  });

  testWidgets('insertionIndexAt maps a strip offset to a slot', (
    tester,
  ) async {
    final tabs = _tabs(['a', 'b', 'c']);
    await tester.pumpWidget(_Host(tabs: tabs));
    final controller = tester.state<_HostState>(find.byType(_Host)).controller;

    // 720px for the list (800 less the two buttons), less 8px padding, / 3.
    expect(controller.renderedTabWidth, closeTo(237.3, 0.1));
    expect(controller.insertionIndexAt(-5, 3), 0);
    expect(controller.insertionIndexAt(4 + 100, 3), 0);
    expect(controller.insertionIndexAt(4 + 200, 3), 1);
    expect(controller.insertionIndexAt(4 + 700, 3), 3);
    expect(controller.insertionIndexAt(5000, 3), 3);
    expect(controller.insertionIndexAt(4 + 300, 3, externalGap: 1), 1);
    expect(controller.insertionIndexAt(0, 0), 0);
  });

  testWidgets('tab fills can be overridden', (tester) async {
    final tabs = _tabs(['a', 'b']);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DocumentTabStrip<_Tab>(
            tabs: tabs.tabs,
            activeIndex: tabs.activeIndex,
            controller: DocumentTabStripController(),
            titleOf: (tab) => tab.title,
            onActivate: tabs.activate,
            onClose: (_) {},
            onReorder: tabs.reorder,
            activeTabColor: Colors.red,
            tabColor: Colors.blue,
          ),
        ),
      ),
    );
    Color fillOf(String title) => tester
        .widget<Material>(find
            .ancestor(of: _label(title), matching: find.byType(Material))
            .first)
        .color!;
    expect(fillOf('a'), Colors.blue);
    expect(fillOf('b'), Colors.red);
  });
}
