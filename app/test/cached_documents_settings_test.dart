import 'dart:async';

import 'package:dart_pdf_editor_app/cached_documents_settings.dart';
import 'package:dart_pdf_editor_app/pdf_cache.dart';
import 'package:dart_pdf_editor_app/recents.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('shows usage and clears snapshots while preserving Recents',
      (tester) async {
    final recents = RecentsStore();
    addTearDown(recents.dispose);
    await recents.add(title: 'cached.pdf', cachePath: 'key');
    await recents.add(title: 'local.pdf', path: '/local.pdf');
    var usage = const PdfCacheUsage(12 * 1024 * 1024, 1);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: CachedDocumentsSettings(
      recents: recents,
      readUsage: () async => usage,
      clearCache: () async {
        usage = const PdfCacheUsage(0, 0);
        return true;
      },
    ))));
    await tester.pumpAndSettle();
    expect(find.text('12.0 MiB of 256 MiB used'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('settings-clear-cache')));
    await tester.pumpAndSettle();
    expect(find.text('0.0 MiB of 256 MiB used'), findsOneWidget);
    expect(recents.items.map((entry) => entry.id), ['/local.pdf', 'key']);
    expect(recents.items.first.isReopenable, isTrue);
    expect(recents.items.last.isReopenable, isFalse);
    final reloaded = RecentsStore();
    addTearDown(reloaded.dispose);
    await reloaded.load();
    expect(reloaded.items.last.cacheAvailable, isFalse);
  });

  testWidgets('failed clear retains reopenability and reports failure',
      (tester) async {
    final recents = RecentsStore();
    addTearDown(recents.dispose);
    await recents.add(title: 'cached.pdf', cachePath: 'key');
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: CachedDocumentsSettings(
      recents: recents,
      readUsage: () async => const PdfCacheUsage(1024, 1),
      clearCache: () async => false,
    ))));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('settings-clear-cache')));
    await tester.pumpAndSettle();
    expect(recents.items.single.isReopenable, isTrue);
    expect(find.text('Could not clear cached documents. Try again.'),
        findsOneWidget);
  });

  testWidgets('unavailable usage does not pretend the cache is empty',
      (tester) async {
    final recents = RecentsStore();
    addTearDown(recents.dispose);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: CachedDocumentsSettings(
      recents: recents,
      readUsage: () async => null,
    ))));
    await tester.pumpAndSettle();
    expect(find.text('Cache size unavailable'), findsOneWidget);
    expect(
        tester
            .widget<TextButton>(
                find.byKey(const ValueKey('settings-clear-cache')))
            .onPressed,
        isNotNull);
  });

  testWidgets('dismissing settings during clear still updates Recents',
      (tester) async {
    final recents = RecentsStore();
    addTearDown(recents.dispose);
    await recents.add(title: 'cached.pdf', cachePath: 'key');
    final cleared = Completer<bool>();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: CachedDocumentsSettings(
      recents: recents,
      readUsage: () async => const PdfCacheUsage(1024, 1),
      clearCache: () => cleared.future,
    ))));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('settings-clear-cache')));
    await tester.pumpWidget(const SizedBox());
    cleared.complete(true);
    await tester.pumpAndSettle();
    expect(recents.items.single.isReopenable, isFalse);
  });
}
