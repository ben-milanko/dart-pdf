import 'package:flutter/foundation.dart';
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

    testWidgets('returns false on unsupported platforms before launching',
        (tester) async {
      expect(await openContainingFolder('/Users/ben/file.pdf'), isFalse);
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));
  });
}
