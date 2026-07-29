import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';

import 'package:dart_pdf_editor_app/recent_thumbnails.dart';
import 'package:dart_pdf_editor_app/recents.dart';

void main() {
  RecentFile entry({String? path, String title = 'a.pdf'}) =>
      RecentFile(title: title, path: path, openedAt: 0);

  testWidgets('renders a first-page PNG thumbnail from the entry bytes',
      (tester) async {
    final pdf = PdfBlankDocument.create();
    var reads = 0;
    final cache = RecentThumbnailCache(readBytes: (path, {bookmark}) async {
      reads++;
      return pdf;
    });

    RecentThumbnail? thumb;
    await tester.runAsync(() async {
      thumb = await cache.thumbnailFor(entry(path: '/a.pdf'));
    });

    expect(thumb, isNotNull);
    // PNG signature.
    expect(thumb!.pngBytes.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
    // A blank page is portrait (taller than wide), so aspect < 1.
    expect(thumb!.aspectRatio, greaterThan(0));
    expect(thumb!.aspectRatio, lessThan(1));

    // A second request is served from the memo, not a fresh read/render.
    await tester.runAsync(() async {
      expect(await cache.thumbnailFor(entry(path: '/a.pdf')), same(thumb));
    });
    expect(reads, 1);

    cache.dispose();
  });

  testWidgets('evicts the least-recently-used entry past maxEntries',
      (tester) async {
    final pdf = PdfBlankDocument.create();
    final reads = <String>[];
    final cache = RecentThumbnailCache(
      maxEntries: 1,
      readBytes: (path, {bookmark}) async {
        reads.add(path);
        return pdf;
      },
    );

    await tester.runAsync(() async {
      await cache.thumbnailFor(entry(path: '/a.pdf'));
      await cache.thumbnailFor(entry(path: '/b.pdf')); // evicts /a.pdf
      await cache.thumbnailFor(entry(path: '/a.pdf')); // re-rendered
    });

    // /a.pdf was read twice: once before eviction, once after.
    expect(reads, ['/a.pdf', '/b.pdf', '/a.pdf']);

    cache.dispose();
  });

  testWidgets('an entry with no readable source resolves to null',
      (tester) async {
    final cache = RecentThumbnailCache(
        readBytes: (path, {bookmark}) async => fail('must not read'));
    await tester.runAsync(() async {
      // No path and no cache path: nothing to read.
      expect(await cache.thumbnailFor(entry(title: 'web.pdf')), isNull);
    });
  });

  testWidgets('a read failure resolves to null and is memoized',
      (tester) async {
    var reads = 0;
    final cache = RecentThumbnailCache(readBytes: (path, {bookmark}) async {
      reads++;
      throw StateError('file gone');
    });
    await tester.runAsync(() async {
      expect(await cache.thumbnailFor(entry(path: '/a.pdf')), isNull);
      expect(await cache.thumbnailFor(entry(path: '/a.pdf')), isNull);
    });
    expect(reads, 1);
  });

  test('serializes thumbnail reads instead of hydrating recents together',
      () async {
    final first = Completer<Uint8List>();
    final second = Completer<Uint8List>();
    final reads = <String>[];
    final cache = RecentThumbnailCache(readBytes: (path, {bookmark}) {
      reads.add(path);
      return path == '/a.pdf' ? first.future : second.future;
    });
    addTearDown(cache.dispose);

    final a = cache.thumbnailFor(entry(path: '/a.pdf'));
    final b = cache.thumbnailFor(entry(path: '/b.pdf'));
    await Future<void>.delayed(Duration.zero);

    expect(reads, ['/a.pdf']);

    // Invalid bytes make the first render resolve to the generic-icon fallback;
    // once it leaves the queue the second source is allowed to start.
    first.complete(Uint8List(0));
    expect(await a, isNull);
    await Future<void>.delayed(Duration.zero);
    expect(reads, ['/a.pdf', '/b.pdf']);

    second.complete(Uint8List(0));
    expect(await b, isNull);
  });
}
