import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:dart_pdf_editor_app/recent_thumbnail_store.dart';

void main() {
  late Directory root;
  late PathProviderPlatform originalPathProvider;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    root = Directory.systemTemp.createTempSync('dartpdf_thumb_store_test');
    originalPathProvider = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _TempPathProvider(root.path);
  });

  tearDown(() {
    PathProviderPlatform.instance = originalPathProvider;
    root.deleteSync(recursive: true);
  });

  test('writes and reads a thumbnail from application support', () async {
    final bytes = Uint8List.fromList([1, 2, 3, 4]);

    await writeStoredRecentThumbnail('drawing', bytes);

    expect(await readStoredRecentThumbnail('drawing'), bytes);
    expect(
      File('${root.path}/recent_thumbnails/drawing.thumb').existsSync(),
      isTrue,
    );
  });

  test('prunes thumbnails no longer represented by Recent files', () async {
    await writeStoredRecentThumbnail('keep', Uint8List.fromList([1]));
    await writeStoredRecentThumbnail('drop', Uint8List.fromList([2]));

    await pruneStoredRecentThumbnails({'keep'});

    expect(await readStoredRecentThumbnail('keep'), [1]);
    expect(await readStoredRecentThumbnail('drop'), isNull);
  });

  test('an unavailable support directory degrades to a cache miss', () async {
    PathProviderPlatform.instance = _BrokenPathProvider();

    await writeStoredRecentThumbnail('drawing', Uint8List.fromList([1]));
    expect(await readStoredRecentThumbnail('drawing'), isNull);
    await pruneStoredRecentThumbnails({'drawing'});
  });
}

class _TempPathProvider extends PathProviderPlatform {
  _TempPathProvider(this.root);

  final String root;

  @override
  Future<String?> getApplicationSupportPath() async => root;
}

class _BrokenPathProvider extends PathProviderPlatform {
  @override
  Future<String?> getApplicationSupportPath() async =>
      throw MissingPluginException('no path_provider here');
}
