import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dart_pdf_editor_app/incoming_file.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('push forwards a file on the stream', () async {
    final service = IncomingFileService();
    addTearDown(service.dispose);

    final received = service.files.first;
    service.push(IncomingFile(name: 'x.pdf', bytes: Uint8List(3)));
    final file = await received;

    expect(file.name, 'x.pdf');
    expect(file.bytes, isNotNull);
  });

  test('initialFile is null when no native handler answers', () async {
    final service = IncomingFileService();
    addTearDown(service.dispose);
    expect(await service.initialFile(), isNull);
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
    await TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .handlePlatformMessage(
            IncomingFileService.channelName, message, (_) {});

    final file = await received;
    expect(file.name, 'shared.pdf');
    expect(file.path, '/tmp/shared.pdf');
  });
}
