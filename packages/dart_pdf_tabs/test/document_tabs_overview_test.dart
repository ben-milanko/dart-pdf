import 'package:dart_pdf_tabs/dart_pdf_tabs.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

class _Overview extends StatefulWidget {
  const _Overview({required this.titles, this.onShare});

  final List<String> titles;
  final Future<void> Function(List<String> tabs)? onShare;

  @override
  State<_Overview> createState() => _OverviewState();
}

class _OverviewState extends State<_Overview> {
  late final List<String> tabs = [...widget.titles];
  int active = 0;
  int opens = 0;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: DocumentTabsOverview<String>(
          tabs: tabs,
          activeIndex: active,
          titleOf: (tab) => tab,
          onActivate: (i) => setState(() => active = i),
          onOpen: () => opens++,
          shareLabel: widget.onShare == null ? null : 'Share',
          shareIcon: widget.onShare == null ? null : Icons.share,
          onShare: widget.onShare,
          onCloseTabs: (closing) async =>
              setState(() => tabs.removeWhere(closing.contains)),
          tileBuilder: (context, index, selection) => DocumentTabTile(
            key: ValueKey(tabs[index]),
            title: tabs[index],
            selected: index == active,
            selection: selection,
            onTap: () => setState(() => active = index),
            onClose: () => setState(() => tabs.removeAt(index)),
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

void main() {
  testWidgets('search filters tiles; Enter activates the first match', (
    tester,
  ) async {
    await tester.pumpWidget(
      const _Overview(titles: ['alpha.pdf', 'beta.pdf', 'gamma.pdf']),
    );
    expect(find.byType(DocumentTabTile), findsNWidgets(3));
    expect(find.text('3 tabs open'), findsOneWidget);

    await tester.enterText(
        find.byKey(const ValueKey('tabs-tabs-search')), 'ga');
    await tester.pump();
    expect(find.byType(DocumentTabTile), findsOneWidget);

    await tester.testTextInput.receiveAction(TextInputAction.go);
    await tester.pump();
    expect(tester.state<_OverviewState>(find.byType(_Overview)).active, 2);

    await tester.enterText(
        find.byKey(const ValueKey('tabs-tabs-search')), 'zz');
    await tester.pump();
    expect(find.byKey(const ValueKey('tabs-tabs-no-matches')), findsOneWidget);
  });

  testWidgets('select, check and close several tabs together', (
    tester,
  ) async {
    final shared = <String>[];
    await tester.pumpWidget(
      _Overview(
        titles: const ['a', 'b', 'c'],
        onShare: (tabs) async => shared.addAll(tabs),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('tabs-tabs-select')));
    await tester.pump();
    expect(find.byKey(const ValueKey('mobile-tab-tile-checkbox')),
        findsNWidgets(3));

    await tester.tap(_label('a'));
    await tester.tap(_label('c'));
    await tester.pump();
    expect(find.text('2 items selected'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('tabs-tabs-share-selected')));
    await tester.pump();
    expect(shared, ['a', 'c']);

    await tester.tap(find.byKey(const ValueKey('tabs-tabs-close-selected')));
    await tester.pumpAndSettle();
    expect(find.byType(DocumentTabTile), findsOneWidget);
    expect(_label('b'), findsOneWidget);
  });

  testWidgets('the share action is hidden without a handler', (tester) async {
    await tester.pumpWidget(const _Overview(titles: ['a']));
    await tester.tap(find.byKey(const ValueKey('tabs-tabs-select')));
    await tester.pump();
    expect(
        find.byKey(const ValueKey('tabs-tabs-share-selected')), findsNothing);
  });

  testWidgets('the add button calls back', (tester) async {
    await tester.pumpWidget(const _Overview(titles: ['a']));
    await tester.tap(find.byKey(const ValueKey('tabs-tabs-open')));
    expect(tester.state<_OverviewState>(find.byType(_Overview)).opens, 1);
  });

  testWidgets('DocumentTabsButton badges the count', (tester) async {
    var pressed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DocumentTabsButton(count: 4, onPressed: () => pressed = true),
        ),
      ),
    );
    expect(find.text('4'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('mobile-tabs-button')));
    expect(pressed, isTrue);
  });
}
