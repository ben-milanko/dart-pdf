// PdfImageCache must (a) hand out independent clones backed by a retained
// master, (b) evict by total decoded bytes, oldest-first, and (c) never alter
// the rendered pixels — a warm (cache-hot) render is byte-identical to a cold
// one.
import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pdf_document/pdf_document.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';

Future<ui.Image> _solid(int w, int h, int r) {
  final px = Uint8List(w * h * 4);
  for (var i = 0; i < px.length; i += 4) {
    px[i] = r;
    px[i + 3] = 255;
  }
  final c = Completer<ui.Image>();
  ui.decodeImageFromPixels(px, w, h, ui.PixelFormat.rgba8888, c.complete);
  return c.future;
}

Future<int> _topLeftRed(ui.Image image) async {
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  return data!.getUint8(0);
}

void main() {
  test('take/put hand out independent clones over a retained master',
      () async {
    final cache = PdfImageCache();
    final key = Object();
    expect(cache.take(key), isNull);

    final master = await _solid(8, 8, 200);
    final first = cache.put(key, master);
    expect(cache.debugLength, 1);
    expect(await _topLeftRed(first), 200);

    // Disposing the handed-out clone must not affect the cached master.
    first.dispose();
    final second = cache.take(key);
    expect(second, isNotNull);
    expect(await _topLeftRed(second!), 200);
    second.dispose();
    cache.dispose();
  });

  test('evicts least-recently-used masters past the byte budget', () async {
    // Each 100x100 RGBA image is 40 000 bytes; a 90 000-byte budget holds two.
    final cache = PdfImageCache(maxBytes: 90000);
    final a = Object(), b = Object(), c = Object();
    cache.put(a, await _solid(100, 100, 10)).dispose();
    cache.put(b, await _solid(100, 100, 20)).dispose();
    expect(cache.debugLength, 2);
    expect(cache.debugBytes, 80000);

    // Touch a so b is now the least-recently-used.
    cache.take(a)!.dispose();
    cache.put(c, await _solid(100, 100, 30)).dispose();

    expect(cache.debugLength, 2);
    expect(cache.take(b), isNull, reason: 'b was the LRU and should be gone');
    expect(cache.take(a), isNotNull);
    expect(cache.take(c), isNotNull);
    cache.dispose();
  });

  test('an oversized image is kept until the next insert displaces it',
      () async {
    final cache = PdfImageCache(maxBytes: 1000); // smaller than one image
    final big = Object();
    cache.put(big, await _solid(50, 50, 99)).dispose(); // 10 000 bytes
    expect(cache.debugLength, 1, reason: 'kept for this render despite budget');
    cache.put(Object(), await _solid(50, 50, 88)).dispose();
    expect(cache.take(big), isNull, reason: 'aged out on the next insert');
    cache.dispose();
  });

  test('clear empties the cache', () async {
    final cache = PdfImageCache();
    cache.put(Object(), await _solid(8, 8, 1)).dispose();
    cache.put(Object(), await _solid(8, 8, 2)).dispose();
    expect(cache.debugLength, 2);
    cache.clear();
    expect(cache.debugLength, 0);
    expect(cache.debugBytes, 0);
    cache.dispose();
  });

  testWidgets('a warm render is byte-identical to a cold one', (tester) async {
    await tester.runAsync(() async {
      // A one-page PDF carrying a real RGB image, so the render path actually
      // decodes and caches an image XObject.
      final png = Uint8List.fromList(img.encodePng(img.Image(width: 24, height: 24)
        ..clear(img.ColorRgb8(180, 60, 30))));
      final doc = PdfDocument.open(PdfImageDocument.fromImageBytes([png]));
      final page = doc.page(0);

      PdfImageCache.instance.clear();
      final cold = await PdfPageRenderer.renderImage(page, pixelRatio: 2);
      expect(PdfImageCache.instance.debugLength, greaterThan(0),
          reason: 'the page image should have been cached');
      final warm = await PdfPageRenderer.renderImage(page, pixelRatio: 2);

      final coldBytes =
          (await cold.toByteData(format: ui.ImageByteFormat.rawRgba))!
              .buffer
              .asUint8List();
      final warmBytes =
          (await warm.toByteData(format: ui.ImageByteFormat.rawRgba))!
              .buffer
              .asUint8List();
      expect(warmBytes, equals(coldBytes));

      cold.dispose();
      warm.dispose();
      PdfImageCache.instance.clear();
    });
  });
}
