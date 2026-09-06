import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dart_pdf_editor_app/windows_drop_target.dart';

void main() {
  const channel = MethodChannel('dev.milanko.dartpdf/windows_drop');
  const codec = StandardMethodCodec();

  testWidgets('routes a native drop to its registered window', (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    final registrations = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (call) async {
        registrations.add(call);
        return true;
      },
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));

    DropDoneDetails? dropped;
    await tester.pumpWidget(MaterialApp(
      home: WindowsDropTarget(
        windowHandle: 42,
        onDragDone: (details) => dropped = details,
        child: const SizedBox.expand(),
      ),
    ));
    await tester.pump();
    expect(registrations.single.method, 'register');

    Future<void> send(String method, {List<String>? paths}) async {
      final message = codec.encodeMethodCall(MethodCall(method, {
        'handle': 42,
        'x': 100.0,
        'y': 120.0,
        if (paths != null) 'paths': paths,
      }));
      await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        channel.name,
        message,
        (_) {},
      );
      await tester.pump();
    }

    await send('entered');
    await send('performOperation', paths: [r'C:\drawings\plan.pdf']);

    expect(dropped, isNotNull);
    expect(dropped!.files.single.path, endsWith(r'plan.pdf'));
    expect(dropped!.globalPosition, const Offset(100, 120));

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(registrations.last.method, 'unregister');
  });

  testWidgets('ignores events addressed to another window', (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => true);
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));

    var drops = 0;
    await tester.pumpWidget(MaterialApp(
      home: WindowsDropTarget(
        windowHandle: 7,
        onDragDone: (_) => drops++,
        child: const SizedBox.expand(),
      ),
    ));
    await tester.pump();

    for (final method in ['entered', 'performOperation']) {
      final message = codec.encodeMethodCall(MethodCall(method, {
        'handle': 8,
        'x': 100.0,
        'y': 120.0,
        'paths': [r'C:\other.pdf'],
      }));
      await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        channel.name,
        message,
        (_) {},
      );
    }
    await tester.pump();
    expect(drops, 0);
  });
}
