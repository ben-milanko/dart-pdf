import 'dart:convert';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dart_pdf_editor_app/editor_screen.dart';

import 'test_finders.dart';

void main() {
  late PdfEditingPreferences prefs;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    prefs = PdfEditingPreferences();
  });

  tearDown(() => prefs.dispose());

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(home: EditorScreen(prefs: prefs)));
    await tester.pump();
    await tester.pump();
  }

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

  void seedRecents() {
    SharedPreferences.setMockInitialValues({
      'dart_pdf_editor_app.recents': jsonEncode([
        {
          't': 'alpha.pdf',
          'p': '/docs/alpha.pdf',
          'o': 2000,
        },
        {
          't': 'beta.pdf',
          'p': '/docs/beta.pdf',
          'o': 1000,
        },
      ]),
    });
  }

  testWidgets(
    'app menu and recent submenu use compact rows on desktop',
    (tester) async {
      seedRecents();
      await pumpApp(tester);

      await openAppMenu(tester);
      final newItemFinder = find.byKey(const ValueKey('menu-new-document'));
      final newItem = tester.widget<PopupMenuItem<dynamic>>(newItemFinder);
      final newTileFinder = find.descendant(
        of: newItemFinder,
        matching: find.byType(ListTile),
      );
      final newTile = tester.widget<ListTile>(newTileFinder);
      expect(newItem.height, 36);
      expect(newTile.minTileHeight, 36);
      final openItemFinder = find.byKey(const ValueKey('menu-open'));
      expect(
        tester.getCenter(openItemFinder).dy -
            tester.getCenter(newItemFinder).dy,
        lessThan(kMinInteractiveDimension),
      );

      await tester.tap(find.text('Open Recent'));
      await tester.pumpAndSettle();
      final recentItemFinder = find.ancestor(
        of: findMiddleEllipsisText('alpha.pdf'),
        matching: find.byType(PopupMenuItem<VoidCallback>),
      );
      final recentItem = tester.widget<PopupMenuItem<VoidCallback>>(
        recentItemFinder,
      );
      final recentTileFinder = find.descendant(
        of: recentItemFinder,
        matching: find.byType(ListTile),
      );
      final recentTile = tester.widget<ListTile>(recentTileFinder);
      expect(recentItem.height, 48);
      expect(recentTile.minTileHeight, 48);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'app menu keeps touch-sized rows on mobile',
    (tester) async {
      await pumpApp(tester);

      await openAppMenu(tester);
      final itemFinder = find.byKey(const ValueKey('menu-new-document'));
      final item = tester.widget<PopupMenuItem<dynamic>>(itemFinder);
      final tile = tester.widget<ListTile>(
        find.descendant(of: itemFinder, matching: find.byType(ListTile)),
      );
      expect(item.height, kMinInteractiveDimension);
      expect(tile.minTileHeight, isNull);
      expect(
        tester.getSize(itemFinder).height,
        greaterThanOrEqualTo(kMinInteractiveDimension),
      );
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets('DartPDF menu shows Open and Open Recent entries',
      (tester) async {
    seedRecents();
    await pumpApp(tester);

    await openAppMenu(tester);

    expect(find.byKey(const ValueKey('menu-open')), findsOneWidget);
    expect(find.text('Open a PDF…'), findsOneWidget);
    expect(find.byKey(const ValueKey('open-recent-submenu')), findsOneWidget);
    expect(find.text('Open Recent'), findsOneWidget);
    expect(find.text(shortcut('O')), findsOneWidget);
    expect(find.text(shortcut('O', shift: true)), findsOneWidget);

    await tester.tap(find.text('Open Recent'));
    await tester.pumpAndSettle();

    expect(findMiddleEllipsisText('alpha.pdf'), findsWidgets);
    expect(findMiddleEllipsisText('beta.pdf'), findsWidgets);
    expect(
      find.byKey(const ValueKey('view-all-recent-files')),
      findsOneWidget,
    );
    expect(find.text('Clear recent files'), findsWidgets);
  });

  testWidgets('Open Recent opens the full searchable recent-files browser',
      (tester) async {
    seedRecents();
    await pumpApp(tester);

    await openRecentsSubmenu(tester);
    await tester.tap(find.byKey(const ValueKey('view-all-recent-files')));
    await tester.pumpAndSettle();

    expect(find.text('Recent files'), findsOneWidget);
    final search = find.byKey(const ValueKey('recent-files-search'));
    expect(search, findsOneWidget);

    await tester.enterText(search, 'BETA');
    await tester.pump();

    expect(find.byKey(const ValueKey('recent-tile-/docs/beta.pdf')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('recent-tile-/docs/alpha.pdf')),
        findsNothing);
  });

  testWidgets('Open Recent stays visible when there are no recent files',
      (tester) async {
    await pumpApp(tester);

    await openRecentsSubmenu(tester);

    expect(find.text('Open Recent'), findsOneWidget);
    expect(find.text('No recent files'), findsOneWidget);
    expect(find.byKey(const ValueKey('view-all-recent-files')), findsOneWidget);
    expect(find.text('Clear recent files'), findsNothing);
  });
}
