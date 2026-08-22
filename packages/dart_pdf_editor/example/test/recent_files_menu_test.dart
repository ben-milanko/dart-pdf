import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_viewer_example/main.dart';
import 'package:pdf_viewer_example/recent_files.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Uint8List doc(int seed) =>
      Uint8List.fromList(List.generate(64, (i) => (seed * 31 + i) & 0xff));

  Future<void> openAppMenu(WidgetTester tester) async {
    await tester.tap(find.byTooltip('DartPDF menu'));
    await tester.pumpAndSettle();
  }

  Future<void> openRecentsSubmenu(WidgetTester tester) async {
    await openAppMenu(tester);
    await tester.tap(find.text('Open Recent'));
    await tester.pumpAndSettle();
  }

  String shortcut(String key, {bool shift = false}) {
    final apple = defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.iOS;
    return apple
        ? '${shift ? '⇧' : ''}⌘$key'
        : 'Ctrl+${shift ? 'Shift+' : ''}$key';
  }

  testWidgets('open recent lives behind a submenu, not inline', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final backend = PdfMemoryCacheStore();
    final seed = RecentFilesStore(backend);
    await seed.record('alpha.pdf', doc(1));
    await seed.record('beta.pdf', doc(2));

    await tester.pumpWidget(ViewerApp(cacheStore: backend));
    // use-deferred-loading makes the localizations delegate load async; settle
    // so the localized app (and its post-frame demo open) builds.
    await tester.pumpAndSettle();

    await openAppMenu(tester);
    // the parent menu only shows the "Open Recent" row; the files
    // themselves stay hidden until the submenu is opened
    expect(find.text('Open Recent'), findsOneWidget);
    expect(find.text('alpha.pdf'), findsNothing);
    expect(find.text('beta.pdf'), findsNothing);

    await tester.tap(find.text('Open Recent'));
    await tester.pumpAndSettle();
    expect(find.text('View all recent files…'), findsOneWidget);
    expect(find.text('alpha.pdf'), findsOneWidget);
    expect(find.text('beta.pdf'), findsOneWidget);
    expect(find.text('Clear recent files'), findsOneWidget);
  });

  testWidgets('app menu shows shortcut labels', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final backend = PdfMemoryCacheStore();
    final seed = RecentFilesStore(backend);
    await seed.record('alpha.pdf', doc(1));

    await tester.pumpWidget(ViewerApp(cacheStore: backend));
    // use-deferred-loading makes the localizations delegate load async; settle
    // so the localized app (and its post-frame demo open) builds.
    await tester.pumpAndSettle();

    await openAppMenu(tester);
    expect(find.text(shortcut('S')), findsOneWidget);
    expect(find.text(shortcut('O')), findsOneWidget);
    expect(find.text(shortcut('O', shift: true)), findsOneWidget);
  });

  testWidgets('app menu includes a feedback link', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(ViewerApp(cacheStore: PdfMemoryCacheStore()));
    // use-deferred-loading makes the localizations delegate load async; settle
    // so the localized app builds before opening the menu.
    await tester.pumpAndSettle();

    await openAppMenu(tester);
    expect(find.text('Supply feedback…'), findsOneWidget);
  });

  testWidgets('files already open in a tab are excluded from recents',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final backend = PdfMemoryCacheStore();
    final seed = RecentFilesStore(backend);
    // 'Feature showcase' is the demo tab the app opens on launch
    await seed.record('Feature showcase', doc(1));
    await seed.record('alpha.pdf', doc(2));

    await tester.pumpWidget(ViewerApp(cacheStore: backend));
    // use-deferred-loading makes the localizations delegate load async; settle
    // so the localized app (and its post-frame demo open) builds.
    await tester.pumpAndSettle();

    // the demo title shows once, in the tab strip
    expect(find.text('Feature showcase'), findsOneWidget);

    await openRecentsSubmenu(tester);
    // the closed file is offered…
    expect(find.text('alpha.pdf'), findsOneWidget);
    // …but the open demo isn't added to the submenu (still just the tab)
    expect(find.text('Feature showcase'), findsOneWidget);
  });

  testWidgets('clearing recents leaves an empty open recent row',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final backend = PdfMemoryCacheStore();
    final seed = RecentFilesStore(backend);
    await seed.record('alpha.pdf', doc(1));

    await tester.pumpWidget(ViewerApp(cacheStore: backend));
    // use-deferred-loading makes the localizations delegate load async; settle
    // so the localized app (and its post-frame demo open) builds.
    await tester.pumpAndSettle();

    await openRecentsSubmenu(tester);
    await tester.tap(find.text('Clear recent files'));
    await tester.pumpAndSettle();

    await openAppMenu(tester);
    expect(find.text('Open Recent'), findsOneWidget);
    expect(find.text('alpha.pdf'), findsNothing);
    expect(find.text('Clear recent files'), findsNothing);
  });

  testWidgets('with no recents the Open Recent row is still visible',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(ViewerApp(cacheStore: PdfMemoryCacheStore()));
    // use-deferred-loading makes the localizations delegate load async; settle
    // so the localized app builds before opening the menu.
    await tester.pumpAndSettle();

    await openAppMenu(tester);
    expect(find.text('Open Recent'), findsOneWidget);
    expect(find.text('Clear recent files'), findsNothing);
  });

  testWidgets('full recent browser exposes all files and searches them',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final backend = PdfMemoryCacheStore();
    final seed = RecentFilesStore(backend);
    for (var i = 0; i < 10; i++) {
      await seed.record('Report-$i.pdf', doc(i + 1));
    }

    await tester.pumpWidget(ViewerApp(cacheStore: backend));
    await tester.pumpAndSettle();

    await openRecentsSubmenu(tester);
    // The oldest files remain out of the eight-row quick-open section.
    expect(find.text('Report-0.pdf'), findsNothing);

    await tester.tap(find.text('View all recent files…'));
    await tester.pumpAndSettle();
    expect(find.text('Recent files'), findsOneWidget);
    expect(find.byKey(const ValueKey('recent-files-grid')), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('recent-files-search')),
      'rEpOrT-0',
    );
    await tester.pump();
    expect(find.text('Report-0.pdf'), findsOneWidget);
    expect(find.text('Report-9.pdf'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('recent-files-list-view')));
    await tester.pump();
    expect(find.byKey(const ValueKey('recent-files-list')), findsOneWidget);
    expect(find.text('Report-0.pdf'), findsOneWidget);
  });

  testWidgets('recent search shows a no-match state and can be cleared',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final backend = PdfMemoryCacheStore();
    final seed = RecentFilesStore(backend);
    await seed.record('alpha.pdf', doc(1));

    await tester.pumpWidget(ViewerApp(cacheStore: backend));
    await tester.pumpAndSettle();
    await openRecentsSubmenu(tester);
    await tester.tap(find.text('View all recent files…'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('recent-files-search')),
      'missing',
    );
    await tester.pump();
    expect(find.text('No recent files match your search'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('recent-files-search-clear')),
    );
    await tester.pump();
    expect(find.text('alpha.pdf'), findsOneWidget);
  });
}
