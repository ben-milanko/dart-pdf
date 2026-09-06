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

    testWidgets('returns false on unsupported platforms before launching',
        (tester) async {
      expect(await openContainingFolder('/Users/ben/file.pdf'), isFalse);
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));
  });
}
