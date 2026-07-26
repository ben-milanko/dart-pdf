// The decoded-image cache budget: the platform-aware default
// (pdfDefaultImageCacheBytes), the live maxBytes knob a host can set, and the
// memory-pressure signal that drops the cache. See issue #281 - the numbers
// below are the measured policy, so a change here should come with a re-run of
// benchmark_image_cache_budget_test.dart, not just a new expectation.
import 'dart:async';
import 'dart:ui' as ui;

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';

const int _mb = 1024 * 1024;

/// A 100x100 RGBA master, as the cache counts it (width * height * 4).
const int _imageBytes = 100 * 100 * 4;

Future<ui.Image> _solid() {
  final px = Uint8List(_imageBytes);
  for (var i = 3; i < px.length; i += 4) {
    px[i] = 255;
  }
  final c = Completer<ui.Image>();
  ui.decodeImageFromPixels(px, 100, 100, ui.PixelFormat.rgba8888, c.complete);
  return c.future;
}

/// Decoding runs on the engine, which the fake-async zone inside [testWidgets]
/// never pumps - the completer would hang forever without [WidgetTester.runAsync].
Future<void> _putProbe(WidgetTester tester, PdfImageCache cache, Object key) =>
    tester.runAsync(() async => cache.put(key, await _solid()));

void main() {
  group('platform default', () {
    test('desktop keeps the 256 MB budget - RSS is cheap there', () {
      expect(
          pdfDefaultImageCacheBytes(
              platform: PdfPerformancePlatform.desktop, deviceMemoryGb: 16),
          256 * _mb);
    });

    test('mobile halves it, where an iOS jetsam limit makes RSS expensive', () {
      expect(pdfDefaultImageCacheBytes(platform: PdfPerformancePlatform.mobile),
          128 * _mb);
    });

    test('web takes the mobile budget under a tab ceiling', () {
      expect(
          pdfDefaultImageCacheBytes(
              platform: PdfPerformancePlatform.web, deviceMemoryGb: 16),
          128 * _mb);
    });

    test('a small-memory device browser drops to 64 MB', () {
      expect(
          pdfDefaultImageCacheBytes(
              platform: PdfPerformancePlatform.web, deviceMemoryGb: 2),
          64 * _mb);
    });

    test('web without a deviceMemory reading falls back to the constant', () {
      // Firefox, Safari, and any insecure context report nothing at all.
      expect(pdfDefaultImageCacheBytes(platform: PdfPerformancePlatform.web),
          128 * _mb);
    });

    test('an unknown platform gets the conservative middle', () {
      expect(pdfDefaultImageCacheBytes(platform: PdfPerformancePlatform.other),
          128 * _mb);
    });

    test('every platform lands in a sane range', () {
      for (final platform in PdfPerformancePlatform.values) {
        final budget = pdfDefaultImageCacheBytes(platform: platform);
        expect(budget, greaterThanOrEqualTo(64 * _mb), reason: '$platform');
        expect(budget, lessThanOrEqualTo(256 * _mb), reason: '$platform');
      }
    });

    test('a default-constructed cache adopts the platform budget', () {
      expect(PdfImageCache().maxBytes, pdfDefaultImageCacheBytes());
    });
  });

  group('maxBytes', () {
    test('lowering it evicts down to the new budget at once', () async {
      final cache = PdfImageCache(maxBytes: 5 * _imageBytes);
      for (var i = 0; i < 4; i++) {
        cache.put('k$i', await _solid());
      }
      expect(cache.debugLength, 4);
      expect(cache.bytes, 4 * _imageBytes);

      cache.maxBytes = 2 * _imageBytes;

      expect(cache.maxBytes, 2 * _imageBytes);
      expect(cache.bytes, 2 * _imageBytes);
      expect(cache.debugLength, 2, reason: 'the oldest two evicted');
      expect(cache.take('k0'), isNull);
      expect(cache.take('k3'), isNotNull, reason: 'the newest survives');
    });

    test('raising it evicts nothing', () async {
      final cache = PdfImageCache(maxBytes: _imageBytes);
      cache.put('a', await _solid());
      cache.maxBytes = 256 * _mb;
      expect(cache.debugLength, 1);
      expect(cache.bytes, _imageBytes);
    });
  });

  testWidgets('memory pressure drops the decoded images', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PdfViewer(document: PdfDocument.open(buildMultiPagePdf(1))),
      ),
    ));
    await tester.pump();

    final cache = PdfImageCache.instance;
    addTearDown(cache.clear);
    await _putProbe(tester, cache, 'pressure-probe');
    expect(cache.bytes, greaterThan(0));

    await _sendMemoryPressure(tester);

    expect(cache.debugLength, 0);
    expect(cache.bytes, 0);
  });

  testWidgets('an unmounted viewer stops answering memory pressure',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PdfViewer(document: PdfDocument.open(buildMultiPagePdf(1))),
      ),
    ));
    await tester.pump();
    await tester.pumpWidget(const MaterialApp(home: Scaffold()));
    await tester.pump();

    final cache = PdfImageCache.instance;
    addTearDown(cache.clear);
    await _putProbe(tester, cache, 'pressure-probe');

    await _sendMemoryPressure(tester);

    expect(cache.debugLength, 1,
        reason: 'the disposed viewer must have removed its observer');
  });
}

/// The platform's low-memory warning, as the engine delivers it.
Future<void> _sendMemoryPressure(WidgetTester tester) async {
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    SystemChannels.system.name,
    const JSONMessageCodec()
        .encodeMessage(<String, dynamic>{'type': 'memoryPressure'}),
    (_) {},
  );
  await tester.pump();
}
