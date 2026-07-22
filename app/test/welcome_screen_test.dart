import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dart_pdf_editor_app/recent_thumbnails.dart';
import 'package:dart_pdf_editor_app/recents.dart';
import 'package:dart_pdf_editor_app/welcome_screen.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pump(WidgetTester tester, WelcomeScreen screen) =>
      tester.pumpWidget(MaterialApp(home: Scaffold(body: screen)));

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
}
