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
    await tester.pump();
    await tester.pump();

    await openAppMenu(tester);
    // the parent menu only shows the "Open Recent" row; the files
    // themselves stay hidden until the submenu is opened
    expect(find.text('Open Recent'), findsOneWidget);
    expect(find.text('alpha.pdf'), findsNothing);
    expect(find.text('beta.pdf'), findsNothing);

    await tester.tap(find.text('Open Recent'));
    await tester.pumpAndSettle();
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
    await tester.pump();
    await tester.pump();

    await openAppMenu(tester);
    expect(find.text(shortcut('S')), findsOneWidget);
    expect(find.text(shortcut('O')), findsOneWidget);
    expect(find.text(shortcut('O', shift: true)), findsOneWidget);
  });

  testWidgets('app menu includes a feedback link', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(ViewerApp(cacheStore: PdfMemoryCacheStore()));
    await tester.pump();

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
    await tester.pump();
    await tester.pump();

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
    await tester.pump();
    await tester.pump();

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
    await tester.pump();

    await openAppMenu(tester);
    expect(find.text('Open Recent'), findsOneWidget);
    expect(find.text('Clear recent files'), findsNothing);
  });
}
