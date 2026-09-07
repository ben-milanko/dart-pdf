import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dart_pdf_editor_app/file_io.dart';

void main() {
  group('containingFolderPath', () {
    test('returns POSIX parent folders', () {
      expect(containingFolderPath('/Users/ben/Documents/file.pdf'),
          '/Users/ben/Documents');
      expect(containingFolderPath('/file.pdf'), '/');
      expect(containingFolderPath('/Users/ben/Documents/'), '/Users/ben');
    });

    test('returns Windows parent folders', () {
      expect(containingFolderPath(r'C:\Users\ben\file.pdf'), r'C:\Users\ben');
      expect(containingFolderPath(r'C:\file.pdf'), r'C:\');
      expect(containingFolderPath(r'C:\Users\ben\'), r'C:\Users');
    });

    test('rejects paths without a containing folder', () {
      expect(containingFolderPath(''), isNull);
      expect(containingFolderPath('file.pdf'), isNull);
    });
  });

  group('open containing folder support', () {
    for (final scenario in [
      (
        platform: TargetPlatform.macOS,
        supported: true,
        label: 'Open in Finder',
      ),
      (
        platform: TargetPlatform.windows,
        supported: true,
        label: 'Open in File Explorer',
      ),
      (
        platform: TargetPlatform.linux,
        supported: true,
        label: 'Open containing folder',
      ),
      (
        platform: TargetPlatform.android,
        supported: false,
        label: 'Open containing folder',
      ),
    ]) {
      testWidgets('uses ${scenario.platform.name} support and label',
          (tester) async {
        expect(supportsOpenContainingFolder, scenario.supported);
        expect(openContainingFolderLabel, scenario.label);
      }, variant: TargetPlatformVariant.only(scenario.platform));
    }

    testWidgets('returns false without a usable path on desktop',
        (tester) async {
      expect(await openContainingFolder(null), isFalse);
      expect(await openContainingFolder('file.pdf'), isFalse);
    }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

    testWidgets('macOS reveals the selected file with its security bookmark',
        (tester) async {
      const channel = MethodChannel('dev.milanko.dartpdf/file_access');
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return true;
      });
      addTearDown(() => TestDefaultBinaryMessengerBinding
          .instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null));

      expect(
        await openContainingFolder(
          '/Users/ben/Library/CloudStorage/OneDrive/file.pdf',
          bookmark: 'security-scope',
        ),
        isTrue,
      );
      expect(calls, hasLength(1));
      expect(calls.single.method, 'revealFile');
      expect(calls.single.arguments, {
        'path': '/Users/ben/Library/CloudStorage/OneDrive/file.pdf',
        'bookmark': 'security-scope',
      });
    }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

    testWidgets('Windows selects the file through the runner', (tester) async {
      final calls = <MethodCall>[];
      final launched = _mockUrlLauncher();
      _mockFileAccess((call) async {
        calls.add(call);
        return true;
      });

      expect(
          await openContainingFolder(r'C:\Users\ben\Desktop\copy.pdf'), isTrue);

      expect(calls.single.method, 'revealFile');
      expect(
          calls.single.arguments, {'path': r'C:\Users\ben\Desktop\copy.pdf'});
      // Naming the item is the whole point: no folder URL is launched, so
      // Explorer cannot answer with a window it already had open elsewhere.
      expect(launched, isEmpty);
    }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

    testWidgets('Windows falls back to the folder without a runner reveal',
        (tester) async {
      final launched = _mockUrlLauncher();
      // An older runner has no reveal method; a null reply is what the channel
      // turns into MissingPluginException.
      _mockFileAccess((call) async => null);

      expect(
          await openContainingFolder(r'C:\Users\ben\Desktop\copy.pdf'), isTrue);

      expect(launched, [r'file:///C:/Users/ben/Desktop']);
    }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

    testWidgets('Windows falls back to the folder when Explorer refuses',
        (tester) async {
      final launched = _mockUrlLauncher();
      _mockFileAccess((call) async => false);

      expect(
          await openContainingFolder(r'C:\Users\ben\Desktop\copy.pdf'), isTrue);

      expect(launched, [r'file:///C:/Users/ben/Desktop']);
    }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

    testWidgets('Linux opens the containing folder', (tester) async {
      final launched = _mockUrlLauncher();

      expect(await openContainingFolder('/home/ben/Desktop/copy.pdf'), isTrue);

      expect(launched, ['file:///home/ben/Desktop']);
    }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

    testWidgets('returns false on unsupported platforms before launching',
        (tester) async {
      expect(await openContainingFolder('/Users/ben/file.pdf'), isFalse);
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));
  });
}

/// Records the URLs `launchUrl` is handed, reporting success.
List<String> _mockUrlLauncher() {
  final launched = <String>[];
  const channel = MethodChannel('plugins.flutter.io/url_launcher');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (call) async {
    if (call.method == 'launch') {
      launched.add((call.arguments as Map)['url'] as String);
    }
    return true;
  });
  addTearDown(() => TestDefaultBinaryMessengerBinding
      .instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, null));
  return launched;
}

/// Answers the runner's file-access channel with [handler]. The channel must
/// always be handled: an unmocked one leaves the reply pending forever under
/// flutter_test, so a "no such method" runner is a handler returning null.
void _mockFileAccess(Future<Object?> Function(MethodCall call) handler) {
  const channel = MethodChannel('dev.milanko.dartpdf/file_access');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, handler);
  addTearDown(() => TestDefaultBinaryMessengerBinding
      .instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, null));
}
