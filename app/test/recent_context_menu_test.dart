import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind, kSecondaryButton;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dart_pdf_editor_app/recents.dart';
import 'package:dart_pdf_editor_app/welcome_screen.dart';

/// The recents context menu: right-click on desktop, long-press on touch,
/// offered by both layouts (list rows and grid tiles).
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  const wide = Size(1000, 800); // defaults to the grid
  const narrow = Size(420, 800); // defaults to the list

  Future<void> pump(
    WidgetTester tester,
    WelcomeScreen screen, {
    Size size = narrow,
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: screen)));
    await tester.pump();
  }

  Future<void> rightClick(WidgetTester tester, Finder target) async {
    final gesture = await tester.startGesture(
      tester.getCenter(target),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryButton,
    );
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
  }

  Finder listRow(String id) => find.byKey(ValueKey('recent-$id'));
  Finder gridTile(String id) => find.byKey(ValueKey('recent-tile-$id'));

  testWidgets('a right-click on a list row opens the entry menu',
      (tester) async {
    final store = RecentsStore();
    await store.add(title: 'a.pdf', path: '/docs/a.pdf');

    await pump(
        tester,
        WelcomeScreen(
          recents: store,
          onOpen: () {},
          onOpenRecent: (_) {},
        ));

    await rightClick(tester, listRow('/docs/a.pdf'));

    expect(find.byKey(const ValueKey('recent-menu-open')), findsOneWidget);
    expect(find.byKey(const ValueKey('recent-menu-copy-path')), findsOneWidget);
    expect(find.byKey(const ValueKey('recent-menu-copy-name')), findsOneWidget);
    expect(find.byKey(const ValueKey('recent-menu-remove')), findsOneWidget);
    expect(find.byKey(const ValueKey('recent-menu-clear')), findsOneWidget);
    // No multi-window host here, and no folder support on this platform.
    expect(find.byKey(const ValueKey('recent-menu-new-window')), findsNothing);
    expect(find.byKey(const ValueKey('recent-menu-open-folder')), findsNothing);
  });

  testWidgets('a long-press on a grid tile opens the entry menu',
      (tester) async {
    final store = RecentsStore();
    await store.add(title: 'a.pdf', path: '/docs/a.pdf');

    await pump(
        tester,
        size: wide,
        WelcomeScreen(
          recents: store,
          onOpen: () {},
          onOpenRecent: (_) {},
        ));

    // The tile's tooltip owns a long-press of its own; the menu must win it.
    await tester.longPress(gridTile('/docs/a.pdf'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('recent-menu-open')), findsOneWidget);
  });

  testWidgets('Open runs the open callback', (tester) async {
    final store = RecentsStore();
    await store.add(title: 'a.pdf', path: '/docs/a.pdf');
    RecentFile? opened;

    await pump(
        tester,
        WelcomeScreen(
          recents: store,
          onOpen: () {},
          onOpenRecent: (entry) => opened = entry,
        ));

    await rightClick(tester, listRow('/docs/a.pdf'));
    await tester.tap(find.byKey(const ValueKey('recent-menu-open')));
    await tester.pumpAndSettle();

    expect(opened?.id, '/docs/a.pdf');
  });

  testWidgets('Open is disabled for an entry that cannot be reopened',
      (tester) async {
    final store = RecentsStore();
    // No path and no snapshot (a web pick): nothing to reopen from.
    await store.add(title: 'web.pdf');
    var opened = false;

    await pump(
        tester,
        WelcomeScreen(
          recents: store,
          onOpen: () {},
          onOpenRecent: (_) => opened = true,
        ));

    await rightClick(tester, listRow('web.pdf'));

    final item = tester.widget<PopupMenuItem<dynamic>>(
        find.byKey(const ValueKey('recent-menu-open')));
    expect(item.enabled, isFalse);
    // Without a path there is nothing to copy as one, but the name still is.
    expect(find.byKey(const ValueKey('recent-menu-copy-path')), findsNothing);
    expect(find.byKey(const ValueKey('recent-menu-copy-name')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('recent-menu-open')));
    await tester.pumpAndSettle();
    expect(opened, isFalse);
  });

  testWidgets('Open in new window shows only with a multi-window host',
      (tester) async {
    final store = RecentsStore();
    await store.add(title: 'a.pdf', path: '/docs/a.pdf');
    RecentFile? movedOut;

    await pump(
        tester,
        WelcomeScreen(
          recents: store,
          onOpen: () {},
          onOpenRecent: (_) {},
          onOpenRecentInNewWindow: (entry) => movedOut = entry,
        ));

    await rightClick(tester, listRow('/docs/a.pdf'));
    await tester.tap(find.byKey(const ValueKey('recent-menu-new-window')));
    await tester.pumpAndSettle();

    expect(movedOut?.id, '/docs/a.pdf');
  });

  testWidgets('Copy path and Copy name write to the clipboard', (tester) async {
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add((call.arguments as Map)['text'] as String);
        }
        return null;
      },
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));

    final store = RecentsStore();
    await store.add(title: 'a.pdf', path: '/docs/a.pdf');

    await pump(
        tester,
        WelcomeScreen(
          recents: store,
          onOpen: () {},
          onOpenRecent: (_) {},
        ));

    await rightClick(tester, listRow('/docs/a.pdf'));
    await tester.tap(find.byKey(const ValueKey('recent-menu-copy-path')));
    await tester.pumpAndSettle();

    await rightClick(tester, listRow('/docs/a.pdf'));
    await tester.tap(find.byKey(const ValueKey('recent-menu-copy-name')));
    await tester.pumpAndSettle();

    expect(copied, ['/docs/a.pdf', 'a.pdf']);
    expect(find.text('Copied to clipboard'), findsOneWidget);
  });

  testWidgets('Remove drops just that entry; Clear drops them all',
      (tester) async {
    final store = RecentsStore();
    await store.add(title: 'a.pdf', path: '/docs/a.pdf');
    await store.add(title: 'b.pdf', path: '/docs/b.pdf');

    await pump(
        tester,
        WelcomeScreen(
          recents: store,
          onOpen: () {},
          onOpenRecent: (_) {},
        ));

    await rightClick(tester, listRow('/docs/a.pdf'));
    await tester.tap(find.byKey(const ValueKey('recent-menu-remove')));
    await tester.pumpAndSettle();

    expect(store.items.map((e) => e.id), ['/docs/b.pdf']);

    await rightClick(tester, listRow('/docs/b.pdf'));
    await tester.tap(find.byKey(const ValueKey('recent-menu-clear')));
    await tester.pumpAndSettle();

    expect(store.items, isEmpty);
  });

  testWidgets('desktop offers the containing folder for a real path',
      (tester) async {
    final store = RecentsStore();
    await store.add(title: 'a.pdf', path: '/docs/a.pdf');

    await pump(
        tester,
        WelcomeScreen(
          recents: store,
          onOpen: () {},
          onOpenRecent: (_) {},
        ));

    await rightClick(tester, listRow('/docs/a.pdf'));

    expect(
        find.byKey(const ValueKey('recent-menu-open-folder')), findsOneWidget);
    expect(find.text('Open in Finder'), findsOneWidget);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('the menu is also reachable from the recent-files browser',
      (tester) async {
    final store = RecentsStore();
    await store.add(title: 'a.pdf', path: '/docs/a.pdf');

    await tester.binding.setSurfaceSize(narrow);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      home: RecentFilesScreen(recents: store, onOpenRecent: (_) {}),
    ));
    await tester.pump();

    await rightClick(tester, listRow('/docs/a.pdf'));

    expect(find.byKey(const ValueKey('recent-menu-open')), findsOneWidget);
  });

  testWidgets('menu rows stay tight on desktop and tappable on touch',
      (tester) async {
    final store = RecentsStore();
    await store.add(title: 'a.pdf', path: '/docs/a.pdf');

    await pump(
        tester,
        WelcomeScreen(
          recents: store,
          onOpen: () {},
          onOpenRecent: (_) {},
        ));

    await rightClick(tester, listRow('/docs/a.pdf'));

    final item = tester.widget<PopupMenuItem<dynamic>>(
        find.byKey(const ValueKey('recent-menu-open')));
    expect(
      item.height,
      defaultTargetPlatform == TargetPlatform.linux
          ? 36
          : kMinInteractiveDimension,
    );
  },
      variant: const TargetPlatformVariant({
        TargetPlatform.linux,
        TargetPlatform.android,
      }));
}
