import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:dart_pdf_editor_app/pdf_cache.dart';

void main() {
  late Directory root;
  late PathProviderPlatform originalPathProvider;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    root = Directory.systemTemp.createTempSync('dartpdf_pdf_cache_test');
    originalPathProvider = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _TempPathProvider(root.path);
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    PathProviderPlatform.instance = originalPathProvider;
    root.deleteSync(recursive: true);
  });

  /// The key an install from before an iOS app update recorded for [live]:
  /// same snapshot file, but under the old data-container UUID.
  String staleKey(String live) => live.replaceFirst(
      root.path, '/var/mobile/Containers/Data/Application/OLD-UUID');

  test('a key from before an app update resolves to the live snapshot',
      () async {
    final live = (await cacheOpenedPdf(Uint8List.fromList([1, 2, 3])))!;

    expect(await resolveCachedPdfKey(staleKey(live)), live);
    expect(await resolveCachedPdfKey(live), live);
  });

  test('a missing snapshot or a non-snapshot key does not resolve', () async {
    expect(
        await resolveCachedPdfKey('/elsewhere/recent_pdfs/gone.pdf'), isNull);
    expect(await resolveCachedPdfKey('/docs/a.pdf'), isNull);
  });

  test('pruning keeps snapshots still referenced by a pre-update key',
      () async {
    final kept = (await cacheOpenedPdf(Uint8List.fromList([1])))!;
    final dropped = (await cacheOpenedPdf(Uint8List.fromList([2])))!;

    await pruneCachedPdfs({staleKey(kept)});

    expect(File(kept).existsSync(), isTrue);
    expect(File(dropped).existsSync(), isFalse);
  });
}

class _TempPathProvider extends PathProviderPlatform {
  _TempPathProvider(this.root);

  final String root;

  @override
  Future<String?> getApplicationSupportPath() async => root;
}
