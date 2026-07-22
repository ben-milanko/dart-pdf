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

    Uint8List? png;
    await tester.runAsync(() async {
      png = await cache.thumbnailFor(entry(path: '/a.pdf'));
    });

    expect(png, isNotNull);
    // PNG signature.
    expect(png!.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);

    // A second request is served from the memo, not a fresh read/render.
    await tester.runAsync(() async {
      expect(await cache.thumbnailFor(entry(path: '/a.pdf')), same(png));
    });
    expect(reads, 1);

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
}
