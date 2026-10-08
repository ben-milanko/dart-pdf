import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dart_pdf_editor_app/incoming_file.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('push forwards a file on the stream', () async {
    final service = IncomingFileService();
    addTearDown(service.dispose);

    final received = service.files.first;
    service.push([IncomingFile(name: 'x.pdf', bytes: Uint8List(3))]);
    final file = (await received).single;

    expect(file.name, 'x.pdf');
    expect(file.bytes, isNotNull);
  });

  test('initialFiles is empty when no native handler answers', () async {
    final service = IncomingFileService();
    addTearDown(service.dispose);
    expect(await service.initialFiles(), isEmpty);
  });

  group('initialFiles', () {
    const channel = MethodChannel(IncomingFileService.channelName);
    tearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));

    void answer(Object? Function(MethodCall call) handler) =>
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async => handler(call));

    test('returns every file of a multi-file launch', () async {
      answer((call) => call.method == 'getInitialFiles'
          ? [
              {'name': 'a.pdf', 'path': '/a.pdf'},
              {'name': 'b.pdf', 'path': '/b.pdf'},
            ]
          : null);
      final service = IncomingFileService();
      addTearDown(service.dispose);
      final files = await service.initialFiles();
      expect([for (final f in files) f.path], ['/a.pdf', '/b.pdf']);
    });

    test('falls back to getInitialFile on a runner without the batch call',
        () async {
      answer((call) {
        if (call.method == 'getInitialFile') {
          return {'name': 'a.pdf', 'path': '/a.pdf'};
        }
        throw MissingPluginException();
      });
      final service = IncomingFileService();
      addTearDown(service.dispose);
      final files = await service.initialFiles();
      expect(files.single.path, '/a.pdf');
    });
  });

  test('a native openFiles call lands on the stream as one batch', () async {
    final service = IncomingFileService();
    addTearDown(service.dispose);
    service.start();

    final received = service.files.first;
    const codec = StandardMethodCodec();
    final message = codec.encodeMethodCall(const MethodCall('openFiles', [
      {'name': 'a.pdf', 'path': '/tmp/a.pdf'},
      {'name': 'ignored'},
      {'name': 'b.pdf', 'path': '/tmp/b.pdf'},
    ]));
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
            IncomingFileService.channelName, message, (_) {});

    final files = await received;
    expect([for (final f in files) f.path], ['/tmp/a.pdf', '/tmp/b.pdf']);
  });

  test('openFiles carries the "Combine with DartPDF" mark', () async {
    final service = IncomingFileService();
    addTearDown(service.dispose);
    service.start();

    final received = service.files.first;
    const codec = StandardMethodCodec();
    final message = codec.encodeMethodCall(const MethodCall('openFiles', [
      {'name': 'a.pdf', 'path': '/tmp/a.pdf', 'combine': true},
      {'name': 'b.pdf', 'path': '/tmp/b.pdf'},
    ]));
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
            IncomingFileService.channelName, message, (_) {});

    final files = await received;
    expect([for (final f in files) f.combine], [true, false]);
  });

  test('a native openFile call lands on the stream', () async {
    final service = IncomingFileService();
    addTearDown(service.dispose);
    service.start();

    final received = service.files.first;
    // Simulate the native side invoking openFile on the channel.
    const codec = StandardMethodCodec();
    final message = codec.encodeMethodCall(const MethodCall('openFile', {
      'name': 'shared.pdf',
      'path': '/tmp/shared.pdf',
    }));
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
            IncomingFileService.channelName, message, (_) {});

    final file = (await received).single;
    expect(file.name, 'shared.pdf');
    expect(file.path, '/tmp/shared.pdf');
  });

  test('native openFile preserves a security bookmark', () async {
    final service = IncomingFileService();
    addTearDown(service.dispose);
    service.start();

    final received = service.files.first;
    const codec = StandardMethodCodec();
    final message = codec.encodeMethodCall(const MethodCall('openFile', {
      'name': 'cloud.pdf',
      'path': '/Users/ben/Library/CloudStorage/cloud.pdf',
      'bookmark': 'bookmark-data',
    }));
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
            IncomingFileService.channelName, message, (_) {});

    final file = (await received).single;
    expect(file.path, '/Users/ben/Library/CloudStorage/cloud.pdf');
    expect(file.bookmark, 'bookmark-data');
  });
}
