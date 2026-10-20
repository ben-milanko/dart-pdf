import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:dart_pdf_editor_app/unsaved_changes.dart';
import 'package:dart_pdf_editor_app/unsaved_changes_store.dart';

/// The native crash-recovery mirror against a real filesystem: the append,
/// truncate and torn-write behaviour is the part that has to be right, because
/// it is only ever exercised for real by a crash.
void main() {
  late Directory root;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    root = Directory.systemTemp.createTempSync('dartpdf_unsaved_test');
    PathProviderPlatform.instance = _TempPathProvider(root.path);
  });

  tearDown(() {
    root.deleteSync(recursive: true);
  });

  Directory storeDir() => Directory('${root.path}/unsaved_changes');

  UnsavedRecord recordOf(int length, {String id = 'doc-1', int saved = 100}) =>
      UnsavedRecord(
        id: id,
        title: 'work.pdf',
        length: length,
        originPath: '/docs/work.pdf',
        savedLength: saved,
        updatedAt: 7,
      );

  Uint8List filled(int length, int seed) =>
      Uint8List.fromList([for (var i = 0; i < length; i++) (seed + i) & 0xff]);

  test('a mirrored document is listed and read back byte for byte', () async {
    final store = openUnsavedChangesStore()!;
    final bytes = filled(2048, 1);
    await store.write(recordOf(bytes.length), bytes);

    // A fresh store is what the next launch gets - it must find everything
    // from the files alone.
    final relaunched = openUnsavedChangesStore()!;
    final records = await relaunched.list();
    expect(records, hasLength(1));
    expect(records.single.title, 'work.pdf');
    expect(records.single.originPath, '/docs/work.pdf');
    expect(records.single.savedLength, 100);
    expect(await relaunched.read(records.single), bytes);
  });

  test('a later revision appends its tail instead of rewriting the file',
      () async {
    final store = openUnsavedChangesStore()!;
    final first = filled(4096, 1);
    await store.write(recordOf(first.length), first);

    // Poison a byte the store already wrote. A rewrite would heal it; an append
    // cannot touch it - so if it survives, only the tail was written.
    final data = File('${storeDir().path}/doc-1.pdf');
    final poisoned = data.readAsBytesSync();
    poisoned[10] = poisoned[10] ^ 0xff;
    data.writeAsBytesSync(poisoned);

    final second = Uint8List(6144)..setRange(0, 4096, first);
    second.setRange(4096, 6144, filled(2048, 9));
    await store.write(recordOf(second.length), second);

    final onDisk = data.readAsBytesSync();
    expect(onDisk, hasLength(6144));
    expect(onDisk[10], poisoned[10], reason: 'the prefix was not rewritten');
    expect(Uint8List.sublistView(onDisk, 4096), Uint8List.sublistView(second, 4096));
  });

  test('undo past the mirrored length cuts the stale tail off', () async {
    final store = openUnsavedChangesStore()!;
    final long = filled(4096, 1);
    await store.write(recordOf(long.length), long);

    final short = Uint8List.sublistView(long, 0, 1500);
    await store.write(recordOf(short.length), short);

    final data = File('${storeDir().path}/doc-1.pdf');
    expect(data.lengthSync(), 1500,
        reason: 'bytes we would never read again must not linger');
    final records = await openUnsavedChangesStore()!.list();
    expect(await openUnsavedChangesStore()!.read(records.single), short);
  });

  test('a crash mid-append recovers the last whole revision', () async {
    final store = openUnsavedChangesStore()!;
    final committed = filled(2048, 1);
    await store.write(recordOf(committed.length), committed);

    // A half-written append: the bytes landed, the commit that would have
    // described them never did.
    final data = File('${storeDir().path}/doc-1.pdf');
    data.writeAsBytesSync(filled(700, 42), mode: FileMode.append, flush: true);

    final relaunched = openUnsavedChangesStore()!;
    final records = await relaunched.list();
    expect(records.single.length, 2048);
    expect(await relaunched.read(records.single), committed,
        reason: 'recovery reads the committed length, never the torn tail');
  });

  test('a record whose bytes are gone or short is not offered', () async {
    final store = openUnsavedChangesStore()!;
    await store.write(recordOf(2048, id: 'missing'), filled(2048, 1));
    await store.write(recordOf(2048, id: 'short'), filled(2048, 1));
    File('${storeDir().path}/missing.pdf').deleteSync();
    File('${storeDir().path}/short.pdf').writeAsBytesSync(filled(10, 1));

    expect(await openUnsavedChangesStore()!.list(), isEmpty,
        reason: 'half a document is not a recovery');
  });

  test('a torn commit is skipped, not half-read', () async {
    final store = openUnsavedChangesStore()!;
    await store.write(recordOf(2048), filled(2048, 1));
    File('${storeDir().path}/doc-1.json').writeAsStringSync('{"i":"doc-1","t":');

    expect(await openUnsavedChangesStore()!.list(), isEmpty);
  });

  test('deleting a document removes its bytes and its record', () async {
    final store = openUnsavedChangesStore()!;
    await store.write(recordOf(2048), filled(2048, 1));

    await store.delete('doc-1');

    expect(storeDir().listSync(), isEmpty);
    expect(await openUnsavedChangesStore()!.list(), isEmpty);
  });

  test('pruning keeps the adopted documents and sweeps the rest', () async {
    final store = openUnsavedChangesStore()!;
    await store.write(recordOf(2048, id: 'keep'), filled(2048, 1));
    await store.write(recordOf(2048, id: 'drop'), filled(2048, 2));
    // A commit interrupted by a crash leaves one of these behind.
    File('${storeDir().path}/stray.json.tmp').writeAsStringSync('{');

    await store.pruneExcept({'keep'});

    final names = storeDir()
        .listSync()
        .map((e) => e.uri.pathSegments.last)
        .toList()
      ..sort();
    expect(names, ['keep.json', 'keep.pdf']);
  });

  test('an unwritable store degrades to no recovery at all', () async {
    PathProviderPlatform.instance = _BrokenPathProvider();
    final store = openUnsavedChangesStore()!;

    // Every operation has to swallow its failure: crash recovery is a safety
    // net, and a safety net that throws into the editor is worse than none.
    await store.write(recordOf(16), filled(16, 1));
    expect(await store.list(), isEmpty);
    expect(await store.read(recordOf(16)), isNull);
    await store.delete('doc-1');
    await store.pruneExcept(const {});
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
