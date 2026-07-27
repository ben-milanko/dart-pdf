import 'dart:async';
import 'dart:typed_data';

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
    final readGate = Completer<Uint8List>();
    final cache =
        RecentThumbnailCache(readBytes: (path, {bookmark}) => readGate.future);
    late Future<RecentThumbnail?> thumbnail;

    // The production renderer uses an isolate. Start it in runAsync's real
    // async zone before the widget's FutureBuilder requests the same in-flight
    // thumbnail from the fake-async test zone.
    await tester.runAsync(() async {
      thumbnail = cache.thumbnailFor(store.items.single);
      await Future<void>.delayed(Duration.zero);
    });

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
    await tester.runAsync(() async {
      readGate.complete(pdf);
      await thumbnail;
    });
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

    // Resolve the real-async cache work before FutureBuilder observes it.
    await tester.runAsync(() => cache.thumbnailFor(store.items.single));

    await pump(
        tester,
        WelcomeScreen(
          recents: store,
          onOpen: () {},
          onOpenRecent: (_) {},
          thumbnails: cache,
        ));

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

  testWidgets('grid tiles are shaped to the page aspect ratio', (tester) async {
    final store = RecentsStore();
    await store.add(title: 'landscape.pdf', path: '/landscape.pdf');
    final landscape =
        PdfBlankDocument.create(pageSize: PdfPageSize.letter.landscape);
    final cache =
        RecentThumbnailCache(readBytes: (path, {bookmark}) async => landscape);

    // PdfRenderWorker isolate replies must be driven from runAsync, not from
    // the widget test binding's fake-async zone.
    await tester.runAsync(() => cache.thumbnailFor(store.items.single));

    await pump(
        tester,
        size: wide,
        WelcomeScreen(
          recents: store,
          onOpen: () {},
          onOpenRecent: (_) {},
          thumbnails: cache,
        ));

    // Let the aspect-aware box consume the cached render.
    await tester.pump();

    final size = tester.getSize(
        find.byKey(const ValueKey('recent-tile-thumb-/landscape.pdf')));
    // A landscape page yields a wider-than-tall tile; the portrait placeholder
    // default (taller than wide) never would, so this proves the box follows
    // the rendered page's real aspect ratio.
    expect(size.width, greaterThan(size.height));

    cache.dispose();
  });

  testWidgets('grid tiles centre thumbnails and share a title baseline',
      (tester) async {
    final store = RecentsStore();
    await store.add(title: 'portrait.pdf', path: '/portrait.pdf');
    await store.add(title: 'landscape.pdf', path: '/landscape.pdf');
    final portrait = PdfBlankDocument.create();
    final landscape =
        PdfBlankDocument.create(pageSize: PdfPageSize.letter.landscape);
    final cache = RecentThumbnailCache(
        readBytes: (path, {bookmark}) async =>
            path.contains('landscape') ? landscape : portrait);

    await tester.runAsync(() async {
      for (final e in store.items) {
        await cache.thumbnailFor(e);
      }
    });

    await pump(
        tester,
        size: wide,
        WelcomeScreen(
          recents: store,
          onOpen: () {},
          onOpenRecent: (_) {},
          thumbnails: cache,
        ));

    await tester.pump();

    final pThumb = tester
        .getRect(find.byKey(const ValueKey('recent-tile-thumb-/portrait.pdf')));
    final lThumb = tester.getRect(
        find.byKey(const ValueKey('recent-tile-thumb-/landscape.pdf')));
    // The landscape page is shorter than the portrait one...
    expect(lThumb.height, lessThan(pThumb.height));
    // ...but both are centred in the same fixed slot, so their vertical
    // centres line up.
    expect(lThumb.center.dy, moreOrLessEquals(pThumb.center.dy, epsilon: 0.5));

    // The titles share one bottom baseline despite the differing thumbnails.
    final pTitle = tester.getRect(find.text('portrait.pdf'));
    final lTitle = tester.getRect(find.text('landscape.pdf'));
    expect(lTitle.bottom, moreOrLessEquals(pTitle.bottom, epsilon: 0.5));
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
