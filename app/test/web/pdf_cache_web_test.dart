@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:typed_data';

import 'package:dart_pdf_editor_app/idb_web.dart';
import 'package:dart_pdf_editor_app/pdf_cache_web.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web/web.dart' as web;

void main() {
  var serial = 0;
  late String name;
  late WebPdfCache cache;
  final clients = <WebPdfCache>[];

  Uint8List bytes(int marker, [int size = 4]) =>
      Uint8List(size)..fillRange(0, size, marker);
  WebPdfCache client(
      {int budget = 10,
      int fileLimit = 8,
      Future<PdfStorageEstimate> Function()? estimate}) {
    final result = WebPdfCache(
        databaseName: name,
        maxBytes: budget,
        maxFileBytes: fileLimit,
        estimateStorage: estimate ?? () async => (usage: 0, quota: 1000));
    clients.add(result);
    return result;
  }

  setUp(() {
    name =
        'pdf-cache-test-${DateTime.now().microsecondsSinceEpoch}-${serial++}';
    cache = client();
  });
  tearDown(() async {
    for (final client in clients) {
      await client.close();
    }
    clients.clear();
    await idbRequest<void>(web.window.indexedDB.deleteDatabase(name), (_) {});
  });

  Future<void> legacy(Map<String, Uint8List> files) async {
    final db = await openIdb(name, const ['pdfs']);
    final store = db.transaction('pdfs'.toJS, 'readwrite').objectStore('pdfs');
    await Future.wait([
      for (final entry in files.entries)
        idbRequest<void>(store.put(entry.value.toJS, entry.key.toJS), (_) {}),
    ]);
    db.close();
  }

  test('evicts by bytes and keeps recently read snapshots across clients',
      () async {
    final a = (await cache.put(bytes(1)))!;
    final b = (await cache.put(bytes(2)))!;
    expect(await cache.read(a), bytes(1));
    final other = client();
    final c = (await other.put(bytes(3)))!;
    expect(await other.read(a), bytes(1));
    expect(await other.read(c), bytes(3));
    await expectLater(other.read(b), throwsStateError);
    final usage = (await other.usage())!;
    expect(usage.bytes, 8);
    expect(usage.documents, 2);
  });

  test('duplicate picks touch the LRU without spending bytes again', () async {
    final a = await cache.put(bytes(1));
    final b = await cache.put(bytes(2));
    expect(await cache.put(bytes(1)), a);
    await cache.put(bytes(3));
    expect((await cache.usage())!.bytes, 8);
    await expectLater(cache.read(b!), throwsStateError);
    expect(await cache.read(a!), bytes(1));
  });

  test('oversized picks skip without evicting existing snapshots', () async {
    final a = (await cache.put(bytes(1)))!;
    expect(await cache.put(bytes(2, 9)), isNull);
    expect(await cache.read(a), bytes(1));
    expect((await cache.usage())!.bytes, 4);
    expect(await cache.put(bytes(3, 8)), isNotNull); // inclusive per-file limit
    expect((await cache.usage())!.bytes, 8);
  });

  test('quota pressure skips a new snapshot but reuses an existing one',
      () async {
    final a = (await cache.put(bytes(1)))!;
    final pressured = client(estimate: () async => (usage: 88, quota: 100));
    expect(await pressured.put(bytes(2)), isNull);
    expect(await pressured.put(bytes(1)), a);
    expect(await pressured.read(a), bytes(1));
    expect((await cache.usage())!.bytes, 4);
  });

  test('missing or failing estimates still obey the app budget', () async {
    for (final estimate in <Future<PdfStorageEstimate> Function()>[
      () async => (usage: null, quota: null),
      () async => throw StateError('estimate unavailable'),
    ]) {
      final fallback = client(estimate: estimate);
      expect(await fallback.put(bytes(1)), isNotNull);
      expect(await fallback.put(bytes(2)), isNotNull);
      expect(await fallback.put(bytes(3)), isNotNull);
      expect((await fallback.usage())!.bytes, 8);
      await fallback.clear();
    }
  });

  test('concurrent tabs share one transactionally enforced budget', () async {
    final other = client();
    final keys = await Future.wait([
      cache.put(bytes(1)),
      other.put(bytes(2)),
      cache.put(bytes(3)),
      other.put(bytes(4)),
    ]);
    expect(keys, everyElement(isNotNull));
    final kept = (await cache.prune(keys.cast<String>().toSet()))!;
    expect(kept.length, 2);
    expect((await cache.usage())!.bytes, 8);
    for (final key in kept) {
      expect(await cache.read(key), hasLength(4));
    }
  });

  test('legacy migration preserves small snapshots and drops oversized files',
      () async {
    await legacy({'old-a': bytes(1), 'old-big': bytes(2, 20)});
    final kept = await cache.prune({'old-a', 'old-big'});
    expect(kept, {'old-a'});
    expect(await cache.read('old-a'), bytes(1));
    expect((await cache.usage())!.bytes, 4);
    await expectLater(cache.read('old-big'), throwsStateError);
  });

  test('startup trims a legacy cache even without opening another file',
      () async {
    await legacy({'a': bytes(1), 'b': bytes(2), 'c': bytes(3)});
    final kept = (await cache.prune({'a', 'b', 'c'}))!;
    expect(kept, {'b', 'c'});
    expect((await cache.usage())!.bytes, 8);
    await expectLater(cache.read('a'), throwsStateError);
  });

  test('a legacy tab blocking upgrade fails promptly and permits retry',
      () async {
    final oldTab = await openIdb(name, const ['pdfs']);
    expect(
        await cache.put(bytes(1)).timeout(const Duration(seconds: 5)), isNull);
    oldTab.close();
    // The formerly blocked upgrade finishes, then this connection can open.
    final key = await cache.put(bytes(1));
    expect(key, isNotNull);
    expect(await cache.read(key!), bytes(1));
  });

  test('a schema upgrade releases and refreshes an existing connection',
      () async {
    final key = (await cache.put(bytes(1)))!;
    final upgraded =
        await openIdb(name, const ['pdfs', 'metadata', 'future-store']);
    upgraded.close();
    expect(await cache.read(key), bytes(1));
  });

  test('prune removes unreferenced snapshots and returns the live inventory',
      () async {
    final a = (await cache.put(bytes(1)))!;
    final b = (await cache.put(bytes(2)))!;
    expect(await cache.prune({a, 'already-evicted'}), {a});
    await expectLater(cache.read(b), throwsStateError);
    expect((await cache.usage())!.documents, 1);
  });

  test('clear deletes payloads and metadata and allows caching again',
      () async {
    final key = (await cache.put(bytes(1)))!;
    expect(await cache.clear(), isTrue);
    expect((await cache.usage())!.bytes, 0);
    expect((await cache.usage())!.documents, 0);
    await expectLater(cache.read(key), throwsStateError);
    expect(await cache.put(bytes(1)), key);
    expect(await cache.read(key), bytes(1));
  });

  test('failed transactions return failure and can recover on clear', () async {
    final key = (await cache.put(bytes(1)))!;
    final db = await openIdb(name, const ['pdfs', 'metadata']);
    final store =
        db.transaction('metadata'.toJS, 'readwrite').objectStore('metadata');
    await idbRequest<void>(store.put('broken metadata'.toJS, key.toJS), (_) {});
    db.close();
    expect(await cache.put(bytes(2)), isNull);
    await expectLater(cache.read(key), throwsStateError);
    expect(await cache.prune({key}), isNull); // must not report an empty cache
    expect(await cache.usage(), isNull);
    expect(await cache.clear(), isTrue);
    expect(await cache.put(bytes(2)), isNotNull);
  });
}
