import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dart_pdf_editor_app/recent_thumbnails.dart';
import 'package:dart_pdf_editor_app/recents.dart';
import 'package:dart_pdf_editor_app/welcome_screen.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // A wide surface defaults to the grid; a narrow one to the list.
  const wide = Size(1000, 800);
  const narrow = Size(420, 800);

  Future<void> pump(WidgetTester tester, WelcomeScreen screen,
      {Size size = narrow}) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: screen)));
  }

  testWidgets('a recent row shows its first-page thumbnail once it renders',
      (tester) async {
    final store = RecentsStore();
    await store.add(title: 'a.pdf', path: '/a.pdf');
    final pdf = PdfBlankDocument.create();
    final cache =
        RecentThumbnailCache(readBytes: (path, {bookmark}) async => pdf);

    await pump(
        tester,
        WelcomeScreen(
          recents: store,
          onOpen: () {},
          onOpenRecent: (_) {},
          thumbnails: cache,
        ));

    // Before the thumbnail lands the row shows the placeholder icon.
    await tester.pump();
    expect(find.byIcon(Icons.description_outlined), findsOneWidget);
    expect(find.byType(Image), findsNothing);

    // Drive the (real-async) render, then let the FutureBuilder rebuild.
    await tester.runAsync(() => cache.thumbnailFor(store.items.single));
    await tester.pump();

    expect(find.byType(Image), findsOneWidget);
    expect(find.byIcon(Icons.description_outlined), findsNothing);

    cache.dispose();
  });

  testWidgets('falls back to the document icon when the render fails',
      (tester) async {
    final store = RecentsStore();
    await store.add(title: 'a.pdf', path: '/a.pdf');
    // A cache that can't read the bytes resolves the thumbnail to null.
    final cache = RecentThumbnailCache(
        readBytes: (path, {bookmark}) async => throw StateError('gone'));

    await pump(
        tester,
        WelcomeScreen(
          recents: store,
          onOpen: () {},
          onOpenRecent: (_) {},
          thumbnails: cache,
        ));

    await tester.runAsync(() => cache.thumbnailFor(store.items.single));
    await tester.pump();

    expect(find.byIcon(Icons.description_outlined), findsOneWidget);
    expect(find.byType(Image), findsNothing);

    cache.dispose();
  });

  testWidgets('falls back to the document icon without a thumbnail cache',
      (tester) async {
    final store = RecentsStore();
    await store.add(title: 'a.pdf', path: '/a.pdf');

    await pump(
        tester,
        WelcomeScreen(
          recents: store,
          onOpen: () {},
          onOpenRecent: (_) {},
        ));
    await tester.pump();

    expect(find.byIcon(Icons.description_outlined), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('defaults to the list on a narrow surface', (tester) async {
    final store = RecentsStore();
    await store.add(title: 'a.pdf', path: '/a.pdf');

    await pump(
        tester,
        size: narrow,
        WelcomeScreen(
          recents: store,
          onOpen: () {},
          onOpenRecent: (_) {},
        ));
    await tester.pump();

    // The list renders ListTile rows; the grid does not.
    expect(find.byType(ListTile), findsOneWidget);
    expect(find.byKey(const ValueKey('recent-tile-/a.pdf')), findsNothing);
  });

  testWidgets('defaults to the grid on a wide surface', (tester) async {
    final store = RecentsStore();
    await store.add(title: 'a.pdf', path: '/a.pdf');

    await pump(
        tester,
        size: wide,
        WelcomeScreen(
          recents: store,
          onOpen: () {},
          onOpenRecent: (_) {},
        ));
    await tester.pump();

    expect(find.byKey(const ValueKey('recent-tile-/a.pdf')), findsOneWidget);
    expect(find.byType(ListTile), findsNothing);
  });

  testWidgets('the toggle switches the layout and overrides the default',
      (tester) async {
    final store = RecentsStore();
    await store.add(title: 'a.pdf', path: '/a.pdf');

    // Wide surface -> grid by default.
    await pump(
        tester,
        size: wide,
        WelcomeScreen(
          recents: store,
          onOpen: () {},
          onOpenRecent: (_) {},
        ));
    await tester.pump();
    expect(find.byKey(const ValueKey('recent-tile-/a.pdf')), findsOneWidget);

    // Tapping the list segment switches to the list even though the surface
    // is still wide (an explicit choice sticks).
    await tester.tap(find.byIcon(Icons.view_list_outlined));
    await tester.pump();
    expect(find.byType(ListTile), findsOneWidget);
    expect(find.byKey(const ValueKey('recent-tile-/a.pdf')), findsNothing);
  });

  testWidgets('tapping a grid tile opens the entry', (tester) async {
    final store = RecentsStore();
    await store.add(title: 'a.pdf', path: '/a.pdf');
    RecentFile? opened;

    await pump(
        tester,
        size: wide,
        WelcomeScreen(
          recents: store,
          onOpen: () {},
          onOpenRecent: (e) => opened = e,
        ));
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('recent-tile-thumb-/a.pdf')));
    await tester.pump();
    expect(opened?.id, '/a.pdf');
  });

  testWidgets("a grid tile's remove button drops the entry", (tester) async {
    final store = RecentsStore();
    await store.add(title: 'a.pdf', path: '/a.pdf');

    await pump(
        tester,
        size: wide,
        WelcomeScreen(
          recents: store,
          onOpen: () {},
          onOpenRecent: (_) {},
        ));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    expect(store.items, isEmpty);
    expect(find.byKey(const ValueKey('recent-tile-/a.pdf')), findsNothing);
  });

  testWidgets('a non-reopenable grid tile is dimmed and not tappable',
      (tester) async {
    final store = RecentsStore();
    // No path / cache path -> not reopenable (a web pick with no snapshot).
    await store.add(title: 'web.pdf');
    var opened = false;

    await pump(
        tester,
        size: wide,
        WelcomeScreen(
          recents: store,
          onOpen: () {},
          onOpenRecent: (_) => opened = true,
        ));
    await tester.pump();

    final tile = find.byKey(const ValueKey('recent-tile-web.pdf'));
    expect(tile, findsOneWidget);
    final opacity = tester.widget<Opacity>(
        find.descendant(of: tile, matching: find.byType(Opacity)).first);
    expect(opacity.opacity, lessThan(1.0));

    await tester.tap(find.byKey(const ValueKey('recent-tile-thumb-web.pdf')));
    await tester.pump();
    expect(opened, isFalse);
  });
}
